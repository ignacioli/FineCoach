#if DEBUG
    import XCTest

    @testable import FineCoach

    final class InsightsDemoSeedTests: XCTestCase {
        @MainActor
        func testSeedAppendsFiveInsightsAndIsIdempotent() async throws {
            let root = try TemporaryProtectedDirectory()
            let clock = ArchiveExportDebugSeed.makeClock()
            let environment = try AppEnvironment(
                rootURL: root.url, clock: clock, notificationCenter: FakeNotificationScheduling(),
                sessionActivityController: NoopSessionActivityController())
            let students = try XCTUnwrap(environment.studentUseCases)
            let unrelated = try await students.create(
                draft: StudentDraft(displayName: "虚构无关学员", sex: .undisclosed))
            let seeded = await ArchiveExportDebugSeed.seedInsightsDemo(in: environment)
            XCTAssertTrue(seeded)
            let roster = try await students.searchActive(query: "")
            XCTAssertEqual(roster.count, 6)
            XCTAssertEqual(roster.first { $0.id == unrelated.id }, unrelated)
            let insights = InsightUseCases(
                students: students, history: try XCTUnwrap(environment.historyUseCases),
                appointments: try XCTUnwrap(environment.appointmentUseCases),
                credits: try XCTUnwrap(environment.creditLedgerUseCases),
                exercises: try XCTUnwrap(environment.exerciseUseCases),
                snoozes: InsightSnoozeStore(directory: root.url))
            let now = Date()
            let output = try await insights.load(now: now)
            XCTAssertEqual(output.count, 5)
            func insight(_ name: String, kind: Insight.Kind) throws -> Insight {
                let student = try XCTUnwrap(roster.first { $0.displayName.value == name })
                let matches = output.filter { $0.studentID == student.id }
                XCTAssertEqual(matches.count, 1, name)
                let value = try XCTUnwrap(matches.first)
                XCTAssertEqual(value.kind, kind, name)
                return value
            }
            let stagnant = try insight("吴停滞", kind: .stagnant)
            let squatID = try StableExerciseID("a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")
            XCTAssertEqual(stagnant.exerciseID, squatID)
            XCTAssertEqual(stagnant.baselineMetric, .estimatedOneRepMax)
            XCTAssertEqual(stagnant.stagnantSessionCount, 3)
            let baseline = try XCTUnwrap(stagnant.baselineBest)
            XCTAssertEqual(
                NSDecimalNumber(decimal: baseline.decimal).doubleValue, 64 * (1 + 8.0 / 30), accuracy: 0.0001)
            let low = try insight("郑快用完", kind: .packageLow)
            XCTAssertEqual(low.balance, 1)
            XCTAssertNil(low.daysUntilExpiry)
            let expiring = try insight("钱快到期", kind: .packageLow)
            XCTAssertEqual(expiring.balance, 8)
            XCTAssertEqual(expiring.daysUntilExpiry, 3)
            XCTAssertEqual(try insight("林已用完", kind: .packageExhausted).balance, 0)
            let inactive = try insight("冯很久没来", kind: .inactive)
            XCTAssertEqual(inactive.daysInactive, 20)
            XCTAssertFalse(inactive.hasNeverTrained)
            XCTAssertLessThan(abs(clock.nowUTC().timeIntervalSinceNow), 2)
            let seededAgain = await ArchiveExportDebugSeed.seedInsightsDemo(in: environment)
            XCTAssertTrue(seededAgain)
            let repeatedRoster = try await students.searchActive(query: "")
            XCTAssertEqual(Set(repeatedRoster.map(\.id)), Set(roster.map(\.id)))
            XCTAssertEqual(repeatedRoster.first { $0.id == unrelated.id }, unrelated)
            let repeatedOutput = try await insights.load(now: now)
            XCTAssertEqual(repeatedOutput, output)
        }
    }
#endif
