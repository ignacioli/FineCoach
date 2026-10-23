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
    private let isNewRecord: Bool
    private let newRecordIdentifier: String?
    private let onConfirm: (() -> Void)?
    private let onEdit: (() -> Void)?
    private let onUndo: (() -> Void)?

    public init(
        title: String,
        value: String,
        state: State,
        isNewRecord: Bool = false,
        newRecordIdentifier: String? = nil,
        onConfirm: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onUndo: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.state = state
        self.isNewRecord = isNewRecord && state == .completed
        self.newRecordIdentifier = newRecordIdentifier
        self.onConfirm = onConfirm
        self.onEdit = onEdit
        self.onUndo = onUndo
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
            // One line, as D8 / P0-a draw it: title, then the value pushed
            // toward the trailing status (experience P0 Δ5).
            HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space2) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: FCPrimitives.space2) {
                        rowTitle
                        recordBadge
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                        rowTitle
                        recordBadge
                    }
                }
                Spacer(minLength: FCPrimitives.space2)
                Text(value)
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5) {
                onEdit?()
            }
            // A just-confirmed set offers undo in place of its status for a
            // few seconds (P0-D11).
            if let onUndo {
                FCLinkButton(title: String(localized: "session.action.undo"), action: onUndo)
            } else {
                Text(state.rawValue)
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            editControl
        }
        .padding(.vertical, FCPrimitives.space2)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityHint(state.isConfirmable ? Text(String(localized: "session.set.confirmHint")) : Text(""))
        .accessibilityAction {
            onConfirm?()
        }
        .accessibilityAction(named: Text(String(localized: "session.set.editAction"))) {
            onEdit?()
        }
        .accessibilityActions {
            if let onUndo {
                Button(String(localized: "session.action.undo"), action: onUndo)
            }
        }

    }

    private var accessibilityText: String {
        [title, value, isNewRecord ? String(localized: "session.set.newRecord") : nil, state.rawValue]
            .compactMap { $0 }.joined(separator: "，")
    }

    private var rowTitle: some View {
        Text(title)
            .fcFont(.body)
            .foregroundStyle(state == .completed ? FCSemanticColors.textPrimary : FCSemanticColors.textSecondary)
            .fixedSize()
    }

    @ViewBuilder
    private var recordBadge: some View {
        if isNewRecord {
            FCNewRecordBadge()
                .accessibilityIdentifier(newRecordIdentifier ?? "")
        }
    }

    /// The circle stays in one place so the 0.2s stroke-to-check transition
    /// can run. The clear button is only there while the set can still be
    /// confirmed.
    private var confirmControl: some View {
        ZStack {
            FCSetStateCircle(circleState)
            if state.isConfirmable {
                Button {
                    onConfirm?()
                } label: {
                    Color.clear
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
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

#if DEBUG
    #Preview {
        VStack {
            FCSetRow(title: "第 1 组", value: "80 kg × 5", state: .pending)
            FCSetRow(title: "第 2 组", value: "82.5 kg × 5", state: .completed, isNewRecord: true)
        }
    }
#endif
