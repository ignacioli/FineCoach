import SwiftUI

/// The standard input row (`design/design-system/README.md` §8 "输入框（08）":
/// 358×48, `radius.sm`, `surface.canvas` bg, placeholder `callout` 400
/// `text.secondary`). Entered text uses `body` (§3.2 body's documented use
/// includes "字段值" — field values — which is not the placeholder style).
/// Fills available width — see `FCButton`'s width note.
public struct FCTextField: View {
    private let title: String
    @Binding private var text: String

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    public var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(title)
                .fcFont(.callout)
                .foregroundStyle(FCSemanticColors.textSecondary)
        )
        .fcFont(.body)
        .foregroundStyle(FCSemanticColors.textPrimary)
        .padding(.horizontal, FCPrimitives.space4)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(FCSemanticColors.surfaceCanvas)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
        .accessibilityLabel(Text(title))
    }
}

/// The search field (§8 "搜索框": 358×40, `radius.sm`, `surface.canvas` bg,
/// placeholder `callout` 400 `text.secondary`). The magnifying-glass glyph is
/// not itself called out with a size/color in §7.2's character table, but is
/// the standard iOS affordance that makes this row legible as search rather
/// than a plain input row at a glance; colored with `text.secondary` like the
/// placeholder it sits beside, not an invented token.
public struct FCSearchField: View {
    private let title: String
    @Binding private var text: String

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    public var body: some View {
        HStack(spacing: FCPrimitives.space2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityHidden(true)
            TextField(
                "",
                text: $text,
                prompt: Text(title)
                    .fcFont(.callout)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            )
            .fcFont(.callout)
            .foregroundStyle(FCSemanticColors.textPrimary)
        }
        .padding(.horizontal, FCPrimitives.space4)
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        .background(FCSemanticColors.surfaceCanvas)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
        .accessibilityLabel(Text(title))
    }
}
