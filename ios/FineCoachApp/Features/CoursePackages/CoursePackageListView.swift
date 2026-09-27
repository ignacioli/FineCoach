import SwiftUI

/// Active + historical course packages for a Student (T024, data-model §2.3).
/// Balance is always re-derived from the ledger on load -- never trusts a
/// stale cache -- so what the coach sees here can never drift from
/// `CreditAdjustmentTrailView`'s own total.
@MainActor
final class CoursePackageListViewModel: ObservableObject {
    @Published var packages: [CoursePackage] = []
    @Published var balances: [StableUUID: Int] = [:]
    @Published var errorMessage: String?

    let studentID: StableUUID
    private let useCases: CreditLedgerUseCases

    init(studentID: StableUUID, useCases: CreditLedgerUseCases) {
        self.studentID = studentID
        self.useCases = useCases
    }

    var activePackage: CoursePackage? {
        packages.first { $0.status == .active }
    }

    var historicalPackages: [CoursePackage] {
        packages.filter { $0.status == .ended }
    }

    func reload() async {
        do {
            let loaded = try await useCases.packages(studentID: studentID)
            packages = loaded
            var newBalances: [StableUUID: Int] = [:]
            for package in loaded {
                newBalances[package.id] = try await useCases.balance(packageID: package.id)
            }
            balances = newBalances
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "coursePackages.error.generic")
        }
    }

    func balance(for package: CoursePackage) -> Int {
        balances[package.id] ?? package.remainingCreditsCache
    }

    func endActivePackage() async {
        guard let activePackage else {
            return
        }
        do {
            _ = try await useCases.endPackage(packageID: activePackage.id)
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "coursePackages.error.generic")
        }
    }
}

struct CoursePackageListView: View {
    @StateObject private var viewModel: CoursePackageListViewModel
    @Binding var path: [RootDestination]

    init(studentID: StableUUID, useCases: CreditLedgerUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(
            wrappedValue: CoursePackageListViewModel(studentID: studentID, useCases: useCases)
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FCSemanticColors.destructive)
                }

                sectionTitle(String(localized: "coursePackages.activeSectionTitle"))

                if let active = viewModel.activePackage {
                    packageCard(active)

                    FCButton(title: String(localized: "coursePackages.manualAdjust")) {
                        path.append(.manualCreditAdjustment(active.id.rawValue))
                    }
                    .accessibilityIdentifier(FCAccessibilityID.coursePackageListManualAdjust)

                    Button(String(localized: "coursePackages.endActive")) {
                        Task { await viewModel.endActivePackage() }
                    }
                    .frame(minHeight: 44)
                    .foregroundStyle(FCSemanticColors.destructive)
                    .accessibilityIdentifier(FCAccessibilityID.coursePackageListEnd)
                } else {
                    Text(String(localized: "coursePackages.noActive"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                }

                FCButton(title: String(localized: "coursePackages.newPackage")) {
                    path.append(.coursePackageEditor(viewModel.studentID.rawValue))
                }
                .accessibilityIdentifier(FCAccessibilityID.coursePackageListAdd)

                if !viewModel.historicalPackages.isEmpty {
                    Divider()
                    sectionTitle(String(localized: "coursePackages.historySectionTitle"))
                    ForEach(viewModel.historicalPackages) { package in
                        packageCard(package)
                    }
                }
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "coursePackages.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.coursePackageListRoot)
        .task { await viewModel.reload() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FCSemanticColors.secondaryText)
    }

    /// Tapping a package opens its full traceable ledger trail (data-model
    /// §2.4: "每笔余额变化可查看对应课时调整").
    private func packageCard(_ package: CoursePackage) -> some View {
        Button {
            path.append(.creditAdjustmentTrail(package.id.rawValue))
        } label: {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                HStack {
                    Text(package.displayName)
                        .font(.headline)
                        .foregroundStyle(FCSemanticColors.primaryText)
                    Spacer()
                    Text(
                        package.status == .active
                            ? String(localized: "coursePackages.statusActive")
                            : String(localized: "coursePackages.statusEnded")
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        package.status == .active ? FCSemanticColors.actionPrimary : FCSemanticColors.secondaryText
                    )
                }
                Text(
                    String(
                        format: String(localized: "coursePackages.balanceFormat"),
                        viewModel.balance(for: package),
                        package.totalCredits
                    )
                )
                .foregroundStyle(FCSemanticColors.secondaryText)
                Text(validityPeriodText(package))
                    .foregroundStyle(FCSemanticColors.secondaryText)
                HStack(spacing: FCPrimitives.space1) {
                    Text(String(localized: "coursePackages.viewTrailHint"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.secondaryText)
                    FCSymbol(.forward)
                }
            }
            .padding(FCPrimitives.spacingMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FCSemanticColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMedium))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(FCAccessibilityID.coursePackageRow(package.id))
    }

    /// "有效期：<start> ~ <end>" -- `LocalDate.canonicalString` is already
    /// yyyy-MM-dd (the same format `CoursePackage.displayName`'s fallback
    /// uses), so no separate date formatter is needed here.
    private func validityPeriodText(_ package: CoursePackage) -> String {
        let start = package.startDate?.canonicalString ?? String(localized: "coursePackages.noStartDate")
        let end = package.endDate?.canonicalString ?? String(localized: "coursePackages.noEndDate")
        return String(format: String(localized: "coursePackages.validityPeriodFormat"), start, end)
    }
}
