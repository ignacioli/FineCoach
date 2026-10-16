import Foundation
import os

// DEBUG-only seed for the human review of the M2 export screens (tasks T038) and an M1 UI
// regression walkthrough (several fictional students, packages, appointments, templates). All
// data is fictional. Launch with `-FineCoachSeedArchiveExport` (add `-FineCoachResetStore` to start from
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

        /// Seeds the review roster: 王小明 (M2-02 export review fixture: one student with a display
        /// name, sex, six completed sessions, three summaries, body metrics) plus the M1 walkthrough
        /// students listed in `seedMoreStudents`. Injury note, coach private note and contact
        /// fields are filled in so the reviewer can see they are absent from the export.
        /// Returns `false` when seeding stopped early; an existing non-empty store counts as done.
        @MainActor
        @discardableResult
        static func seed(in environment: AppEnvironment) async -> Bool {
            guard let students = environment.studentUseCases,
                let sessions = environment.sessionUseCases,
                let exercises = environment.exerciseUseCases,
                let history = environment.historyUseCases,
                let body = environment.bodyDataUseCases,
                let appointments = environment.appointmentUseCases,
                let credits = environment.creditLedgerUseCases,
                let templates = environment.templateUseCases
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
                try await seedReviewStudent(students: students, sessions: sessions, history: history, body: body)
                try await seedMoreStudents(
                    students: students, sessions: sessions, history: history, body: body,
                    appointments: appointments, credits: credits, templates: templates)
                // A leftover in-progress training would block every other flow.
                return try await students.inProgressTraining() == nil
            } catch {
                return false
            }
        }

        @MainActor
        private static func seedReviewStudent(
            students: StudentUseCases,
            sessions: ActiveSessionUseCases,
            history: HistoryUseCases,
            body: BodyDataUseCases
        ) async throws {
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
        }

        // MARK: M1 walkthrough roster

        /// Fictional students for the M1 UI regression walkthrough. Names, phones (13800138xxx
        /// placeholders) and WeChat IDs are synthetic. Only catalog exercises are used here: custom
        /// and one-off exercise names share one global namespace with the catalog, and a collision
        /// aborts the whole seed.
        ///
        /// - 李思远: active 10-credit package (5 used: 4 past sessions + today's completed
        ///   appointment), weekly series of 6 starting today 18:00.
        /// - 陈嘉怡: 3-credit package fully used (balance 0 -> low-balance alert), absent today
        ///   09:00 (not charged), one scheduled appointment in 2 days.
        /// - 欧阳慕容雪莉安娜·德拉克鲁瓦-史密斯（长名字换行测试）: sex 其他, expired package
        ///   (end date in the past), cancelled-with-reason appointment today 11:00.
        /// - 张浩然: no package, four sessions with summaries, body measurements, scheduled today
        ///   13:00 plus an every-two-days series from tomorrow; source of one saved template.
        /// - 赵无数: sex undisclosed, no other data (empty states), scheduled today 15:30.
        /// - 孙已归档: two sessions, then archived.
        /// - Templates: 「推日·胸肩」 (saved from 张浩然's last session) and 「腿日基础」 (blank + exercises).
        @MainActor
        private static func seedMoreStudents(
            students: StudentUseCases,
            sessions: ActiveSessionUseCases,
            history: HistoryUseCases,
            body: BodyDataUseCases,
            appointments: AppointmentUseCases,
            credits: CreditLedgerUseCases,
            templates: TemplateUseCases
        ) async throws {
            let calendar = Calendar.current
            let today = appointments.todayLocalDate()
            func at(_ hour: Int, _ minute: Int = 0) throws -> LocalTime { try LocalTime(hour: hour, minute: minute) }

            // 李思远
            let siyuan = try await students.create(
                draft: StudentDraft(
                    displayName: "李思远", sex: .male, trainingGoal: "合成测试目标：减脂塑形",
                    injuryNotes: "", privateCoachNote: "合成测试备注：喜欢早上训练。",
                    phone: "13800138001", wechatID: "synthetic_lisiyuan"))
            let siyuanPackage = try await credits.createActivePackage(
                studentID: siyuan.id, name: "私教 10 次卡", totalCredits: 10,
                startDate: today.addingDays(-30, calendar: calendar),
                endDate: today.addingDays(60, calendar: calendar))
            for (index, days) in [24, 17, 10, 3].enumerated() {
                setDaysAgo(days)
                let finished = try await trainedSession(
                    studentID: siyuan.id, exercises: [squatID, benchID], base: 40 + index * 5, using: sessions)
                try await credits.debitOnSessionComplete(packageID: siyuanPackage.id, sessionID: finished.id)
            }
            setDaysAgo(0)
            // Today 07:00, completed through the real appointment -> training flow.
            let completedToday = try await appointments.createSingle(
                studentID: siyuan.id, date: today, startTime: try at(7), reminderEnabled: false,
                reminderLeadMinutes: nil, trainingFocus: [.thighs, .chest], overrideConflict: false)
            _ = try await appointments.startTraining(appointmentID: completedToday.id)
            let completedSession = try await trainedSession(
                studentID: siyuan.id, exercises: [squatID, inclineID], base: 60, using: sessions)
            _ = try await appointments.completeSession(appointmentID: completedToday.id)
            try await credits.debitOnSessionComplete(packageID: siyuanPackage.id, sessionID: completedSession.id)
            _ = try await appointments.createRecurring(
                studentID: siyuan.id,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyWeek, termination: .repeatCount(6), firstOccurrenceDate: today,
                    startTime: try at(18), trainingFocus: [.thighs, .glutes]),
                overrideConflict: false)

            // 陈嘉怡
            let jiayi = try await students.create(
                draft: StudentDraft(
                    displayName: "陈嘉怡", sex: .female, trainingGoal: "合成测试目标：体态改善",
                    phone: "13800138002", wechatID: "synthetic_chenjiayi"))
            let jiayiPackage = try await credits.createActivePackage(
                studentID: jiayi.id, name: "体验 3 次卡", totalCredits: 3,
                startDate: today.addingDays(-20, calendar: calendar),
                endDate: today.addingDays(30, calendar: calendar))
            for days in [14, 8, 2] {
                setDaysAgo(days)
                let finished = try await trainedSession(
                    studentID: jiayi.id, exercises: [inclineID], base: 20, using: sessions)
                try await credits.debitOnSessionComplete(packageID: jiayiPackage.id, sessionID: finished.id)
            }
            setDaysAgo(0)
            let absent = try await appointments.createSingle(
                studentID: jiayi.id, date: today, startTime: try at(9), reminderEnabled: false,
                reminderLeadMinutes: nil, overrideConflict: false)
            _ = try await appointments.markAbsent(appointmentID: absent.id, creditChoice: .notCharged)
            _ = try await appointments.createSingle(
                studentID: jiayi.id, date: today.addingDays(2, calendar: calendar), startTime: try at(15),
                trainingFocus: [.back], overrideConflict: false)

            // Long display name + expired package
            let longName = try await students.create(
                draft: StudentDraft(
                    displayName: "欧阳慕容雪莉安娜·德拉克鲁瓦-史密斯（长名字换行测试）", sex: .other,
                    trainingGoal: "合成测试目标：一个很长很长很长很长很长很长很长很长很长的训练目标描述，用来检查多行换行。",
                    phone: "13800138003", wechatID: "synthetic_long_name"))
            let longPackage = try await credits.createActivePackage(
                studentID: longName.id, name: "已过期的五次卡", totalCredits: 5,
                startDate: today.addingDays(-60, calendar: calendar),
                endDate: today.addingDays(-3, calendar: calendar))
            setDaysAgo(40)
            let longSession = try await trainedSession(
                studentID: longName.id, exercises: [benchID], base: 30, using: sessions)
            try await credits.debitOnSessionComplete(packageID: longPackage.id, sessionID: longSession.id)
            setDaysAgo(0)
            let cancelled = try await appointments.createSingle(
                studentID: longName.id, date: today, startTime: try at(11), reminderEnabled: false,
                reminderLeadMinutes: nil, overrideConflict: false)
            _ = try await appointments.cancel(appointmentID: cancelled.id, reason: "合成测试：学员临时有事")

            // 张浩然: sessions, summaries, body data, appointments, template source
            let haoran = try await students.create(
                draft: StudentDraft(
                    displayName: "张浩然", sex: .male, trainingGoal: "合成测试目标：增肌增重",
                    injuryNotes: "合成测试备注：右肩轻微不适。", phone: "13800138004",
                    wechatID: "synthetic_zhanghaoran"))
            var lastHaoranSession: Session?
            for (index, days) in [20, 13, 6, 2].enumerated() {
                setDaysAgo(days)
                let finished = try await trainedSession(
                    studentID: haoran.id, exercises: [benchID, inclineID, squatID], base: 55 + index * 5,
                    using: sessions)
                _ = try await history.saveSummaryNotes(
                    sessionID: finished.id, trainingFocus: [.chest, .shoulders],
                    privateCoachNote: "合成测试备注：教练私有记录。",
                    studentFacingSummary: index % 2 == 0 ? "" : "合成测试总结：本周重量稳步提升。")
                lastHaoranSession = finished
            }
            setDaysAgo(0)
            let now = Date()
            func day(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }
            let measurements: [(BuiltInBodyMetric, String, [(Int, String)])] = [
                (.weight, "kg", [(28, "72.0"), (20, "72.8"), (13, "73.4"), (6, "73.9"), (1, "74.5")]),
                (.bodyFatPercent, "%", [(28, "16.2"), (13, "15.8"), (1, "15.1")]),
                (.waist, "cm", [(28, "80"), (1, "79")]),
                (.height, "cm", [(28, "178")]),
            ]
            for (metric, unit, points) in measurements {
                for (days, value) in points {
                    try await body.recordMeasurement(
                        studentID: haoran.id, metricID: metric.id, value: value, enteredUnit: unit, at: day(days))
                }
            }
            _ = try await appointments.createSingle(
                studentID: haoran.id, date: today, startTime: try at(13), trainingFocus: [.chest],
                overrideConflict: false)
            _ = try await appointments.createRecurring(
                studentID: haoran.id,
                draft: RecurringAppointmentDraft(
                    intervalDays: .everyTwoDays, termination: .repeatCount(4),
                    firstOccurrenceDate: today.addingDays(1, calendar: calendar), startTime: try at(10),
                    trainingFocus: [.back, .arms]),
                overrideConflict: false)
            if let lastHaoranSession {
                let sections = try await templates.sessionSections(sessionID: lastHaoranSession.id)
                try await templates.saveAsTemplate(
                    from: lastHaoranSession, existingSessionSections: sections, name: "推日·胸肩",
                    trainingFocus: [.chest, .shoulders])
            }
            let legDay = try await templates.createBlankTemplate(name: "腿日基础", trainingFocus: [.thighs, .glutes])
            try await templates.addExercise(templateID: legDay.id, displayName: "杠铃深蹲", recordMode: .weightReps)
            try await templates.addExercise(templateID: legDay.id, displayName: "罗马尼亚硬拉", recordMode: .weightReps)

            // 赵无数: almost no data
            let empty = try await students.create(
                draft: StudentDraft(displayName: "赵无数", sex: .undisclosed))
            _ = try await appointments.createSingle(
                studentID: empty.id, date: today, startTime: try at(15, 30), overrideConflict: false)

            // 孙已归档
            let archived = try await students.create(
                draft: StudentDraft(
                    displayName: "孙已归档", sex: .female, trainingGoal: "合成测试目标：已停课",
                    phone: "13800138005", wechatID: "synthetic_sun_archived"))
            for days in [50, 45] {
                setDaysAgo(days)
                _ = try await trainedSession(
                    studentID: archived.id, exercises: [squatID], base: 35, using: sessions)
            }
            setDaysAgo(0)
            _ = try await students.archive(id: archived.id)
        }

        /// Starts (or reopens) the active session, records three confirmed sets per catalog
        /// exercise, finishes it, and returns the completed session.
        @MainActor
        private static func trainedSession(
            studentID: StableUUID,
            exercises: [StableExerciseID],
            base: Int,
            using sessions: ActiveSessionUseCases
        ) async throws -> Session {
            _ = try await sessions.startOrOpen(studentID: studentID)
            for catalogID in exercises {
                let session = try await sessions.addCatalogExercise(itemID: catalogID)
                try await recordSets(session, base: base, using: sessions)
            }
            return try await sessions.finish()
        }

        private enum Extra {
            case custom(String)
            case oneOff(String)
        }

        @MainActor
        private static func recordSets(_ session: Session, base: Int, using sessions: ActiveSessionUseCases)
            async throws
        {
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
