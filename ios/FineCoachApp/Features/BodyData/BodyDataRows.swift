import SwiftUI

/// One 06-artwork metric row: label, big value, unit. Value-type input so the Coach body-data
/// page and the archive viewer's M2-14 draw the same row. Column widths were measured from
/// `06-body-data` and scale with Dynamic Type.
struct BodyMetricValueRow: View {
    let name: String
    let value: String
    let unit: String
    @ScaledMetric(relativeTo: .title2) private var valueColumnWidth: CGFloat = 90
    @ScaledMetric(relativeTo: .footnote) private var unitColumnWidth: CGFloat = 84

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(name)
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .fcFont(.numeralLarge)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .frame(minWidth: valueColumnWidth, alignment: .leading)
            Text(unit)
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .frame(minWidth: unitColumnWidth, alignment: .leading)
        }
        .padding(.vertical, FCPrimitives.space3)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// One measurement of a metric's history: date over value, with an optional trailing control
/// (the Coach page puts its delete button there; the archive viewer passes none).
struct BodyMeasurementHistoryRow<Trailing: View>: View {
    let dateText: String
    let valueText: String
    let trailing: Trailing

    init(dateText: String, valueText: String, @ViewBuilder trailing: () -> Trailing) {
        self.dateText = dateText
        self.valueText = valueText
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                Text(dateText)
                    .fcFont(.body)
                Text(valueText)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            Spacer()
            trailing
        }
        .padding(FCPrimitives.space4)
        .background(FCSemanticColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMd))
    }
}
