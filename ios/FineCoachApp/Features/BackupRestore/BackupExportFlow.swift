import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var fineCoachBackup: UTType {
        UTType(exportedAs: "com.finecoach.backup")
    }
}

@MainActor
final class BackupExportFlowViewModel: ObservableObject {
    @Published var password = ""
    @Published var passwordConfirm = ""
    @Published var exportStatus: String?
    @Published var errorMessage: String?
    @Published var showsRetry = false
    @Published var isExporting = false

    private let coordinator: BackupCoordinator
    private let exporter = UIKitDocumentExportPresenter()
    private var exportTask: Task<Void, Never>?

    init(coordinator: BackupCoordinator) {
        self.coordinator = coordinator
    }

    func export() {
        guard !isExporting else {
            return
        }
        exportTask?.cancel()
        exportTask = Task { await performExport() }
    }

    func cancelInFlight() {
        exportTask?.cancel()
        isExporting = false
        clearPasswords()
    }

    /// The 口令 must not outlive the export flow in memory (T052 finding 3).
    private func clearPasswords() {
        password = ""
        passwordConfirm = ""
    }

    private func performExport() async {
        isExporting = true
        defer { isExporting = false }
        exportStatus = nil
        errorMessage = nil
        showsRetry = false

        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-FineCoachSimulateBackupExportCancel")
                || arguments.contains("-FineCoachSimulateBackupExportFailure")
            {
                showsRetry = true
                return
            }
            if arguments.contains("-FineCoachSimulateBackupExportCompletion") {
                exportStatus = String(localized: "backup.export.handedOff")
                return
            }
        #endif

        guard password == passwordConfirm else {
            errorMessage = String(localized: "backup.password.mismatch")
            showsRetry = true
            return
        }
        var handedOffDirectory: URL?
        do {
            let created = try BackupPassword(creating: password)
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            handedOffDirectory = destination
            let result = try await coordinator.exportInventory(
                BackupExportRequest(password: created, destinationDirectory: destination)
            )
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            let outcome = await exporter.export(fileURL: result.fileURL)
            try? FileManager.default.removeItem(at: destination)
            handedOffDirectory = nil
            switch outcome {
            case .completed:
                exportStatus = String(localized: "backup.export.handedOff")
                clearPasswords()
            case .cancelled, .failed:
                showsRetry = true
            }
        } catch {
            if let handedOffDirectory {
                try? FileManager.default.removeItem(at: handedOffDirectory)
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
            showsRetry = true
        }
    }
}

/// 08 备份与恢复 (T071, `08-backup-restore`): title + subtitle, then the
/// 导出 and 恢复 sections split by a divider. The artwork draws the two
/// password fields under 恢复; they belong to export (set + confirm the
/// 口令), while restore needs one 口令 and a file -- placed by function,
/// backup/restore logic unchanged.
struct BackupExportFlowView: View {
    @StateObject private var viewModel: BackupExportFlowViewModel
    @Binding var path: [RootDestination]
    private let coordinator: BackupCoordinator

    init(coordinator: BackupCoordinator, path: Binding<[RootDestination]>) {
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: BackupExportFlowViewModel(coordinator: coordinator))
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FCPageHeader(title: String(localized: "backup.title"), back: .init())
                Text(String(localized: "backup.subtitle"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .padding(.top, FCPrimitives.space3)

                exportSection
                    .padding(.top, FCPrimitives.space6)

                FCListRowDivider()
                    .padding(.vertical, FCPrimitives.space6)

                BackupRestoreFlowView(coordinator: coordinator, path: $path)
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(FCAccessibilityID.backupRoot)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .onDisappear {
            viewModel.cancelInFlight()
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space3) {
            FCSectionLabel(String(localized: "backup.export.section"))
            Text(String(localized: "backup.export.lead"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
            FCTextField(String(localized: "backup.password.placeholder"), text: $viewModel.password, isSecure: true)
                .textContentType(.password)
                .accessibilityIdentifier(FCAccessibilityID.backupPassword)
            FCTextField(
                String(localized: "backup.passwordConfirm.placeholder"),
                text: $viewModel.passwordConfirm,
                isSecure: true
            )
            .textContentType(.password)
            .accessibilityIdentifier(FCAccessibilityID.backupPasswordConfirm)
            Text(String(localized: "backup.password.hint"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityIdentifier(FCAccessibilityID.backupPasswordHint)

            if viewModel.isExporting {
                ProgressView(String(localized: "backup.export.working"))
                    .tint(FCSemanticColors.actionPrimary)
                    .fcFont(.callout, weight: .regular)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
            }
            if let exportStatus = viewModel.exportStatus {
                Text(exportStatus)
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .accessibilityIdentifier(FCAccessibilityID.backupExportStatus)
            }

            FCButton(
                title: String(localized: "backup.export"),
                isEnabled: !viewModel.isExporting,
                action: {
                    viewModel.export()
                }
            )
            .padding(.top, FCPrimitives.space1)
            .accessibilityIdentifier(FCAccessibilityID.backupExport)

            if viewModel.showsRetry {
                FCLinkButton(title: String(localized: "backup.retry"), isEnabled: !viewModel.isExporting) {
                    viewModel.export()
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(FCAccessibilityID.backupRetry)
            }
        }
    }
}
