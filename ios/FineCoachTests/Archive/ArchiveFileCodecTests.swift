import CryptoKit
import FineCoach
import XCTest

/// Container and payload tests for `.fcarchive` v1 (contract archive-file-v1, T024).
///
/// Key derivation runs 600,000 PBKDF2 iterations and the contract fixes that number, so the
/// tests that need a real file share one golden file and keep derivations to the cases that
/// genuinely reach the key (round trips, wrong password, salt / nonce tampering, chunk
/// reorder). Structural payload rules are tested through `decodePayload`, which needs no key.
final class ArchiveFileCodecTests: XCTestCase {
    private typealias F = ArchiveFixtures

    private static let goldenFile: Data = {
        try! ArchiveFileCodec.encode(
            snapshot: ArchiveFixtures.fullSnapshot(),
            password: try! ArchivePassword(creating: ArchiveFixtures.password),
            salt: ArchiveFixtures.fixedSalt,
            noncePrefix: ArchiveFixtures.fixedNoncePrefix
        )
    }()

    private var password: ArchivePassword { try! ArchivePassword(creating: F.password) }

    private func assertDecodeFails(
        _ file: Data,
        _ expected: ArchiveFileError,
        _ message: String = "",
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try ArchiveFileCodec.decode(file: file, password: password), message, line: line) {
            XCTAssertEqual($0 as? ArchiveFileError, expected, message, line: line)
        }
    }

    private func assertPayloadFails(
        _ payload: (plaintext: Data, frameCount: UInt64),
        _ message: String,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ArchiveFileCodec.decodePayload(plaintext: payload.plaintext, recordCount: payload.frameCount),
            message,
            line: line
        ) {
            XCTAssertEqual($0 as? ArchiveFileError, .invalidArchive, message, line: line)
        }
    }

    private func assertPayloadFails(_ plaintext: Data, frames: UInt64, _ message: String, line: UInt = #line) {
        assertPayloadFails((plaintext, frames), message, line: line)
    }

    /// Renders frames as `sectionID:json` lines for readable golden comparison.
    private func renderFrames(_ plaintext: Data) -> String {
        var lines: [String] = []
        var offset = 0
        while offset < plaintext.count {
            let id = Int(plaintext[offset]) << 8 | Int(plaintext[offset + 1])
            let length =
                Int(plaintext[offset + 2]) << 24 | Int(plaintext[offset + 3]) << 16
                | Int(plaintext[offset + 4]) << 8 | Int(plaintext[offset + 5])
            let json = String(decoding: plaintext.subdata(in: (offset + 6)..<(offset + 6 + length)), as: UTF8.self)
            lines.append("\(id):\(json)")
            offset += 6 + length
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Golden vector and round trip

    func testGoldenVectorFixedSaltNonceAndPlaintextProduceFixedBytes() throws {
        let snapshot = F.fullSnapshot()
        let payload = try ArchiveFileCodec.encodePayload(snapshot)
        XCTAssertEqual(payload.frameCount, 15)
        XCTAssertEqual(renderFrames(payload.plaintext), Self.expectedFrames)

        let file = Self.goldenFile
        XCTAssertEqual(file.count, 82 + payload.plaintext.count + 16)
        XCTAssertEqual(
            file.prefix(82).archiveHex,
            "46435041" + "0001" + "0052" + "0001" + "01" + "01" + "000927c0"
                + String(repeating: "11", count: 32) + String(repeating: "44", count: 8)
                + "00100000" + String(format: "%016llx", UInt64(payload.plaintext.count))
                + "000000000000000f" + "00000001" + "0001"
        )
        XCTAssertEqual(SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined(), Self.expectedFileSHA256)

        let decoded = try ArchiveFileCodec.decode(file: file, password: password)
        XCTAssertEqual(decoded, snapshot)
    }

    func testRandomEncodeRoundTripsAndNeverReusesSaltOrNonce() throws {
        let snapshot = F.summariesOnlySnapshot()
        let first = try ArchiveFileCodec.encode(snapshot: snapshot, password: password)
        let second = try ArchiveFileCodec.encode(snapshot: snapshot, password: password)
        XCTAssertNotEqual(first.subdata(in: 16..<48), second.subdata(in: 16..<48))
        XCTAssertNotEqual(first.subdata(in: 48..<56), second.subdata(in: 48..<56))
        XCTAssertEqual(try ArchiveFileCodec.decode(file: first, password: password), snapshot)
    }

    func testWrongPasswordIsIndistinguishableFromCorruption() throws {
        let other = try ArchivePassword(importing: "另一个口令xyz12")
        XCTAssertThrowsError(try ArchiveFileCodec.decode(file: Self.goldenFile, password: other)) {
            XCTAssertEqual($0 as? ArchiveFileError, .wrongPasswordOrCorrupted)
        }
        let empty = try ArchivePassword(importing: "")
        XCTAssertThrowsError(try ArchiveFileCodec.decode(file: Self.goldenFile, password: empty)) {
            XCTAssertEqual($0 as? ArchiveFileError, .wrongPasswordOrCorrupted)
        }
    }

    func testPayloadRoundTripKeepsEveryModuleCombination() throws {
        let full = F.fullSnapshot()
        let payload = try ArchiveFileCodec.encodePayload(full)
        XCTAssertEqual(
            try ArchiveFileCodec.decodePayload(plaintext: payload.plaintext, recordCount: payload.frameCount),
            full
        )
        let minimal = F.summariesOnlySnapshot()
        let minimalPayload = try ArchiveFileCodec.encodePayload(minimal)
        XCTAssertEqual(minimalPayload.frameCount, 2)
        XCTAssertEqual(
            try ArchiveFileCodec.decodePayload(
                plaintext: minimalPayload.plaintext,
                recordCount: minimalPayload.frameCount
            ),
            minimal
        )
    }

    func testExerciseWithoutInfoRoundTripsAndKeepsIsAssisted() throws {
        let noInfoModules = F.modules(exerciseInfo: false)
        let snapshot = F.assemble(
            modules: noInfoModules,
            exercises: [
                ArchiveExercise(key: "e1", placeholderNumber: 1, kind: .builtIn, isAssisted: true),
                ArchiveExercise(key: "e2", placeholderNumber: 2, kind: .oneOff, isAssisted: false),
            ]
        )
        let payload = try ArchiveFileCodec.encodePayload(snapshot)
        let text = renderFrames(payload.plaintext)
        XCTAssertTrue(text.contains(#"3:{"isAssisted":true,"key":"e1","kind":"builtIn","placeholderNumber":1}"#))
        XCTAssertFalse(text.contains("name"))
        let decoded = try ArchiveFileCodec.decodePayload(plaintext: payload.plaintext, recordCount: payload.frameCount)
        XCTAssertEqual(decoded.exercises.map(\.isAssisted), [true, false])
        XCTAssertNil(decoded.exercises[0].info)
    }

    func testArchiveBytesContainNoCoachSideIdentifiersOrFileSystemTraces() throws {
        let text = renderFrames(try ArchiveFileCodec.encodePayload(F.fullSnapshot()).plaintext)
        for forbidden in ["catalog", "studentID", "exerciseID", "sessionID", "metricID", "/var/", "file://"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    // MARK: Header: magic, versions, layout (contract §2)

    func testFCBKBackupMagicIsNotAnArchive() {
        var file = Self.goldenFile
        file.replaceSubrange(0..<4, with: Data("FCBK".utf8))
        assertDecodeFails(file, .notAnArchive)
        assertDecodeFails(Data("FCBK".utf8) + Data(count: 4_000), .notAnArchive, "large foreign file")
        assertDecodeFails(Data(), .notAnArchive, "empty file")
        assertDecodeFails(Data("%PDF-1.7".utf8), .notAnArchive, "foreign short file")
    }

    func testMinimumReaderVersion2IsIncompatibleVersion() {
        var file = Self.goldenFile
        file[80] = 0
        file[81] = 2
        assertDecodeFails(file, .incompatibleVersion)
    }

    func testEveryVersionFieldMismatchIsIncompatibleVersion() {
        func mutated(_ offset: Int, _ bytes: [UInt8]) -> Data {
            var file = Self.goldenFile
            file.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
            return file
        }
        assertDecodeFails(mutated(4, [0, 2]), .incompatibleVersion, "containerVersion 2")
        assertDecodeFails(mutated(8, [0, 2]), .incompatibleVersion, "payload schema newer")
        assertDecodeFails(mutated(10, [2]), .incompatibleVersion, "kdfID")
        assertDecodeFails(mutated(11, [2]), .incompatibleVersion, "aeadID")
        assertDecodeFails(mutated(12, [0, 0, 0, 1]), .incompatibleVersion, "iterations 1")
        assertDecodeFails(mutated(12, [0x00, 0x0F, 0x42, 0x40]), .incompatibleVersion, "iterations 1,000,000")
    }

    func testEveryHeaderByteTamperFailsClosedWithItsFieldClass() throws {
        let original = Self.goldenFile
        for offset in 0..<82 {
            var file = original
            file[offset] ^= 0xFF
            let expected: Set<ArchiveFileError>
            switch offset {
            case 0..<4: expected = [.notAnArchive]
            case 4..<6, 8..<10, 10, 11, 12..<16, 80..<82: expected = [.incompatibleVersion]
            case 6..<8, 56..<60, 76..<80: expected = [.invalidArchive]
            case 16..<56: expected = [.wrongPasswordOrCorrupted]
            default:
                // plaintextLength / recordCount: which check trips first depends on the
                // byte's weight; either way the file is rejected before any plaintext.
                expected = [.invalidArchive, .wrongPasswordOrCorrupted]
            }
            XCTAssertThrowsError(try ArchiveFileCodec.decode(file: file, password: password), "byte \(offset)") {
                XCTAssertTrue(
                    expected.contains($0 as? ArchiveFileError ?? .notAnArchive),
                    "byte \(offset): \($0)"
                )
            }
        }
    }

    func testHeaderLayoutAndLimitRejections() {
        func header(
            plaintextLength: UInt64 = 100,
            recordCount: UInt64 = 2,
            chunkCount: UInt32 = 1,
            chunkSize: UInt32 = 1_048_576,
            headerLength: UInt16 = 82
        ) -> Data {
            var data = Data("FCPA".utf8)
            data.append(contentsOf: [0, 1])
            data.append(contentsOf: [UInt8(headerLength >> 8), UInt8(headerLength & 0xFF)])
            data.append(contentsOf: [0, 1, 1, 1])
            data.append(contentsOf: [0x00, 0x09, 0x27, 0xC0])
            data.append(Data(repeating: 0x11, count: 32))
            data.append(Data(repeating: 0x44, count: 8))
            for value in [chunkSize] {
                data.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init))
            }
            data.append(contentsOf: withUnsafeBytes(of: plaintextLength.bigEndian, Array.init))
            data.append(contentsOf: withUnsafeBytes(of: recordCount.bigEndian, Array.init))
            data.append(contentsOf: withUnsafeBytes(of: chunkCount.bigEndian, Array.init))
            data.append(contentsOf: [0, 1])
            return data
        }
        let maxPlaintext = UInt64(64 * 1024 * 1024)
        // The boundary values are accepted by the limit checks and then fail on the exact
        // file-length rule (the test file is deliberately short).
        XCTAssertThrowsError(try ArchiveFileHeader.inspect(header(plaintextLength: 100))) {
            XCTAssertEqual($0 as? ArchiveFileError, .wrongPasswordOrCorrupted)
        }
        XCTAssertThrowsError(try ArchiveFileHeader.inspect(header(plaintextLength: 1))) {
            XCTAssertEqual($0 as? ArchiveFileError, .wrongPasswordOrCorrupted)
        }
        XCTAssertThrowsError(
            try ArchiveFileHeader.inspect(header(plaintextLength: maxPlaintext, chunkCount: 64))
        ) {
            XCTAssertEqual($0 as? ArchiveFileError, .wrongPasswordOrCorrupted, "64 MiB plaintext is within limits")
        }
        XCTAssertThrowsError(
            try ArchiveFileHeader.inspect(header(recordCount: ArchiveFileV1.maxRecordCount))
        ) {
            XCTAssertEqual($0 as? ArchiveFileError, .wrongPasswordOrCorrupted, "max recordCount is within limits")
        }
        // One past each limit, and layout violations.
        let rejections: [(String, Data)] = [
            ("plaintextLength 0", header(plaintextLength: 0, chunkCount: 0)),
            ("plaintextLength 64 MiB + 1", header(plaintextLength: maxPlaintext + 1, chunkCount: 65)),
            ("recordCount max + 1", header(recordCount: ArchiveFileV1.maxRecordCount + 1)),
            ("chunkSize 512 KiB", header(chunkSize: 524_288)),
            ("headerLength 83", header(headerLength: 83)),
            ("chunkCount too small", header(plaintextLength: 1_048_577, chunkCount: 1)),
            ("chunkCount too large", header(plaintextLength: 100, chunkCount: 2)),
        ]
        for (name, data) in rejections {
            XCTAssertThrowsError(try ArchiveFileHeader.inspect(data), name) {
                XCTAssertEqual($0 as? ArchiveFileError, .invalidArchive, name)
            }
        }
    }

    func testFileSizeCeilingFailsClosedAtBoundary() {
        let ceiling = ArchiveFileV1.maxFileBytes
        XCTAssertEqual(ceiling, 82 + 64 * 1024 * 1024 + 16 * 64)
        var overLimit = Data("FCPA".utf8)
        overLimit.append(Data(count: ceiling + 1 - 4))
        XCTAssertThrowsError(try ArchiveFileHeader.inspect(overLimit)) {
            XCTAssertEqual($0 as? ArchiveFileError, .invalidArchive)
        }
        // At the ceiling the size gate passes; the all-zero header then fails on its version.
        var atLimit = Data("FCPA".utf8)
        atLimit.append(Data(count: ceiling - 4))
        XCTAssertThrowsError(try ArchiveFileHeader.inspect(atLimit)) {
            XCTAssertEqual($0 as? ArchiveFileError, .incompatibleVersion)
        }
    }

    // MARK: Length, truncation, appended bytes, chunk reorder (contract §3)

    func testTruncationFailsClosedAtEveryStructuralBoundary() {
        let file = Self.goldenFile
        assertDecodeFails(file.prefix(0), .notAnArchive, "empty")
        for length in [1, 3, 4, 40, 81, 82, 83, file.count - 17, file.count - 16, file.count - 1] {
            assertDecodeFails(file.prefix(length), .wrongPasswordOrCorrupted, "truncated to \(length)")
        }
    }

    func testAppendedBytesFailClosed() {
        assertDecodeFails(Self.goldenFile + Data([0]), .wrongPasswordOrCorrupted)
        assertDecodeFails(Self.goldenFile + Data(count: 16), .wrongPasswordOrCorrupted)
        assertDecodeFails(Self.goldenFile + Self.goldenFile, .wrongPasswordOrCorrupted)
    }

    func testChunkReorderFailsAuthentication() throws {
        // Two full chunks of identical size, so swapping them keeps the file length valid and
        // only authentication can notice.
        let chunk = Int(ArchiveFileV1.chunkSize)
        var plaintext = Data()
        plaintext.append(F.frame(1, "{}"))
        plaintext.append(Data(repeating: 0x41, count: 2 * chunk - plaintext.count))
        let file = try ArchiveFileCodec.seal(
            plaintext: plaintext,
            recordCount: 1,
            password: password,
            salt: F.fixedSalt,
            noncePrefix: F.fixedNoncePrefix
        )
        let region = chunk + ArchiveFileV1.tagSize
        XCTAssertEqual(file.count, 82 + 2 * region)
        // Control: the untouched file authenticates and is then rejected as a bad payload,
        // which proves the swap below is what changes the class.
        assertDecodeFails(file, .invalidArchive, "authenticated but not a valid payload")
        var reordered = file.prefix(82)
        reordered.append(file.subdata(in: (82 + region)..<(82 + 2 * region)))
        reordered.append(file.subdata(in: 82..<(82 + region)))
        assertDecodeFails(reordered, .wrongPasswordOrCorrupted)
    }

    // MARK: Payload frames (contract §4)

    func testFrameOrderAndSectionRules() throws {
        let base = try F.payload(of: F.fullSnapshot())
        let frames = splitFrames(base.plaintext)
        XCTAssertEqual(frames.map(\.id), [1, 2, 3, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 7, 8])

        // Unknown section IDs.
        for unknown: UInt16 in [0, 9, 0xFFFF] {
            assertPayloadFails(
                base.plaintext + F.frame(unknown, "{}"),
                frames: base.frameCount + 1,
                "unknown sectionID \(unknown)"
            )
        }
        // Duplicate manifest, directly after the first and after later frames.
        assertPayloadFails(
            F.frame(1, frames[0].json) + F.frame(1, frames[0].json) + joined(frames.dropFirst()),
            frames: base.frameCount + 1,
            "duplicate manifest"
        )
        assertPayloadFails(
            base.plaintext + F.frame(1, frames[0].json),
            frames: base.frameCount + 1,
            "manifest after other sections"
        )
        // Wrong frame order: a lower section after a higher one.
        var reorderedFrames = frames
        reorderedFrames.swapAt(2, 5)
        assertPayloadFails(joined(reorderedFrames[...]), frames: base.frameCount, "session before exercise")
        // Manifest not first.
        var manifestLast = Array(frames.dropFirst())
        manifestLast.append(frames[0])
        assertPayloadFails(joined(manifestLast[...]), frames: base.frameCount, "manifest not first")
        // No frames at all, a frame header cut short, a JSON body cut short.
        assertPayloadFails(Data(), frames: 0, "empty payload")
        assertPayloadFails(Data([0, 1, 0]), frames: 1, "frame header cut short")
        assertPayloadFails(base.plaintext.dropLast(), frames: base.frameCount, "last frame body cut short")
        assertPayloadFails(base.plaintext + Data([0, 3]), frames: base.frameCount, "trailing partial frame header")
        // A declared JSON length beyond the plaintext.
        var oversized = F.frame(1, frames[0].json)
        oversized.replaceSubrange(2..<6, with: [0xFF, 0xFF, 0xFF, 0xFF])
        assertPayloadFails(oversized, frames: 1, "jsonLength larger than payload")
        // Header recordCount must equal the number of frames.
        assertPayloadFails(base.plaintext, frames: base.frameCount - 1, "recordCount too small")
        assertPayloadFails(base.plaintext, frames: base.frameCount + 1, "recordCount too large")
        // Control: the untouched payload is accepted.
        XCTAssertNoThrow(try ArchiveFileCodec.decodePayload(plaintext: base.plaintext, recordCount: base.frameCount))
    }

    func testCountsMustMatchTheFramesPresent() throws {
        for key in ["student", "exercise", "session", "summary", "bodyMetric", "bodyMeasurement", "attribution"] {
            for delta in [-1, 1] {
                let payload = try F.payload(of: F.fullSnapshot()) { id, object in
                    guard id == 1 else { return }
                    var counts = object["counts"] as! [String: Any]
                    counts[key] = (counts[key] as! Int) + delta
                    object["counts"] = counts
                }
                assertPayloadFails(payload, "counts.\(key) \(delta)")
            }
        }
    }

    func testIdentityMetadataMustBeValid() throws {
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("sourceID not a UUID", { $0["sourceID"] = "not-a-uuid" }),
            ("sourceID empty", { $0["sourceID"] = "" }),
            ("studentArchiveID truncated", { $0["studentArchiveID"] = "AAAAAAAA-BBBB-CCCC-DDDD" }),
            ("snapshotAtUTC unparsable", { $0["snapshotAtUTC"] = "yesterday" }),
            ("snapshotAtUTC impossible date", { $0["snapshotAtUTC"] = "2026-13-45T08:00:00.000Z" }),
            ("snapshotAtUTC wrong type", { $0["snapshotAtUTC"] = 1_791_532_800 }),
            ("sourceID missing", { $0.removeValue(forKey: "sourceID") }),
        ]
        for (name, mutate) in mutations {
            let payload = try F.payload(of: F.fullSnapshot()) { id, object in
                if id == 1 { mutate(&object) }
            }
            assertPayloadFails(payload, name)
        }
    }

    func testReferencesToMissingLocalKeysAreRejected() throws {
        func sessionExerciseKey(_ object: inout [String: Any], to key: String) {
            var sections = object["sections"] as! [[String: Any]]
            var exercises = sections[0]["exercises"] as! [[String: Any]]
            exercises[0]["exerciseKey"] = key
            sections[0]["exercises"] = exercises
            object["sections"] = sections
        }
        let cases: [(String, (UInt16, inout [String: Any]) -> Void)] = [
            ("session -> missing exercise", { id, object in if id == 4 { sessionExerciseKey(&object, to: "e99") } }),
            (
                "summary -> missing session",
                { id, object in if id == 5, object["sessionKey"] != nil { object["sessionKey"] = "s99" } }
            ),
            ("measurement -> missing metric", { id, object in if id == 7 { object["metricKey"] = "m99" } }),
            ("attribution -> missing exercise", { id, object in if id == 8 { object["exerciseKeys"] = ["e99"] } }),
            ("attribution -> non built-in exercise", { id, object in if id == 8 { object["exerciseKeys"] = ["e2"] } }),
            ("duplicate exercise key", { id, object in if id == 3 { object["key"] = "e1" } }),
            ("malformed exercise key", { id, object in if id == 3 { object["key"] = "x1" } }),
            ("placeholderNumber 0", { id, object in if id == 3 { object["placeholderNumber"] = 0 } }),
            ("duplicate session key", { id, object in if id == 4 { object["key"] = "s1" } }),
            ("duplicate metric key", { id, object in if id == 6 { object["key"] = "m1" } }),
        ]
        for (name, mutate) in cases {
            assertPayloadFails(try F.payload(of: F.fullSnapshot(), transform: mutate), name)
        }
    }

    func testExerciseInfoMustAgreeWithTheExerciseInfoModule() throws {
        // exerciseInfo false, yet the archive carries a name / muscles / equipment.
        let noInfo = F.assemble(
            modules: F.modules(exerciseInfo: false),
            exercises: [ArchiveExercise(key: "e1", placeholderNumber: 1, kind: .custom, isAssisted: false)]
        )
        assertPayloadFails(
            try F.payload(of: noInfo) { id, object in if id == 3 { object["name"] = "示例动作" } },
            "name without exerciseInfo"
        )
        assertPayloadFails(
            try F.payload(of: noInfo) { id, object in
                if id == 3 {
                    object["name"] = "示例动作"
                    object["primaryMuscles"] = ["胸"]
                    object["secondaryMuscles"] = [String]()
                    object["equipment"] = "杠铃"
                }
            },
            "full exercise info without exerciseInfo"
        )
        assertPayloadFails(
            try F.payload(of: noInfo) { id, object in if id == 3 { object["primaryMuscles"] = ["胸"] } },
            "muscles only, without exerciseInfo"
        )
        // Partial info with exerciseInfo true is also a malformed writer.
        assertPayloadFails(
            try F.payload(of: F.fullSnapshot()) { id, object in
                if id == 3 { object.removeValue(forKey: "equipment") }
            },
            "partial exercise info"
        )
        // Attribution only belongs to exerciseInfo archives.
        let withAttribution = F.assemble(
            modules: F.modules(exerciseInfo: false),
            exercises: [ArchiveExercise(key: "e1", placeholderNumber: 1, kind: .builtIn, isAssisted: false)],
            attribution: ArchiveAttribution(
                sourceName: "示例",
                licenseName: "示例",
                licenseText: "示例",
                exerciseKeys: ["e1"]
            )
        )
        assertPayloadFails(try F.payload(of: withAttribution), "attribution without exerciseInfo")
    }

    func testIsAssistedIsRequiredOnEveryExercise() throws {
        assertPayloadFails(
            try F.payload(of: F.fullSnapshot()) { id, object in
                if id == 3 { object.removeValue(forKey: "isAssisted") }
            },
            "exercise without isAssisted"
        )
        assertPayloadFails(
            try F.payload(of: F.fullSnapshot()) { id, object in
                if id == 3 { object["isAssisted"] = "yes" }
            },
            "isAssisted not a boolean"
        )
    }

    func testFramesOfUnselectedModulesAreRejected() throws {
        let cases: [(String, ArchiveModuleSet, (ArchiveSnapshot) -> ArchiveSnapshot)] = [
            ("student without displayName/sex", F.modules(displayName: false, sex: false), { $0 }),
            ("summary frames without summaries", F.modules(summaries: false), { $0 }),
            ("body data without bodyData", F.modules(bodyData: false), { $0 }),
            (
                "training frames without trainingRecords",
                F.modules(trainingRecords: false, trends: false, exerciseInfo: false), { $0 }
            ),
            ("display name without displayName", F.modules(displayName: false), { $0 }),
            ("sex without sex", F.modules(sex: false), { $0 }),
        ]
        for (name, modules, adjust) in cases {
            let full = adjust(F.fullSnapshot())
            let snapshot = ArchiveSnapshot(
                manifest: F.manifest(modules: modules, counts: full.derivedCounts),
                student: full.student,
                exercises: full.exercises,
                sessions: full.sessions,
                summaries: full.summaries,
                bodyMetrics: full.bodyMetrics,
                bodyMeasurements: full.bodyMeasurements,
                attribution: full.attribution
            )
            assertPayloadFails(try F.payload(of: snapshot), name)
        }
    }

    func testManifestModuleRulesAreEnforcedOnDecode() throws {
        let invalidModules: [(String, (inout [String: Any]) -> Void)] = [
            ("trends without trainingRecords", { $0["trainingRecords"] = false }),
            (
                "exerciseInfo without trainingRecords",
                {
                    $0["trends"] = false
                    $0["trainingRecords"] = false
                }
            ),
            ("module flag missing", { $0.removeValue(forKey: "exerciseInfo") }),
        ]
        for (name, mutate) in invalidModules {
            let payload = try F.payload(of: F.fullSnapshot()) { id, object in
                guard id == 1 else { return }
                var modules = object["modules"] as! [String: Any]
                mutate(&modules)
                object["modules"] = modules
            }
            assertPayloadFails(payload, name)
        }
        let nothingSelected = try F.payload(of: F.summariesOnlySnapshot()) { id, object in
            guard id == 1 else { return }
            var modules = object["modules"] as! [String: Any]
            modules["summaries"] = false
            object["modules"] = modules
        }
        assertPayloadFails(nothingSelected, "manifest with no module selected")
    }

    func testBodyMetricRulesAreEnforced() throws {
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("unknown built-in kind", { $0["kind"] = "bicepsCurl" }),
            ("custom metric without unit", { $0.removeValue(forKey: "unit") }),
            ("custom metric with empty name", { $0["name"] = "" }),
            ("built-in metric carrying a name", { $0["kind"] = "weight" }),
        ]
        for (name, mutate) in mutations {
            let payload = try F.payload(of: F.fullSnapshot()) { id, object in
                if id == 6, object["kind"] as? String == "custom" { mutate(&object) }
            }
            assertPayloadFails(payload, name)
        }
    }

    func testSetAndDateValuesMustBeWellFormed() throws {
        func mutateFirstSet(_ object: inout [String: Any], _ key: String, _ value: Any) {
            var sections = object["sections"] as! [[String: Any]]
            var exercises = sections[0]["exercises"] as! [[String: Any]]
            var sets = exercises[0]["sets"] as! [[String: Any]]
            sets[0][key] = value
            exercises[0]["sets"] = sets
            sections[0]["exercises"] = exercises
            object["sections"] = sections
        }
        let cases: [(String, (UInt16, inout [String: Any]) -> Void)] = [
            ("non-decimal weight", { id, object in if id == 4 { mutateFirstSet(&object, "weightValue", "heavy") } }),
            (
                "numeric weight instead of string",
                { id, object in if id == 4 { mutateFirstSet(&object, "weightValue", 60) } }
            ),
            ("unknown unit", { id, object in if id == 4 { mutateFirstSet(&object, "unit", "stones") } }),
            ("unknown side", { id, object in if id == 4 { mutateFirstSet(&object, "side", "diagonal") } }),
            (
                "unknown record mode",
                { id, object in
                    if id == 4 {
                        var sections = object["sections"] as! [[String: Any]]
                        var exercises = sections[0]["exercises"] as! [[String: Any]]
                        exercises[0]["recordMode"] = "teleport"
                        sections[0]["exercises"] = exercises
                        object["sections"] = sections
                    }
                }
            ),
            ("unknown body part", { id, object in if id == 4 { object["trainingFocus"] = ["chest", "wings"] } }),
            ("impossible local date", { id, object in if id == 4 { object["localDate"] = "2026-02-30" } }),
            ("non-canonical local date", { id, object in if id == 4 { object["localDate"] = "2026-9-1" } }),
            ("negative duration", { id, object in if id == 4 { object["durationMinutes"] = -1 } }),
            ("completedAtUTC unparsable", { id, object in if id == 4 { object["completedAtUTC"] = "noon" } }),
            ("measurement value not decimal", { id, object in if id == 7 { object["value"] = "7O" } }),
            ("measurement unit empty", { id, object in if id == 7 { object["enteredUnit"] = "" } }),
        ]
        for (name, mutate) in cases {
            assertPayloadFails(try F.payload(of: F.fullSnapshot(), transform: mutate), name)
        }
    }

    // MARK: Resource limits (plan §7.3)

    func testSessionLimitBoundary() throws {
        try assertCountBoundary(limit: ArchiveLimits.maxSessions) { count in
            let sessions = (0..<count).map { offset -> ArchiveSession in
                let index = offset + 1
                return ArchiveSession(
                    key: "s\(index)",
                    localDate: F.day(2026, 9, 1),
                    completedAtUTC: Date(timeIntervalSince1970: 1_788_246_000),
                    durationMinutes: 30,
                    trainingFocus: [],
                    sections: []
                )
            }
            return F.assemble(
                modules: F.modules(
                    displayName: false, sex: false, bodyData: false, trends: false, summaries: false,
                    exerciseInfo: false), sessions: sessions)
        }
    }

    func testExerciseLimitBoundary() throws {
        try assertCountBoundary(limit: ArchiveLimits.maxExercises) { count in
            let exercises = (0..<count).map {
                ArchiveExercise(key: "e\($0 + 1)", placeholderNumber: $0 + 1, kind: .custom, isAssisted: false)
            }
            return F.assemble(
                modules: F.modules(
                    displayName: false, sex: false, bodyData: false, trends: false, summaries: false,
                    exerciseInfo: false), exercises: exercises)
        }
    }

    func testSummaryLimitBoundary() throws {
        try assertCountBoundary(limit: ArchiveLimits.maxSummaries) { count in
            let summaries = (0..<count).map { _ in
                try! ArchiveSummary(localDate: F.day(2026, 9, 1), sessionKey: nil, text: "x")
            }
            return F.assemble(
                modules: F.modules(
                    displayName: false, sex: false, bodyData: false, trainingRecords: false, trends: false,
                    exerciseInfo: false), summaries: summaries)
        }
    }

    func testBodyMetricLimitBoundary() throws {
        try assertCountBoundary(limit: ArchiveLimits.maxBodyMetrics) { count in
            let metrics = (0..<count).map {
                try! ArchiveBodyMetric(key: "m\($0 + 1)", kind: .custom, name: "n\($0)", unit: "u")
            }
            return F.assemble(
                modules: F.modules(
                    displayName: false, sex: false, trainingRecords: false, trends: false, summaries: false,
                    exerciseInfo: false), bodyMetrics: metrics)
        }
    }

    func testBodyMeasurementLimitBoundary() throws {
        try assertCountBoundary(limit: ArchiveLimits.maxBodyMeasurements) { count in
            let measurements = (0..<count).map { _ in
                ArchiveBodyMeasurement(
                    metricKey: "m1", localDay: F.day(2026, 9, 1), value: F.decimal("1"), enteredUnit: "u")
            }
            return F.assemble(
                modules: F.modules(
                    displayName: false, sex: false, trainingRecords: false, trends: false, summaries: false,
                    exerciseInfo: false),
                bodyMetrics: [try! ArchiveBodyMetric(key: "m1", kind: .custom, name: "n", unit: "u")],
                bodyMeasurements: measurements
            )
        }
    }

    func testSingletonSectionsAcceptOnlyOneFrame() throws {
        let base = try F.payload(of: F.fullSnapshot())
        let frames = splitFrames(base.plaintext)
        for id: UInt16 in [2, 8] {
            let frame = frames.first { $0.id == id }!
            assertPayloadFails(
                base.plaintext + F.frame(id, frame.json), frames: base.frameCount + 1, "second frame of section \(id)")
        }
    }

    func testSetLimitBoundary() throws {
        let modules = F.modules(
            displayName: false, sex: false, bodyData: false, trends: false, summaries: false, exerciseInfo: false)
        let exercise = ArchiveExercise(key: "e1", placeholderNumber: 1, kind: .custom, isAssisted: false)
        func snapshot(sets: Int) -> ArchiveSnapshot {
            F.assemble(
                modules: modules,
                exercises: [exercise],
                sessions: [
                    ArchiveSession(
                        key: "s1",
                        localDate: F.day(2026, 9, 1),
                        completedAtUTC: Date(timeIntervalSince1970: 1_788_246_000),
                        durationMinutes: 30,
                        trainingFocus: [],
                        sections: [
                            ArchiveSection(
                                name: nil,
                                exercises: [
                                    ArchiveSessionExercise(
                                        exerciseKey: "e1",
                                        recordMode: .reps,
                                        sets: Array(repeating: ArchiveSet(unit: MeasurementUnit.none), count: sets)
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        }
        XCTAssertEqual(ArchiveLimits.maxSets, 300_000)
        XCTAssertNoThrow(try snapshot(sets: ArchiveLimits.maxSets).validateIntegrity())
        XCTAssertThrowsError(try snapshot(sets: ArchiveLimits.maxSets + 1).validateIntegrity()) {
            XCTAssertEqual($0 as? ArchiveSnapshotError, .limitExceeded)
        }
        // End to end through the codec: one past the limit is invalidArchive.
        let over = try ArchiveFileCodec.encodePayload(snapshot(sets: ArchiveLimits.maxSets + 1))
        assertPayloadFails(over, "300,001 sets")
    }

    func testTextLimitIs64KiBPerField() throws {
        let limit = ArchiveLimits.maxTextUTF8Bytes
        XCTAssertEqual(limit, 65_536)
        XCTAssertNoThrow(
            try ArchiveSummary(
                localDate: F.day(2026, 9, 1), sessionKey: nil, text: String(repeating: "a", count: limit)))
        XCTAssertThrowsError(
            try ArchiveSummary(
                localDate: F.day(2026, 9, 1), sessionKey: nil, text: String(repeating: "a", count: limit + 1))
        ) {
            XCTAssertEqual($0 as? ArchiveSnapshotError, .textTooLong)
        }
        // Multi-byte characters count in UTF-8 bytes, not characters.
        XCTAssertThrowsError(
            try ArchiveSummary(
                localDate: F.day(2026, 9, 1), sessionKey: nil, text: String(repeating: "练", count: limit / 3 + 1)))
        XCTAssertNoThrow(
            try ArchiveSummary(
                localDate: F.day(2026, 9, 1), sessionKey: nil, text: String(repeating: "练", count: limit / 3)))

        // On the wire: summary text, student name, exercise name, section name.
        let long = String(repeating: "a", count: limit + 1)
        let exact = String(repeating: "a", count: limit)
        let cases: [(String, UInt16, String, Any)] = [
            ("summary text", 5, "text", long),
            ("student displayName", 2, "displayName", long),
            ("exercise name", 3, "name", long),
        ]
        for (name, section, key, value) in cases {
            assertPayloadFails(
                try F.payload(of: F.fullSnapshot()) { id, object in
                    if id == section, object[key] != nil { object[key] = value }
                },
                "\(name) over 64 KiB"
            )
            let exactPayload = try F.payload(of: F.fullSnapshot()) { id, object in
                if id == section, object[key] != nil { object[key] = exact }
            }
            XCTAssertNoThrow(
                try ArchiveFileCodec.decodePayload(
                    plaintext: exactPayload.plaintext, recordCount: exactPayload.frameCount),
                "\(name) at exactly 64 KiB"
            )
        }
        assertPayloadFails(
            try F.payload(of: F.fullSnapshot()) { id, object in
                guard id == 4 else { return }
                var sections = object["sections"] as! [[String: Any]]
                sections[0]["name"] = long
                object["sections"] = sections
            },
            "section name over 64 KiB"
        )
    }

    // MARK: Helpers

    private struct RawFrame {
        let id: UInt16
        let json: Data
    }

    private func splitFrames(_ plaintext: Data) -> [RawFrame] {
        var frames: [RawFrame] = []
        var offset = 0
        while offset < plaintext.count {
            let id = UInt16(plaintext[offset]) << 8 | UInt16(plaintext[offset + 1])
            let length =
                Int(plaintext[offset + 2]) << 24 | Int(plaintext[offset + 3]) << 16
                | Int(plaintext[offset + 4]) << 8 | Int(plaintext[offset + 5])
            frames.append(RawFrame(id: id, json: plaintext.subdata(in: (offset + 6)..<(offset + 6 + length))))
            offset += 6 + length
        }
        return frames
    }

    private func joined(_ frames: ArraySlice<RawFrame>) -> Data {
        frames.reduce(into: Data()) { $0.append(F.frame($1.id, $1.json)) }
    }

    /// `limit` frames decode; `limit + 1` frames are invalid.
    private func assertCountBoundary(
        limit: Int,
        line: UInt = #line,
        _ build: (Int) -> ArchiveSnapshot
    ) throws {
        let atLimit = try ArchiveFileCodec.encodePayload(build(limit))
        XCTAssertNoThrow(
            try ArchiveFileCodec.decodePayload(plaintext: atLimit.plaintext, recordCount: atLimit.frameCount),
            "exactly \(limit)",
            line: line
        )
        let over = try ArchiveFileCodec.encodePayload(build(limit + 1))
        assertPayloadFails(over, "\(limit + 1) exceeds the limit", line: line)
    }

    // MARK: Golden data

    private static let expectedFrames = #"""
        1:{"counts":{"attribution":1,"bodyMeasurement":3,"bodyMetric":2,"exercise":3,"session":2,"student":1,"summary":2},"modules":{"bodyData":true,"displayName":true,"exerciseInfo":true,"sex":true,"summaries":true,"trainingRecords":true,"trends":true},"snapshotAtUTC":"2026-10-09T08:00:00.500Z","sourceID":"11111111-2222-3333-4444-555555555555","studentArchiveID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}
        2:{"displayName":"测试学员甲","sex":"female"}
        3:{"equipment":"杠铃","isAssisted":false,"key":"e1","kind":"builtIn","name":"杠铃卧推","placeholderNumber":1,"primaryMuscles":["胸"],"secondaryMuscles":["肱三头肌","三角肌前束"]}
        3:{"equipment":"固定器械","isAssisted":true,"key":"e2","kind":"custom","name":"辅助引体向上（示例）","placeholderNumber":2,"primaryMuscles":["背"],"secondaryMuscles":[]}
        3:{"equipment":"其他","isAssisted":false,"key":"e3","kind":"oneOff","name":"跑步机慢跑","placeholderNumber":3,"primaryMuscles":[],"secondaryMuscles":[]}
        4:{"completedAtUTC":"2026-09-01T07:00:00.250Z","durationMinutes":62,"key":"s1","localDate":"2026-09-01","sections":[{"exercises":[{"exerciseKey":"e1","recordMode":"weightReps","sets":[{"repetitionCount":"8","side":"none","unit":"kilograms","weightValue":"60"},{"repetitionCount":"6","side":"none","unit":"kilograms","weightValue":"62.5"}]},{"exerciseKey":"e2","recordMode":"weightReps","sets":[{"repetitionCount":"10","side":"bilateral","unit":"kilograms","weightValue":"20"}]}],"name":"热身与主项"},{"exercises":[{"exerciseKey":"e3","recordMode":"cardio","sets":[{"distanceValue":"2.4","durationSeconds":"900","resistanceValue":"3","side":"none","speedValue":"9.6","unit":"seconds"}]}]}],"trainingFocus":["chest","back"]}
        4:{"completedAtUTC":"2026-09-08T07:00:00.750Z","durationMinutes":45,"key":"s2","localDate":"2026-09-08","sections":[{"exercises":[{"exerciseKey":"e1","recordMode":"weightReps","sets":[{"leftValue":"12","rightValue":"12.5","side":"none","unit":"kilograms"}]}]}],"trainingFocus":[]}
        5:{"localDate":"2026-09-01","sessionKey":"s1","text":"本节课状态良好，注意呼吸节奏。"}
        5:{"localDate":"2026-09-05","text":"课外补充：多喝水 / hydrate."}
        6:{"key":"m1","kind":"weight"}
        6:{"key":"m2","kind":"custom","name":"颈围（示例）","unit":"cm"}
        7:{"enteredUnit":"kg","localDay":"2026-09-01","metricKey":"m1","value":"70.5"}
        7:{"enteredUnit":"kg","localDay":"2026-09-08","metricKey":"m1","value":"70"}
        7:{"enteredUnit":"cm","localDay":"2026-09-08","metricKey":"m2","value":"34"}
        8:{"exerciseKeys":["e1"],"licenseName":"示例许可证 1.0","licenseText":"https://example.invalid/license","sourceName":"示例动作库"}
        """#
    /// SHA-256 of the whole golden file. Reproduced independently of the codec from the frame
    /// text above, the header layout (contract §2) and the AAD / nonce rules (contract §3).
    private static let expectedFileSHA256 = "213c17ddc7bf0fd81acaaca1cdb5dc65c93922c98cb7d3be5d584eb67e23bb37"
}
