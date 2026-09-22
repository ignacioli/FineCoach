import Combine
import Foundation

@MainActor
final class ExerciseLibraryViewModel: ObservableObject {
    @Published var query = ""
    @Published var includeHidden = false
    @Published var muscleFilter: String?
    @Published var equipmentFilter: String?
    @Published var entries: [ExerciseLibraryEntry] = []
    @Published var sections: [ExerciseCatalogBrowse.Section] = []
    @Published var errorMessage: String?
    @Published var conflictMessage: String?

    let useCases: ExerciseLibraryUseCases
    private var reloadGeneration = 0
    private var reloadTask: Task<Void, Never>?

    init(useCases: ExerciseLibraryUseCases) {
        self.useCases = useCases
    }

    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { await reload() }
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        do {
            let result = try await PerformanceSignposts.shared.measureExerciseSearch {
                try await useCases.search(query: query, includeHidden: includeHidden)
            }
            guard generation == reloadGeneration, !Task.isCancelled else {
                return
            }
            entries = result
            rebuildSections()
            errorMessage = nil
            conflictMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == reloadGeneration else {
                return
            }
            present(error)
        }
    }

    func selectMuscle(_ value: String?) {
        muscleFilter = value
        rebuildSections()
    }

    func selectEquipment(_ value: String?) {
        equipmentFilter = value
        rebuildSections()
    }

    func toggleFavorite(_ entry: ExerciseLibraryEntry) async {
        let next = !(entry.preference?.isFavorite ?? false)
        await run {
            try await self.useCases.setFavorite(id: entry.id, isFavorite: next)
            await self.reload()
        }
    }

    func toggleHidden(_ entry: ExerciseLibraryEntry) async {
        let next = !(entry.preference?.isHidden ?? false)
        await run {
            try await self.useCases.setHidden(id: entry.id, isHidden: next)
            await self.reload()
        }
    }

    func toggleAssisted(_ entry: ExerciseLibraryEntry) async {
        let next = !(entry.preference?.isAssisted ?? false)
        await run {
            try await self.useCases.setAssisted(id: entry.id, isAssisted: next)
            await self.reload()
        }
    }

    private func rebuildSections() {
        sections = ExerciseCatalogBrowse.sections(
            from: entries,
            muscleFilter: muscleFilter,
            equipmentFilter: equipmentFilter
        )
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        do {
            try await work()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        if error as? DomainError == .conflict {
            conflictMessage = String(localized: "exercise.conflict")
            errorMessage = nil
            return
        }
        conflictMessage = nil
        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
    }
}
