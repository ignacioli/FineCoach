import Foundation
import os

// DEBUG-only seed for the human review of the M2 export screens (tasks T038). All data is
// fictional. Launch with `-FineCoachSeedArchiveExport` (add `-FineCoachResetStore` to start from
// an empty store; an existing non-empty store is left untouched). Not compiled into Release.
#if DEBUG
    enum ArchiveExportDebugSeed {
        static let launchArgument = "-FineCoachSeedArchiveExport"

        /// Seconds the seed clock runs behind real time while sessions are being recorded, so the
        /// completed sessions land on different days. Zero outside seeding.
        private static let offsetSeconds = OSAllocatedUnfairLock(initialState: 0.0)

        static var isRequested: Bool {
            ProcessInfo.processInfo.arguments.contains(launchArgument)
        }

        static func makeClock() -> SystemClock {
            SystemClock(wallClock: { Date().addingTimeInterval(-offsetSeconds.withLock { $0 }) })
        }

        private static func setDaysAgo(_ days: Int) {
            offsetSeconds.withLock { $0 = Double(days) * 86_400 }
        }

        private static let benchID = StableExerciseID(rawValue: "3717d144-7815-4a97-9a56-956fb889c996")!
        private static let squatID = StableExerciseID(rawValue: "a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")!
        private static let inclineID = StableExerciseID(rawValue: "275fb49f-975c-4d6e-9d63-2c86ed740f40")!

        /// One fictional student with a display name, sex, six completed sessions (built-in,
        /// custom and one-off exercises), three student summaries, and body metrics. Injury note,
        /// coach private note and contact fields are filled in so the reviewer can see they are
        /// absent from the export.
        /// Returns `false` when seeding stopped early; an existing non-empty store counts as done.
        @MainActor
        @discardableResult
        static func seed(in environment: AppEnvironment) async -> Bool {
            guard let students = environment.studentUseCases,
                let sessions = environment.sessionUseCases,
                let exercises = environment.exerciseUseCases,
                let history = environment.historyUseCases,
                let body = environment.bodyDataUseCases
            else {
                return false
            }
            defer { setDaysAgo(0) }
            do {
                if try await !students.searchActive(query: "").isEmpty {
                    try await students.completeOnboarding()
                    return true
                }
                try await students.completeOnboarding()
                try await exercises.seedIfNeeded()
                let student = try await students.create(
                    draft: StudentDraft(
                        displayName: "王小明",
                        sex: .male,
                        trainingGoal: "合成测试目标：增肌",
                        injuryNotes: "合成测试备注：左膝旧伤，避免深蹲过低。",
                        privateCoachNote: "合成测试备注：偏好电话沟通。",
                        phone: "13800138000",
                        wechatID: "synthetic_wechat"
                    )
                )

                // (days ago, catalog exercises, extra exercise, summary)
                let plan: [(Int, [StableExerciseID], Extra?, String?)] = [
                    (35, [benchID, squatID], nil, nil),
                    (28, [benchID, inclineID], .custom("弹力带侧走"), "今天深蹲感觉膝盖比上周稳，最后一组有点吃力。"),
                    (21, [squatID, benchID], .oneOff("手腕灵活性练习"), nil),
                    (14, [benchID, squatID], nil, "睡得不太好，热身多做了五分钟。"),
                    (7, [inclineID, benchID], .oneOff("平衡垫单腿站"), nil),
                    (1, [benchID, squatID], nil, "第一次做到 90kg × 8，很开心！"),
                ]
                for (index, entry) in plan.enumerated() {
                    setDaysAgo(entry.0)
                    _ = try await sessions.startOrOpen(studentID: student.id)
                    for catalogID in entry.1 {
                        let session = try await sessions.addCatalogExercise(itemID: catalogID)
                        try await recordSets(session, base: 50 + index * 5, using: sessions)
                    }
                    switch entry.2 {
                    case .custom(let name):
                        let session = try await sessions.addCustomToLibraryAndSession(name: name, recordMode: .weightReps)
                        try await recordSets(session, base: 10, using: sessions)
                    case .oneOff(let name):
                        let session = try await sessions.addSessionOnlyExercise(displayName: name, recordMode: .weightReps)
                        try await recordSets(session, base: 16, using: sessions)
                    case nil:
                        break
                    }
                    let finished = try await sessions.finish()
                    _ = try await history.saveSummaryNotes(
                        sessionID: finished.id,
                        trainingFocus: [.chest, .thighs],
                        privateCoachNote: "合成测试备注：教练私有记录。",
                        studentFacingSummary: entry.3 ?? ""
                    )
                }
                setDaysAgo(0)

                let shoulder = try await body.createCustomMetric(studentID: student.id, name: "肩宽", unit: "cm")
                let now = Date()
                func day(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }
                for (days, value) in [(30, "70.5"), (15, "69.8"), (2, "69.2")] {
                    try await body.recordMeasurement(
                        studentID: student.id, metricID: BuiltInBodyMetric.weight.id,
                        value: value, enteredUnit: "kg", at: day(days))
                }
                for (days, value) in [(30, "18.5"), (2, "17.9")] {
                    try await body.recordMeasurement(
                        studentID: student.id, metricID: BuiltInBodyMetric.bodyFatPercent.id,
                        value: value, enteredUnit: "%", at: day(days))
                }
                for (days, value) in [(30, "44"), (2, "44.5")] {
                    try await body.recordMeasurement(
                        studentID: student.id, metricID: shoulder.id,
                        value: value, enteredUnit: "cm", at: day(days))
                }
                return true
            } catch {
                return false
            }
        }

        private enum Extra {
            case custom(String)
            case oneOff(String)
        }

        @MainActor
        private static func recordSets(_ session: Session, base: Int, using sessions: ActiveSessionUseCases) async throws {
            guard let exerciseID = session.exercises.last?.id else {
                return
            }
            for offset in 0..<3 {
                let added = try await sessions.addSet(
                    exerciseID: exerciseID,
                    input: TrainingSetInput(
                        recordMode: .weightReps,
                        weightValue: String(base + offset * 2),
                        repetitionCount: "8",
                        unit: .kilograms
                    )
                )
                if let setID = added.exercises.last?.sets.last?.id {
                    _ = try await sessions.confirmSet(setID: setID)
                }
            }
        }
    }
#endif
