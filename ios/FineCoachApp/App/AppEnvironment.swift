import Combine
import CoreData
import Foundation

@MainActor
public final class AppEnvironment: ObservableObject {
    private let persistenceController: PersistenceController?
    public let persistenceWriter: PersistenceWriter?
    public let studentUseCases: StudentUseCases?
    public let sessionUseCases: ActiveSessionUseCases?
    public let startupErrorDescription: String?
    private let studentRepository: CoreDataStudentRepository?
    private let sessionRepository: CoreDataSessionRepository?

    public var isStorageAvailable: Bool {
        persistenceController != nil && persistenceWriter != nil && studentUseCases != nil
            && sessionUseCases != nil
    }

    public static func bootstrap() -> AppEnvironment {
        do {
            #if DEBUG
                return try AppEnvironment.makeForCurrentProcess()
            #else
                return try AppEnvironment()
            #endif
        } catch {
            return AppEnvironment(failure: error)
        }
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

        let controller: PersistenceController
        if let existing = try pointerStore.read() {
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
            let generationUUID = UUID()
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
        self.persistenceController = controller
        self.persistenceWriter = controller.writer
        let repository = CoreDataStudentRepository(writer: controller.writer)
        let sessions = CoreDataSessionRepository(writer: controller.writer)
        self.studentRepository = repository
        self.sessionRepository = sessions
        self.studentUseCases = StudentUseCases(
            repository: repository,
            clock: clock,
            ids: idGenerator
        )
        self.sessionUseCases = ActiveSessionUseCases(
            sessionRepository: sessions,
            studentRepository: repository,
            clock: clock,
            ids: idGenerator
        )
        self.startupErrorDescription = nil
    }

    private init(failure: Error) {
        self.persistenceController = nil
        self.persistenceWriter = nil
        self.studentRepository = nil
        self.sessionRepository = nil
        self.studentUseCases = nil
        self.sessionUseCases = nil
        self.startupErrorDescription = (failure as? LocalizedError)?.errorDescription ?? "本地存储暂不可用。"
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
            return try AppEnvironment(rootURL: root)
        }

        func applyUITestSeedingIfNeeded() async {
            let arguments = ProcessInfo.processInfo.arguments
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
    public static var unavailableForPreview: AppEnvironment {
        AppEnvironment(failure: PersistenceControllerError.storeLoadFailed)
    }
}
