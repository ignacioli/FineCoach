import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BackupRestoreFlowViewModel: ObservableObject {
    @Published var password = ""
    @Published var errorMessage: String?
    @Published var failed = false
    /// Restore committed and the live stack reloaded: show 恢复完成 in place
    /// (owner 2026-09-29) so the coach knows to check the restored data.
    @Published var succeeded = false
    @Published var showsRetry = false
    @Published var isRestoring = false
    @Published var pickedFileURL: URL?
    @Published var pickedFileName: String?
    @Published var isConfirmingRestore = false

    private let coordinator: BackupCoordinator
    private var restoreTask: Task<Void, Never>?

    init(coordinator: BackupCoordinator) {
        self.coordinator = coordinator
    }

    func requestRestore() {
        guard !isRestoring else {
            return
        }
        isConfirmingRestore = true
    }

    func confirmRestore(using environment: AppEnvironment) {
        guard isConfirmingRestore, !isRestoring else {
            return
        }
        isConfirmingRestore = false
        restoreTask?.cancel()
        restoreTask = Task { await restoreNow(using: environment) }
    }

    func cancelInFlight() {
        restoreTask?.cancel()
        isConfirmingRestore = false
        isRestoring = false
        password = ""
    }

    func restoreNow(using environment: AppEnvironment) async {
        isRestoring = true
        defer { isRestoring = false }
        errorMessage = nil
        failed = false
        succeeded = false
        showsRetry = false

        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-FineCoachSimulateRestoreFailure") {
                failed = true
                showsRetry = true
                return
            }
            if arguments.contains("-FineCoachSimulateRestoreCompletion") {
                succeeded = true
                return
            }
        #endif

        guard let sourceURL = pickedFileURL else {
            failed = true
            showsRetry = true
            errorMessage = String(localized: "backup.restore.needFile")
            return
        }
        do {
            let imported = try BackupPassword(importing: password)
            try await coordinator.restoreReplacingCurrent(
                BackupRestoreRequest(password: imported, sourceFileURL: sourceURL)
            )
            try environment.reloadAfterCommittedRestore()
            // The widget snapshot still names the replaced data's Students;
            // rebuild it from the restored store now, not on next foreground.
            await environment.widgetSnapshotPublisher?.refresh()
            // The restored generation is verified and opened before the
            // current catalog comparison. The restore result is reported
            // separately from catalogUnavailableMessage if this follow-up
            // sync cannot complete; the next launch retries the same path.
            await environment.prepareExerciseCatalog()
            succeeded = true
            password = ""
        } catch {
            failed = true
            showsRetry = true
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }
}

struct BackupRestoreFlowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: BackupRestoreFlowViewModel
    @Binding var path: [RootDestination]
    @State private var isImporterPresented = false

    init(coordinator: BackupCoordinator, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(wrappedValue: BackupRestoreFlowViewModel(coordinator: coordinator))
        _path = path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space3) {
            FCSectionLabel(String(localized: "backup.restore.section"))
            Text(String(localized: "backup.restore.warning"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityIdentifier(FCAccessibilityID.restoreWarning)
            Text(String(localized: "backup.restore.suggestBackup"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityIdentifier(FCAccessibilityID.restoreSuggestBackup)
            FCSecondaryButton(
                title: String(localized: "backup.restore.pickFile"),
                isEnabled: !viewModel.isRestoring,
                action: {
                    isImporterPresented = true
                }
            )
            .accessibilityIdentifier(FCAccessibilityID.restorePickFile)
            if let pickedFileName = viewModel.pickedFileName {
                Text(pickedFileName)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            FCTextField(String(localized: "backup.restore.password"), text: $viewModel.password, isSecure: true)
                .textContentType(.password)
                .accessibilityIdentifier(FCAccessibilityID.restorePassword)
            if viewModel.isRestoring {
                ProgressView(String(localized: "backup.restore.working"))
                    .tint(FCSemanticColors.actionPrimary)
                    .fcFont(.callout, weight: .regular)
            }
            FCButton(
                title: String(localized: "backup.restore.confirm"),
                isEnabled: !viewModel.isRestoring,
                action: {
                    viewModel.requestRestore()
                }
            )
            .padding(.top, FCPrimitives.space1)
            .accessibilityIdentifier(FCAccessibilityID.restoreConfirm)

            if viewModel.succeeded {
                successState
                    .padding(.top, FCPrimitives.space4)
            }
            if viewModel.failed {
                failureState
                    .padding(.top, FCPrimitives.space4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.restoreRoot)
        .fcConfirmationDialog(isPresented: $viewModel.isConfirmingRestore) {
            FCConfirmationDialog(
                title: String(localized: "backup.restore.replaceConfirm.title"),
                message: String(localized: "backup.restore.replaceConfirm.message"),
                cancelAction: .init(
                    title: String(localized: "backup.restore.replaceConfirm.cancel"),
                    accessibilityIdentifier: FCAccessibilityID.restoreReplaceCancel
                ) {
                    viewModel.isConfirmingRestore = false
                },
                confirmAction: .init(
                    title: String(localized: "backup.restore.replaceConfirm.confirm"),
                    accessibilityIdentifier: FCAccessibilityID.restoreReplaceConfirm
                ) {
                    viewModel.confirmRestore(using: environment)
                }
            )
        }
        .onDisappear {
            viewModel.cancelInFlight()
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.fineCoachBackup, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.pickedFileURL = url
                viewModel.pickedFileName = url.lastPathComponent
            }
        }
    }

    /// 恢复完成: an `action.primary` ✓ result (informational, §7.2) with a
    /// prompt to check the restored data. Text only -- no navigation link
    /// (owner 2026-09-29).
    private var successState: some View {
        FCInlineResult(
            .success,
            title: String(localized: "backup.restore.succeededTitle"),
            message: String(localized: "backup.restore.succeeded"),
            accessibilityIdentifier: FCAccessibilityID.restoreSucceeded
        )
    }

    /// 08's failure result: "恢复失败" in `status.destructive` with a "!" badge
    /// (state is never color-only, NFR-005 / §7.2), then why and that the
    /// current data is untouched, plus 重试.
    private var failureState: some View {
        FCInlineResult(
            .failure,
            title: String(localized: "backup.restore.failedTitle"),
            message: viewModel.errorMessage ?? String(localized: "backup.restore.failed"),
            retry: retryAction,
            accessibilityIdentifier: FCAccessibilityID.restoreFailed
        )
    }

    private var retryAction: FCInlineResult.Retry? {
        guard viewModel.showsRetry else { return nil }
        return FCInlineResult.Retry(
            title: String(localized: "backup.retry"),
            isEnabled: !viewModel.isRestoring,
            accessibilityIdentifier: FCAccessibilityID.restoreRetry,
            handler: { viewModel.requestRestore() }
        )
    }
}
