import SwiftUI

public struct FCSetRow: View {
    public enum State: String, Sendable {
        case draft = "草稿"
        case pending = "待完成"
        case completed = "已完成"
    }

    private let title: String
    private let value: String
    private let state: State

    public init(title: String, value: String, state: State) {
        self.title = title
        self.value = value
        self.state = state
    }

    public var body: some View {
        HStack(spacing: FCPrimitives.spacingSmall) {
            Image(systemName: iconName)
                .foregroundStyle(state == .completed ? FCSemanticColors.primaryText : FCSemanticColors.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                Text(title).font(.body)
                Text(value).font(.subheadline).foregroundStyle(FCSemanticColors.secondaryText)
            }
            Spacer(minLength: FCPrimitives.spacingSmall)
            Text(state.rawValue)
                .font(.subheadline)
                .foregroundStyle(FCSemanticColors.secondaryText)
        }
        .padding(.vertical, FCPrimitives.spacingSmall)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value)，\(state.rawValue)"))
    }

    private var iconName: String {
        switch state {
        case .draft:
            return "pencil.circle"
        case .pending:
            return "circle"
        case .completed:
            return "checkmark.circle.fill"
        }
    }
}
