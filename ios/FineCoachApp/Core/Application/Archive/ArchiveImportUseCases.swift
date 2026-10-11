import Foundation

// M2 first-import use case (T040, plan §7.2, contract archive-file-v1 §5-§6).
//
// UI binding: the import page (M2-08) calls `importArchive(from:password:)` with the file the
// user picked (or the system opened) and the password text. While it runs, `state` is
// `.importing`; the call returns an `ArchiveImportSummary` (M2-10) or throws an
// `ArchiveImportFailure`, which maps one-to-one onto the reason categories of
// `design/m2-hifi/implementation-map.md` §5. Nothing here holds Coach write use cases.
//
// Replacement (US-3) is two steps on the same type: `prepareReplacement` validates in memory and
// applies `ArchiveReplacementPolicy`, `confirmReplacement` commits the held candidate after the
// user agreed (M2-FR-038). A rejected or interrupted replacement leaves the installed snapshot
// byte-identical (M2-FR-039).
//
// Fail-closed order: cancellation -> install state (a Coach install never reads the file) ->
// read -> decode and validate in memory (contract §5) -> commit through
// `ArchiveSnapshotStore`. Any failure drops the in-memory plaintext and writes nothing;
// a failed commit additionally runs the store janitor so no orphan generation is left.

/// Why a first import did not create an archive. The UI owns all wording.
public enum ArchiveImportFailure: Error, Equatable, Sendable {
    /// Wrong password, tampering, truncation, appended bytes, reordered chunks.
    case wrongPasswordOrCorrupted
    /// Container / KDF / schema version this build cannot read.
    case incompatibleVersion
    /// Not an archive (including a Coach backup file), unreadable, over a resource limit, or
    /// authenticated but structurally invalid (references, counts, identity metadata).
    case invalidArchive
    /// Coach data or a completed Coach onboarding exists (M2-FR-026). The file was not read.
    case blockedByCoachData
    /// An archive is already installed; replacing it is the "import a newer archive" flow
    /// (US-3), not a first import. The file was not read.
    case alreadyInstalled
    /// The Coach store could not be read, so "no Coach data" cannot be shown. Fails closed;
    /// the file was not read.
    case installStateUnavailable
    /// Cancelled, or the commit did not complete. The install is back in its pre-import state
    /// and the UI shows no error (contract §6).
    case interrupted
    /// A second import was requested while one is running (duplicate tap).
    case importInProgress
}

/// Facts for the success summary (M2-10, M2-FR-029). Nothing sensitive: no student name.
public struct ArchiveImportSummary: Equatable, Sendable {
    /// The four digits of 「来源 · NNNN」 (D-007).
    public let sourceLabel: String
    public let snapshotAtUTC: Date
    public let modules: ArchiveModuleSet

    public init(sourceLabel: String, snapshotAtUTC: Date, modules: ArchiveModuleSet) {
        self.sourceLabel = sourceLabel
        self.snapshotAtUTC = snapshotAtUTC
        self.modules = modules
    }
}

public enum ArchiveImportState: Equatable, Sendable {
    case idle
    case importing
    case imported(ArchiveImportSummary)
    case failed(ArchiveImportFailure)
}

/// Why a replacement did not happen (US-3, M2-FR-039). Whatever the reason, the installed
/// snapshot is untouched. The UI owns all wording (implementation map §5).
public enum ArchiveReplaceFailure: Error, Equatable, Sendable {
    /// Candidate `snapshotAtUTC` is older than or equal to the installed one (D-004).
    case notNewer
    /// Candidate comes from another Coach install.
    case differentSource
    /// Candidate belongs to another student of the same source.
    case differentStudent
    case wrongPasswordOrCorrupted
    case incompatibleVersion
    case invalidArchive
    /// No readable archive is installed, so there is nothing to replace.
    case notInstalled
    /// Cancelled, or the commit did not complete. The installed snapshot stands.
    case interrupted
    /// A second import or replacement was requested while one is running.
    case importInProgress
    /// `confirmReplacement()` without a validated candidate.
    case noPendingReplacement
}

/// What the confirmation page (M2-19a) shows before the user agrees (M2-FR-038).
public struct ArchiveReplacementPreview: Equatable, Sendable {
    public let current: ArchiveImportSummary
    public let candidate: ArchiveImportSummary

    public init(current: ArchiveImportSummary, candidate: ArchiveImportSummary) {
        self.current = current
        self.candidate = candidate
    }
}

/// Reads the bytes of the chosen archive. The default implementation goes through
/// `SecurityScopedFileAdapter`; tests inject a recorder to prove a branch never reads.
public protocol ArchiveFileReading: Sendable {
    func readArchive(at url: URL) throws -> Data
}

