import SwiftUI

struct FinishSessionFlow: View {
    let gate: SessionFinishGate
    let onAbandon: () -> Void
    let onDiscard: () -> Void
    let onReturn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(bodyText)
                .foregroundStyle(FCSemanticColors.secondaryText)

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
        .padding(FCPrimitives.spacingMedium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.background)
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
