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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
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
                // §7.2 − / + glyph as a symbol; the amount keeps its state color.
                HStack(spacing: FCPrimitives.space1) {
                    FCSymbol(adjustment.direction == .debit ? .minus : .plus, color: amountColor(adjustment))
                    Text("\(adjustment.amount)")
                        .fcFont(.callout, weight: .semibold)
                        .foregroundStyle(amountColor(adjustment))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(signedAmount(adjustment)))
            }
            if let reasonText = adjustment.reasonText, !reasonText.isEmpty {
                Text(reasonText.value)
                    .foregroundStyle(FCSemanticColors.secondaryText)
            }
            Text(Self.dateTimeText(adjustment.createdAtUTC))
                .font(.caption)
                .foregroundStyle(FCSemanticColors.secondaryText)
        }
        .padding(FCPrimitives.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMedium))
        .accessibilityIdentifier(FCAccessibilityID.creditTrailRow(adjustment.id))
    }

    private func amountColor(_ adjustment: CreditAdjustment) -> Color {
        adjustment.direction == .debit ? FCSemanticColors.destructive : FCSemanticColors.actionPrimary
    }

    private func signedAmount(_ adjustment: CreditAdjustment) -> String {
        let sign = adjustment.direction == .debit ? "-" : "+"
        return "\(sign)\(adjustment.amount)"
    }

    private static func dateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
