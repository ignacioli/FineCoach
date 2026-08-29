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

struct BackupExportFlowView: View {
    @StateObject private var viewModel: BackupExportFlowViewModel
    @Binding var path: [RootDestination]
    @State private var showingRestore = false
    private let coordinator: BackupCoordinator

    init(coordinator: BackupCoordinator, path: Binding<[RootDestination]>) {
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: BackupExportFlowViewModel(coordinator: coordinator))
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                SecureField(String(localized: "backup.password.placeholder"), text: $viewModel.password)
                    .textContentType(.password)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.backupPassword)
                SecureField(String(localized: "backup.passwordConfirm.placeholder"), text: $viewModel.passwordConfirm)
                    .textContentType(.password)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.backupPasswordConfirm)
                Text(String(localized: "backup.password.hint"))
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)
                    .accessibilityIdentifier(FCAccessibilityID.backupPasswordHint)

                if viewModel.isExporting {
                    ProgressView(String(localized: "backup.export.working"))
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FCSemanticColors.destructive)
                }
                if let exportStatus = viewModel.exportStatus {
                    Text(exportStatus)
                        .accessibilityIdentifier(FCAccessibilityID.backupExportStatus)
                }

                FCButton(
                    title: String(localized: "backup.export"),
                    isEnabled: !viewModel.isExporting,
                    action: {
                        viewModel.export()
                    }
                )
                .accessibilityIdentifier(FCAccessibilityID.backupExport)

                if viewModel.showsRetry {
                    FCButton(
                        title: String(localized: "backup.retry"),
                        isEnabled: !viewModel.isExporting,
                        action: {
                            viewModel.export()
                        }
                    )
                    .accessibilityIdentifier(FCAccessibilityID.backupRetry)
                }

                FCButton(
                    title: String(localized: "backup.restore.entry"),
                    isEnabled: !viewModel.isExporting,
                    action: {
                        showingRestore = true
                    }
                )
                .accessibilityIdentifier(FCAccessibilityID.restoreImporter)

                if showingRestore {
                    BackupRestoreFlowView(coordinator: coordinator, path: $path)
                }
            }
            .padding(FCPrimitives.spacingMedium)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(FCAccessibilityID.backupRoot)
        }
        .safeAreaInset(edge: .bottom) {
            FCButton(
                title: String(localized: "backup.cancel"),
                action: {
                    viewModel.cancelInFlight()
                    path.removeAll()
                }
            )
            .padding(.horizontal, FCPrimitives.spacingMedium)
            .padding(.bottom, FCPrimitives.spacingSmall)
            .accessibilityIdentifier(FCAccessibilityID.backupCancel)
        }
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "backup.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            viewModel.cancelInFlight()
        }
    }
}