public struct SecurityScopedArchiveFileReader: ArchiveFileReading {
    private let adapter: SecurityScopedFileAdapter

    public init(adapter: SecurityScopedFileAdapter = SecurityScopedFileAdapter()) {
        self.adapter = adapter
    }

    /// Rejects anything that is not a regular file no larger than the largest legal archive
    /// before reading it (plan §7.3).
    public func readArchive(at url: URL) throws -> Data {
        try adapter.withAccess(to: url) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                let size = values.fileSize,
                size <= ArchiveFileV1.maxFileBytes
            else {
                throw ArchiveFileError.invalidArchive
            }
            return try Data(contentsOf: url)
        }
    }
}

public actor ArchiveImportUseCases {
    public private(set) var state: ArchiveImportState = .idle

    private let store: ArchiveSnapshotStore
    private let resolver: InstallStateResolver
    private let reader: any ArchiveFileReading
    private let logger: any AppLogging
    private let inboxRootURL: URL?
    private var isRunning = false
    /// The decoded candidate of a validated replacement, held in memory only until the user
    /// confirms, cancels or leaves the page. Never written anywhere before the commit.
    private var pendingReplacement: ArchiveSnapshot?

    /// - Parameters:
    ///   - resolver: the same install-state resolver the app root uses (viewer > coach >
    ///     unselected). A first import runs only when it resolves to `unselected`.
    ///   - inboxRootURL: the app container's `Documents/Inbox`, the only place
    ///     `discardInboxCopy(at:)` may delete from. `nil` resolves it from the documents
    ///     directory.
    public init(
        store: ArchiveSnapshotStore,
        resolver: InstallStateResolver,
        reader: any ArchiveFileReading = SecurityScopedArchiveFileReader(),
        logger: any AppLogging = AppLogger.standard,
        inboxRootURL: URL? = nil
    ) {
        self.store = store
        self.resolver = resolver
        self.reader = reader
        self.logger = logger
        self.inboxRootURL = inboxRootURL
    }

    /// Where an archive opened from outside the app goes. Reads no file content (D-010).
    /// Throws `.installStateUnavailable` when the Coach store cannot be read.
    public func openDestination() async throws -> ArchiveOpenDestination {
        do {
            return ArchiveOpenRouter.destination(for: try await resolver.resolve())
        } catch {
            throw ArchiveImportFailure.installStateUnavailable
        }
    }

    /// Back to `idle` (the user left the page). Ignored while an import is running.
    public func reset() {
        guard !isRunning else {
            return
        }
        state = .idle
        pendingReplacement = nil
    }

    /// First import. See the file header for the order of checks.
    @discardableResult
    public func importArchive(from fileURL: URL, password rawPassword: String) async throws -> ArchiveImportSummary {
        guard !isRunning else {
            throw ArchiveImportFailure.importInProgress
        }
        isRunning = true
        state = .importing
        defer { isRunning = false }
        do {
            let summary = try await performImport(from: fileURL, password: rawPassword)
            state = .imported(summary)
            logger.info(.archiveImportCompleted, operation: .archiveImport)
            return summary
        } catch {
            let failure = (error as? ArchiveImportFailure) ?? .interrupted
            state = .failed(failure)
            log(failure)
            throw failure
        }
    }

    // MARK: Replacement (US-3)

    /// Step 1 of a replacement (viewer mode only): decodes and validates the candidate in
    /// memory, applies `ArchiveReplacementPolicy` against the installed snapshot and, when it
    /// accepts, keeps the candidate in memory for `confirmReplacement()`. Writes nothing; every
    /// failure leaves the installed snapshot untouched (M2-FR-039).
    public func prepareReplacement(from fileURL: URL, password rawPassword: String) async throws -> ArchiveReplacementPreview {
        guard !isRunning else {
            throw ArchiveReplaceFailure.importInProgress
        }
        isRunning = true
        pendingReplacement = nil
        defer { isRunning = false }
        do {
            let preview = try await performPrepare(from: fileURL, password: rawPassword)
            return preview
        } catch {
            let failure = (error as? ArchiveReplaceFailure) ?? .interrupted
            log(failure)
            throw failure
        }
    }

    /// Step 2: replaces the installed snapshot with the validated candidate as a whole
    /// (M2-FR-037, M2-FR-040). The policy is evaluated again against what is installed now.
    /// Display settings are kept by `ArchiveSnapshotStore.commit`.
    @discardableResult
    public func confirmReplacement() async throws -> ArchiveImportSummary {
        guard !isRunning else {
            throw ArchiveReplaceFailure.importInProgress
        }
        guard let candidate = pendingReplacement else {
            throw ArchiveReplaceFailure.noPendingReplacement
        }
        isRunning = true
        defer { isRunning = false }
        do {
            try Task.checkCancellation()
            let current = try await currentManifest()
            try Self.requireAccepted(current: current, candidate: candidate.manifest)
            let store = self.store
            do {
                try await Task.detached(priority: .userInitiated) {
                    try store.commit(snapshot: candidate)
                }.value
            } catch {
                // The installed snapshot stands; the janitor removes a generation the failed
                // commit may have left behind. Best effort: the launch janitor repeats it.
                try? store.runStartupJanitor()
                throw ArchiveReplaceFailure.interrupted
            }
            pendingReplacement = nil
            logger.info(.archiveReplaceCompleted, operation: .archiveReplace)
            return Self.summary(of: candidate.manifest)
        } catch is CancellationError {
            pendingReplacement = nil
            log(ArchiveReplaceFailure.interrupted)
            throw ArchiveReplaceFailure.interrupted
        } catch {
            pendingReplacement = nil
            let failure = (error as? ArchiveReplaceFailure) ?? .interrupted
            log(failure)
            throw failure
        }
    }

    /// The user left the confirmation page without confirming: the candidate is dropped.
    public func cancelReplacement() {
        pendingReplacement = nil
    }

    /// Deletes the copy the system placed in the app's `Documents/Inbox/` once a branch of the
    /// system-open flow ended (D-010). Never deletes anything outside the Inbox, so the
    /// original in "Files" or another app is untouched (M2-FR-024). Returns whether a file
    /// was deleted.
    @discardableResult
    public func discardInboxCopy(at url: URL) -> Bool {
        guard let inbox = inboxRoot() else {
            return false
        }
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        let root = inbox.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPath), file.path != root.path else {
            return false
        }
        return (try? FileManager.default.removeItem(at: file)) != nil
    }

    // MARK: Steps

    private func performImport(from fileURL: URL, password rawPassword: String) async throws -> ArchiveImportSummary {
        try Task.checkCancellation()

        // The install state comes first: a Coach install never reads the file (M2-FR-026).
        let installState: InstallState
        do {
            installState = try await resolver.resolve()
        } catch {
            throw ArchiveImportFailure.installStateUnavailable
        }
        switch installState {
        case .unselected: break
        case .coach: throw ArchiveImportFailure.blockedByCoachData
        case .viewer: throw ArchiveImportFailure.alreadyInstalled
        }

        let password: ArchivePassword
        do {
            password = try ArchivePassword(importing: rawPassword)
        } catch {
            throw ArchiveImportFailure.wrongPasswordOrCorrupted
        }

        let snapshot = try await decode(fileURL: fileURL, password: password)
        try Task.checkCancellation()

        let store = self.store
        do {
            try await Task.detached(priority: .userInitiated) {
                try store.commit(snapshot: snapshot)
            }.value
        } catch {
            // A failed first commit may have left a new generation behind; with no pointer the
            // janitor removes all of it. Best effort: the launch janitor repeats it.
            try? store.runStartupJanitor()
            throw ArchiveImportFailure.interrupted
        }
        return ArchiveImportSummary(
            sourceLabel: ArchiveIdentityService.shortLabel(forSourceID: snapshot.manifest.sourceID),
            snapshotAtUTC: snapshot.manifest.snapshotAtUTC,
            modules: snapshot.manifest.modules
        )
    }

    private func performPrepare(from fileURL: URL, password rawPassword: String) async throws -> ArchiveReplacementPreview {
        try Task.checkCancellation()

        // The installed snapshot comes first: with nothing to replace the file is not read.
        let current = try await currentManifest()

        let password: ArchivePassword
        do {
            password = try ArchivePassword(importing: rawPassword)
        } catch {
            throw ArchiveReplaceFailure.wrongPasswordOrCorrupted
        }
        let candidate: ArchiveSnapshot
        do {
            candidate = try await decode(fileURL: fileURL, password: password)
        } catch let failure as ArchiveImportFailure {
            throw Self.replaceFailure(for: failure)
        }
        try Task.checkCancellation()
        try Self.requireAccepted(current: current, candidate: candidate.manifest)
        pendingReplacement = candidate
        return ArchiveReplacementPreview(
            current: Self.summary(of: current),
            candidate: Self.summary(of: candidate.manifest)
        )
    }

    /// The manifest of the readable installed snapshot, loaded off the actor.
    private func currentManifest() async throws -> ArchiveManifest {
        let store = self.store
        let loaded = await Task.detached(priority: .userInitiated) { try? store.load() }.value
        guard let loaded else {
            throw ArchiveReplaceFailure.notInstalled
        }
        return loaded.manifest
    }

    private static func requireAccepted(current: ArchiveManifest, candidate: ArchiveManifest) throws {
        switch ArchiveReplacementPolicy.evaluate(current: current, candidate: candidate) {
        case .accept: return
        case .differentSource: throw ArchiveReplaceFailure.differentSource
        case .differentStudent: throw ArchiveReplaceFailure.differentStudent
        case .notNewer: throw ArchiveReplaceFailure.notNewer
        }
    }

    private static func summary(of manifest: ArchiveManifest) -> ArchiveImportSummary {
        ArchiveImportSummary(
            sourceLabel: ArchiveIdentityService.shortLabel(forSourceID: manifest.sourceID),
            snapshotAtUTC: manifest.snapshotAtUTC,
            modules: manifest.modules
        )
    }

    private static func replaceFailure(for failure: ArchiveImportFailure) -> ArchiveReplaceFailure {
        switch failure {
        case .wrongPasswordOrCorrupted: return .wrongPasswordOrCorrupted
        case .incompatibleVersion: return .incompatibleVersion
        case .interrupted: return .interrupted
        case .invalidArchive, .blockedByCoachData, .alreadyInstalled, .installStateUnavailable, .importInProgress:
            return .invalidArchive
        }
    }

    /// Reads and decodes off the actor (the key derivation is deliberately slow). The plaintext
    /// lives only inside the detached task.
    private func decode(fileURL: URL, password: ArchivePassword) async throws -> ArchiveSnapshot {
        let reader = self.reader
        let task = Task.detached(priority: .userInitiated) { () throws -> ArchiveSnapshot in
            let file = try reader.readArchive(at: fileURL)
            return try ArchiveFileCodec.decode(file: file, password: password)
        }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            throw Self.failure(for: error)
        }
    }

    private static func failure(for error: Error) -> ArchiveImportFailure {
        if error is CancellationError {
            return .interrupted
        }
        if let failure = error as? ArchiveImportFailure {
            return failure
        }
        switch error as? ArchiveFileError {
        case .wrongPasswordOrCorrupted: return .wrongPasswordOrCorrupted
        case .incompatibleVersion: return .incompatibleVersion
        case .notAnArchive, .invalidArchive: return .invalidArchive
        case nil:
            // Structural snapshot errors and unreadable files are "invalid file".
            return .invalidArchive
        }
    }

    private func inboxRoot() -> URL? {
        if let inboxRootURL {
            return inboxRootURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    private func log(_ failure: ArchiveReplaceFailure) {
        switch failure {
        case .notNewer:
            logger.failure(.archiveReplaceRejectedNotNewer, operation: .archiveReplace, category: .conflict)
        case .differentSource:
            logger.failure(.archiveReplaceRejectedSource, operation: .archiveReplace, category: .conflict)
        case .differentStudent:
            logger.failure(.archiveReplaceRejectedStudent, operation: .archiveReplace, category: .conflict)
        case .wrongPasswordOrCorrupted:
            logger.failure(.archiveImportRejectedCorrupted, operation: .archiveReplace, category: .validation)
        case .incompatibleVersion:
            logger.failure(.archiveImportRejectedIncompatible, operation: .archiveReplace, category: .incompatibleInput)
        case .invalidArchive:
            logger.failure(.archiveImportRejectedInvalid, operation: .archiveReplace, category: .validation)
        case .interrupted:
            logger.failure(.archiveReplaceInterrupted, operation: .archiveReplace, category: .externalCancelled)
        case .notInstalled, .importInProgress, .noPendingReplacement:
            break
        }
    }

    private func log(_ failure: ArchiveImportFailure) {
        switch failure {
        case .wrongPasswordOrCorrupted:
            logger.failure(.archiveImportRejectedCorrupted, operation: .archiveImport, category: .validation)
        case .incompatibleVersion:
            logger.failure(.archiveImportRejectedIncompatible, operation: .archiveImport, category: .incompatibleInput)
        case .invalidArchive:
            logger.failure(.archiveImportRejectedInvalid, operation: .archiveImport, category: .validation)
        case .blockedByCoachData:
            logger.failure(.archiveImportBlockedCoachData, operation: .archiveImport, category: .conflict)
        case .alreadyInstalled:
            logger.failure(.archiveImportBlockedNotFirst, operation: .archiveImport, category: .conflict)
        case .installStateUnavailable:
            logger.failure(.archiveImportStateUnavailable, operation: .archiveImport, category: .persistenceFailed)
        case .interrupted:
            logger.failure(.archiveImportInterrupted, operation: .archiveImport, category: .externalCancelled)
        case .importInProgress:
            break
        }
    }
}
