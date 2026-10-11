import XCTest

@testable import FineCoach

#if DEBUG
    /// T053 support: the DEBUG viewer seed installs a viewer archive with every module, built by the
    /// real export policy from fictional data. All data is fictional.
    final class ArchiveViewerDebugSeedTests: XCTestCase {
        private struct EmptyCoachProbe: CoachInstallProbe {
            func read() async throws -> CoachInstallSnapshot {
                CoachInstallSnapshot(onboardingCompleted: false, hasWorkData: false)
            }
        }

        private func makeStore() -> ArchiveSnapshotStore {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ViewerSeedTests-\(UUID().uuidString)", isDirectory: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: root) }
            return ArchiveSnapshotStore(rootURL: root)
        }

        func testSeedInstallsAViewerArchiveWithEveryModule() async throws {
            let store = makeStore()
            XCTAssertTrue(ArchiveViewerDebugSeed.install(into: store))

            let resolver = InstallStateResolver(store: store, probe: EmptyCoachProbe())
            let state = try await resolver.resolve()
            XCTAssertEqual(state, .viewer)

            let content = try await ArchiveViewerUseCases(store: store).load()
            let modules = content.manifest.modules
            XCTAssertTrue(
                modules.displayName && modules.sex && modules.bodyData && modules.trainingRecords
                    && modules.trends && modules.summaries && modules.exerciseInfo)
            XCTAssertEqual(content.studentDisplayName, "王小明")
            XCTAssertGreaterThanOrEqual(content.snapshot.sessions.count, 6)
            XCTAssertGreaterThanOrEqual(content.snapshot.bodyMetrics.count, 3)
            XCTAssertFalse(content.snapshot.summaries.isEmpty)
            XCTAssertNotNil(content.snapshot.attribution)
            XCTAssertTrue(content.snapshot.exercises.contains { $0.isAssisted })
            XCTAssertTrue(try content.trendExercises().count >= 3)
        }

        func testSeedIsIdempotentAndKeepsAnExistingArchive() throws {
            let store = makeStore()
            XCTAssertTrue(ArchiveViewerDebugSeed.install(into: store))
            let first = try XCTUnwrap(store.load()).manifest.sourceID
            XCTAssertTrue(ArchiveViewerDebugSeed.install(into: store))
            XCTAssertEqual(try XCTUnwrap(store.load()).manifest.sourceID, first)
        }
    }
#endif
