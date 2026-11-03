#if DEBUG
    import Foundation
    import XCTest

    @testable import FineCoach

    final class ReviewDemoArchiveTests: XCTestCase {
        // Public review-demo password; protects fictional demonstration data only.
        private let password = "FineCoachDemo2026"
        private let baseline = Date(timeIntervalSince1970: 1_791_000_000)

        func testGenerateReviewDemoArchive() async throws {
            guard let output = ProcessInfo.processInfo.environment["FINECOACH_DEMO_ARCHIVE_OUT"], !output.isEmpty else {
                throw XCTSkip("Set FINECOACH_DEMO_ARCHIVE_OUT to generate the fictional review archive.")
            }
            let directory = try TemporaryProtectedDirectory()
            let controller = try PersistenceController(
                storeURL: directory.url.appendingPathComponent("demo.sqlite"), inMemory: true)
            let writer = controller.writer
            let clock = TestClock(utcDate: baseline)
            let calendar = TestCalendarProvider(timeZone: TimeZone(secondsFromGMT: 0)!)
            let studentRepository = CoreDataStudentRepository(writer: writer)
            let students = StudentUseCases(repository: studentRepository, clock: clock, ids: SystemIDGenerator())
            let student = try await students.create(
                draft: StudentDraft(displayName: "王小明（虚构演示）", sex: .male))
            let library = ExerciseLibraryUseCases(
                repository: CoreDataExerciseRepository(writer: writer), clock: clock, ids: SystemIDGenerator())
            try await library.seedIfNeeded()
            let custom = try await library.createCustom(name: "演示自定义推举", recordMode: .weightReps)
            let catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(.main)
            let records = Dictionary(uniqueKeysWithValues: catalog.provenance.records.map { ($0.recordID, $0) })
            // Include actual catalog exercises from both public datasets, never invented references.
            let builtIns = ["free-exercise-db", "wger.de"].flatMap { source in
                catalog.exercises.filter {
                    $0.recordMode == .weightReps && $0.retired != true
                        && records[$0.provenanceRef]?.sourceIdentifier.hasPrefix(source + ":") == true
                }.prefix(2)
            }
            XCTAssertEqual(builtIns.count, 4)
            let sessions = ActiveSessionUseCases(
                sessionRepository: CoreDataSessionRepository(writer: writer), studentRepository: studentRepository,
                exerciseRepository: CoreDataExerciseRepository(writer: writer),
                sectionRepository: CoreDataSessionSectionRepository(writer: writer),
                recoveryStore: ActiveSessionRecoveryStore(url: directory.url.appendingPathComponent("recovery.json")),
                storeGenerationUUID: UUID(), clock: clock, ids: SystemIDGenerator())
            for week in 0..<4 {
                clock.setUTC(baseline.addingTimeInterval(Double(week) * 7 * 86_400))
                let session = try await sessions.startOrOpen(studentID: student.id, trainingFocus: [.chest, .arms])
                let itemIDs = try builtIns.map { try StableExerciseID($0.id) } + [custom.id]
                for itemID in itemIDs {
                    let added = try await sessions.addCatalogExercise(sessionID: session.id, itemID: itemID)
                    let exercise = try XCTUnwrap(added.exercises.last)
                    let withSet = try await sessions.addSet(
                        sessionID: session.id, exerciseID: exercise.id,
                        input: TrainingSetInput(
                            recordMode: .weightReps, weightValue: "\(10 + week * 2)",
                            repetitionCount: "10", unit: .kilograms))
                    let set = try XCTUnwrap(withSet.exercises.last?.sets.last)
                    _ = try await sessions.confirmSet(sessionID: session.id, setID: set.id)
                }
                clock.advance(seconds: 2_700)
                _ = try await sessions.applyCoachAdjustedDuration(sessionID: session.id, DecimalValue("2700"))
                _ = try await sessions.finish(sessionID: session.id)
            }
            let body = BodyDataUseCases(
                repository: CoreDataBodyDataRepository(writer: writer), clock: clock,
                calendarProvider: calendar, ids: SystemIDGenerator())
            for (week, value) in ["70.5", "70.0", "69.5"].enumerated() {
                _ = try await body.recordMeasurement(
                    studentID: student.id, metricID: BuiltInBodyMetric.weight.id, value: value, enteredUnit: "kg",
                    at: baseline.addingTimeInterval(Double(week) * 7 * 86_400))
            }
            let source = try await ArchiveExportSourceReader(
                writer: writer, calendarProvider: calendar, catalogLoader: { catalog }
            ).read(studentID: student.id)
            let snapshot = try ArchiveExportPolicy.makeSnapshot(
                source: source, selection: ArchiveModuleSelection(availability: source.availability),
                identity: ArchiveIdentity(
                    sourceID: UUID(uuidString: "5eed0000-0000-4000-8000-000000000001")!,
                    studentArchiveID: UUID(uuidString: "5eed0000-0000-4000-8000-000000000002")!),
                now: baseline.addingTimeInterval(28 * 86_400))
            let file = try ArchiveFileCodec.encode(snapshot: snapshot, password: ArchivePassword(creating: password))
            let decoded = try ArchiveFileCodec.decode(file: file, password: ArchivePassword(importing: password))
            XCTAssertEqual(decoded, snapshot)
            XCTAssertEqual(decoded.sessions.count, 4)
            XCTAssertEqual(decoded.exercises.filter { $0.kind == .builtIn }.count, 4)
            XCTAssertEqual(decoded.exercises.filter { $0.kind == .custom }.count, 1)
            XCTAssertEqual(decoded.bodyMeasurements.count, 3)
            let attribution = try XCTUnwrap(decoded.attribution)
            let expectedSources = Set(
                builtIns.compactMap {
                    records[$0.provenanceRef]?.sourceIdentifier.split(separator: ":").first.map(String.init)
                })
            XCTAssertEqual(Set(attribution.sourceName.components(separatedBy: ", ")), expectedSources)
            XCTAssertFalse(attribution.licenseName.isEmpty)
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded))
            assertExcludedFieldsAbsent(object)
            let url = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.write(to: url, options: .atomic)
            XCTAssertEqual(
                try ArchiveFileCodec.decode(
                    file: Data(contentsOf: url), password: ArchivePassword(importing: password)),
                snapshot)
        }

        private func assertExcludedFieldsAbsent(_ object: Any) {
            let forbidden = ["phone", "wechatID", "injuryNotes", "privateCoachNote", "actionPrivateNote", "coachNote"]
            if let dictionary = object as? [String: Any] {
                XCTAssertTrue(Set(dictionary.keys).isDisjoint(with: forbidden))
                for value in dictionary.values { assertExcludedFieldsAbsent(value) }
            } else if let array = object as? [Any] {
                for value in array { assertExcludedFieldsAbsent(value) }
            }
        }
    }
#endif
