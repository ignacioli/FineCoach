import CoreData
import XCTest

#if DEBUG
    @testable import FineCoach
#else
    import FineCoach
#endif

#if DEBUG
    private final class TransactionConcurrencyProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var activeTransactions = 0
        private(set) var maximumConcurrentTransactions = 0

        func enter() {
            lock.lock()
            activeTransactions += 1
            maximumConcurrentTransactions = max(maximumConcurrentTransactions, activeTransactions)
            lock.unlock()
        }

        func leave() {
            lock.lock()
            activeTransactions -= 1
            lock.unlock()
        }
    }
#endif

final class FoundationIntegrationTests: XCTestCase {
    #if DEBUG
        private func assertProtectionRawValue(
            _ actual: String?,
            expected: FileProtectionType,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            #if targetEnvironment(simulator)
                let attachment = XCTAttachment(
                    string: "requested=\(expected.rawValue) observed=\(actual ?? "unavailable")"
                )
                attachment.name = "Simulator Data Protection readback is diagnostic only"
                attachment.lifetime = .keepAlways
                add(attachment)
            #else
                XCTAssertEqual(actual, expected.rawValue, file: file, line: line)
            #endif
        }

        func testV2ModelLoadsWithApprovedEntitySurface() throws {
            // M1-B T004/T005: FineCoachV2 is the bundled current model. It is a
            // purely additive superset of FineCoachV1 (plan D-M1B-006) -- the
            // 11 M1-A entities below are unchanged, plus the 9 new M1-B entities.
            let model = try PersistenceController.loadBundledModel()
            let entities = Set(model.entities.compactMap(\.name))
            let expectedM1A: Set<String> = [
                "StudentMO",
                "ExerciseCatalogMO",
                "ExerciseNameClaimMO",
                "ExercisePreferenceMO",
                "SessionMO",
                "SessionExerciseMO",
                "TrainingSetMO",
                "ShareReportMO",
                "AppSettingMO",
                "ActiveSessionPointerMO",
                "StoreGenerationMetadataMO",
            ]
            let expectedM1B: Set<String> = [
                "RecurrenceSeriesMO",
                "AppointmentMO",
                "CoursePackageMO",
                "CreditAdjustmentMO",
                "TrainingTemplateMO",
                "TemplateExerciseMO",
                "SessionSectionMO",
                "BodyMetricDefinitionMO",
                "BodyMeasurementMO",
            ]
            XCTAssertEqual(entities, expectedM1A.union(expectedM1B))
            XCTAssertEqual(
                model.entities.first(where: { $0.name == "StudentMO" })?.attributesByName["id"]?.attributeType,
                .UUIDAttributeType)
        }

