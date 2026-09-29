import SwiftUI

/// The standard input row (`design/design-system/README.md` §8 "输入框（08）":
/// 358×48, `radius.sm`, `surface.canvas` bg, placeholder `callout` 400
/// `text.secondary`). Entered text uses `body` (§3.2 body's documented use
/// includes "字段值" — field values — which is not the placeholder style).
/// Fills available width — see `FCButton`'s width note.
public struct FCTextField: View {
    private let title: String
    @Binding private var text: String
    private let isSecure: Bool

    /// - Parameter isSecure: masks the entry (backup 口令, 08), same look.
    public init(_ title: String, text: Binding<String>, isSecure: Bool = false) {
        self.title = title
        self._text = text
        self.isSecure = isSecure
    }

    public var body: some View {
        field
            .fcFont(.body)
            .foregroundStyle(FCSemanticColors.textPrimary)
            .padding(.horizontal, FCPrimitives.space4)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(FCSemanticColors.surfaceCanvas)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
            .accessibilityLabel(Text(title))
    }

    @ViewBuilder
    private var field: some View {
        let prompt = Text(title)
            .fcFont(.callout)
            .foregroundStyle(FCSemanticColors.textSecondary)
        if isSecure {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt)
        }
    }
}

/// The search field (§8 "搜索框": 358×40, `radius.sm`, `surface.canvas` bg,
/// placeholder `callout` 400 `text.secondary`). No magnifying-glass icon —
/// `design/m1-b-hifi/screens/10-student-list.png` (the authoritative artwork,
/// §1) shows only the placeholder text ("搜索学员") left-aligned at the
/// standard inner inset on the `surface.canvas` fill, no icon.
public struct FCSearchField: View {
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
        .fcFont(.callout)
        .foregroundStyle(FCSemanticColors.textPrimary)
        .padding(.horizontal, FCPrimitives.space4)
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        .background(FCSemanticColors.surfaceCanvas)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
        .accessibilityLabel(Text(title))
    }
}
