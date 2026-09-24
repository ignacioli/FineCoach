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
                editorRow(String(localized: "manualAdjustment.direction")) {
                    Picker("", selection: $viewModel.direction) {
                        Text(String(localized: "manualAdjustment.direction.debit")).tag(CreditDirection.debit)
                        Text(String(localized: "manualAdjustment.direction.credit")).tag(CreditDirection.credit)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentDirection)
                Divider()

                editorRow(String(localized: "manualAdjustment.amount")) {
                    HStack(spacing: FCPrimitives.spacingSmall) {
                        Text("\(viewModel.amount)")
                        Stepper("", value: $viewModel.amount, in: 1...999)
                            .labelsHidden()
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentAmount)
                Divider()

                Text(String(localized: "manualAdjustment.reasonLabel"))
                    .foregroundStyle(FCSemanticColors.primaryText)
                    .padding(.top, FCPrimitives.spacingMedium)
                TextField(String(localized: "manualAdjustment.reasonPlaceholder"), text: $viewModel.reason, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding(FCPrimitives.spacingSmall)
                    .background(FCSemanticColors.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
                    .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentReason)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FCSemanticColors.destructive)
                        .padding(.vertical, FCPrimitives.spacingSmall)
                }

                FCButton(
                    title: String(localized: "manualAdjustment.save"),
                    isEnabled: viewModel.canSave && !viewModel.isSaving
                ) {
                    Task { await viewModel.save() }
                }
                .padding(.top, FCPrimitives.spacingMedium)
                .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentSave)
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "manualAdjustment.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.manualAdjustmentRoot)
        .onChange(of: viewModel.didSave) { _, saved in
            if saved {
                dismiss()
            }
        }
    }

    private func editorRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(FCSemanticColors.primaryText)
            Spacer()
            control()
                .foregroundStyle(FCSemanticColors.primaryText)
        }
        .frame(minHeight: 44)
    }
}
