import SwiftUI

public struct FCTextField: View {
    private let title: String
    @Binding private var text: String

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    public var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: 44)
            .accessibilityLabel(Text(title))
    }
}
