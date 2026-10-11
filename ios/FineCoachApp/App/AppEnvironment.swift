import Combine
import CoreData
import Foundation
import os

@MainActor
public final class AppEnvironment: ObservableObject {
    private var persistenceController: PersistenceController?
    public private(set) var persistenceWriter: PersistenceWriter?
    public private(set) var studentUseCases: StudentUseCases?
    public private(set) var sessionUseCases: ActiveSessionUseCases?
    public private(set) var exerciseUseCases: ExerciseLibraryUseCases?
    public private(set) var historyUseCases: HistoryUseCases?
    public private(set) var appointmentUseCases: AppointmentUseCases?
    public private(set) var creditLedgerUseCases: CreditLedgerUseCases?
    public private(set) var templateUseCases: TemplateUseCases?
    public private(set) var bodyDataUseCases: BodyDataUseCases?
    public private(set) var backupCoordinator: BackupCoordinator?
    public private(set) var archiveExportUseCases: ArchiveExportUseCases?
    public let startupErrorDescription: String?
    @Published public private(set) var catalogUnavailableMessage: String?
    private var studentRepository: CoreDataStudentRepository?
    private var sessionRepository: CoreDataSessionRepository?
    private var reportsRootURL: URL?
    private var shareAdapter: SystemShareAdapter?
    private let applicationRootURL: URL?
    private let clock: any Clock
    private let idGenerator: any IDGenerator

    public var isStorageAvailable: Bool {
        persistenceController != nil && persistenceWriter != nil && studentUseCases != nil
            && sessionUseCases != nil && exerciseUseCases != nil && historyUseCases != nil
            && creditLedgerUseCases != nil && templateUseCases != nil && bodyDataUseCases != nil
    }

    public static func bootstrap() -> AppEnvironment {
        do {
            if T116PerformanceHarness.isRequested {
                return try makeIsolatedStore(
                    folderName: T116PerformanceHarness.storeFolderName,
                    reset: true
                )
            }
            #if DEBUG
                return try AppEnvironment.makeForCurrentProcess()
            #else
                return try AppEnvironment()
            #endif
        } catch {
            return AppEnvironment(failure: error)
        }
    }

