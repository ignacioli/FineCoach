import SwiftUI

/// M2-02 选择导出内容 (T030): three group rows, collapsed and all selected by default
/// (M2-FR-007, M2-FR-049); expanding a group shows its items with a note, a selection circle or
/// the reason it is unavailable (D-005, D-009, D-015). The Coach's choice lives in
/// `ArchiveExportFlow.selection`; this view only forwards taps and re-reads it.
struct ArchiveSelectionView: View {
    @ObservedObject var model: ArchiveExportViewModel

    var body: some View {
        ArchiveExportPage {
            FCPageHeader(
                title: String(localized: "archive.export.selection.title"),
                subtitle: String(format: String(localized: "archive.export.selection.subtitle"), model.displayName)
            )
            if let selection = model.selection {
                VStack(alignment: .leading, spacing: 0) {
                    FCSectionLabel(String(localized: "archive.export.selection.section"))
                        .padding(.bottom, FCPrimitives.space2)
                    FCListRowDivider()
                    ForEach(ArchiveModuleGroup.allCases, id: \.self) { group in
                        groupBlock(group, selection: selection)
                        FCListRowDivider()
                    }
                }
            }
            ArchiveExclusionNote()
        }
        .archiveBottomButton {
            FCButton(
                title: String(localized: "archive.export.selection.preview"),
                isEnabled: (model.selection?.canPreview ?? false) && !model.isBusy
            ) {
                Task { await model.showPreview() }
            }
            .accessibilityIdentifier(FCAccessibilityID.archiveExportPreview)
        }
    }

    @ViewBuilder
    private func groupBlock(_ group: ArchiveModuleGroup, selection: ArchiveModuleSelection) -> some View {
        let key = ArchiveExportPresentation.accessibilityKey(group)
        let title = ArchiveExportPresentation.groupTitle(group)
        if selection.groupState(group) == .unavailable {
            FCListRow.unavailable(
                title: title,
                titleStyle: .headline,
                reason: ArchiveExportPresentation.reason(.noData)
            )
            .accessibilityIdentifier(FCAccessibilityID.archiveExportGroup(key))
        } else {
            let selectable = selection.items(in: group).filter { selection.state(of: $0).isSelectable }
            let isExpanded = model.expandedGroups.contains(group)
            FCListGroupRow(
                title: title,
                note: ArchiveExportPresentation.groupNote(group, selection: selection),
                childSelections: selectable.map { selection.state(of: $0).isSelected },
                isExpanded: isExpanded,
                onToggleSelection: { Task { await model.toggleGroup(group) } },
                onToggleExpansion: { model.toggleExpansion(group) }
            )
            .accessibilityIdentifier(FCAccessibilityID.archiveExportGroup(key))
            if isExpanded {
                ForEach(selection.items(in: group), id: \.self) { item in
                    FCListRowDivider()
                        .padding(.leading, FCPrimitives.space4 * 2)
                    itemRow(item, selection: selection)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: ArchiveModuleItem, selection: ArchiveModuleSelection) -> some View {
        let availability = selection.availability
        let title = ArchiveExportPresentation.itemTitle(item, availability: availability)
        let identifier = FCAccessibilityID.archiveExportItem(ArchiveExportPresentation.accessibilityKey(item))
        switch selection.state(of: item) {
        case .unavailable(let reason):
            FCListRow.unavailable(
                title: title,
                isIndented: true,
                reason: ArchiveExportPresentation.reason(reason)
            )
            .accessibilityIdentifier(identifier)
        case .selected, .unselected:
            FCListRow(
                title: title,
                isIndented: true,
                note: ArchiveExportPresentation.itemNote(item, availability: availability),
                isSelected: selection.state(of: item).isSelected,
                toggle: { Task { await model.toggleItem(item) } }
            )
            .accessibilityIdentifier(identifier)
        }
    }
}
