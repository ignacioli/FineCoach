import SwiftUI

/// The 04 课包详情 body (T069f; `04-package-detail`), shared by the active
/// package page (`CoursePackageListView`) and a historical package's page
/// below: student name, `numeralHero` balance, "剩余课时 | 共 N 课时",
/// "有效期", and the full traceable ledger (data-model §2.4: every debit /
/// credit-back / absence charge is visible, newest first).
struct PackageDetailContent: View {
    let studentName: String?
    let package: CoursePackage
    let balance: Int
    let adjustments: [CreditAdjustment]

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            if let studentName, !studentName.isEmpty {
                Text(studentName)
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }

            Text("\(balance)")
                .fcFont(.numeralHero)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .accessibilityLabel(Text(String(format: String(localized: "packageDetail.balanceA11yFormat"), balance)))

            VStack(spacing: 0) {
                FCLabelValueRow(
                    label: String(localized: "packageDetail.remaining"),
                    value: String(format: String(localized: "packageDetail.totalFormat"), package.totalCredits)
                )
                FCLabelValueRow(
                    label: String(localized: "packageDetail.validity"),
                    value: PackageDetailPresentation.validity(package)
                )
                if package.status == .ended {
                    FCLabelValueRow(
                        label: String(localized: "packageDetail.status"),
                        value: String(localized: "coursePackages.statusEnded")
                    )
                }
                FCListRowDivider()
            }

            FCSectionLabel(String(localized: "packageDetail.adjustments"))

            if adjustments.isEmpty {
                Text(String(localized: "creditTrail.empty"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(adjustments) { adjustment in
                        adjustmentRow(adjustment)
                        FCListRowDivider()
                    }
                }
            }
        }
    }

    /// "− 扣减 1 课时 / 完成训练 · 备注 ... 9月1日"
    private func adjustmentRow(_ adjustment: CreditAdjustment) -> some View {
        HStack(alignment: .top, spacing: FCPrimitives.space3) {
            FCSymbol(adjustment.direction == .debit ? .minus : .plus, color: FCSemanticColors.textPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                Text(PackageDetailPresentation.amountTitle(adjustment))
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                Text(PackageDetailPresentation.reason(adjustment))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            Spacer(minLength: FCPrimitives.space2)
            Text(PackageDetailPresentation.day(adjustment.createdAtUTC))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
        .padding(.vertical, FCPrimitives.space3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(FCAccessibilityID.creditTrailRow(adjustment.id))
    }
}

enum PackageDetailPresentation {
    /// "扣减 1 课时" / "返还 1 课时"
    static func amountTitle(_ adjustment: CreditAdjustment) -> String {
        let format = adjustment.direction == .debit
            ? String(localized: "packageDetail.debitFormat")
            : String(localized: "packageDetail.creditFormat")
        return String(format: format, adjustment.amount)
    }

    /// "完成训练" plus the coach's reason text, if any.
    static func reason(_ adjustment: CreditAdjustment) -> String {
        let title: String
        switch adjustment.reasonKind {
        case .sessionComplete: title = String(localized: "creditTrail.reason.sessionComplete")
        case .appointmentAbsent: title = String(localized: "creditTrail.reason.appointmentAbsent")
        case .adhocSession: title = String(localized: "creditTrail.reason.adhocSession")
        case .manualCorrection: title = String(localized: "creditTrail.reason.manualCorrection")
        case .sessionReopen: title = String(localized: "creditTrail.reason.sessionReopen")
        }
        guard let text = adjustment.reasonText?.value, !text.isEmpty else {
            return title
        }
        return "\(title) · \(text)"
    }

    /// "9月1日" in the device's time zone.
    static func day(_ instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: instant)
    }

    /// "2026年12月31日", or "长期有效" without an end date.
    static func validity(_ package: CoursePackage) -> String {
        guard let end = package.endDate else {
            return String(localized: "packageDetail.noEndDate")
        }
        return "\(end.year)年\(end.month)月\(end.day)日"
    }
}

/// A single package's page (route `.creditAdjustmentTrail`), used for
/// historical packages: the same 04 layout, read-only.
@MainActor
final class CreditAdjustmentTrailViewModel: ObservableObject {
    @Published var package: CoursePackage?
    @Published var adjustments: [CreditAdjustment] = []
    @Published var balance: Int = 0
    @Published var errorMessage: String?

    let packageID: StableUUID
    private let useCases: CreditLedgerUseCases

    init(packageID: StableUUID, useCases: CreditLedgerUseCases) {
        self.packageID = packageID
        self.useCases = useCases
    }

    func reload() async {
        do {
            package = try await useCases.package(id: packageID)
            adjustments = try await useCases.adjustments(packageID: packageID)
                .sorted { $0.createdAtUTC > $1.createdAtUTC }
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
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(title: viewModel.package?.displayName ?? String(localized: "packageDetail.title"), back: .init())

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if let package = viewModel.package {
                    PackageDetailContent(
                        studentName: nil,
                        package: package,
                        balance: viewModel.balance,
                        adjustments: viewModel.adjustments
                    )
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.creditTrailRoot)
        .task { await viewModel.reload() }
    }
}
