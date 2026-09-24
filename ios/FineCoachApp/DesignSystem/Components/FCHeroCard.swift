import SwiftUI

/// The dark hero card (§8 "深色 hero 卡（01）": 358×100, `radius.lg`,
/// `action.primary` bg; badge 56×24 capsule with `surface.canvas` bg and
/// `sectionLabel` `action.primary` text; `headline` white title;
/// `text.onActionSecondary` subtitle; `callout` 600 white action link).
///
/// §2.4: "每屏最多一个深色 hero 面板" — at most one per screen. That is a
/// screen-composition rule for callers (T068/T069), not something this
/// component can enforce on its own.
public struct FCHeroCard: View {
    private let badgeText: String
    private let title: String
    private let subtitle: String
    private let actionTitle: String?
    private let action: (() -> Void)?

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
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            Text(badgeText)
                .fcFont(.sectionLabel)
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .frame(width: 56, height: 24)
                .background(Capsule().fill(FCSemanticColors.surfaceCanvas))

            Spacer(minLength: 0)

            Text(title)
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.actionOn)
            Text(subtitle)
                .fcFont(.callout)
                .foregroundStyle(FCSemanticColors.textOnActionSecondary)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .fcFont(.callout, weight: .semibold)
                        .foregroundStyle(FCSemanticColors.actionOn)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(FCSemanticColors.actionPrimary)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusLg))
    }
}
