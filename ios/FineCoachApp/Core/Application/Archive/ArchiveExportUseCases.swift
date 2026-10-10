import Foundation

// M2 export use case and flow state machine (T034, data-model §2 / §7, plan D-M2-006).
//
// UI binding: a view model calls `ArchiveExportUseCases.beginFlow(studentID:)`, then drives the
// returned `ArchiveExportFlow` actor. Every transition is validated here, so a view can neither
// skip a step nor generate twice. No view, no localized text, no export history (D-011).

/// Where an export flow is. `cancelled` and `failed` have already deleted the temporary archive;
/// `retry()` goes back through `generating` (data-model §2).
public enum ArchiveExportFlowState: Equatable, Sendable {
    case selecting
    case previewing
    case confirmingFacts
    case settingPassword
    case generating
    case generated
    case handedToSystem
    case cancelled
    case failed
}

public enum ArchiveExportFlowError: Error, Equatable, Sendable {
    /// The requested step is not allowed from the current state (M2-FR-014).
    case invalidTransition(from: ArchiveExportFlowState)
    /// The effective selection is empty, so there is nothing to preview (spec §5).
    case nothingSelected
    /// Fewer than 8 characters (M2-FR-016). No file is generated.
    case passwordTooShort
    /// The two entries differ. No file is generated.
    case passwordMismatch
    /// A delivery is already open (duplicate tap).
    case deliveryInProgress
    /// The flow was left; it cannot be reused.
    case flowClosed
}

public protocol ArchiveExportIdentityProviding: Sendable {
    func ensureIdentity(forStudent studentID: StableUUID) async throws -> ArchiveIdentity
}

extension ArchiveIdentityService: ArchiveExportIdentityProviding {}

public struct ArchiveExportUseCases: Sendable {
    private let sourceReader: any ArchiveExportSourceReading
    private let configuration: ArchiveExportFlow.Configuration
    private let ids: any IDGenerator

    /// - Parameters:
    ///   - tempRootURL: the app-managed root that holds `archive-export-flows/` (protected,
    ///     excluded from backup). The same root `AppEnvironment` uses for report files works.
    ///   - share: the system share boundary; inject a fake presenter in tests.
    ///   - limitAssertion: called when an export exceeds a plan §7.3 limit, after the fixed
    ///     `archive.export_limit_exceeded` event is logged. Defaults to `assertionFailure`.
    public init(
        sourceReader: any ArchiveExportSourceReading,
        identity: any ArchiveExportIdentityProviding,
        share: SystemShareAdapter,
        tempRootURL: URL,
        clock: any Clock,
        calendarProvider: any LocalCalendarProvider,
        random: any SecureRandomSource = SecureRandomGenerator(),
        ids: any IDGenerator = SystemIDGenerator(),
        logger: any AppLogging = AppLogger.standard,
        limitAssertion: @escaping @Sendable () -> Void = {
            assertionFailure("archive export exceeded a plan 7.3 limit")
        }
    ) {
        self.sourceReader = sourceReader
        self.ids = ids
        self.configuration = ArchiveExportFlow.Configuration(
            identity: identity,
            share: share,
            tempRootURL: tempRootURL,
            clock: clock,
            calendarProvider: calendarProvider,
            random: random,
            logger: logger,
            limitAssertion: limitAssertion
        )
    }

    /// Reads the student's projection once (archived students included, D-006) and returns a
    /// fresh flow with every item selected (M2-FR-007). Nothing is remembered from earlier flows.
    public func beginFlow(studentID: StableUUID) async throws -> ArchiveExportFlow {
        let source = try await sourceReader.read(studentID: studentID)
        return ArchiveExportFlow(
            studentID: studentID,
            source: source,
            flowID: ids.makeID(),
            configuration: configuration
        )
    }

    /// Launch janitor for archives left behind by a process that died mid-flow. Safe to call
    /// before any flow exists.
    public static func cleanupOrphans(in tempRootURL: URL) throws {
        try ArchiveExportTempLease.cleanupOrphans(in: tempRootURL)
    }
}

