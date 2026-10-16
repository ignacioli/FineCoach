import FineCoach
import Foundation

/// Fictional archive data for M2 tests. Nothing here resembles a real person.
enum ArchiveFixtures {
    static let sourceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let studentArchiveID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    /// 2026-10-09T08:00:00.500Z (binary-exact fraction, so millisecond round trips are exact).
    static let snapshotAt = Date(timeIntervalSince1970: 1_791_532_800.5)
    static let password = "测试口令abcd"
    static let fixedSalt = Data(repeating: 0x11, count: 32)
    static let fixedNoncePrefix = Data(repeating: 0x44, count: 8)

    static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> LocalDate {
        try! LocalDate(year: year, month: month, day: dayOfMonth)
    }

    static func modules(
        displayName: Bool = true,
        sex: Bool = true,
        bodyData: Bool = true,
        trainingRecords: Bool = true,
        trends: Bool = true,
        summaries: Bool = true,
        exerciseInfo: Bool = true
    ) -> ArchiveModuleSet {
        try! ArchiveModuleSet(
            displayName: displayName,
            sex: sex,
            bodyData: bodyData,
            trainingRecords: trainingRecords,
            trends: trends,
            summaries: summaries,
            exerciseInfo: exerciseInfo
        )
    }

    static func manifest(
        modules: ArchiveModuleSet,
        counts: ArchiveCounts,
        snapshotAt: Date = ArchiveFixtures.snapshotAt,
        sourceID: UUID = ArchiveFixtures.sourceID,
        studentArchiveID: UUID = ArchiveFixtures.studentArchiveID
    ) -> ArchiveManifest {
        try! ArchiveManifest(
            sourceID: sourceID,
            studentArchiveID: studentArchiveID,
            snapshotAtUTC: snapshotAt,
            modules: modules,
            counts: counts
        )
    }

    static func decimal(_ raw: String) -> DecimalValue {
        try! DecimalValue(raw)
    }

    /// Full snapshot: every module selected, three exercise kinds, one assisted exercise,
    /// two sections (one unsectioned), a cardio entry, two body metrics.
    static func fullSnapshot(snapshotAt: Date = ArchiveFixtures.snapshotAt) -> ArchiveSnapshot {
        let exercises = [
            ArchiveExercise(
                key: "e1",
                placeholderNumber: 1,
                kind: .builtIn,
                isAssisted: false,
                info: ArchiveExerciseInfo(
                    name: "杠铃卧推",
                    primaryMuscles: ["胸"],
                    secondaryMuscles: ["肱三头肌", "三角肌前束"],
                    equipment: "杠铃"
                )
            ),
            ArchiveExercise(
                key: "e2",
                placeholderNumber: 2,
                kind: .custom,
                isAssisted: true,
                info: ArchiveExerciseInfo(
                    name: "辅助引体向上（示例）",
                    primaryMuscles: ["背"],
                    secondaryMuscles: [],
                    equipment: "固定器械"
                )
            ),
            ArchiveExercise(
                key: "e3",
                placeholderNumber: 3,
                kind: .oneOff,
                isAssisted: false,
                info: ArchiveExerciseInfo(name: "跑步机慢跑", primaryMuscles: [], secondaryMuscles: [], equipment: "其他")
            ),
        ]
        let session1 = ArchiveSession(
            key: "s1",
            localDate: day(2026, 9, 1),
            completedAtUTC: Date(timeIntervalSince1970: 1_788_246_000.25),
            durationMinutes: 62,
            trainingFocus: [.chest, .back],
            sections: [
                ArchiveSection(
                    name: "热身与主项",
                    exercises: [
                        ArchiveSessionExercise(
                            exerciseKey: "e1",
                            recordMode: .weightReps,
                            sets: [
                                ArchiveSet(
                                    weightValue: decimal("60"),
                                    repetitionCount: decimal("8"),
                                    unit: .kilograms
                                ),
                                ArchiveSet(
                                    weightValue: decimal("62.5"),
                                    repetitionCount: decimal("6"),
                                    unit: .kilograms
                                ),
                            ]
                        ),
                        ArchiveSessionExercise(
                            exerciseKey: "e2",
                            recordMode: .weightReps,
                            sets: [
                                ArchiveSet(
                                    weightValue: decimal("20"),
                                    repetitionCount: decimal("10"),
                                    unit: .kilograms,
                                    side: .bilateral
                                )
                            ]
                        ),
                    ]
                ),
                ArchiveSection(
                    name: nil,
                    exercises: [
                        ArchiveSessionExercise(
                            exerciseKey: "e3",
                            recordMode: .cardio,
                            sets: [
                                ArchiveSet(
                                    durationSeconds: decimal("900"),
                                    unit: .seconds,
                                    distanceValue: decimal("2.4"),
                                    speedValue: decimal("9.6"),
                                    resistanceValue: decimal("3")
                                )
                            ]
                        )
                    ]
                ),
            ]
        )
        let session2 = ArchiveSession(
            key: "s2",
            localDate: day(2026, 9, 8),
            completedAtUTC: Date(timeIntervalSince1970: 1_788_850_800.75),
            durationMinutes: 45,
            trainingFocus: [],
            sections: [
                ArchiveSection(
                    name: nil,
                    exercises: [
                        ArchiveSessionExercise(
                            exerciseKey: "e1",
                            recordMode: .weightReps,
                            sets: [
                                ArchiveSet(
                                    unit: .kilograms,
                                    side: .none,
                                    leftValue: decimal("12"),
                                    rightValue: decimal("12.5")
                                )
                            ]
                        )
                    ]
                )
            ]
        )
        let summaries = [
            try! ArchiveSummary(localDate: day(2026, 9, 1), sessionKey: "s1", text: "本节课状态良好，注意呼吸节奏。"),
            try! ArchiveSummary(localDate: day(2026, 9, 5), sessionKey: nil, text: "课外补充：多喝水 / hydrate."),
        ]
        let metrics = [
            try! ArchiveBodyMetric(key: "m1", kind: .builtIn(.weight)),
            try! ArchiveBodyMetric(key: "m2", kind: .custom, name: "颈围（示例）", unit: "cm"),
        ]
        let measurements = [
            ArchiveBodyMeasurement(
                metricKey: "m1", localDay: day(2026, 9, 1), value: decimal("70.5"), enteredUnit: "kg"),
            ArchiveBodyMeasurement(metricKey: "m1", localDay: day(2026, 9, 8), value: decimal("70"), enteredUnit: "kg"),
            ArchiveBodyMeasurement(metricKey: "m2", localDay: day(2026, 9, 8), value: decimal("34"), enteredUnit: "cm"),
        ]
        let attribution = ArchiveAttribution(
            sourceName: "示例动作库",
            licenseName: "示例许可证 1.0",
            licenseText: "https://example.invalid/license",
            exerciseKeys: ["e1"]
        )
        return assemble(
            modules: modules(),
            snapshotAt: snapshotAt,
            student: ArchiveStudent(displayName: "测试学员甲", sex: .female),
            exercises: exercises,
            sessions: [session1, session2],
            summaries: summaries,
            bodyMetrics: metrics,
            bodyMeasurements: measurements,
            attribution: attribution
        )
    }

