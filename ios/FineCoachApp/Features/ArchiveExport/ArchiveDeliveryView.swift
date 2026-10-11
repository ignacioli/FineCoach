import SwiftUI

/// M2-06a to M2-06d 交付档案 (T034a). Binds only to the flow state: generated, handed to the
/// system, cancelled, failed. The single 「交给系统…」 button also serves as the retry entry
/// after 「已取消」 or 「交付失败」 (the view model regenerates from the flow's in-memory
/// snapshot, then hands over). After handing over, the page-bottom 「完成」 leaves the flow.
/// "Handed to the system" never claims the student received the file (M2-FR-022).
struct ArchiveDeliveryView: View {
    @ObservedObject var model: ArchiveExportViewModel
    let onFinish: () -> Void

    private var isHandedOver: Bool { model.state == .handedToSystem }

    var body: some View {
        ArchiveExportPage {
            FCPageHeader(
                title: String(localized: "archive.export.delivery.title"),
                subtitle: String(format: String(localized: "archive.export.delivery.subtitle"), model.displayName),
                back: model.headerBack
            )
            result
            if !isHandedOver {
                FCButton(title: String(localized: "archive.export.delivery.deliver"), isEnabled: !model.isBusy) {
                    Task { await model.deliver() }
                }
                .accessibilityIdentifier(FCAccessibilityID.archiveExportDeliver)
            }
            Text(String(localized: "archive.export.delivery.caption"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if isHandedOver {
                FCButton(title: String(localized: "archive.export.delivery.done"), action: onFinish)
                    .accessibilityIdentifier(FCAccessibilityID.archiveExportDone)
                    .padding(.horizontal, FCPrimitives.space4)
                    .padding(.vertical, FCPrimitives.space2)
                    .background(FCSemanticColors.surfacePage)
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.state {
        case .handedToSystem:
            FCInlineResult(
                .success,
                title: String(localized: "archive.export.delivery.handed.title"),
                message: String(localized: "archive.export.delivery.handed.message"),
                accessibilityIdentifier: FCAccessibilityID.archiveExportDeliveryResult
            )
        case .cancelled:
            FCInlineResult(
                .info,
                title: String(localized: "archive.export.delivery.cancelled.title"),
                message: String(localized: "archive.export.delivery.cancelled.message"),
                accessibilityIdentifier: FCAccessibilityID.archiveExportDeliveryResult
            )
        case .failed:
            FCInlineResult(
                .failure,
                title: String(localized: "archive.export.delivery.failed.title"),
                message: String(localized: "archive.export.delivery.failed.message"),
                accessibilityIdentifier: FCAccessibilityID.archiveExportDeliveryResult
            )
        default:
            FCInlineResult(
                .success,
                title: String(localized: "archive.export.delivery.generated.title"),
                message: String(localized: "archive.export.delivery.generated.message"),
                accessibilityIdentifier: FCAccessibilityID.archiveExportDeliveryResult
            )
        }
    }
}
