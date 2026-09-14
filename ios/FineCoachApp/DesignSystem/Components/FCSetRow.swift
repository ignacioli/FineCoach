import SwiftUI

public struct FCSetRow: View {
    public enum State: String, Sendable {
        case draft = "草稿"
        case pending = "待完成"
        case completed = "已完成"

        /// Draft and pending sets are not yet recorded and can still be
        /// confirmed directly from the row (M1-A fix: explicit per-row
        /// addressing instead of implicitly operating on the last set).
        var isConfirmable: Bool {
            self != .completed
        }
    }

    private let title: String
    private let value: String
    private let state: State
    private let onConfirm: (() -> Void)?
    private let onEdit: (() -> Void)?

    public init(
        title: String,
        value: String,
        state: State,
        onConfirm: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.state = state
        self.onConfirm = onConfirm
        self.onEdit = onEdit
    }

    public var body: some View {
        HStack(spacing: FCPrimitives.spacingSmall) {
            confirmControl
            VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(state == .completed ? FCSemanticColors.primaryText : FCSemanticColors.secondaryText)
                Text(value).font(.subheadline).foregroundStyle(FCSemanticColors.secondaryText)
            }
            Spacer(minLength: FCPrimitives.spacingSmall)
            Text(state.rawValue)
                .font(.subheadline)
                .foregroundStyle(FCSemanticColors.secondaryText)
            editControl
        }
        .padding(.vertical, FCPrimitives.spacingSmall)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            onEdit?()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title)，\(value)，\(state.rawValue)"))
        .accessibilityHint(state.isConfirmable ? Text(String(localized: "session.set.confirmHint")) : Text(""))
        .accessibilityAction {
            onConfirm?()
        }
        .accessibilityAction(named: Text(String(localized: "session.set.editAction"))) {
            onEdit?()
        }
    }

    @ViewBuilder
    private var confirmControl: some View {
        if state.isConfirmable {
            Button {
                onConfirm?()
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(FCSemanticColors.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityHidden(true)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(FCSemanticColors.primaryText)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var editControl: some View {
        if let onEdit {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(FCSemanticColors.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityHidden(true)
        }
    }
}
