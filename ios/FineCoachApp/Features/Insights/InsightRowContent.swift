import Foundation

struct InsightRowContent: Equatable {
    enum Context: CaseIterable {
        case today, list, studentDetail
    }

    let title: String
    let subtitle: String?
    let accessibilityLabel: String

    static func make(
        insight: Insight, studentName: String, exerciseName: String, context: Context
    ) -> Self {
        func text(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }
        func number(_ key: String, _ value: Int?) -> String {
            String(format: text(key), value ?? 0)
        }
        let group: String
        var title: String
        var subtitle: String?
        switch insight.kind {
        case .packageExhausted:
            group = text("insights.group.package")
            title = text("insights.package.exhausted")
            subtitle = number("insights.package.balance", insight.balance)
        case .packageExpired:
            group = text("insights.group.package")
            title = text("insights.package.expired")
            subtitle = insight.packageEndDate.map {
                String(format: text("insights.package.validUntil"), AppointmentEditorFormatting.monthDay($0))
            }
        case .packageLow:
            group = text("insights.group.package")
            if let balance = insight.balance, balance <= 2 {
                title = number("insights.package.remaining", balance)
                subtitle = insight.packageEndDate.map {
                    String(format: text("insights.package.validUntil"), AppointmentEditorFormatting.monthDay($0))
                }
            } else {
                title =
                    insight.daysUntilExpiry == 0
                    ? text("insights.package.expiresToday")
                    : number("insights.package.expiresIn", insight.daysUntilExpiry)
                subtitle = number("insights.package.remainingBalance", insight.balance)
            }
        case .inactive:
            group = text("insights.group.inactive")
            title = number(
                insight.hasNeverTrained ? "insights.inactive.never" : "insights.inactive.days", insight.daysInactive)
            subtitle = text("insights.inactive.subtitle")
        case .stagnant:
            group = text("insights.group.stagnant")
            let unchanged = text("insights.stagnant.unchanged")
            let best = baseline(insight)
            switch context {
            case .today:
                title = exerciseName
                subtitle = unchanged
            case .list:
                title = exerciseName
                subtitle = [unchanged, best].compactMap { $0 }.joined(separator: " · ")
            case .studentDetail:
                title = "\(exerciseName) · \(unchanged)"
                subtitle = best
            }
        }
        let label = [group, studentName, title, subtitle].compactMap { $0 }.joined(separator: "，")
        if context != .studentDetail { title = "\(studentName) · \(title)" }
        return Self(title: title, subtitle: subtitle, accessibilityLabel: label)
    }

    private static func baseline(_ insight: Insight) -> String? {
        guard let value = insight.baselineBest, let metric = insight.baselineMetric else { return nil }
        let key: String
        let formatted: String
        switch metric {
        case .estimatedOneRepMax, .highestWeight, .lowestAssistance:
            switch metric {
            case .estimatedOneRepMax: key = "insights.stagnant.e1rm"
            case .lowestAssistance: key = "insights.stagnant.assistance"
            default: key = "insights.stagnant.weight"
            }
            formatted = TrendLineChart.pointLabel(NSDecimalNumber(decimal: value.decimal).doubleValue, unit: "kg")
        case .mostReps:
            key = "insights.stagnant.reps"
            formatted = value.canonicalString
        case .longestDuration:
            key = "insights.stagnant.duration"
            formatted = DurationTextParser.formatForEditing(secondsText: value.canonicalString)
        }
        return String(format: String(localized: String.LocalizationValue(key)), formatted)
    }
}

struct TodayInsightSelection {
    let rows: [Insight]
    let totalCount: Int
    var showsAll: Bool { totalCount > 3 }

    init(_ insights: [Insight]) {
        rows = Array(insights.prefix(3))
        totalCount = insights.count
    }
}

enum InsightNavigation {
    static func destination(for insight: Insight, today: LocalDate) -> RootDestination? {
        switch insight.kind {
        case .packageExhausted, .packageExpired, .packageLow:
            return .coursePackages(insight.studentID.rawValue)
        case .inactive:
            return .appointmentEditor(.create(studentID: insight.studentID.rawValue, date: today))
        case .stagnant:
            guard let exerciseID = insight.exerciseID else { return nil }
            return .insightTrend(studentID: insight.studentID.rawValue, exerciseID: exerciseID)
        }
    }
}
