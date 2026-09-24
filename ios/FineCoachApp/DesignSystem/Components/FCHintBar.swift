import SwiftUI

/// The hint bar (§8 "提示条": 358×44, `radius.md`, `surface.selected` bg,
/// `caption` `action.primary` text). Fills available width — see
/// `FCButton`'s width note.
public struct FCHintBar: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .fcFont(.caption)
            .foregroundStyle(FCSemanticColors.actionPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, FCPrimitives.space4)
            .background(FCSemanticColors.surfaceSelected)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMd))
    }
}
