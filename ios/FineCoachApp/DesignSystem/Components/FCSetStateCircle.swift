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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ state: State) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            stroke
                .opacity(state == .completed ? 0 : 1)
            completed
                .opacity(state == .completed ? 1 : 0)
        }
        .frame(width: 22, height: 22)
        // §14.4: the set circle flips with `fast` + `symmetric`; Reduce Motion
        // switches directly.
        .animation(
            reduceMotion ? nil : FCMotion.curveSymmetric(duration: FCMotion.durationFast),
            value: state == .completed
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var stroke: some View {
        switch state {
        case .draft:
            Circle().strokeBorder(
                FCSemanticColors.textSecondary,
                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
            )
        case .pending, .completed:
            Circle().strokeBorder(FCSemanticColors.borderControl, lineWidth: 1.5)
        }
    }

    private var completed: some View {
        ZStack {
            Circle().fill(FCSemanticColors.actionPrimary)
            FCSymbol(.checkOnFill)
        }
    }
}
