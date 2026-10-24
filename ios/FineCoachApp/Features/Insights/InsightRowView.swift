import SwiftUI

struct InsightRowView: View {
    let insight: Insight
    let content: InsightRowContent
    let open: () -> Void
    let snooze: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            FCListRow(
                title: content.title, titleStyle: .body, subtitle: content.subtitle,
                showsDisclosure: false, action: open
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(content.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(FCAccessibilityID.insightRow(insight.id))
            FCMoreMenu(accessibilityIdentifier: FCAccessibilityID.insightMore(insight.id)) {
                Button(String(localized: "insights.action.snooze"), action: snooze)
                    .accessibilityIdentifier(FCAccessibilityID.insightSnooze(insight.id))
            }
        }
    }
}

/// The same feature-owned section composes the rows in all three contexts.
struct InsightSectionView: View {
    @ObservedObject var model: InsightsViewModel
    let title: String
    let rows: [Insight]
    let context: InsightRowContent.Context
    @Binding var path: [RootDestination]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(title)
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            ForEach(rows) { insight in
                InsightRowView(
                    insight: insight, content: model.content(for: insight, context: context),
                    open: {
                        if let destination = InsightNavigation.destination(
                            for: insight, today: LocalDate(date: Date(), calendar: .current))
                        {
                            path.append(destination)
                        }
                    },
                    snooze: { Task { await model.snooze(insight) } })
                FCListRowDivider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    open: {}, snooze: {})
                FCListRowDivider()
            }
        }
        .padding(FCPrimitives.space4)
        .background(FCSemanticColors.surfacePage)
    }
#endif
