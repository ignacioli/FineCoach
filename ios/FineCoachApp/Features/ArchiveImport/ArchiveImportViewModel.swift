import Foundation
import SwiftUI

/// State of the import page (M2-08) and what it hands to its host. It holds only the archive
/// import use case; the password lives in memory and is dropped when the model goes away.
@MainActor
final class ArchiveImportViewModel: ObservableObject {
    enum Phase: Equatable {
        case form
        case importing
        case failed(ArchiveImportFailure)
    }

    /// What the host does next.
    enum Outcome: Equatable {
        case imported(ArchiveImportSummary)
        /// A Coach install appeared (M2-FR-026): show M2-09.
        case blocked
        /// An archive is already installed: the host re-resolves the install state.
        case alreadyInstalled
    }

    @Published var fileURL: URL?
    @Published var password = ""
    @Published var isPickerPresented = false
    @Published private(set) var phase: Phase = .form
    @Published private(set) var outcome: Outcome?

    /// The Inbox copy a system open prefilled; deleted when the flow ends.
    let prefilledURL: URL?
    private let useCases: ArchiveImportUseCases

    init(useCases: ArchiveImportUseCases, prefilledURL: URL?) {
        self.useCases = useCases
        self.prefilledURL = prefilledURL
        self.fileURL = prefilledURL
    }

    var canImport: Bool {
        fileURL != nil && !password.isEmpty && phase != .importing
    }

    var failure: ArchiveImportFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    func fileChosen(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            fileURL = url
            if case .failed = phase { phase = .form }
        }
    }

    func submit() async {
        guard canImport, let fileURL else { return }
        phase = .importing
        do {
            let summary = try await useCases.importArchive(from: fileURL, password: password)
            password = ""
            phase = .form
            outcome = .imported(summary)
            await finish()
        } catch let failure as ArchiveImportFailure {
            switch failure {
            case .interrupted:
                // Back to the pre-import state without an error (contract §6).
                phase = .form
            case .blockedByCoachData:
                phase = .form
                outcome = .blocked
                await finish()
            case .alreadyInstalled:
                phase = .form
                outcome = .alreadyInstalled
                await finish()
            case .importInProgress:
                phase = .importing
            case .wrongPasswordOrCorrupted, .incompatibleVersion, .invalidArchive, .installStateUnavailable:
                phase = .failed(failure)
            }
        } catch {
            phase = .form
        }
    }

    /// Ends the flow's use of the prefilled file: only the Inbox copy is deleted, never the
    /// file the user picked (D-010, M2-FR-024). Called on every exit.
    func finish() async {
        password = ""
        if let prefilledURL {
            await useCases.discardInboxCopy(at: prefilledURL)
        }
    }
}