/// One export flow. State and secrets (password, snapshot) live only in this actor's memory and
/// are dropped when the flow ends or is left. Retry after `cancelled` / `failed` re-encodes the
/// in-memory snapshot with the in-memory password.
public actor ArchiveExportFlow {
    struct Configuration: Sendable {
        let identity: any ArchiveExportIdentityProviding
        let share: SystemShareAdapter
        let tempRootURL: URL
        let clock: any Clock
        let calendarProvider: any LocalCalendarProvider
        let random: any SecureRandomSource
        let logger: any AppLogging
        let limitAssertion: @Sendable () -> Void
    }

    public private(set) var state: ArchiveExportFlowState = .selecting
    /// The Coach's current choice; mutate through the methods below while `selecting`.
    public private(set) var selection: ArchiveModuleSelection
    /// Facts for the selection screen: counts, date range, no-data reasons.
    public nonisolated let availability: ArchiveModuleAvailability
    /// The snapshot generation encodes: nil until the first generation, kept across cancelled /
    /// failed so a retry re-encodes the same content, dropped at `handedToSystem` and on leave.
    public private(set) var generatedSnapshot: ArchiveSnapshot?

    private let studentID: StableUUID
    private let source: ArchiveExportSource
    private let configuration: Configuration
    private var lease: ArchiveExportTempLease
    private var password: ArchivePassword?
    private var isDelivering = false
    private var isClosed = false

    init(studentID: StableUUID, source: ArchiveExportSource, flowID: UUID, configuration: Configuration) {
        self.studentID = studentID
        self.source = source
        self.configuration = configuration
        self.availability = source.availability
        self.selection = ArchiveModuleSelection(availability: source.availability)
        self.lease = ArchiveExportTempLease(rootURL: configuration.tempRootURL, flowID: flowID)
    }

    // MARK: Selecting

    @discardableResult
    public func setSelected(_ selected: Bool, item: ArchiveModuleItem) throws -> Bool {
        try require(.selecting)
        return selection.setSelected(selected, item: item)
    }

    public func setGroup(_ group: ArchiveModuleGroup, selected: Bool) throws {
        try require(.selecting)
        selection.setGroup(group, selected: selected)
    }

    public func toggleGroup(_ group: ArchiveModuleGroup) throws {
        try require(.selecting)
        selection.toggleGroup(group)
    }

    // MARK: Preview, confirmation, password

    /// `selecting -> previewing`. The returned snapshot is the content the archive will carry
    /// (M2-FR-008); its identity and time fields are placeholders until generation, because
    /// identities are created only when an export is actually generated.
    public func preview() throws -> ArchiveSnapshot {
        try require(.selecting)
        guard selection.canPreview else {
            throw ArchiveExportFlowError.nothingSelected
        }
        let nilUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let placeholder = ArchiveIdentity(sourceID: nilUUID, studentArchiveID: nilUUID)
        let snapshot = try ArchiveExportPolicy.makeSnapshot(
            source: source,
            selection: selection,
            identity: placeholder,
            now: configuration.clock.nowUTC()
        )
        state = .previewing
        return snapshot
    }

    /// `previewing -> confirmingFacts`.
    public func confirmPreview() throws {
        try require(.previewing)
        state = .confirmingFacts
    }

    /// `confirmingFacts -> settingPassword` (M2-FR-013: the Coach confirmed the delivery facts).
    public func confirmFacts() throws {
        try require(.confirmingFacts)
        state = .settingPassword
    }

    /// One step back: `previewing -> selecting`, `confirmingFacts -> previewing`,
    /// `settingPassword -> confirmingFacts`. Going back never keeps a password.
    public func back() throws {
        try requireOpen()
        switch state {
        case .previewing: state = .selecting
        case .confirmingFacts: state = .previewing
        case .settingPassword: state = .confirmingFacts
        default: throw ArchiveExportFlowError.invalidTransition(from: state)
        }
        password = nil
    }

    /// `settingPassword -> generating -> generated | failed`. A rejected password changes
    /// nothing and generates nothing (M2-FR-018, AC-004). The returned state is `generated` or
    /// `failed`.
    @discardableResult
    public func submitPassword(_ entry: String, confirmation: String) async throws -> ArchiveExportFlowState {
        try require(.settingPassword)
        let validated: ArchivePassword
        do {
            validated = try ArchivePassword(creating: entry)
        } catch {
            throw ArchiveExportFlowError.passwordTooShort
        }
        guard entry == confirmation else {
            throw ArchiveExportFlowError.passwordMismatch
        }
        password = validated
        return await generate()
    }

    // MARK: Delivery

    /// `generated -> handedToSystem | cancelled | failed` through the system share boundary.
    /// The temporary archive is deleted whatever the outcome (AC-005, M2-FR-023). "Handed to
    /// system" never means the student received it (M2-FR-022).
    @discardableResult
    public func deliver() async throws -> ArchiveExportFlowState {
        try require(.generated)
        guard !isDelivering else {
            throw ArchiveExportFlowError.deliveryInProgress
        }
        guard let fileURL = lease.fileURL else {
            throw ArchiveExportFlowError.invalidTransition(from: state)
        }
        isDelivering = true
        let outcome = await configuration.share.share(fileURLs: [fileURL])
        isDelivering = false
        guard !isClosed else {
            return state
        }
        // Best effort: the janitor removes anything left over at the next launch.
        try? lease.discard()
        switch outcome {
        case .completed:
            state = .handedToSystem
            password = nil
            generatedSnapshot = nil
            configuration.logger.info(.archiveExportHandedOff, operation: .archiveExport)
        case .cancelled:
            state = .cancelled
            configuration.logger.failure(
                .archiveExportDeliveryCancelled, operation: .archiveExport, category: .externalCancelled)
        case .failed:
            state = .failed
            configuration.logger.failure(
                .archiveExportFailed, operation: .archiveExport, category: .persistenceFailed)
        }
        return state
    }

    /// `cancelled | failed -> generating -> generated | failed`: encodes the in-memory snapshot
    /// again with the in-memory password. It does not deliver by itself.
    @discardableResult
    public func retry() async throws -> ArchiveExportFlowState {
        try requireOpen()
        guard state == .cancelled || state == .failed, password != nil else {
            throw ArchiveExportFlowError.invalidTransition(from: state)
        }
        return await generate()
    }

    /// Ends the flow: the temporary archive, password and snapshot are dropped and nothing is
    /// recorded (D-011). Safe to call at any state, repeatedly.
    public func leave() {
        isClosed = true
        try? lease.discard()
        password = nil
        generatedSnapshot = nil
    }

    // MARK: Generation

    private func generate() async -> ArchiveExportFlowState {
        state = .generating
        do {
            guard let password else {
                throw ArchiveExportFlowError.invalidTransition(from: state)
            }
            let snapshot: ArchiveSnapshot
            if let kept = generatedSnapshot {
                snapshot = kept
            } else {
                // Identity first, in its own transaction (T018); only now does anything get
                // written to the Coach store.
                let identity = try await configuration.identity.ensureIdentity(forStudent: studentID)
                let made = try ArchiveExportPolicy.makeSnapshot(
                    source: source,
                    selection: selection,
                    identity: identity,
                    now: configuration.clock.nowUTC()
                )
                try checkLimits(made)
                generatedSnapshot = made
                snapshot = made
            }
            let random = configuration.random
            let encoded = try await Task.detached(priority: .userInitiated) {
                try ArchiveFileCodec.encode(snapshot: snapshot, password: password, random: random)
            }.value
            guard !isClosed else {
                return state
            }
            let name = ArchiveExportPolicy.fileName(
                snapshotAtUTC: snapshot.manifest.snapshotAtUTC,
                timeZone: configuration.calendarProvider.currentCalendar().timeZone
            )
            try lease.write(archive: encoded, fileName: name)
            state = .generated
        } catch {
            try? lease.discard()
            guard !isClosed else {
                return state
            }
            state = .failed
            configuration.logger.failure(.archiveExportFailed, operation: .archiveExport, category: .persistenceFailed)
        }
        return state
    }

    /// Export only asserts and logs a fixed event (plan §7.3); the importer fails closed on an
    /// over-limit archive. Any other integrity problem is a bug and fails the export.
    private func checkLimits(_ snapshot: ArchiveSnapshot) throws {
        do {
            try snapshot.validateIntegrity()
        } catch ArchiveSnapshotError.limitExceeded, ArchiveSnapshotError.textTooLong {
            configuration.logger.failure(.archiveExportLimitExceeded, operation: .archiveExport, category: .validation)
            configuration.limitAssertion()
        }
    }

    // MARK: Guards

    private func requireOpen() throws {
        guard !isClosed else {
            throw ArchiveExportFlowError.flowClosed
        }
    }

    private func require(_ expected: ArchiveExportFlowState) throws {
        try requireOpen()
        guard state == expected else {
            throw ArchiveExportFlowError.invalidTransition(from: state)
        }
    }
}
