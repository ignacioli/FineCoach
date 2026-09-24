import SwiftUI

/// The avatar (§8 "头像": 44×44 circle, `surface.selected` bg, initial
/// `headline` `action.primary`). Purely decorative — the surrounding row is
/// expected to carry the accessible name.
public struct FCAvatar: View {
    private let initial: String

    public init(initial: String) {
        self.initial = initial
    }

    public var body: some View {
        Circle()
            .fill(FCSemanticColors.surfaceSelected)
            .frame(width: 44, height: 44)
            .overlay(
                Text(initial)
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.actionPrimary)
            )
            .accessibilityHidden(true)
    }
}
