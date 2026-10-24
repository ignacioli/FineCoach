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
