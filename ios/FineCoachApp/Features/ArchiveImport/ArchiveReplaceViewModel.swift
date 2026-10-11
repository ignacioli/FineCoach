import Foundation
import SwiftUI

/// State of the 「导入较新档案」 pages (M2-19a/b). Like the import model it holds only
/// `ArchiveImportUseCases` (no Coach use case); the password lives in memory and is dropped when
/// the candidate is confirmed, cancelled or the page is left.
@MainActor
final class ArchiveReplaceViewModel: ObservableObject {
    enum Phase: Equatable {
        /// File row, password, 「导入」 (M2-19b without a result).
        case form
        /// Validating the candidate.
        case working
        /// The candidate passed; current and new facts, waiting for 「替换为新档案」 (M2-19a).
        case confirm(ArchiveReplacementPreview)
        /// Replacing.
        case committing(ArchiveReplacementPreview)
        /// Rejected or interrupted; the installed archive is unchanged (M2-19b).
        case rejected(ArchiveReplaceFailure)
    }

    @Published var fileURL: URL?
    @Published var password = ""
    @Published var isPickerPresented = false
    @Published private(set) var phase: Phase = .form
    /// Set once the installed archive was replaced; the host reloads the viewer.
    @Published private(set) var replaced = false

    /// The Inbox copy a system open prefilled; deleted when the flow ends.
    let prefilledURL: URL?
    private let useCases: ArchiveImportUseCases

    init(useCases: ArchiveImportUseCases, prefilledURL: URL?) {
        self.useCases = useCases
        self.prefilledURL = prefilledURL
        self.fileURL = prefilledURL
    }

    var isBusy: Bool {
        switch phase {
        case .working, .committing: return true
        case .form, .confirm, .rejected: return false
        }
    }

    var canImport: Bool {
        fileURL != nil && !password.isEmpty && !isBusy
    }

    var failure: ArchiveReplaceFailure? {
        if case .rejected(let failure) = phase { return failure }
        return nil
    }

    func fileChosen(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            fileURL = url
            if case .rejected = phase { phase = .form }
        }
    }

    /// 「导入」: validates the candidate and, when it may replace the installed archive, moves to
    /// the confirmation facts. Nothing is written.
    func submit() async {
        guard canImport, let fileURL else { return }
        phase = .working
        do {
            phase = .confirm(try await useCases.prepareReplacement(from: fileURL, password: password))
        } catch let failure as ArchiveReplaceFailure {
            switch failure {
            case .importInProgress:
                phase = .working
            case .noPendingReplacement:
                phase = .form
            default:
                phase = .rejected(failure)
            }
        } catch {
            phase = .rejected(.interrupted)
        }
    }

    /// 「替换为新档案」, the explicit confirmation (M2-FR-038). A second tap while replacing is
    /// ignored.
    func confirm() async {
        guard case .confirm(let preview) = phase else { return }
        phase = .committing(preview)
        do {
            _ = try await useCases.confirmReplacement()
            password = ""
            replaced = true
            await finish()
        } catch let failure as ArchiveReplaceFailure {
            password = ""
            phase = .rejected(failure)
        } catch {
            password = ""
            phase = .rejected(.interrupted)
        }
    }

    /// Back from the confirmation facts to the form: the candidate and the password are dropped.
    func backToForm() async {
        guard case .confirm = phase else { return }
        await useCases.cancelReplacement()
        password = ""
        phase = .form
    }

    /// Ends the flow's use of the prefilled file: only the Inbox copy is deleted, never the
    /// file the user picked (D-010, M2-FR-024). Called on every exit.
    func finish() async {
        password = ""
        await useCases.cancelReplacement()
        if let prefilledURL {
            await useCases.discardInboxCopy(at: prefilledURL)
        }
    }
}
