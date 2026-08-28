import Foundation

public struct StudentUseCases: Sendable {
    private let repository: CoreDataStudentRepository
    private let clock: any Clock
    private let ids: any IDGenerator

    public init(
        repository: CoreDataStudentRepository,
        clock: any Clock,
        ids: any IDGenerator
    ) {
        self.repository = repository
        self.clock = clock
        self.ids = ids
    }

    public func create(draft: StudentDraft) async throws -> Student {
        let student = try draft.makeStudent(id: StableUUID(ids.makeID()), now: clock.nowUTC())
        return try await repository.create(student)
    }

    public func update(id: StableUUID, draft: StudentDraft) async throws -> Student {
        let current = try await repository.student(id: id)
        let updated = try current.updating(from: draft, now: clock.nowUTC())
        return try await repository.update(updated)
    }

    public func student(id: StableUUID) async throws -> Student {
        try await repository.student(id: id)
    }

    public func searchActive(query: String) async throws -> [Student] {
        try await repository.searchActive(displayNameQuery: query)
    }

    public func listArchived() async throws -> [Student] {
        try await repository.listArchived()
    }

    public func archive(id: StableUUID) async throws -> Student {
        let current = try await repository.student(id: id)
        return try await repository.archive(current, now: clock.nowUTC())
    }

    public func restore(id: StableUUID) async throws -> Student {
        let current = try await repository.student(id: id)
        return try await repository.restore(current, now: clock.nowUTC())
    }

    public func deletionImpact(id: StableUUID) async throws -> StudentDeletionImpact {
        try await repository.deletionImpact(id: id)
    }

    public func delete(id: StableUUID, confirmedDisplayName: String) async throws {
        try await repository.delete(id: id, confirmedDisplayName: confirmedDisplayName)
    }

    public func inProgressTraining() async throws -> InProgressTrainingSummary? {
        try await repository.inProgressTraining()
    }

    public func isOnboardingCompleted() async throws -> Bool {
        try await repository.isOnboardingCompleted()
    }

    public func completeOnboarding() async throws {
        try await repository.markOnboardingCompleted()
    }
}
