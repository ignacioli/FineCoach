import XCTest

@testable import FineCoach

final class InsightPresentationTests: XCTestCase {
    private let studentID = StableUUID(UUID(uuidString: "aaaaaaaa-1111-4111-8111-111111111111")!)
    private let exerciseID = try! StableExerciseID("a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")

    private func check(
        _ insight: Insight, title: String, subtitle: String?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for context in InsightRowContent.Context.allCases {
            let content = InsightRowContent.make(
                insight: insight, studentName: "虚构学员", exerciseName: "虚构深蹲", context: context)
            XCTAssertEqual(
                content.title, context == .studentDetail ? title : "虚构学员 · \(title)", file: file, line: line)
            XCTAssertEqual(content.subtitle, subtitle, file: file, line: line)
            XCTAssertTrue(content.accessibilityLabel.contains("虚构学员"), file: file, line: line)
            XCTAssertTrue(content.accessibilityLabel.contains(title), file: file, line: line)
            if let subtitle {
                XCTAssertTrue(content.accessibilityLabel.contains(subtitle), file: file, line: line)
            }
        }
    }

    func testPackageCopyInEveryContext() throws {
        let date = try LocalDate(year: 2026, month: 10, day: 24)
        check(.init(kind: .packageExhausted, studentID: studentID, balance: 0), title: "课包已用完", subtitle: "余额 0 节")
        check(
            .init(kind: .packageExpired, studentID: studentID, balance: 4, packageEndDate: date),
            title: "课包已过期", subtitle: "有效期至 10月24日")
        check(
            .init(kind: .packageLow, studentID: studentID, balance: 2, packageEndDate: date, daysUntilExpiry: 7),
            title: "课包剩 2 节", subtitle: "有效期至 10月24日")
        check(
            .init(kind: .packageLow, studentID: studentID, balance: 1), title: "课包剩 1 节", subtitle: nil)
        check(
            .init(kind: .packageLow, studentID: studentID, balance: 4, packageEndDate: date, daysUntilExpiry: 7),
            title: "课包 7 天后到期", subtitle: "剩 4 节")
        check(
            .init(kind: .packageLow, studentID: studentID, balance: 4, packageEndDate: date, daysUntilExpiry: 0),
            title: "课包今天到期", subtitle: "剩 4 节")
        // Low balance takes precedence over expiry copy, including today.
        check(
            .init(kind: .packageLow, studentID: studentID, balance: 2, packageEndDate: date, daysUntilExpiry: 0),
            title: "课包剩 2 节", subtitle: "有效期至 10月24日")
    }

    func testInactivityCopyInEveryContext() {
        check(
            .init(kind: .inactive, studentID: studentID, daysInactive: 21),
            title: "21 天没来", subtitle: "也没约下次课")
        check(
            .init(kind: .inactive, studentID: studentID, daysInactive: 14, hasNeverTrained: true),
            title: "建档 14 天还没上过课", subtitle: "也没约下次课")
    }

    func testStagnationAllMetricsAndContextsWithDecimalFormatting() throws {
        let samples: [(Insight.Metric, String, String)] = [
            (.estimatedOneRepMax, "93.333333", "估算 1RM 93.3 kg"),
            (.estimatedOneRepMax, "100", "估算 1RM 100 kg"),
            (.highestWeight, "40.55", "最大 40.6 kg"),
            (.highestWeight, "80", "最大 80 kg"),
            (.lowestAssistance, "20.5", "最轻辅助 20.5 kg"),
            (.mostReps, "12", "最多 12 次"),
            (.longestDuration, "330", "最长 5 分 30 秒"),
        ]
        for (metric, value, best) in samples {
            let insight = Insight(
                kind: .stagnant, studentID: studentID, exerciseID: exerciseID, stagnantSessionCount: 3,
                baselineBest: try DecimalValue(value), baselineMetric: metric)
            for context in InsightRowContent.Context.allCases {
                let content = InsightRowContent.make(
                    insight: insight, studentName: "虚构学员", exerciseName: "虚构动作", context: context)
                switch context {
                case .today:
                    XCTAssertEqual(content.title, "虚构学员 · 虚构动作")
                    XCTAssertEqual(content.subtitle, "连续 3 节没有创新高")
                case .list:
                    XCTAssertEqual(content.title, "虚构学员 · 虚构动作")
                    XCTAssertEqual(content.subtitle, "连续 3 节没有创新高 · \(best)")
                case .studentDetail:
                    XCTAssertEqual(content.title, "虚构动作 · 连续 3 节没有创新高")
                    XCTAssertEqual(content.subtitle, best)
                }
                XCTAssertTrue(content.accessibilityLabel.hasPrefix("进步停滞，虚构学员，"))
                XCTAssertTrue(content.accessibilityLabel.contains("虚构动作"))
                XCTAssertTrue(content.accessibilityLabel.contains("连续 3 节没有创新高"))
            }
        }
    }

    func testTodayLimitAndAllEntryThresholdPreserveEngineOrder() {
        let rows: [Insight] = [
            .init(kind: .packageExhausted, studentID: studentID),
            .init(kind: .packageExpired, studentID: studentID),
            .init(kind: .inactive, studentID: studentID),
            .init(kind: .stagnant, studentID: studentID, exerciseID: exerciseID),
        ]
        for count in 0...4 {
            let selection = TodayInsightSelection(Array(rows.prefix(count)))
            XCTAssertEqual(selection.rows, Array(rows.prefix(min(count, 3))))
            XCTAssertEqual(selection.totalCount, count)
            XCTAssertEqual(selection.showsAll, count > 3)
        }
    }

    func testNavigationPrefillsStudentDateAndExerciseForEveryKind() throws {
        let today = try LocalDate(year: 2026, month: 10, day: 24)
        for kind: Insight.Kind in [.packageExhausted, .packageExpired, .packageLow] {
            XCTAssertEqual(
                InsightNavigation.destination(for: .init(kind: kind, studentID: studentID), today: today),
                .coursePackages(studentID.rawValue))
        }
        XCTAssertEqual(
            InsightNavigation.destination(for: .init(kind: .inactive, studentID: studentID), today: today),
            .appointmentEditor(.create(studentID: studentID.rawValue, date: today)))
        XCTAssertEqual(
            InsightNavigation.destination(
                for: .init(kind: .stagnant, studentID: studentID, exerciseID: exerciseID), today: today),
            .insightTrend(studentID: studentID.rawValue, exerciseID: exerciseID))
    }
}
