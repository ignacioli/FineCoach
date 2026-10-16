#if DEBUG
    import CoreData
    import XCTest

    @testable import FineCoach

    /// T063 (US-5, AC-011, SC-007): the archive exported with and without 「动作资料」, through a real
    /// on-disk Core Data store, the real file codec and a real temporary directory. The decoded
    /// payload is re-framed and its JSON inspected: neither archive may carry an image, a data URL
    /// or a remote URL field; with exercise info every built-in exercise is attributed, without it
    /// the archive holds no exercise name, muscle or equipment. All data is fictional.
    final class ArchiveExerciseInfoIntegrationTests: XCTestCase {
        private typealias X = ArchiveExportFixtures
        private let password = "长度足够的口令abc"

        /// Field names that would carry media or a remote reference. Matched case-insensitively
        /// as substrings of every JSON key in every frame.
        private let mediaKeyFragments = [
            "image", "img", "icon", "photo", "picture", "thumb", "media", "video", "gif", "animation",
            "url", "uri", "href", "link", "src", "remote", "asset",
        ]

        /// The only fields an exercise frame may have (data-model §1).
        private let exerciseFrameKeys: Set<String> = [
            "key", "placeholderNumber", "kind", "isAssisted", "name", "primaryMuscles", "secondaryMuscles",
            "equipment",
        ]

        private struct Exported {
            let snapshot: ArchiveSnapshot
            /// The decoded snapshot re-framed: the JSON of every frame, by section.
            let frames: [(section: ArchiveFileV1.Section, json: Any)]
            let plaintext: String
        }

        private func export(exerciseInfo: Bool) async throws -> Exported {
            let store = try X.Store(inMemory: false)
            try await X.seed(store)
            let tempRoot = try TemporaryProtectedDirectory()
            let share = ScriptedSharePresenter([.completed])
            let calendar = TestCalendarProvider(timeZone: X.shanghai)
            let useCases = ArchiveExportUseCases(
                sourceReader: ArchiveExportSourceReader(writer: store.writer, calendarProvider: calendar),
                identity: ArchiveIdentityService(writer: store.writer),
                share: SystemShareAdapter(presenter: share),
                tempRootURL: tempRoot.url,
                clock: TestClock(utcDate: X.now),
                calendarProvider: calendar,
                logger: RecordingLogger()
            )
            let flow = try await useCases.beginFlow(studentID: X.studentID)
            if !exerciseInfo {
                _ = try await flow.setSelected(false, item: .exerciseInfo)
            }
            _ = try await flow.preview()
            try await flow.confirmPreview()
            try await flow.confirmFacts()
            let generated = try await flow.submitPassword(password, confirmation: password)
            XCTAssertEqual(generated, .generated)
            let delivered = try await flow.deliver()
            XCTAssertEqual(delivered, .handedToSystem)

            let file = try XCTUnwrap(share.presentedData.first ?? nil)
            let snapshot = try ArchiveFileCodec.decode(file: file, password: try ArchivePassword(importing: password))
            return Exported(
                snapshot: snapshot, frames: try Self.frames(of: snapshot), plaintext: try Self.plaintext(of: snapshot))
        }

        private static func plaintext(of snapshot: ArchiveSnapshot) throws -> String {
            String(decoding: try ArchiveFileCodec.encodePayload(snapshot).plaintext, as: UTF8.self)
        }

        /// Walks the framed plaintext: `section (2 bytes BE) · length (4 bytes BE) · JSON`.
        private static func frames(of snapshot: ArchiveSnapshot) throws -> [(ArchiveFileV1.Section, Any)] {
            let data = try ArchiveFileCodec.encodePayload(snapshot).plaintext
            var frames: [(ArchiveFileV1.Section, Any)] = []
            var offset = 0
            while offset < data.count {
                let raw = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
                let length = data[(offset + 2)..<(offset + 6)].reduce(0) { ($0 << 8) | Int($1) }
                let json = try JSONSerialization.jsonObject(with: data[(offset + 6)..<(offset + 6 + length)])
                frames.append((try XCTUnwrap(ArchiveFileV1.Section(rawValue: raw)), json))
                offset += 6 + length
            }
            return frames
        }

        private func allKeys(_ value: Any) -> [String] {
            if let object = value as? [String: Any] {
                return object.keys + object.values.flatMap(allKeys)
            }
            if let array = value as? [Any] {
                return array.flatMap(allKeys)
            }
            return []
        }

        private func allStrings(_ value: Any) -> [String] {
            if let text = value as? String { return [text] }
            if let object = value as? [String: Any] { return object.values.flatMap(allStrings) }
            if let array = value as? [Any] { return array.flatMap(allStrings) }
            return []
        }

        /// AC-011 / SC-007: no media or remote-reference field, in either archive.
        private func assertNoMediaOrRemoteReference(_ exported: Exported, _ label: String) {
            for (section, json) in exported.frames {
                for key in allKeys(json) {
                    for fragment in mediaKeyFragments {
                        XCTAssertFalse(
                            key.lowercased().contains(fragment), "\(label): \(section) frame has field \(key)")
                    }
                }
                for text in allStrings(json) {
                    XCTAssertFalse(text.lowercased().hasPrefix("data:"), "\(label): \(section) holds a data URL")
                    // The attribution frame's `licenseText` is the licence's link text (contract §4)
                    // and is the one place a web address may appear, as text.
                    if section != .attribution {
                        XCTAssertFalse(text.contains("://"), "\(label): \(section) holds a URL: \(text)")
                    }
                }
            }
            XCTAssertFalse(exported.plaintext.contains("base64"), label)
            XCTAssertFalse(exported.plaintext.contains("data:image"), label)
        }

        func testExportWithExerciseInfoIsTextOnlyAndEveryBuiltInExerciseIsAttributed() async throws {
            let exported = try await export(exerciseInfo: true)
            let snapshot = exported.snapshot
            XCTAssertTrue(snapshot.manifest.modules.exerciseInfo)
            assertNoMediaOrRemoteReference(exported, "with exercise info")

            // Names, muscles and equipment are there, nothing else.
            XCTAssertFalse(snapshot.exercises.isEmpty)
            XCTAssertTrue(snapshot.exercises.allSatisfy { $0.info != nil })
            let names = Set(snapshot.exercises.compactMap(\.info?.name))
            XCTAssertTrue(names.isSuperset(of: [X.builtInName, X.secondBuiltInName, X.customExerciseName]))
            for (section, json) in exported.frames where section == .exercise {
                let keys = Set(try XCTUnwrap(json as? [String: Any]).keys)
                XCTAssertTrue(keys.isSubset(of: exerciseFrameKeys), "unexpected exercise fields: \(keys)")
            }

            // Every built-in exercise carries the attribution; custom and one-off ones do not.
            let attribution = try XCTUnwrap(snapshot.attribution)
            let builtInKeys = snapshot.exercises.filter { $0.kind == .builtIn }.map(\.key)
            XCTAssertFalse(builtInKeys.isEmpty)
            XCTAssertEqual(Set(attribution.exerciseKeys), Set(builtInKeys))
            XCTAssertEqual(attribution.exerciseKeys.count, builtInKeys.count, "no duplicates, none missing")
            XCTAssertEqual(attribution.sourceName, "wger.de")
            XCTAssertFalse(attribution.licenseName.isEmpty)
            XCTAssertEqual(snapshot.manifest.counts.attribution, 1)
            XCTAssertEqual(exported.frames.filter { $0.section == .attribution }.count, 1)
            for (_, json) in exported.frames.filter({ $0.section == .attribution }) {
                XCTAssertEqual(
                    Set(try XCTUnwrap(json as? [String: Any]).keys),
                    ["sourceName", "licenseName", "licenseText", "exerciseKeys"])
            }
        }

        func testExportWithoutExerciseInfoHasNoExerciseNamesMusclesEquipmentOrAttribution() async throws {
            let exported = try await export(exerciseInfo: false)
            let snapshot = exported.snapshot
            XCTAssertFalse(snapshot.manifest.modules.exerciseInfo)
            XCTAssertTrue(snapshot.manifest.modules.trainingRecords, "records stay; only the exercise info is left out")
            assertNoMediaOrRemoteReference(exported, "without exercise info")

            // Exercises are bare placeholders: no name, muscle or equipment field in any frame.
            XCTAssertFalse(snapshot.exercises.isEmpty)
            XCTAssertTrue(snapshot.exercises.allSatisfy { $0.info == nil })
            for (section, json) in exported.frames where section == .exercise {
                let keys = Set(try XCTUnwrap(json as? [String: Any]).keys)
                XCTAssertEqual(keys, ["key", "placeholderNumber", "kind", "isAssisted"])
            }
            for text in [X.builtInName, X.secondBuiltInName, X.customExerciseName] + X.oneOffNames {
                XCTAssertFalse(exported.plaintext.contains(text), "archive holds the exercise name \(text)")
            }
            for equipment in ["杠铃", "哑铃", ArchiveExportPolicy.unknownEquipment] {
                XCTAssertFalse(
                    exported.plaintext.contains("\"equipment\":\"\(equipment)\""), "archive holds equipment")
            }

            // Built-in content is absent, so there is nothing to attribute.
            XCTAssertNil(snapshot.attribution)
            XCTAssertEqual(snapshot.manifest.counts.attribution, 0)
            XCTAssertTrue(exported.frames.allSatisfy { $0.section != .attribution })
            XCTAssertFalse(exported.plaintext.contains("wger"))
        }

        func testViewerShowsNoExerciseListWithoutExerciseInfoAndNamesWithIt() async throws {
            let with = ArchiveViewerContent(snapshot: try await export(exerciseInfo: true).snapshot)
            let entries = try with.exercises()
            XCTAssertTrue(with.hasExerciseInfo)
            XCTAssertTrue(entries.contains { ArchiveViewerPresentation.exerciseName($0) == X.builtInName })
            XCTAssertTrue(entries.allSatisfy { ArchiveViewerPresentation.exerciseMeta($0) != nil })

            let without = ArchiveViewerContent(snapshot: try await export(exerciseInfo: false).snapshot)
            XCTAssertFalse(without.hasExerciseInfo)
            let placeholders = try without.exercises().map(ArchiveViewerPresentation.exerciseName)
            XCTAssertTrue(placeholders.allSatisfy { $0.hasPrefix("动作 ") }, "\(placeholders)")
            XCTAssertTrue(
                try without.exercises().allSatisfy {
                    ArchiveViewerPresentation.exerciseMeta($0) == nil || $0.kind != .builtIn
                })
        }
    }
#endif
