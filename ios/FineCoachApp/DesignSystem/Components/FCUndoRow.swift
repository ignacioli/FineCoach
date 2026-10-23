import SwiftUI

/// The temporary replacement for a deleted list item (`DS-UNDO-ROW`,
/// `design/design-system/components.md` §4.8). The caller keeps the deleted
/// item's position occupied for the shared four-second undo window.
public struct FCUndoRow: View {
    /// The single undo window shared by every reversible list-item deletion.
    /// `ActiveSessionViewModel.undoWindow` aliases this value so the UI and
    /// domain timer cannot drift apart.
    public static let undoWindow: Duration = .seconds(4)

    private let message: String
    private let accessibilityIdentifier: String?
    private let onUndo: () -> Void

    public init(
        message: String,
        accessibilityIdentifier: String? = nil,
        onUndo: @escaping () -> Void
    ) {
        self.message = message
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onUndo = onUndo
    }

    public var body: some View {
        HStack(spacing: FCPrimitives.space2) {
            Text(message)
                .fcFont(.body)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            let button = FCLinkButton(
                title: String(localized: "designSystem.undo"),
                action: onUndo
            )
            if let accessibilityIdentifier {
                button.accessibilityIdentifier(accessibilityIdentifier)
            } else {
                button
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(message))
        .accessibilityAction(named: Text("designSystem.undo"), onUndo)
    }
}

#if DEBUG
    #Preview("Undo row") {
        FCUndoRow(message: "第 1 组已删除", onUndo: {})
            .padding(.horizontal, FCPrimitives.space4)
    }
#endif