        func testSingleWriterSerializesTransactionsAndPersistsValues() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")
            let controller = try PersistenceController(storeURL: storeURL)
            let writer = controller.writer
            let probe = TransactionConcurrencyProbe()

            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<32 {
                    group.addTask {
                        try await writer.transaction { context in
                            probe.enter()
                            defer { probe.leave() }

                            let setting = NSEntityDescription.insertNewObject(
                                forEntityName: "AppSettingMO",
                                into: context
                            )
                            setting.setValue("test.setting.\(index)", forKey: "key")
                            setting.setValue("value-\(index)", forKey: "typedValue")
                            setting.setValue(Int64(1), forKey: "schemaVersion")
                        }
                    }
                }
                try await group.waitForAll()
            }

            XCTAssertEqual(probe.maximumConcurrentTransactions, 1)

            let keys = try await writer.read { context -> [String] in
                let request = NSFetchRequest<NSManagedObject>(entityName: "AppSettingMO")
                request.sortDescriptors = [NSSortDescriptor(key: "key", ascending: true)]
                return try context.fetch(request).compactMap { $0.value(forKey: "key") as? String }
            }
            XCTAssertEqual(Set(keys), Set((0..<32).map { "test.setting.\($0)" }))

            let storeAudits = try controller.secureStoreArtifacts()
            let expectedArtifacts = [
                storeURL,
                URL(fileURLWithPath: storeURL.path + "-wal"),
                URL(fileURLWithPath: storeURL.path + "-shm"),
            ]
            for artifactURL in expectedArtifacts {
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: artifactURL.path),
                    "Expected SQLite artifact \(artifactURL.lastPathComponent)"
                )
                let audit = try XCTUnwrap(storeAudits[artifactURL])
                assertProtectionRawValue(
                    audit.protectionRawValue,
                    expected: .completeUnlessOpen
                )
                XCTAssertTrue(audit.isExcludedFromBackup)
            }
            try await controller.shutdownForTesting()
        }

        func testIncompatibleModelDoesNotEraseExistingStore() async throws {
            let directory = try TemporaryProtectedDirectory()
            let storeURL = directory.url.appendingPathComponent("generation/FineCoach.sqlite")

            do {
                let controller = try PersistenceController(storeURL: storeURL)
                try await controller.writer.transaction { context in
                    let setting = NSEntityDescription.insertNewObject(
                        forEntityName: "AppSettingMO",
                        into: context
                    )
                    setting.setValue("preserved.marker", forKey: "key")
                    setting.setValue("still-present", forKey: "typedValue")
                    setting.setValue(Int64(1), forKey: "schemaVersion")
                }
                try await controller.shutdownForTesting()
            }

            let incompatibleModel = NSManagedObjectModel()
            let incompatibleEntity = NSEntityDescription()
            incompatibleEntity.name = "DifferentSchema"
            incompatibleEntity.managedObjectClassName = "NSManagedObject"
            incompatibleModel.entities = [incompatibleEntity]

            XCTAssertThrowsError(
                try PersistenceController(storeURL: storeURL, model: incompatibleModel)
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
            let reopened = try PersistenceController(storeURL: storeURL)
            let values = try await reopened.writer.read { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "AppSettingMO")
                return try context.fetch(request).map { object in
                    (
                        object.value(forKey: "key") as? String,
                        object.value(forKey: "typedValue") as? String
                    )
                }
            }
            XCTAssertEqual(values.count, 1)
            XCTAssertEqual(values.first?.0, "preserved.marker")
            XCTAssertEqual(values.first?.1, "still-present")
            try await reopened.shutdownForTesting()
        }

        func testProtectedDirectoryAndAtomicFileReadBackPolicy() throws {
            let directory = try TemporaryProtectedDirectory()
            let protectedStore = ProtectedFileStore()
            let businessDirectory = directory.url.appendingPathComponent("business", isDirectory: true)
            let businessAudit = try protectedStore.prepareDirectory(at: businessDirectory, policy: .business)
            assertProtectionRawValue(
                businessAudit.protectionRawValue,
                expected: .completeUnlessOpen
            )
            XCTAssertTrue(businessAudit.isExcludedFromBackup)

            let reportURL = businessDirectory.appendingPathComponent("report-001.png")
            let reportAudit = try protectedStore.atomicReplace(
                data: Data([0x01, 0x02, 0x03]),
                at: reportURL,
                policy: .ephemeralReport
            )
            assertProtectionRawValue(reportAudit.protectionRawValue, expected: .complete)
            XCTAssertTrue(reportAudit.isExcludedFromBackup)
            XCTAssertEqual(try Data(contentsOf: reportURL), Data([0x01, 0x02, 0x03]))

            let replacedReportData = Data([0x04, 0x05, 0x06])
            let replacedReportAudit = try protectedStore.atomicReplace(
                data: replacedReportData,
                at: reportURL,
                policy: .ephemeralReport
            )
            assertProtectionRawValue(replacedReportAudit.protectionRawValue, expected: .complete)
            XCTAssertTrue(replacedReportAudit.isExcludedFromBackup)
            XCTAssertEqual(try Data(contentsOf: reportURL), replacedReportData)

            let candidateURL = businessDirectory.appendingPathComponent("candidate.bin")
            let candidateData = Data([0x0A, 0x0B, 0x0C])
            let candidateAudit = try protectedStore.atomicReplace(
                data: candidateData,
                at: candidateURL,
                policy: .backupCandidate
            )
            assertProtectionRawValue(
                candidateAudit.protectionRawValue,
                expected: .completeUnlessOpen
            )
            XCTAssertTrue(candidateAudit.isExcludedFromBackup)
            XCTAssertEqual(try protectedStore.readData(from: candidateURL), candidateData)

            let remainingNames = try FileManager.default.contentsOfDirectory(
                at: businessDirectory,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent).sorted()
            XCTAssertEqual(remainingNames, ["candidate.bin", "report-001.png"])
        }

        func testGenerationPointerAndMetadataRejectMismatchWithoutChangingPointer() throws {
            let temporaryDirectory = try TemporaryProtectedDirectory()
            let directory = StoreGenerationDirectory(rootURL: temporaryDirectory.url)
            let pointerStore = CurrentGenerationPointerStore(url: directory.currentPointerURL)
            let metadataStore = StoreGenerationMetadataStore(directory: directory)
            let protectedStore = ProtectedFileStore()
            let first = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
            let second = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
            try protectedStore.prepareDirectory(at: directory.generationURL(for: first))
            try metadataStore.write(
                try StoreGenerationMetadata(
                    generationUUID: first,
                    createdAtUTC: Date(timeIntervalSince1970: 0),
                    validationState: .current
                )
            )
            try pointerStore.replace(with: try CurrentGenerationPointer(generationUUID: first))

            XCTAssertThrowsError(try CurrentGenerationPointer(generationUUID: second, schemaVersion: 2))
            XCTAssertEqual(try pointerStore.read()?.generationUUID, first)

            let mismatchedMetadata = try StoreGenerationMetadata(
                generationUUID: second,
                createdAtUTC: Date(timeIntervalSince1970: 1),
                validationState: .current
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try protectedStore.atomicReplace(
                data: encoder.encode(mismatchedMetadata),
                at: directory.metadataURL(for: first),
                policy: .business
            )

            XCTAssertThrowsError(try metadataStore.validate(generationUUID: first)) { error in
                XCTAssertEqual(error as? StoreGenerationError, .metadataMismatch)
            }
            XCTAssertEqual(try pointerStore.read()?.generationUUID, first)
            XCTAssertTrue(try protectedStore.audit(url: directory.currentPointerURL).isExcludedFromBackup)
            XCTAssertTrue(try protectedStore.audit(url: directory.metadataURL(for: first)).isExcludedFromBackup)
        }

        @MainActor
        func testCompositionRootFailsClosedWhenPointerGenerationIsIncomplete() throws {
            let temporaryDirectory = try TemporaryProtectedDirectory()
            let directory = StoreGenerationDirectory(rootURL: temporaryDirectory.url)
            let generationUUID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
            try CurrentGenerationPointerStore(url: directory.currentPointerURL).replace(
                with: try CurrentGenerationPointer(generationUUID: generationUUID)
            )

            XCTAssertThrowsError(try AppEnvironment(rootURL: temporaryDirectory.url)) { error in
                XCTAssertEqual(error as? StoreGenerationError, .invalidGeneration)
            }
        }

        func testLoggerCanaryOnlyExposesFixedNonBusinessValues() {
            let logger = AppLogger(subsystem: "com.finecoach.tests", category: "canary")
            logger.info(.modelLoaded, operation: .startup)
            logger.failure(.writerTransaction, operation: .persistence, category: .persistenceFailed)

            let fixedValues =
                (AppLogEvent.allCases.map(\.rawValue) + AppLogOperation.allCases.map(\.rawValue)
                + AppLogErrorCategory.allCases.map(\.rawValue)).joined(separator: "|")
            let forbiddenBusinessValues = [
                FictitiousFixtures.student.displayName,
                FictitiousFixtures.student.trainingGoal,
                FictitiousFixtures.student.syntheticNote,
                FictitiousFixtures.student.id.uuidString,
            ]
            for value in forbiddenBusinessValues {
                XCTAssertFalse(fixedValues.contains(value))
            }
        }

        func testFaultInjectionBoundaryIsExplicitlyDebugOnly() throws {
            let injector = TestFaultInjector(failingPoints: [.persistenceWriterSave])
            XCTAssertThrowsError(try injector.check(.persistenceWriterSave))
            try injector.check(.currentPointerReplace)
        }

        func testFaultInjectionAdaptersInterruptRealWriteBoundaries() async throws {
            let directory = try TemporaryProtectedDirectory()

            let writerInjector = TestFaultInjector(failingPoints: [.persistenceWriterSave])
            let controller = try PersistenceController(
                storeURL: directory.url.appendingPathComponent("writer/FineCoach.sqlite"),
                faultInjectionBoundary: FaultInjectionBoundary(injector: writerInjector)
            )
            do {
                try await controller.writer.transaction { context in
                    let setting = NSEntityDescription.insertNewObject(
                        forEntityName: "AppSettingMO",
                        into: context
                    )
                    setting.setValue("must-not-save", forKey: "key")
                    setting.setValue("synthetic", forKey: "typedValue")
                    setting.setValue(Int64(1), forKey: "schemaVersion")
                }
                XCTFail("Expected the writer fault point to interrupt the save")
            } catch {
                XCTAssertEqual(
                    error as? FaultInjectionError,
                    .injected(.persistenceWriterSave)
                )
            }
            let savedCount = try await controller.writer.read { context in
                try context.count(for: NSFetchRequest(entityName: "AppSettingMO"))
            }
            XCTAssertEqual(savedCount, 0)
            try await controller.shutdownForTesting()

            let generationDirectory = StoreGenerationDirectory(
                rootURL: directory.url.appendingPathComponent("generation")
            )
            let generationUUID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
            let metadataInjector = TestFaultInjector(failingPoints: [.generationMetadataWrite])
            let metadataStore = StoreGenerationMetadataStore(
                directory: generationDirectory,
                faultInjectionBoundary: FaultInjectionBoundary(injector: metadataInjector)
            )
            XCTAssertThrowsError(
                try metadataStore.write(
                    StoreGenerationMetadata(
                        generationUUID: generationUUID,
                        createdAtUTC: Date(timeIntervalSince1970: 0),
                        validationState: .candidate
                    )
                )
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: generationDirectory.metadataURL(for: generationUUID).path
                )
            )

            let pointerInjector = TestFaultInjector(failingPoints: [.currentPointerReplace])
            let pointerStore = CurrentGenerationPointerStore(
                url: generationDirectory.currentPointerURL,
                faultInjectionBoundary: FaultInjectionBoundary(injector: pointerInjector)
            )
            XCTAssertThrowsError(
                try pointerStore.replace(
                    with: CurrentGenerationPointer(generationUUID: generationUUID)
                )
            )
            XCTAssertNil(try pointerStore.read())
        }
    #else
        func testReleaseArtifactsExcludeFaultInjectionSymbols() throws {
            let testBundle = Bundle(for: FoundationIntegrationTests.self)
            let appBundleURL = testBundle.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let appBundle = Bundle(url: appBundleURL)
            let appExecutableURL = try XCTUnwrap(appBundle?.executableURL)
            let forbiddenSymbols = [
                "FaultInjectionPoint",
                "FaultInjectionError",
                "TestFaultInjector",
                "FaultInjectionBoundary",
            ]

            let executableData = try Data(contentsOf: appExecutableURL)
            for symbol in forbiddenSymbols {
                XCTAssertFalse(
                    executableData.range(of: Data(symbol.utf8)) != nil,
                    "Release app contains forbidden fault-injection symbol \(symbol)"
                )
            }
        }
    #endif
}