    static func makeIsolatedStore(folderName: String, reset: Bool) throws -> AppEnvironment {
        let fileManager = FileManager.default
        guard
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw PersistenceControllerError.storeLoadFailed
        }
        let root = applicationSupport.appendingPathComponent(folderName, isDirectory: true)
        if reset {
            try? fileManager.removeItem(at: root)
        }
        return try AppEnvironment(rootURL: root)
    }

    func requireUseCases() -> StudentUseCases {
        guard let studentUseCases else {
            preconditionFailure("Student use cases require available local storage.")
        }
        return studentUseCases
    }

    func requireSessionUseCases() -> ActiveSessionUseCases {
        guard let sessionUseCases else {
            preconditionFailure("Session use cases require available local storage.")
        }
        return sessionUseCases
    }

    func requireExerciseUseCases() -> ExerciseLibraryUseCases {
        guard let exerciseUseCases else {
            preconditionFailure("Exercise use cases require available local storage.")
        }
        return exerciseUseCases
    }

    func requireHistoryUseCases() -> HistoryUseCases {
        guard let historyUseCases else {
            preconditionFailure("History use cases require available local storage.")
        }
        return historyUseCases
    }

    func requireAppointmentUseCases() -> AppointmentUseCases {
        guard let appointmentUseCases else {
            preconditionFailure("Appointment use cases require available local storage.")
        }
        return appointmentUseCases
    }

    func requireCreditLedgerUseCases() -> CreditLedgerUseCases {
        guard let creditLedgerUseCases else {
            preconditionFailure("Credit ledger use cases require available local storage.")
        }
        return creditLedgerUseCases
    }

    func requireTemplateUseCases() -> TemplateUseCases {
        guard let templateUseCases else {
            preconditionFailure("Template use cases require available local storage.")
        }
        return templateUseCases
    }

    func requireBodyDataUseCases() -> BodyDataUseCases {
        guard let bodyDataUseCases else {
            preconditionFailure("Body data use cases require available local storage.")
        }
        return bodyDataUseCases
    }

    func requireCalendar() -> Calendar {
        SystemLocalCalendarProvider().currentCalendar()
    }

    func requireReportsRootURL() -> URL {
        guard let reportsRootURL else {
            preconditionFailure("Report file root requires available local storage.")
        }
        return reportsRootURL
    }

    func requireShareAdapter() -> SystemShareAdapter {
        guard let shareAdapter else {
            preconditionFailure("System share adapter requires available local storage.")
        }
        return shareAdapter
    }

    func requireArchiveExportUseCases() -> ArchiveExportUseCases {
        guard let archiveExportUseCases else {
            preconditionFailure("Archive export use cases require available local storage.")
        }
        return archiveExportUseCases
    }

    func requireBackupCoordinator() -> BackupCoordinator {
        guard let backupCoordinator else {
            preconditionFailure("Backup coordinator requires available local storage.")
        }
        return backupCoordinator
    }

    /// Seeds the built-in exercise catalog once local storage is open.
    /// Call from `RootNavigation.loadInitialState` alongside onboarding load; do not call from `init`.
    func prepareExerciseCatalog() async {
        guard let exerciseUseCases else {
            return
        }
        do {
            try await exerciseUseCases.seedIfNeeded()
            catalogUnavailableMessage = nil
        } catch {
            catalogUnavailableMessage =
                (error as? LocalizedError)?.errorDescription ?? String(localized: "exercise.catalog.unavailable")
        }
    }

    public init(
        rootURL: URL? = nil,
        clock: any Clock = SystemClock(),
        idGenerator: any IDGenerator = SystemIDGenerator()
    ) throws {
        let fileManager = FileManager.default
        let root: URL
        if let rootURL {
            root = rootURL.standardizedFileURL
        } else {
            guard
                let applicationSupport = fileManager.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first
            else {
                throw PersistenceControllerError.storeLoadFailed
            }
            root = applicationSupport.appendingPathComponent("FineCoach", isDirectory: true)
        }

        let directory = StoreGenerationDirectory(rootURL: root)
        let protectedStore = ProtectedFileStore(fileManager: fileManager)
        try protectedStore.prepareDirectory(at: directory.rootURL, policy: .business)
        try protectedStore.prepareDirectory(at: directory.generationsURL, policy: .business)
        try protectedStore.prepareDirectory(at: directory.flowURL, policy: .business)
        let pointerStore = CurrentGenerationPointerStore(
            url: directory.currentPointerURL,
            fileManager: fileManager,
            protectedFileStore: protectedStore
        )
        let metadataStore = StoreGenerationMetadataStore(
            directory: directory,
            fileManager: fileManager,
            protectedFileStore: protectedStore
        )

        let pointerExists = fileManager.fileExists(atPath: directory.currentPointerURL.path)
        if pointerExists {
            try protectedStore.apply(policy: .business, to: directory.currentPointerURL)
        }
        let existingIntent = try RestoreGenerationSwitcher.readIntent(from: directory)
        if let existing = try pointerStore.read() {
            switch RestoreGenerationSwitcher.decision(
                intent: existingIntent,
                pointerUUID: existing.generationUUID
            ) {
            case .failClosed:
                throw StoreGenerationError.pointerMismatch
            case .verifyNewThenCommit:
                try Self.verifyNewGenerationOrRollBack(
                    pointer: existing,
                    intent: existingIntent,
                    directory: directory,
                    metadataStore: metadataStore,
                    pointerStore: pointerStore,
                    protectedStore: protectedStore,
                    fileManager: fileManager
                )
            case .keepOldDiscardCandidate:
                try RestoreGenerationSwitcher.clearIntent(in: directory)
            case .openCurrent:
                break
            }
            let pointerAfter = try pointerStore.read() ?? existing
            let intentAfter = try RestoreGenerationSwitcher.readIntent(from: directory)
            try FileFlowJanitor.cleanupOrphans(
                rootURL: root,
                currentGenerationUUID: pointerAfter.generationUUID,
                restoreIntent: intentAfter,
                keepingFlowIDs: []
            )
        }

        let controller: PersistenceController
        let generationUUID: UUID
        if let existing = try pointerStore.read() {
            generationUUID = existing.generationUUID
            let generationURL = directory.generationURL(for: existing.generationUUID)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: generationURL.path, isDirectory: &isDirectory),
                isDirectory.boolValue,
                fileManager.fileExists(atPath: directory.databaseURL(for: existing.generationUUID).path)
            else {
                throw StoreGenerationError.invalidGeneration
            }
            try protectedStore.apply(policy: .business, to: generationURL)
            try protectedStore.apply(
                policy: .business,
                to: directory.metadataURL(for: existing.generationUUID)
            )
            _ = try protectedStore.secureSQLiteStoreArtifacts(
                at: directory.databaseURL(for: existing.generationUUID)
            )
            let metadata = try metadataStore.validate(generationUUID: existing.generationUUID)
            guard metadata.validationState == .current else {
                throw StoreGenerationError.metadataMismatch
            }
            controller = try PersistenceController(
                storeURL: directory.databaseURL(for: existing.generationUUID),
                protectedFileStore: protectedStore
            )
        } else {
            let existingGenerations = try fileManager.contentsOfDirectory(
                at: directory.generationsURL,
                includingPropertiesForKeys: nil
            )
            guard existingGenerations.isEmpty else {
                throw StoreGenerationError.pointerMismatch
            }
            generationUUID = UUID()
            let newPointer = try CurrentGenerationPointer(generationUUID: generationUUID)
            try protectedStore.prepareDirectory(
                at: directory.generationURL(for: generationUUID),
                policy: .business
            )
            controller = try PersistenceController(
                storeURL: directory.databaseURL(for: generationUUID),
                protectedFileStore: protectedStore
            )
            let metadata = try StoreGenerationMetadata(
                generationUUID: generationUUID,
                createdAtUTC: Date(),
                validationState: .current
            )
            try metadataStore.write(metadata)
            try pointerStore.replace(with: newPointer)
        }
        self.persistenceController = nil
        self.persistenceWriter = nil
        self.studentRepository = nil
        self.sessionRepository = nil
        self.studentUseCases = nil
        self.sessionUseCases = nil
        self.exerciseUseCases = nil
        self.historyUseCases = nil
        self.appointmentUseCases = nil
        self.creditLedgerUseCases = nil
        self.templateUseCases = nil
        self.bodyDataUseCases = nil
        self.backupCoordinator = nil
        self.archiveExportUseCases = nil
        self.reportsRootURL = nil
        self.shareAdapter = nil
        self.applicationRootURL = root
        self.clock = clock
        self.idGenerator = idGenerator
        self.startupErrorDescription = nil
        self.catalogUnavailableMessage = nil
        try bindLiveStack(
            controller: controller,
            generationUUID: generationUUID,
            root: root,
            directory: directory,
            protectedStore: protectedStore,
            clock: clock,
            idGenerator: idGenerator
        )
        try TempReportLease.cleanupOrphans(in: root, keepingFlowIDs: [])
        // A failed archive-export janitor is retried at the next launch; it must not block startup.
        try? ArchiveExportUseCases.cleanupOrphans(in: root)
    }

    private init(failure: Error) {
        self.persistenceController = nil
        self.persistenceWriter = nil
        self.studentRepository = nil
        self.sessionRepository = nil
        self.studentUseCases = nil
        self.sessionUseCases = nil
        self.exerciseUseCases = nil
        self.historyUseCases = nil
        self.appointmentUseCases = nil
        self.creditLedgerUseCases = nil
        self.templateUseCases = nil
        self.bodyDataUseCases = nil
        self.backupCoordinator = nil
        self.archiveExportUseCases = nil
        self.reportsRootURL = nil
        self.shareAdapter = nil
        self.applicationRootURL = nil
        self.clock = SystemClock()
        self.idGenerator = SystemIDGenerator()
        self.startupErrorDescription = (failure as? LocalizedError)?.errorDescription ?? "本地存储暂不可用。"
        self.catalogUnavailableMessage = nil
    }

    func reloadAfterCommittedRestore() throws {
        guard let root = applicationRootURL else {
            throw BackupError.invalidState
        }
        try persistenceController?.detachPersistentStores()
        let fileManager = FileManager.default
        let directory = StoreGenerationDirectory(rootURL: root)
        let protectedStore = ProtectedFileStore(fileManager: fileManager)
        let pointerStore = CurrentGenerationPointerStore(
            url: directory.currentPointerURL,
            fileManager: fileManager,
            protectedFileStore: protectedStore
        )
        guard let pointer = try pointerStore.read() else {
            throw StoreGenerationError.pointerMismatch
        }
        let controller = try PersistenceController(
            storeURL: directory.databaseURL(for: pointer.generationUUID),
            protectedFileStore: protectedStore
        )
        try bindLiveStack(
            controller: controller,
            generationUUID: pointer.generationUUID,
            root: root,
            directory: directory,
            protectedStore: protectedStore,
            clock: clock,
            idGenerator: idGenerator
        )
        objectWillChange.send()
    }

    private func bindLiveStack(
        controller: PersistenceController,
        generationUUID: UUID,
        root: URL,
        directory: StoreGenerationDirectory,
        protectedStore: ProtectedFileStore,
        clock: any Clock,
        idGenerator: any IDGenerator
    ) throws {
        persistenceController = controller
        persistenceWriter = controller.writer
        let repository = CoreDataStudentRepository(writer: controller.writer)
        let sessions = CoreDataSessionRepository(writer: controller.writer)
        let exercises = CoreDataExerciseRepository(writer: controller.writer)
        studentRepository = repository
        sessionRepository = sessions
        studentUseCases = StudentUseCases(
            repository: repository,
            clock: clock,
            ids: idGenerator
        )
        exerciseUseCases = ExerciseLibraryUseCases(
            repository: exercises,
            clock: clock,
            ids: idGenerator
        )
        let recoveryStore = ActiveSessionRecoveryStore(
            url: directory.activeRecoveryURL,
            protectedFileStore: protectedStore
        )
        sessionUseCases = ActiveSessionUseCases(
            sessionRepository: sessions,
            studentRepository: repository,
            exerciseRepository: exercises,
            sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
            recoveryStore: recoveryStore,
            storeGenerationUUID: generationUUID,
            clock: clock,
            ids: idGenerator
        )
        historyUseCases = HistoryUseCases(
            sessionRepository: sessions,
            clock: clock,
            ids: idGenerator
        )
        appointmentUseCases = AppointmentUseCases(
            appointmentRepository: CoreDataAppointmentRepository(writer: controller.writer),
            studentRepository: repository,
            activeSession: sessionUseCases!,
            notifications: NotificationScheduler(
                notificationCenter: SystemNotificationAdapter(),
                calendarProvider: SystemLocalCalendarProvider()
            ),
            clock: clock,
            calendarProvider: SystemLocalCalendarProvider(),
            ids: idGenerator
        )
        creditLedgerUseCases = CreditLedgerUseCases(
            repository: CoreDataCoursePackageRepository(writer: controller.writer),
            clock: clock,
            ids: idGenerator
        )
        templateUseCases = TemplateUseCases(
            templateRepository: CoreDataTemplateRepository(writer: controller.writer),
            sectionRepository: CoreDataSessionSectionRepository(writer: controller.writer),
            clock: clock,
            ids: idGenerator
        )
        bodyDataUseCases = BodyDataUseCases(
            repository: CoreDataBodyDataRepository(writer: controller.writer),
            clock: clock,
            calendarProvider: SystemLocalCalendarProvider(),
            ids: idGenerator
        )
        reportsRootURL = root
        if shareAdapter == nil {
            shareAdapter = SystemShareAdapter(presenter: LaunchArgumentSharePresenter())
        }
        if let shareAdapter {
            archiveExportUseCases = ArchiveExportUseCases(
                sourceReader: ArchiveExportSourceReader(writer: controller.writer),
                identity: Self.archiveExportIdentity(writer: controller.writer, ids: idGenerator),
                share: shareAdapter,
                tempRootURL: root,
                clock: clock,
                calendarProvider: SystemLocalCalendarProvider(),
                ids: idGenerator
            )
        }
        backupCoordinator = BackupCoordinator(
            rootURL: root,
            writer: controller.writer,
            clock: clock,
            ids: idGenerator
        )
    }

    private static func verifyNewGenerationOrRollBack(
        pointer: CurrentGenerationPointer,
        intent: RestoreIntent?,
        directory: StoreGenerationDirectory,
        metadataStore: StoreGenerationMetadataStore,
        pointerStore: CurrentGenerationPointerStore,
        protectedStore: ProtectedFileStore,
        fileManager: FileManager
    ) throws {
        guard let intent else {
            throw StoreGenerationError.pointerMismatch
        }
        let newUUID = pointer.generationUUID
        let databaseURL = directory.databaseURL(for: newUUID)
        func rollBackToOld() throws {
            try pointerStore.replace(with: try CurrentGenerationPointer(generationUUID: intent.oldGenerationUUID))
            try RestoreGenerationSwitcher.clearIntent(in: directory)
        }
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            try rollBackToOld()
            return
        }
        do {
            let candidate = try PersistenceController(
                storeURL: databaseURL,
                protectedFileStore: protectedStore
            )
            _ = try candidate.readInventoryBlocking()
            try candidate.detachPersistentStores()
            var metadata = try metadataStore.validate(generationUUID: newUUID)
            metadata.validationState = .current
            try metadataStore.write(metadata)
            try RestoreGenerationSwitcher.writeIntent(
                RestoreIntent(
                    oldGenerationUUID: intent.oldGenerationUUID,
                    newGenerationUUID: intent.newGenerationUUID,
                    phase: .committed
                ),
                to: directory
            )
        } catch {
            try rollBackToOld()
        }
    }

    #if DEBUG
        static func makeForCurrentProcess() throws -> AppEnvironment {
            let arguments = ProcessInfo.processInfo.arguments
            let fileManager = FileManager.default
            guard
                let applicationSupport = fileManager.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first
            else {
                throw PersistenceControllerError.storeLoadFailed
            }
            let folderName = arguments.contains("-FineCoachUITesting") ? "FineCoachUITesting" : "FineCoach"
            let root = applicationSupport.appendingPathComponent(folderName, isDirectory: true)
            if arguments.contains("-FineCoachResetStore") {
                try? fileManager.removeItem(at: root)
            }
            return try AppEnvironment(
                rootURL: root,
                clock: ArchiveExportDebugSeed.isRequested ? ArchiveExportDebugSeed.makeClock() : SystemClock()
            )
        }

        func applyUITestSeedingIfNeeded() async {
            let arguments = ProcessInfo.processInfo.arguments
            if ArchiveExportDebugSeed.isRequested {
                await ArchiveExportDebugSeed.seed(in: self)
                return
            }
            guard arguments.contains("-FineCoachSeedInProgressSession"),
                let useCases = studentUseCases,
                let repository = studentRepository
            else {
                return
            }
            do {
                let existing = try await useCases.searchActive(query: "")
                if !existing.isEmpty {
                    try await useCases.completeOnboarding()
                    return
                }
                try await useCases.completeOnboarding()
                let student = try await repository.create(
                    try StudentDraft(
                        displayName: "林青",
                        sex: .female,
                        injuryNotes: "合成测试备注：保持动作节奏。"
                    ).makeStudent(
                        id: StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!),
                        now: Date()
                    )
                )
                try await repository.insertInProgressSessionForTesting(
                    studentID: student.id,
                    sessionID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                    now: Date()
                )
            } catch {
                return
            }
        }
    #endif
}

