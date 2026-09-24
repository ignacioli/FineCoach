import SwiftUI

/// The set-state circle (§6: 22×22; pending 1.5pt `border.control` stroke
/// (§10 O2); draft 1pt `text.secondary` dashed stroke; completed
/// `action.primary` fill with a white checkmark). Purely decorative — the
/// caller (e.g. `FCSetRow`) owns the accessible label/state text.
public struct FCSetStateCircle: View {
    public enum State: Sendable {
        case pending
        case draft
        case completed
    }

    private let state: State

    public init(_ state: State) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            switch state {
            case .pending:
                Circle().strokeBorder(FCSemanticColors.borderControl, lineWidth: 1.5)
            case .draft:
                Circle().strokeBorder(
                    FCSemanticColors.textSecondary,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
            case .completed:
                Circle().fill(FCSemanticColors.actionPrimary)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FCSemanticColors.actionOn)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
