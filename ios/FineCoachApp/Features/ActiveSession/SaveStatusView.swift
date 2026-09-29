import SwiftUI

struct SaveStatusView: View {
    let status: PersistenceProjectionStatus
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            FCSaveStatusView(status: displayStatus)
                .accessibilityIdentifier(statusIdentifier)

            if case .failed = status {
                Text(String(localized: "session.save.finishBlocked"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionFinishBlocked)

                FCButton(title: String(localized: "session.save.retry"), action: onRetry)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionRetry)
            }
        }
    }

    private var displayStatus: FCSaveStatusView.Status {
        switch status {
        case .saving:
            return .saving
        case .saved:
            return .saved
        case .failed:
            return .failed
        }
    }

    private var statusIdentifier: String {
        switch status {
        case .saving:
            return FCAccessibilityID.activeSessionSaveStatusSaving
        case .saved:
            return FCAccessibilityID.activeSessionSaveStatusSaved
        case .failed:
            return FCAccessibilityID.activeSessionSaveStatusFailed
        }
    }
}
