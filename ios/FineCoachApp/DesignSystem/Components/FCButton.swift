import SwiftUI

public struct FCButton: View {
    public enum State: Equatable, Sendable {
        case `default`
        case disabled
    }

    private let title: String
    private let state: State
    private let action: () -> Void

    public init(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.state = isEnabled ? .default : .disabled
        self.action = action
    }

    public init(
        title: String,
        state: State,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(FCButtonStyle(state: state))
        .disabled(state == .disabled)
        .accessibilityLabel(Text(title))
    }
}

private struct FCButtonStyle: ButtonStyle {
    let state: FCButton.State

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(state == .default ? FCSemanticColors.elevatedSurface : FCSemanticColors.secondaryText)
            .background(state == .default ? FCSemanticColors.primaryText : FCSemanticColors.separator)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
            .opacity(configuration.isPressed && state == .default ? 0.82 : 1)
    }
}
