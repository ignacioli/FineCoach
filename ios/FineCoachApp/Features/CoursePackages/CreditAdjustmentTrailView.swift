import SwiftUI

/// Full traceable ledger trail for one `CoursePackage` (data-model §2.4:
/// "每笔扣减/返还/缺席扣课都可查看"). Also the one place a `sessionReopen`
/// credit-back is explained to the coach in plain language (T024
/// "重开返还提示") -- there is no separate "reopen" trigger UI in this
/// codebase yet (no Session-reopen feature exists outside the ledger), so
/// this view's row rendering is where that entry becomes visible after the
/// fact.
@MainActor
final class CreditAdjustmentTrailViewModel: ObservableObject {
    @Published var adjustments: [CreditAdjustment] = []
    @Published var balance: Int = 0
    @Published var errorMessage: String?

    let packageID: StableUUID
    private let useCases: CreditLedgerUseCases

    init(packageID: StableUUID, useCases: CreditLedgerUseCases) {
        self.packageID = packageID
        self.useCases = useCases
    }

    /// Newest first, for the coach's most recent change to always be at the top.
    var orderedAdjustments: [CreditAdjustment] {
        adjustments.sorted { $0.createdAtUTC > $1.createdAtUTC }
    }

    func reload() async {
        do {
            adjustments = try await useCases.adjustments(packageID: packageID)
            balance = try await useCases.balance(packageID: packageID)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "creditTrail.error.generic")
        }
    }
}

struct CreditAdjustmentTrailView: View {
    @StateObject private var viewModel: CreditAdjustmentTrailViewModel

    init(packageID: StableUUID, useCases: CreditLedgerUseCases) {
        _viewModel = StateObject(
            wrappedValue: CreditAdjustmentTrailViewModel(packageID: packageID, useCases: useCases)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FCSemanticColors.destructive)
                }

                Text(String(format: String(localized: "creditTrail.balanceFormat"), viewModel.balance))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FCSemanticColors.primaryText)

                if viewModel.orderedAdjustments.isEmpty {
                    Text(String(localized: "creditTrail.empty"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                }

                ForEach(viewModel.orderedAdjustments) { adjustment in
                    row(for: adjustment)
                }
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "creditTrail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.creditTrailRoot)
        .task { await viewModel.reload() }
    }

    private func row(for adjustment: CreditAdjustment) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            HStack {
                Text(reasonTitle(adjustment))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FCSemanticColors.primaryText)
                Spacer()
                Text(signedAmount(adjustment))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        adjustment.direction == .debit ? FCSemanticColors.destructive : FCSemanticColors.brand
                    )
            }
            if let reasonText = adjustment.reasonText, !reasonText.isEmpty {
                Text(reasonText.value)
                    .foregroundStyle(FCSemanticColors.secondaryText)
            }
        }
        .padding(FCPrimitives.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMedium))
        .accessibilityIdentifier(FCAccessibilityID.creditTrailRow(adjustment.id))
    }

    private func signedAmount(_ adjustment: CreditAdjustment) -> String {
        let sign = adjustment.direction == .debit ? "-" : "+"
        return "\(sign)\(adjustment.amount)"
    }

    private func reasonTitle(_ adjustment: CreditAdjustment) -> String {
        switch adjustment.reasonKind {
        case .sessionComplete:
            return String(localized: "creditTrail.reason.sessionComplete")
        case .appointmentAbsent:
            return String(localized: "creditTrail.reason.appointmentAbsent")
        case .adhocSession:
            return String(localized: "creditTrail.reason.adhocSession")
        case .manualCorrection:
            return String(localized: "creditTrail.reason.manualCorrection")
        case .sessionReopen:
            return String(localized: "creditTrail.reason.sessionReopen")
        }
    }
}
