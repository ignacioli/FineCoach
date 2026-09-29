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
        HStack(spacing: FCPrimitives.space2) {
            confirmControl
            // Long-press-to-edit is scoped to JUST this title+value block,
            // not the whole row -- a `.onLongPressGesture` on the full
            // HStack would sit on top of `confirmControl`/`editControl` and
            // steal their tap gestures (classic SwiftUI parent-gesture-wins
            // conflict), which is exactly what made both buttons dead on a
            // real device despite compiling and unit-testing fine.
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                Text(title)
                    .fcFont(.body)
                    .foregroundStyle(state == .completed ? FCSemanticColors.textPrimary : FCSemanticColors.textSecondary)
                Text(value).fcFont(.callout, weight: .regular).foregroundStyle(FCSemanticColors.textSecondary)
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5) {
                onEdit?()
            }
            Spacer(minLength: FCPrimitives.space2)
            Text(state.rawValue)
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
            editControl
        }
        .padding(.vertical, FCPrimitives.space2)
        .frame(minHeight: 44)
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
        // Visual only: swapped the plain SF Symbol circle for the design
        // system's FCSetStateCircle (§6), which distinguishes draft (dashed)
        // from pending (solid stroke) — the confirm button wiring,
        // accessibility hiding, and hit-area frame are unchanged.
        if state.isConfirmable {
            Button {
                onConfirm?()
            } label: {
                FCSetStateCircle(circleState)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityHidden(true)
        } else {
            FCSetStateCircle(circleState)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)
        }
    }

    private var circleState: FCSetStateCircle.State {
        switch state {
        case .draft: return .draft
        case .pending: return .pending
        case .completed: return .completed
        }
    }

    @ViewBuilder
    private var editControl: some View {
        if let onEdit {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityHidden(true)
        }
    }
}
