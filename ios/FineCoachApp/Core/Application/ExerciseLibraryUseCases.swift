import Foundation

public struct ExerciseLibraryUseCases: Sendable {
    private let repository: CoreDataExerciseRepository
    private let clock: any Clock
    private let ids: any IDGenerator

    public init(repository: CoreDataExerciseRepository, clock: any Clock, ids: any IDGenerator) {
        self.repository = repository
        self.clock = clock
        self.ids = ids
    }

    public func seedIfNeeded() async throws {
        try await repository.seedPlaceholderCatalogIfNeeded(now: clock.nowUTC())
    }

    public func hasBuiltInCatalog() async throws -> Bool {
        try await repository.hasBuiltInCatalog()
    }

    public func search(query: String, includeHidden: Bool = false) async throws -> [ExerciseLibraryEntry] {
        try await repository.searchActive(query: query, includeHidden: includeHidden)
    }

    public func assistedExerciseIDs() async throws -> Set<StableExerciseID> {
        Set(try await search(query: "", includeHidden: true).filter { $0.preference?.isAssisted == true }.map(\.id))
    }

    public func createCustom(name: String, recordMode: RecordMode) async throws -> ExerciseCatalogItem {
        try await repository.createCustom(
            name: name,
            recordMode: recordMode,
            id: try StableExerciseID(ids.makeID().uuidString),
            now: clock.nowUTC()
        )
    }

    public func updateCustom(id: StableExerciseID, name: String, recordMode: RecordMode) async throws
        -> ExerciseCatalogItem
    {
        try await repository.updateCustom(
            id: id,
            name: name,
            recordMode: recordMode,
            now: clock.nowUTC()
        )
    }

    public func archiveCustom(id: StableExerciseID) async throws -> ExerciseCatalogItem {
        try await repository.archiveCustom(id: id, now: clock.nowUTC())
    }

    public func restoreCustom(id: StableExerciseID) async throws -> ExerciseCatalogItem {
        try await repository.restoreCustom(id: id, now: clock.nowUTC())
    }

    public func setFavorite(id: StableExerciseID, isFavorite: Bool) async throws {
        _ = try await repository.setPreference(
            exerciseID: id,
            alias: nil,
            isFavorite: isFavorite,
            isHidden: nil
        )
    }

    public func setHidden(id: StableExerciseID, isHidden: Bool) async throws {
        _ = try await repository.setPreference(
            exerciseID: id,
            alias: nil,
            isFavorite: nil,
            isHidden: isHidden
        )
    }

    public func setAssisted(id: StableExerciseID, isAssisted: Bool) async throws {
        _ = try await repository.setPreference(
            exerciseID: id,
            alias: nil,
            isFavorite: nil,
            isHidden: nil,
            isAssisted: isAssisted
        )
    }

    /// P0-D8: the coach's override of the library's unilateral default.
    public func setUnilateral(id: StableExerciseID, isUnilateral: Bool) async throws {
        _ = try await repository.setPreference(
            exerciseID: id,
            alias: nil,
            isFavorite: nil,
            isHidden: nil,
            isUnilateral: isUnilateral
        )
    }
}
