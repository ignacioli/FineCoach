import SwiftUI

/// One personal-best row (`32-training-history-v2`): exercise name over the record kind, the
/// value big, the day and the set behind it on the right. Value-type input, shared by the Coach
/// history page and the archive viewer's M2-15.
struct PersonalBestRowView: View {
    let name: String
    let kind: String
    let value: String
    let day: String?
    let detail: String?

    var allowsValueWrapping = false

    var body: some View {
        HStack(alignment: .center, spacing: FCPrimitives.space4) {
            VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                Text(name)
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                Text(kind)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .fcFont(.titleEmphasis)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .lineLimit(allowsValueWrapping ? nil : 1)
            VStack(alignment: .trailing, spacing: FCPrimitives.space1) {
                if let day {
                    Text(day)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                if let detail {
                    Text(detail)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
            }
            .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(.vertical, FCPrimitives.space3)
        .accessibilityElement(children: .combine)
    }
}
