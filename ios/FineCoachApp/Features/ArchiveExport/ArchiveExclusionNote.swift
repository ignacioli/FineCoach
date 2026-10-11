import SwiftUI

/// `M2-EXCLUSION-NOTE` (implementation-map §4.1): the permanent-exclusion statement on M2-02.
/// It is text. There is no switch, no selection circle and nothing that unlocks an excluded
/// field (M2-FR-010: no temporary unlock). The only control is the 「查看全部」 link, which
/// reveals the full list of what is never exported and changes nothing else.
struct ArchiveExclusionNote: View {
    @State private var showsFullList = false

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space2) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .accessibilityHidden(true)
                Text(String(localized: "archive.export.exclusion.text"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showsFullList.toggle()
                } label: {
                    Text(showsFullList ? "archive.export.exclusion.collapse" : "archive.export.exclusion.viewAll")
                        .fcFont(.sectionLabel)
                        .foregroundStyle(FCSemanticColors.actionPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(FCAccessibilityID.archiveExportExclusionViewAll)
            }
            if showsFullList {
                Text(String(localized: "archive.export.exclusion.fullList"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(FCAccessibilityID.archiveExportExclusionList)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
