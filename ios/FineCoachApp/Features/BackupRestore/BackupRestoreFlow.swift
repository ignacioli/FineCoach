import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BackupRestoreFlowViewModel: ObservableObject {
    @Published var password = ""
    @Published var errorMessage: String?
    @Published var failed = false
    @Published var showsRetry = false
    @Published var isRestoring = false
    @Published var pickedFileURL: URL?
    @Published var pickedFileName: String?

    private let coordinator: BackupCoordinator
    private var restoreTask: Task<Void, Never>?

    init(coordinator: BackupCoordinator) {
        self.coordinator = coordinator
    }

    func restore(using environment: AppEnvironment) {
        guard !isRestoring else {
            return
        }
        restoreTask?.cancel()
        restoreTask = Task { await performRestore(using: environment) }
    }

    func cancelInFlight() {
        restoreTask?.cancel()
        isRestoring = false
    }

    private func performRestore(using environment: AppEnvironment) async {
        isRestoring = true
        defer { isRestoring = false }
        errorMessage = nil
        failed = false
        showsRetry = false

        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-FineCoachSimulateRestoreFailure") {
                failed = true
                showsRetry = true
                return
            }
            if arguments.contains("-FineCoachSimulateRestoreCompletion") {
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
                    viewModel.restore(using: environment)
                }
            )
            .padding(.top, FCPrimitives.space1)
            .accessibilityIdentifier(FCAccessibilityID.restoreConfirm)

            if viewModel.failed {
                failureState
                    .padding(.top, FCPrimitives.space4)
            }
            if viewModel.showsRetry {
                FCLinkButton(title: String(localized: "backup.retry"), isEnabled: !viewModel.isRestoring) {
                    viewModel.restore(using: environment)
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(FCAccessibilityID.restoreRetry)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.restoreRoot)
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

    /// 08's failure block: "恢复失败" in `status.destructive` with a "!" badge
    /// (state is never color-only, NFR-005 / §7.2), then why and that the
    /// current data is untouched.
    private var failureState: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space1) {
            HStack(spacing: FCPrimitives.space2) {
                FCStatusBadge(symbolName: "exclamationmark", color: FCSemanticColors.statusDestructive)
                Text(String(localized: "backup.restore.failedTitle"))
                    .fcFont(.callout, weight: .semibold)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
            }
            Text(viewModel.errorMessage ?? String(localized: "backup.restore.failed"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(FCAccessibilityID.restoreFailed)
    }
}
