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
        VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
            Text(String(localized: "backup.restore.warning"))
                .accessibilityIdentifier(FCAccessibilityID.restoreWarning)
            Text(String(localized: "backup.restore.suggestBackup"))
                .foregroundStyle(FCSemanticColors.secondaryText)
                .accessibilityIdentifier(FCAccessibilityID.restoreSuggestBackup)
            SecureField(String(localized: "backup.restore.password"), text: $viewModel.password)
                .textContentType(.password)
                .frame(minHeight: 44)
                .accessibilityIdentifier(FCAccessibilityID.restorePassword)
            FCButton(
                title: String(localized: "backup.restore.pickFile"),
                isEnabled: !viewModel.isRestoring,
                action: {
                    isImporterPresented = true
                }
            )
            .accessibilityIdentifier(FCAccessibilityID.restorePickFile)
            if let pickedFileName = viewModel.pickedFileName {
                Text(pickedFileName)
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)
            }
            if viewModel.isRestoring {
                ProgressView(String(localized: "backup.restore.working"))
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(FCSemanticColors.destructive)
            }
            if viewModel.failed {
                Text(String(localized: "backup.restore.failed"))
                    .foregroundStyle(FCSemanticColors.destructive)
                    .accessibilityIdentifier(FCAccessibilityID.restoreFailed)
            }
            FCButton(
                title: String(localized: "backup.restore.confirm"),
                isEnabled: !viewModel.isRestoring,
                action: {
                    viewModel.restore(using: environment)
                }
            )
            .accessibilityIdentifier(FCAccessibilityID.restoreConfirm)
            if viewModel.showsRetry {
                FCButton(
                    title: String(localized: "backup.retry"),
                    isEnabled: !viewModel.isRestoring,
                    action: {
                        viewModel.restore(using: environment)
                    }
                )
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
}