extension AppEnvironment {
    /// The identity step of archive generation. In DEBUG, `-FineCoachSimulateArchiveGenerationFailure`
    /// makes the first generation after launch fail (M2-06d), so the failure state and the
    /// 「交给系统…」 retry can be walked through by hand; later attempts succeed.
    fileprivate static func archiveExportIdentity(
        writer: PersistenceWriter,
        ids: any IDGenerator
    ) -> any ArchiveExportIdentityProviding {
        let service = ArchiveIdentityService(writer: writer, ids: ids)
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-FineCoachSimulateArchiveGenerationFailure") {
                return FailFirstArchiveIdentity(wrapped: service)
            }
        #endif
        return service
    }
}

#if DEBUG
    private final class FailFirstArchiveIdentity: ArchiveExportIdentityProviding, @unchecked Sendable {
        private let wrapped: ArchiveIdentityService
        private let failed = OSAllocatedUnfairLock(initialState: false)

        init(wrapped: ArchiveIdentityService) {
            self.wrapped = wrapped
        }

        func ensureIdentity(forStudent studentID: StableUUID) async throws -> ArchiveIdentity {
            let shouldFail = failed.withLock { alreadyFailed in
                defer { alreadyFailed = true }
                return !alreadyFailed
            }
            if shouldFail {
                throw FaultInjectionError.injected(.persistenceWriterSave)
            }
            return try await wrapped.ensureIdentity(forStudent: studentID)
        }
    }
#endif

extension AppEnvironment {
    public static var unavailableForPreview: AppEnvironment {
        AppEnvironment(failure: PersistenceControllerError.storeLoadFailed)
    }
}
