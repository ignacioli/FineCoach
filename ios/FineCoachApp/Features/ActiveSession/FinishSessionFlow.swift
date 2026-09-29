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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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

    init(elapsedSeconds: String, onCancel: @escaping () -> Void, onConfirm: @escaping (String) -> Void) {
        self.elapsedSeconds = elapsedSeconds
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _durationText = State(initialValue: elapsedSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(localized: "session.duration.reviewLead"))
                .foregroundStyle(FCSemanticColors.textSecondary)
            FCTextField(String(localized: "session.field.duration"), text: $durationText)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionDurationValue)
            FCButton(title: String(localized: "session.duration.confirm")) {
                onConfirm(durationText)
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionDurationConfirm)
            Button(String(localized: "student.flow.cancel"), action: onCancel)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "session.duration.reviewTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.activeSessionDurationReview)
    }
}
