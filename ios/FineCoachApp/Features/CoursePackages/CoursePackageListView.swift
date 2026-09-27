import SwiftUI

/// Active + historical course packages for a Student (T024, data-model §2.3).
/// Balance is always re-derived from the ledger on load -- never trusts a
/// stale cache -- so what the coach sees here can never drift from
/// `CreditAdjustmentTrailView`'s own total.
@MainActor
final class CoursePackageListViewModel: ObservableObject {
    @Published var packages: [CoursePackage] = []
    @Published var balances: [StableUUID: Int] = [:]
    @Published var activeAdjustments: [CreditAdjustment] = []
    @Published var studentName: String?
    @Published var errorMessage: String?

    let studentID: StableUUID
    private let useCases: CreditLedgerUseCases
    private let studentUseCases: StudentUseCases?

    init(studentID: StableUUID, useCases: CreditLedgerUseCases, studentUseCases: StudentUseCases? = nil) {
        self.studentID = studentID
        self.useCases = useCases
        self.studentUseCases = studentUseCases
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
            if let active = loaded.first(where: { $0.status == .active }) {
                activeAdjustments = try await useCases.adjustments(packageID: active.id)
                    .sorted { $0.createdAtUTC > $1.createdAtUTC }
            } else {
                activeAdjustments = []
            }
            if studentName == nil, let studentUseCases {
                studentName = try? await studentUseCases.student(id: studentID).displayName.value
            }
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

/// 04 课包详情 (T069f): the student's active package on one page — name,
/// balance, totals, validity, the adjustment trail — with 人工调整 pinned
/// (was split across 课包与课时 and 课时调整记录). Package management that
/// the artwork doesn't draw but M1B-FR-012 needs stays reachable below:
/// 新建课包, 结束当前课包 (confirmed), and 历史课包 rows.
struct CoursePackageListView: View {
    @StateObject private var viewModel: CoursePackageListViewModel
    @Binding var path: [RootDestination]
    @State private var isConfirmingEnd = false

    init(
        studentID: StableUUID,
        useCases: CreditLedgerUseCases,
        studentUseCases: StudentUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: CoursePackageListViewModel(
                studentID: studentID,
                useCases: useCases,
                studentUseCases: studentUseCases
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                Text(String(localized: "packageDetail.title"))
                    .fcFont(.titleLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if let active = viewModel.activePackage {
                    PackageDetailContent(
                        studentName: viewModel.studentName,
                        package: active,
                        balance: viewModel.balance(for: active),
                        adjustments: viewModel.activeAdjustments
                    )
                } else {
                    if let name = viewModel.studentName {
                        Text(name)
                            .fcFont(.headline)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                    Text(String(localized: "coursePackages.noActive"))
                        .fcFont(.callout, weight: .regular)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }

                managementSection
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if let active = viewModel.activePackage {
                    FCButton(title: String(localized: "packageDetail.manualAdjust")) {
                        path.append(.manualCreditAdjustment(active.id.rawValue))
                    }
                    .accessibilityIdentifier(FCAccessibilityID.coursePackageListManualAdjust)
                } else {
                    FCButton(title: String(localized: "coursePackages.newPackage")) {
                        path.append(.coursePackageEditor(viewModel.studentID.rawValue))
                    }
                    .accessibilityIdentifier(FCAccessibilityID.coursePackageListAdd)
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .accessibilityIdentifier(FCAccessibilityID.coursePackageListRoot)
        .fcConfirmationDialog(isPresented: $isConfirmingEnd) {
            FCConfirmationDialog(
                title: String(localized: "packageDetail.endConfirm.title"),
                message: String(localized: "packageDetail.endConfirm.message"),
                cancelAction: .init(title: String(localized: "packageDetail.endConfirm.keep")) {
                    isConfirmingEnd = false
                },
                confirmAction: .init(title: String(localized: "packageDetail.endConfirm.confirm")) {
                    isConfirmingEnd = false
                    Task { await viewModel.endActivePackage() }
                }
            )
        }
        .task { await viewModel.reload() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    @ViewBuilder
    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(String(localized: "packageDetail.management"))
                .padding(.top, FCPrimitives.space4)
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            if viewModel.activePackage != nil {
                FCActionRow(title: String(localized: "coursePackages.newPackage")) {
                    path.append(.coursePackageEditor(viewModel.studentID.rawValue))
                }
                .accessibilityIdentifier(FCAccessibilityID.coursePackageListAdd)
                FCListRowDivider()
                FCActionRow(title: String(localized: "coursePackages.endActive"), role: .destructive) {
                    isConfirmingEnd = true
                }
                .accessibilityIdentifier(FCAccessibilityID.coursePackageListEnd)
                FCListRowDivider()
            }
            ForEach(viewModel.historicalPackages) { package in
                FCActionRow(
                    title: package.displayName,
                    note: String(
                        format: String(localized: "coursePackages.balanceFormat"),
                        viewModel.balance(for: package),
                        package.totalCredits
                    )
                ) {
                    path.append(.creditAdjustmentTrail(package.id.rawValue))
                }
                .accessibilityIdentifier(FCAccessibilityID.coursePackageRow(package.id))
                FCListRowDivider()
            }
        }
    }
}
