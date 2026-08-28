import Combine
import Foundation

@MainActor
final class ExerciseLibraryViewModel: ObservableObject {
    @Published var query = ""
    @Published var includeHidden = false
    @Published var entries: [ExerciseLibraryEntry] = []
    @Published var errorMessage: String?
    @Published var conflictMessage: String?

    let useCases: ExerciseLibraryUseCases

    init(useCases: ExerciseLibraryUseCases) {
        self.useCases = useCases
    }

    func reload() async {
        do {
            entries = try await useCases.search(query: query, includeHidden: includeHidden)
            errorMessage = nil
            conflictMessage = nil
        } catch {
            present(error)
        }
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
