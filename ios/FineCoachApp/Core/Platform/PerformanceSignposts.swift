import os

@MainActor
public struct PerformanceSignposts {
    public static let shared = PerformanceSignposts()

    private let signposter = OSSignposter(subsystem: "com.finecoach.app", category: "performance")

    public func measureSetConfirm<T>(_ work: () async throws -> T) async rethrows -> T {
        try await measure("SetConfirm", work)
    }

    public func measureSessionFinish<T>(_ work: () async throws -> T) async rethrows -> T {
        try await measure("SessionFinish", work)
    }

    public func measureExerciseReorder<T>(_ work: () async throws -> T) async rethrows -> T {
        try await measure("ExerciseReorder", work)
    }

    private func measure<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: signpostID)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}