    /// Builds a snapshot whose manifest counts match its content.
    static func assemble(
        modules: ArchiveModuleSet,
        snapshotAt: Date = ArchiveFixtures.snapshotAt,
        student: ArchiveStudent? = nil,
        exercises: [ArchiveExercise] = [],
        sessions: [ArchiveSession] = [],
        summaries: [ArchiveSummary] = [],
        bodyMetrics: [ArchiveBodyMetric] = [],
        bodyMeasurements: [ArchiveBodyMeasurement] = [],
        attribution: ArchiveAttribution? = nil
    ) -> ArchiveSnapshot {
        let counts = ArchiveCounts(
            student: student == nil ? 0 : 1,
            exercise: exercises.count,
            session: sessions.count,
            summary: summaries.count,
            bodyMetric: bodyMetrics.count,
            bodyMeasurement: bodyMeasurements.count,
            attribution: attribution == nil ? 0 : 1
        )
        return ArchiveSnapshot(
            manifest: manifest(modules: modules, counts: counts, snapshotAt: snapshotAt),
            student: student,
            exercises: exercises,
            sessions: sessions,
            summaries: summaries,
            bodyMetrics: bodyMetrics,
            bodyMeasurements: bodyMeasurements,
            attribution: attribution
        )
    }

    /// Smallest valid snapshot: only the summaries module.
    static func summariesOnlySnapshot(snapshotAt: Date = ArchiveFixtures.snapshotAt) -> ArchiveSnapshot {
        assemble(
            modules: modules(
                displayName: false,
                sex: false,
                bodyData: false,
                trainingRecords: false,
                trends: false,
                summaries: true,
                exerciseInfo: false
            ),
            snapshotAt: snapshotAt,
            summaries: [try! ArchiveSummary(localDate: day(2026, 9, 1), sessionKey: nil, text: "示例")]
        )
    }

    // MARK: Raw payload helpers

    static func frame(_ sectionID: UInt16, _ json: String) -> Data {
        frame(sectionID, Data(json.utf8))
    }

    static func frame(_ sectionID: UInt16, _ json: Data) -> Data {
        var data = Data()
        data.append(UInt8(sectionID >> 8))
        data.append(UInt8(sectionID & 0xFF))
        let length = UInt32(json.count)
        data.append(UInt8(truncatingIfNeeded: length >> 24))
        data.append(UInt8(truncatingIfNeeded: length >> 16))
        data.append(UInt8(truncatingIfNeeded: length >> 8))
        data.append(UInt8(truncatingIfNeeded: length))
        data.append(json)
        return data
    }

    /// Re-frames the payload of `snapshot`, giving each frame's decoded JSON object to
    /// `transform` (section ID, mutable object). Frames are re-emitted with sorted keys.
    static func payload(
        of snapshot: ArchiveSnapshot,
        transform: (UInt16, inout [String: Any]) -> Void = { _, _ in }
    ) throws -> (plaintext: Data, frameCount: UInt64) {
        let encoded = try ArchiveFileCodec.encodePayload(snapshot)
        var out = Data()
        var offset = 0
        var count: UInt64 = 0
        let bytes = encoded.plaintext
        while offset < bytes.count {
            let id = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            let length =
                Int(bytes[offset + 2]) << 24 | Int(bytes[offset + 3]) << 16 | Int(bytes[offset + 4]) << 8
                | Int(bytes[offset + 5])
            let json = bytes.subdata(in: (offset + 6)..<(offset + 6 + length))
            var object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
            transform(id, &object)
            out.append(frame(id, try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])))
            offset += 6 + length
            count += 1
        }
        return (out, count)
    }
}

extension Data {
    init(archiveHex hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }

    var archiveHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
