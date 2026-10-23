import SwiftUI

struct FinishSessionFlow: View {
    let gate: SessionFinishGate
    let onAbandon: () -> Void
    let onDiscard: () -> Void
    let onReturn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(title)
                .fcFont(.title)
            Text(bodyText)
                .foregroundStyle(FCSemanticColors.textSecondary)

            switch gate {
            case .abandonEmpty:
                FCButton(title: String(localized: "session.finish.abandonConfirm")) {
                    onAbandon()
                }
                .accessibilityIdentifier(FCAccessibilityID.activeSessionAbandonConfirm)
            case .unresolvedDrafts:
                FCButton(title: String(localized: "session.finish.discardDrafts")) {
                    onDiscard()
                }
                .accessibilityIdentifier(FCAccessibilityID.activeSessionDiscardDrafts)
                Button(String(localized: "session.finish.returnToDrafts"), action: onReturn)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionReturnToDrafts)
            case .canComplete:
                EmptyView()
            }

            if gate != .unresolvedDrafts {
                Button(String(localized: "student.flow.cancel"), action: onReturn)
                    .frame(minHeight: 44)
            }
            Spacer()
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.surfacePage)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var title: String {
        switch gate {
        case .abandonEmpty:
            return String(localized: "session.finish.abandonTitle")
        case .unresolvedDrafts:
            return String(localized: "session.finish.draftsTitle")
        case .canComplete:
            return String(localized: "session.finish.title")
        }
    }

    private var bodyText: String {
        switch gate {
        case .abandonEmpty:
            return String(localized: "session.finish.abandonLead")
        case .unresolvedDrafts:
            return String(localized: "session.finish.draftsLead")
        case .canComplete:
            return String(localized: "session.finish.completeLead")
        }
    }
}

struct DurationReviewFlow: View {
    let elapsedSeconds: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void
    @State private var durationText: String
    @State private var hasDurationError = false

    init(elapsedSeconds: String, onCancel: @escaping () -> Void, onConfirm: @escaping (String) -> Void) {
        self.elapsedSeconds = elapsedSeconds
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _durationText = State(
            initialValue: DurationTextParser.formatSessionDurationForEditing(seconds: elapsedSeconds)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(localized: "session.duration.reviewTitle"))
                .fcFont(.title)
            Text(String(localized: "session.duration.reviewLead"))
                .foregroundStyle(FCSemanticColors.textSecondary)
            FCTextField(String(localized: "session.field.duration"), text: $durationText)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionDurationValue)
            Text(String(localized: "session.duration.inputHint"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionDurationHint)
            if hasDurationError {
                Text(String(localized: "session.duration.inputError"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
                    .padding(.bottom, FCPrimitives.space2)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionDurationError)
            }
            FCButton(title: String(localized: "session.duration.confirm")) {
                guard let seconds = DurationTextParser.parseSessionDurationSeconds(durationText) else {
                    hasDurationError = true
                    return
                }
                hasDurationError = false
                onConfirm(seconds)
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionDurationConfirm)
            Button(String(localized: "student.flow.cancel"), action: onCancel)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.surfacePage)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier(FCAccessibilityID.activeSessionDurationReview)
    }
}
