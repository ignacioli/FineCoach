import SwiftUI

/// M2-12 训练记录列表 (T047): filter chips (date range, training focus; any-match), name search
/// only when the archive holds exercise info, the 「N 次训练」 count and one row per record.
/// Filtering is an in-memory query of the loaded archive.
struct ArchiveRecordsView: View {
    private enum FilterSheet {
        case date
        case focus
    }

    let content: ArchiveViewerContent
    @ObservedObject var model: ArchiveViewerModel
    let openSession: (String) -> Void

    @State private var datePreset: HistoryDateRangePreset?
    @State private var focus: Set<BodyPart> = []
    @State private var query = ""
    @State private var sheet: FilterSheet?

    private var filter: ArchiveSessionFilter {
        ArchiveSessionFilter(
            dateRange: datePreset.map {
                $0.range(endingAt: ArchiveViewerPresentation.referenceDay(content), calendar: .current)
            },
            trainingFocus: focus,
            exerciseNameQuery: content.isNameSearchAvailable ? query : nil
        )
    }

    private var sessions: [ArchiveSession] {
        (try? content.sessions(matching: filter)) ?? []
    }

    var body: some View {
        let shown = sessions
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.export.item.trainingRecords"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveRecordsBack)
                )
                if content.isNameSearchAvailable {
                    FCSearchField(String(localized: "archive.viewer.records.search"), text: $query)
                        .accessibilityIdentifier(FCAccessibilityID.archiveRecordsSearch)
                }
                chips
                VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                    FCSectionLabel(String(format: String(localized: "history.countFormat"), shown.count))
                    if shown.isEmpty {
                        Text(String(localized: "archive.viewer.records.empty"))
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, FCPrimitives.space2)
                            .accessibilityIdentifier(FCAccessibilityID.archiveRecordsEmpty)
                    } else {
                        VStack(spacing: 0) {
                            FCListRowDivider()
                            ForEach(Array(shown.enumerated()), id: \.element.key) { index, session in
                                FCListRow(
                                    title: ArchiveViewerPresentation.day(session.localDate),
                                    titleStyle: .headline,
                                    subtitle: ArchiveViewerPresentation.sessionMeta(session),
                                    action: { openSession(session.key) }
                                )
                                .accessibilityIdentifier(FCAccessibilityID.archiveRecordsRow(index))
                                FCListRowDivider()
                            }
                        }
                        .environment(\.fcCompactRows, model.settings.density == .compact)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .fcBottomSheet(isPresented: sheetPresented) { sheetContent }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveRecordsRoot)
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack(spacing: FCPrimitives.space2) {
                FCFilterChip(title: String(localized: "history.filter.date"), isSelected: datePreset != nil) {
                    sheet = .date
                }
                .accessibilityIdentifier(FCAccessibilityID.archiveRecordsFilterDate)
                FCFilterChip(title: String(localized: "history.filter.focus"), isSelected: !focus.isEmpty) {
                    sheet = .focus
                }
                .accessibilityIdentifier(FCAccessibilityID.archiveRecordsFilterFocus)
            }
            if datePreset != nil || !focus.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(filterSummary)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                    Spacer(minLength: FCPrimitives.space2)
                    FCLinkButton(title: String(localized: "history.filter.clear")) {
                        datePreset = nil
                        focus = []
                    }
                    .accessibilityIdentifier(FCAccessibilityID.archiveRecordsFilterClear)
                }
            }
        }
    }

    /// 「已筛选：训练重点 大腿、臀 · 近 30 天」
    private var filterSummary: String {
        var parts: [String] = []
        if let names = BodyPart.joinedDisplayNames(for: focus, separator: "、") {
            parts.append(String(format: String(localized: "history.filter.focusSummaryFormat"), names))
        }
        if let datePreset {
            parts.append(datePreset.title)
        }
        return String(format: String(localized: "history.filter.summaryFormat"), parts.joined(separator: " · "))
    }

    private var sheetPresented: Binding<Bool> {
        Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch sheet {
        case .date:
            FCBottomSheet(title: String(localized: "history.filter.date")) {
                FCFlowLayout(horizontalSpacing: FCPrimitives.space2, verticalSpacing: FCPrimitives.space2 - (44 - 30)) {
                    FCFilterChip(title: String(localized: "history.filter.all"), isSelected: datePreset == nil) {
                        datePreset = nil
                        sheet = nil
                    }
                    ForEach(HistoryDateRangePreset.allCases) { preset in
                        FCFilterChip(title: preset.title, isSelected: datePreset == preset) {
                            datePreset = preset
                            sheet = nil
                        }
                    }
                }
            }
        case .focus:
            FCBottomSheet(
                title: String(localized: "history.filter.focus"),
                subtitle: String(localized: "history.filter.focusHint")
            ) {
                VStack(spacing: FCPrimitives.space3) {
                    FCBodyPartPicker(selection: $focus)
                    FCButton(title: String(localized: "history.filter.done")) { sheet = nil }
                }
            }
        case nil:
            EmptyView()
        }
    }
}
