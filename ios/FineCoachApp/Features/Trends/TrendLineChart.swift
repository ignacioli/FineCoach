import Charts
import SwiftUI

/// The per-exercise trend line (M1 训练趋势 and the archive viewer's M2-15 share it). It takes
/// the trend points and a closure that reads the plotted value, so it knows nothing about
/// where the points came from (Coach history or an archive).
struct TrendLineChart: View {
    let points: [Comparison.SetTrendPoint]
    let metricLabel: String
    let unit: String
    let dashed: Bool
    let value: (Comparison.SetTrendPoint) -> Double?

    var body: some View {
        Chart(points, id: \.sessionID) { point in
            if let value = value(point) {
                LineMark(
                    x: .value("date", point.completedAtUTC),
                    y: .value(metricLabel, value)
                )
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .lineStyle(dashed ? StrokeStyle(lineWidth: 2, dash: [4, 4]) : StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("date", point.completedAtUTC),
                    y: .value(metricLabel, value)
                )
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .annotation(position: .top) {
                    Text(Self.pointLabel(value, unit: unit))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
            }
        }
        .frame(height: 200)
    }

    /// Point-label text for chart annotations: at most 1 decimal place,
    /// with a whole number never showing a trailing ".0" (e.g. "40kg", not
    /// "40.0kg", but "40.5kg" stays as-is).
    static func pointLabel(_ value: Double, unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        var text = String(format: "%.1f", rounded)
        if text.hasSuffix(".0") {
            text.removeLast(2)
        }
        return "\(text)\(unit)"
    }
}
