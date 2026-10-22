import SwiftUI

/// The dark hero card (§8 "深色 hero 卡（01）": 358×100, `radius.lg`,
/// `action.primary` bg; badge 24 high, min width 56 and growing with its text,
/// `surface.canvas` bg and `sectionLabel` `action.primary` text; `headline`
/// white title; `text.onActionSecondary` subtitle; `callout` 600 white action
/// link).
///
/// The multi-row variant (`W08-a`, approved 2026-10-22) keeps one card for
/// several Students training at once: badge "进行中 · N", then one independent
/// row per Student, `surface.dividerOnAction` 1pt lines only between rows.
/// The single-row variant's behaviour is unchanged: with an action the whole
/// card is one tap target.
///
/// §2.4: "每屏最多一个深色 hero 面板" — at most one per screen. That is a
/// screen-composition rule for callers (T068/T069), not something this
/// component can enforce on its own.
public struct FCHeroCard: View {
    /// One independent row of the multi-row variant. The component has no
    /// domain types; callers pass the Student UUID as `id` and map it back in
    /// `onRowAction`.
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let actionTitle: String
        public let accessibilityIdentifier: String

        public init(
            id: String,
            title: String,
            subtitle: String,
            actionTitle: String,
            accessibilityIdentifier: String
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.actionTitle = actionTitle
            self.accessibilityIdentifier = accessibilityIdentifier
        }
    }

    private let badgeText: String
    private let title: String?
    private let subtitle: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let isMultiRow: Bool
    private let rows: [Row]
    private let onRowAction: ((String) -> Void)?

    /// The existing single-row card. Appearance and behaviour are unchanged.
    public init(
        badgeText: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.badgeText = badgeText
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.isMultiRow = false
        self.rows = []
        self.onRowAction = nil
    }

    /// Multi-row card (`W08-a`). Each row is its own Button; the card itself
    /// is not a Button. A zero-row card renders nothing, but callers MUST NOT
    /// display it for an empty roster.
    public init(
        badgeText: String,
        rows: [Row],
        onRowAction: @escaping (String) -> Void
    ) {
        self.badgeText = badgeText
        self.title = nil
        self.subtitle = nil
        self.actionTitle = nil
        self.action = nil
        self.isMultiRow = true
        self.rows = rows
        self.onRowAction = onRowAction
    }

    public var body: some View {
        if isMultiRow {
            if rows.isEmpty {
                EmptyView()
            } else if let onRowAction {
                multiRowCard(rows: rows, onRowAction: onRowAction)
            }
        } else {
            singleRowCard
        }
    }

    @ViewBuilder
    private var singleRowCard: some View {
        if let action {
            Button(action: action) { singleRowContent }
                .buttonStyle(.plain)
        } else {
            singleRowContent
                .accessibilityElement(children: .combine)
        }
    }

    /// Badge on top; title and subtitle on the left with the action text
    /// trailing on the title line.
    private var singleRowContent: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space3) {
            badge

            HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space2) {
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(title ?? "")
                        .fcFont(.headline)
                        .foregroundStyle(FCSemanticColors.actionOn)
                    Text(subtitle ?? "")
                        .fcFont(.callout)
                        .foregroundStyle(FCSemanticColors.textOnActionSecondary)
                }
                Spacer(minLength: FCPrimitives.space2)
                if let actionTitle {
                    Text(actionTitle)
                        .fcFont(.callout, weight: .semibold)
                        .foregroundStyle(FCSemanticColors.actionOn)
                }
            }
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(FCSemanticColors.actionPrimary)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusLg))
        .contentShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusLg))
    }

    /// Badge then N rows. `VStack(spacing: space3)` puts `space3` on both
    /// sides of each inter-row divider; the first row has no line above it and
    /// the last row has none below it.
    private func multiRowCard(rows: [Row], onRowAction: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space3) {
            badge

            VStack(spacing: FCPrimitives.space3) {
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle()
                            .fill(FCSemanticColors.surfaceDividerOnAction)
                            .frame(height: 1)
                    }
                    Button {
                        onRowAction(row.id)
                    } label: {
                        rowContent(row)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(row.accessibilityIdentifier)
                }
            }
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(FCSemanticColors.actionPrimary)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusLg))
    }

    private var badge: some View {
        Text(badgeText)
            .fcFont(.sectionLabel)
            .foregroundStyle(FCSemanticColors.actionPrimary)
            .padding(.horizontal, FCPrimitives.space2)
            .frame(minWidth: 56, minHeight: 24, maxHeight: 24)
            .background(Capsule().fill(FCSemanticColors.surfaceCanvas))
    }

    private func rowContent(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space2) {
            VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                Text(row.title)
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.actionOn)
                Text(row.subtitle)
                    .fcFont(.callout)
                    .foregroundStyle(FCSemanticColors.textOnActionSecondary)
            }
            Spacer(minLength: FCPrimitives.space2)
            Text(row.actionTitle)
                .fcFont(.callout, weight: .semibold)
                .foregroundStyle(FCSemanticColors.actionOn)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
