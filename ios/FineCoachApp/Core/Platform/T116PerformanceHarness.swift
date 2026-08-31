import Darwin
import Foundation

/// Release, no-debugger T116 runner. Isolated store `FineCoachT116`; does not touch the Coach production store.
enum T116PerformanceHarness {
    static let launchArgument = "-FineCoachT116Harness"
    static let storeFolderName = "FineCoachT116"
    static let resultFileName = "t116-results.json"
    private static let warmupCount = 5
    private static let sampleCount = 30
    private static let squatID = StableExerciseID(rawValue: "a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")!

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    @MainActor
    static func runIfRequested(using environment: AppEnvironment) async {
        guard isRequested else {
            return
        }
        emit("T116_HARNESS_START")
        do {
            let payload = try await run(using: environment)
            try write(payload)
            emit("T116_HARNESS_RESULT \(encodeLine(payload))")
            if payload.passed {
                emit("T116_HARNESS_DONE passed=true")
            } else {
                emit("T116_HARNESS_DONE passed=false")
            }
        } catch {
            emit("T116_HARNESS_ERROR \(String(describing: error))")
        }
        fflush(stdout)
        fflush(stderr)
    }

    @MainActor
    private static func run(using environment: AppEnvironment) async throws -> ResultPayload {
        let studentUseCases = environment.requireUseCases()
        let sessionUseCases = environment.requireSessionUseCases()
        let exerciseUseCases = environment.requireExerciseUseCases()
        try await studentUseCases.completeOnboarding()
        let student = try await studentUseCases.create(
            draft: StudentDraft(displayName: "林青", sex: .female)
        )
        _ = try await sessionUseCases.startOrOpen(studentID: student.id)
        let session = try await sessionUseCases.addCatalogExercise(itemID: squatID)
        let exerciseID = try unwrap(session.exercises.first?.id, "missing catalog exercise")
        let seeded = try await sessionUseCases.addSet(
            exerciseID: exerciseID,
            input: weightRepsInput()
        )
        let firstSetID = try unwrap(seeded.exercises.first?.sets.last?.id, "missing seed set")
        _ = try await sessionUseCases.confirmSet(setID: firstSetID)

        let recovery = try await sample {
            _ = try await PerformanceSignposts.shared.measureRecovery {
                try await sessionUseCases.reconcileOnLaunch()
            }
        }
        let search = try await sample {
            _ = try await PerformanceSignposts.shared.measureExerciseSearch {
                try await exerciseUseCases.search(query: "深蹲")
            }
        }
        var confirmMilliseconds: [Double] = []
        confirmMilliseconds.reserveCapacity(sampleCount)
        for index in 0..<(warmupCount + sampleCount) {
            let added = try await sessionUseCases.addSet(
                exerciseID: exerciseID,
                input: weightRepsInput()
            )
            let setID = try unwrap(added.exercises.first?.sets.last?.id, "missing confirm set")
            let started = ContinuousClock.now
            _ = try await PerformanceSignposts.shared.measureSetConfirm {
                try await sessionUseCases.confirmSet(setID: setID)
            }
            let elapsed = milliseconds(ContinuousClock.now - started)
            if index >= warmupCount {
                confirmMilliseconds.append(elapsed)
            }
        }
        let confirm = SampleSummary(milliseconds: confirmMilliseconds)
        return ResultPayload(
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            machine: machineIdentifier(),
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            configuration: "Release",
            debuggerAttached: false,
            warmup: warmupCount,
            samples: sampleCount,
            recovery: recovery,
            search: search,
            confirm: confirm
        )
    }

    @MainActor
    private static func sample(work: () async throws -> Void) async throws -> SampleSummary {
        for _ in 0..<warmupCount {
            try await work()
        }
        var milliseconds: [Double] = []
        milliseconds.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            let started = ContinuousClock.now
            try await work()
            milliseconds.append(self.milliseconds(ContinuousClock.now - started))
        }
        return SampleSummary(milliseconds: milliseconds)
    }

    private static func weightRepsInput() -> TrainingSetInput {
        TrainingSetInput(
            recordMode: .weightReps,
            weightValue: "0",
            repetitionCount: "5",
            unit: .kilograms
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw DomainError.notFound
        }
        _ = message
        return value
    }

    private static func machineIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private static func write(_ payload: ResultPayload) throws {
        let data = try JSONSerialization.data(
            withJSONObject: payload.jsonObject(), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: resultURL(), options: .atomic)
    }

    private static func resultURL() throws -> URL {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw DomainError.invalidFileOperation
        }
        let directory = applicationSupport.appendingPathComponent(storeFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(resultFileName)
    }

    private static func encodeLine(_ payload: ResultPayload) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload.jsonObject()),
            let line = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return line
    }

    private static func emit(_ line: String) {
        fputs(line + "\n", stdout)
        fputs(line + "\n", stderr)
    }

    private struct SampleSummary {
        let milliseconds: [Double]

        var p50Milliseconds: Double { percentile(0.50) }
        var p95Milliseconds: Double { percentile(0.95) }

        private func percentile(_ p: Double) -> Double {
            let sorted = milliseconds.sorted()
            guard !sorted.isEmpty else {
                return 0
            }
            let rank = p * Double(sorted.count - 1)
            let lower = Int(rank.rounded(.down))
            let upper = min(sorted.count - 1, lower + 1)
            let weight = rank - Double(lower)
            return sorted[lower] * (1 - weight) + sorted[upper] * weight
        }

        func jsonObject() -> [String: Any] {
            [
                "p50Milliseconds": p50Milliseconds,
                "p95Milliseconds": p95Milliseconds,
                "milliseconds": milliseconds,
            ]
        }
    }

    private struct ResultPayload {
        let recordedAt: String
        let machine: String
        let systemVersion: String
        let configuration: String
        let debuggerAttached: Bool
        let warmup: Int
        let samples: Int
        let recovery: SampleSummary
        let search: SampleSummary
        let confirm: SampleSummary

        var passed: Bool {
            recovery.p95Milliseconds <= 1_000
                && search.p95Milliseconds <= 200
                && confirm.p95Milliseconds <= 100
        }

        func jsonObject() -> [String: Any] {
            [
                "recordedAt": recordedAt,
                "machine": machine,
                "systemVersion": systemVersion,
                "configuration": configuration,
                "debuggerAttached": debuggerAttached,
                "warmup": warmup,
                "samples": samples,
                "passed": passed,
                "budgets": [
                    "recoveryP95Milliseconds": 1_000,
                    "searchP95Milliseconds": 200,
                    "confirmP95Milliseconds": 100,
                ],
                "recovery": recovery.jsonObject(),
                "search": search.jsonObject(),
                "confirm": confirm.jsonObject(),
            ]
        }
    }
}
