import SwiftUI
import UIKit

/// Pre-measurement estimates only; actual text and undo heights come from layout.
/// S3-D13/S3-D15: space.3 + body + space.1 + caption + space.3,
/// followed by the standard divider (README §6). Single-line Text uses the
/// natural font box, not the nominal token line height (README §15.2/§15.5).
enum InsightRowGeometry {
    static func estimatedHeight(
        hasSubtitle: Bool, compatibleWith traits: UITraitCollection? = nil
    ) -> CGFloat {
        // FCListRow calls Text.fcFont directly: match its font factory, weight,
        // scaling base and system-wide Dynamic Type (nil traits), including its
        // documented lack of support for local dynamicTypeSize overrides.
        func naturalLineHeight(_ style: FCTextStyle) -> CGFloat {
            let font = FCFont.uiFont(size: style.size, weight: style.weight)
            return UIFontMetrics(forTextStyle: style.scalingBase)
                .scaledFont(for: font, compatibleWith: traits).lineHeight
        }
        let titleHeight = naturalLineHeight(.body)
        let subtitleHeight =
            hasSubtitle
            ? FCPrimitives.space1 + naturalLineHeight(.caption)
            : 0
        return max(
            FCListRowGeometry.minHeight,
            FCPrimitives.space3 + titleHeight + subtitleHeight + FCPrimitives.space3)
    }

    static let dividerHeight: CGFloat = 1
}

struct InsightRowView: View {
    let insight: Insight
    let content: InsightRowContent
    let open: () -> Void

    var body: some View {
        FCListRow(
            title: content.title, titleStyle: .body, subtitle: content.subtitle,
            showsDisclosure: false, verticalContentPadding: FCPrimitives.space3, action: open
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(FCAccessibilityID.insightRow(insight.id))

    }
}

/// The same feature-owned section composes the rows in all three contexts.
struct InsightSectionView: View {
    @ObservedObject var model: InsightsViewModel
    let title: String
    let rows: [Insight]
    let context: InsightRowContent.Context
    @Binding var path: [RootDestination]

    @State private var contentHeight: CGFloat?
    /// Last laid-out height of each insight row, so its undo row keeps the
    /// same height (`DS-UNDO-ROW`: same row height as the replaced row).
    @State private var rowHeights: [String: CGFloat] = [:]
    @State private var hintOffset: CGFloat = 0
    @AppStorage(InsightSwipeHint.defaultsKey) private var hintShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // README §10 C27: no existing distance/hold token matches the approved hint.
    private static let hintDistance: CGFloat = 72
    private static let hintHold: Duration = .milliseconds(600)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(title)
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            List {
                ForEach(rows) { insight in
                    VStack(spacing: 0) {
                        if model.undoState.pending[insight.snoozeKey] != nil {
                            FCUndoRow(
                                message: model.undoMessage(for: insight, context: context),
                                accessibilityIdentifier: FCAccessibilityID.insightUndo(insight.id)
                            ) { Task { await model.undoSnooze(insight) } }
                            .frame(
                                height: rowHeights[insight.snoozeKey]
                                    ?? InsightRowGeometry.estimatedHeight(
                                        hasSubtitle: model.content(for: insight, context: context).subtitle != nil))
                        } else {
                            insightRow(insight)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { height in
                                    rowHeights[insight.snoozeKey] = height
                                }
                        }
                        FCListRowDivider()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if model.undoState.pending[insight.snoozeKey] == nil {
                            Button {
                                Task { await model.snooze(insight) }
                            } label: {
                                Label(String(localized: "insights.action.snooze"), systemImage: "bell.slash")
                            }
                            .tint(FCSemanticColors.textSecondary)
                            .accessibilityIdentifier(FCAccessibilityID.insightSnooze(insight.id))
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(FCSemanticColors.surfacePage)
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 44)
            .onScrollGeometryChange(
                for: CGFloat.self,
                of: { $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom }
            ) { _, height in
                guard height >= 1 else { return }
                contentHeight = height
            }
            .frame(height: contentHeight ?? estimatedContentHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: reduceMotion) {
            guard
                InsightSwipeHint.shouldPlay(
                    isToday: context == .today, hasRows: !rows.isEmpty, shown: hintShown, reduceMotion: reduceMotion
                )
            else {
                hintOffset = 0
                return
            }
            withAnimation(FCMotion.curveStandard(duration: FCMotion.durationStandard)) {
                hintOffset = -Self.hintDistance
            }
            do {
                try await Task.sleep(for: .seconds(FCMotion.durationStandard))
                try await Task.sleep(for: Self.hintHold)
                withAnimation(FCMotion.curveSymmetric(duration: FCMotion.durationGentle)) { hintOffset = 0 }
                try await Task.sleep(for: .seconds(FCMotion.durationGentle))
                guard !reduceMotion else { return }
                hintShown = true
            } catch { hintOffset = 0 }
        }
    }

    private var estimatedContentHeight: CGFloat {
        rows.reduce(CGFloat.zero) { height, insight in
            height
                + InsightRowGeometry.estimatedHeight(
                    hasSubtitle: model.content(for: insight, context: context).subtitle != nil)
                + InsightRowGeometry.dividerHeight
        }
    }

    private func insightRow(_ insight: Insight) -> some View {
        let offset = insight.id == rows.first?.id ? hintOffset : 0
        return InsightRowView(
            insight: insight, content: model.content(for: insight, context: context),
            open: {
                if let destination = InsightNavigation.destination(
                    for: insight, today: LocalDate(date: Date(), calendar: .current))
                {
                    path.append(destination)
                }
            }
        )
        .background(FCSemanticColors.surfacePage)
        .offset(x: offset)
        .background(alignment: .trailing) {
            if offset != 0 {
                Label(String(localized: "insights.action.snooze"), systemImage: "bell.slash")
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.actionOn)
                    .padding(FCPrimitives.space2)
                    .background(FCSemanticColors.textSecondary, in: Capsule())
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
    }
}

#if DEBUG
    #Preview("课包") {
        insightPreviewRows(kinds: [.packageLow])
    }

    #Preview("没来上课") {
        insightPreviewRows(kinds: [.inactive])
    }

    #Preview("停滞") {
        insightPreviewRows(kinds: [.stagnant])
    }

    #Preview("三类提示 · 最大字体") {
        insightPreviewRows(kinds: [.packageLow, .inactive, .stagnant])
            .dynamicTypeSize(.accessibility5)
    }

    private func insightPreviewRows(kinds: [Insight.Kind]) -> some View {
        VStack(spacing: 0) {
            ForEach(kinds, id: \.rawValue) { kind in
                let insight = Insight(
                    kind: kind, studentID: StableUUID(UUID()),
                    exerciseID: kind == .stagnant ? StableExerciseID(rawValue: "fictional.preview.squat") : nil,
                    balance: 2, daysInactive: 21, stagnantSessionCount: 3,
                    baselineBest: try! DecimalValue("80"), baselineMetric: .estimatedOneRepMax)
                InsightRowView(
                    insight: insight,
                    content: InsightRowContent.make(
                        insight: insight, studentName: "虚构学员", exerciseName: "虚构深蹲", context: .list),
                    open: {})
                FCListRowDivider()
            }
        }
        .padding(FCPrimitives.space4)
        .background(FCSemanticColors.surfacePage)
    }
#endif
