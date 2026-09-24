import SwiftUI

/// The confirmation dialog (§8 "确认弹窗": width 300 on-screen — the artwork's
/// own Foundations swatch export is 320, a swatch-canvas artifact, not the
/// in-screen truth, §1.1/§8 — `radius.lg`, white bg; title `headline`;
/// message `caption` `text.secondary`; two 36-tall buttons at
/// `radius.dialogAction`: the conservative/cancel action is `surface.selected`
/// bg + `callout` 600 `action.primary`, the confirm action is `action.primary`
/// bg + white text).
///
/// This is a content view, not a presentation API — callers own how/where it
/// is shown (e.g. as a custom overlay). §5 registers the 36pt button height
/// as a deliberate, approved exception to the general 44×44 touch-target
/// rule (§10 C8); it is intentionally not padded up to 44 here.
public struct FCConfirmationDialog: View {
    public struct Action {
        public let title: String
        public let handler: () -> Void

        public init(title: String, handler: @escaping () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    private let title: String
    private let message: String
    private let cancelAction: Action
    private let confirmAction: Action

    public init(
        title: String,
        message: String,
        cancelAction: Action,
        confirmAction: Action
    ) {
        self.title = title
        self.message = message
        self.cancelAction = cancelAction
        self.confirmAction = confirmAction
    }

    public var body: some View {
        VStack(spacing: FCPrimitives.space4) {
            VStack(spacing: FCPrimitives.space2) {
                Text(title)
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                Text(message)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: FCPrimitives.space2) {
                dialogButton(cancelAction, isPrimary: false)
                dialogButton(confirmAction, isPrimary: true)
            }
        }
        .padding(FCPrimitives.space4)
        .frame(width: 300)
        .background(FCSemanticColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusLg))
    }

    @ViewBuilder
    private func dialogButton(_ action: Action, isPrimary: Bool) -> some View {
        Button(action: action.handler) {
            Text(action.title)
                .fcFont(.callout, weight: .semibold)
                .foregroundStyle(isPrimary ? FCSemanticColors.actionOn : FCSemanticColors.actionPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isPrimary ? FCSemanticColors.actionPrimary : FCSemanticColors.surfaceSelected)
                .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusDialogAction))
        }
        .buttonStyle(.plain)
    }
}
