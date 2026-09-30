import SwiftUI

/// Coach-entered manual correction (data-model §2.4, M1B-FR-016). `reason`
/// is mandatory -- the Save button stays disabled until it is non-empty, and
/// the domain layer re-validates it regardless (never trust the UI alone).
@MainActor
final class ManualCreditAdjustmentViewModel: ObservableObject {
    @Published var direction: CreditDirection = .debit
    @Published var amount: Int = 1
    @Published var reason: String = ""
    @Published var errorMessage: String?
    @Published var isSaving = false
    @Published var didSave = false

    let packageID: StableUUID
    private let useCases: CreditLedgerUseCases

    init(packageID: StableUUID, useCases: CreditLedgerUseCases) {
        self.packageID = packageID
        self.useCases = useCases
    }

    var canSave: Bool {
        amount > 0 && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() async {
        guard canSave else {
            errorMessage = String(localized: "manualAdjustment.reasonRequired")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await useCases.recordManualCorrection(
                packageID: packageID,
                direction: direction,
                amount: amount,
                reasonText: reason
            )
            didSave = true
        } catch DomainError.invalidState {
            errorMessage = String(localized: "manualAdjustment.wouldGoNegative")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "manualAdjustment.saveFailed")
        }
    }
}

struct ManualCreditAdjustmentView: View {
    @StateObject private var viewModel: ManualCreditAdjustmentViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [RootDestination]

    init(packageID: StableUUID, useCases: CreditLedgerUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(
            wrappedValue: ManualCreditAdjustmentViewModel(packageID: packageID, useCases: useCases)
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "manualAdjustment.title"))
                    .fcFont(.titleLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, FCPrimitives.space4)
                FCListRowDivider()
                editorRow(String(localized: "manualAdjustment.direction")) {
                    FCSegmentedSwitch(
                        options: [
                            .init(
                                id: CreditDirection.debit.rawValue,
                                title: String(localized: "manualAdjustment.direction.debit")
                            ),
                            .init(
                                id: CreditDirection.credit.rawValue,
                                title: String(localized: "manualAdjustment.direction.credit")
                            ),
                        ],
                        selection: Binding(
                            get: { viewModel.direction.rawValue },
                            set: { viewModel.direction = CreditDirection(rawValue: $0) ?? viewModel.direction }
                        )
                    )
                }
                .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentDirection)
                FCListRowDivider()

                editorRow(String(localized: "manualAdjustment.amount")) {
                    FCStepper(
                        String(localized: "manualAdjustment.amount"),
                        value: $viewModel.amount,
                        in: 1...999
                    )
                }
                .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentAmount)
                FCListRowDivider()

                Text(String(localized: "manualAdjustment.reasonLabel"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .padding(.top, FCPrimitives.space4)
                TextField(String(localized: "manualAdjustment.reasonPlaceholder"), text: $viewModel.reason, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .padding(.horizontal, FCPrimitives.space4)
                    .padding(.vertical, FCPrimitives.space3)
                    .background(FCSemanticColors.surfaceCanvas)
                    .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
                    .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentReason)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.callout, weight: .regular)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                        .padding(.vertical, FCPrimitives.space2)
                }

                FCButton(
                    title: String(localized: "manualAdjustment.save"),
                    isEnabled: viewModel.canSave && !viewModel.isSaving
                ) {
                    Task { await viewModel.save() }
                }
                .padding(.top, FCPrimitives.space4)
                .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentSave)
            }
            .padding(FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentRoot)
        .onChange(of: viewModel.didSave) { _, saved in
            if saved {
                dismiss()
            }
        }
    }

    private func editorRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        FCLabelValueRow(label: label) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                control()
                    .foregroundStyle(FCSemanticColors.textPrimary)
            }
        }
    }
}
