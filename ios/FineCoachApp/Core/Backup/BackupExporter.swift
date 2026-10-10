import Foundation

public struct BackupExportRequest: Sendable {
    public let password: BackupPassword
    public let destinationDirectory: URL

    public init(password: BackupPassword, destinationDirectory: URL) {
        self.password = password
        self.destinationDirectory = destinationDirectory
    }
}

public struct BackupExportResult: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

public struct BackupRestoreRequest: Sendable {
    public let password: BackupPassword
    public let sourceFileURL: URL

    public init(password: BackupPassword, sourceFileURL: URL) {
        self.password = password
        self.sourceFileURL = sourceFileURL
    }
}

public struct BackupCoordinator: Sendable {
    private let rootURL: URL
    private let writer: PersistenceWriter
    private let clock: any Clock
    private let ids: any IDGenerator
    private let random: any SecureRandomSource
    private let fileAdapter: SecurityScopedFileAdapter
    private let protectedFileStore: ProtectedFileStore

    public init(
        rootURL: URL,
        writer: PersistenceWriter,
        clock: any Clock,
        ids: any IDGenerator,
        random: any SecureRandomSource = SecureRandomGenerator(),
        fileAdapter: SecurityScopedFileAdapter = SecurityScopedFileAdapter(),
        protectedFileStore: ProtectedFileStore = ProtectedFileStore()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.writer = writer
        self.clock = clock
        self.ids = ids
        self.random = random
        self.fileAdapter = fileAdapter
        self.protectedFileStore = protectedFileStore
    }

    public func exportInventory(_ request: BackupExportRequest) async throws -> BackupExportResult {
        let directory = StoreGenerationDirectory(rootURL: rootURL)
        let pointerUUID = try currentGenerationUUID(in: directory)
        try FileFlowJanitor.cleanupOrphans(
            rootURL: rootURL,
            currentGenerationUUID: pointerUUID,
            restoreIntent: try RestoreGenerationSwitcher.readIntent(from: directory),
            keepingFlowIDs: []
        )

        let inventory = try await writer.read { context in
            try BackupInventoryMapper.collect(in: context)
        }
        let password = request.password
        let randomSource = random
        let plaintext = try await Task.detached {
            try BackupInventoryMapper.encodeFrames(inventory)
        }.value
        let sectionCounts: [Int] = [
            inventory.students.count,
            inventory.catalog.count,
            inventory.preferences.count,
            inventory.claims.count,
            inventory.sessions.count,
            inventory.reports.count,
            inventory.settings.count,
            inventory.appointments.count,
            inventory.recurrenceSeries.count,
            inventory.coursePackages.count,
            inventory.creditAdjustments.count,
            inventory.templates.count,
            inventory.sessionSections.count,
            inventory.bodyMetrics.count,
            inventory.bodyMeasurements.count,
        ]
        let recordCount = UInt64(1 + sectionCounts.reduce(0, +))
        let container: Data
        do {
            container = try await Task.detached {
                try BackupContainerCodec.encrypt(
                    plaintext: plaintext,
                    password: password,
                    recordCount: recordCount,
                    random: randomSource
                )
            }.value
        } catch DomainError.randomSourceFailed {
            throw BackupError.invalidState
        }

        let after = try await writer.read { context in
            try BackupInventoryMapper.collect(in: context)
        }
        guard after == inventory, try currentGenerationUUID(in: directory) == pointerUUID else {
            throw BackupError.invalidState
        }

        let byteBudget = UInt64(container.count)
        try Self.requireTempBudget(directory: directory, additional: byteBudget)

        let backupFileID = ids.makeID()
        let fileName = "FineCoach-Backup-\(backupFileID.uuidString).fcbackup"
        let flowID = UUID()
        let relativePath = "flows/\(flowID.uuidString.lowercased())/\(fileName)"
        let lease = FileFlowLease(
            flowID: flowID,
            kind: .backupExport,
            phase: "writingCandidate",
            managedRelativePaths: [relativePath],
            byteBudget: byteBudget
        )
        try FileFlowLeaseStore.acquire(lease, in: directory)
        defer { try? FileFlowLeaseStore.release(in: directory) }

        let flowDirectory = directory.flowURL.appendingPathComponent(
            flowID.uuidString.lowercased(),
            isDirectory: true
        )
        try protectedFileStore.prepareDirectory(at: flowDirectory, policy: .business)
        let tempURL = flowDirectory.appendingPathComponent(fileName, isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: flowDirectory)
        }
        try protectedFileStore.atomicReplace(data: container, at: tempURL, policy: .business)

        try FileManager.default.createDirectory(
            at: request.destinationDirectory,
            withIntermediateDirectories: true
        )
        let destinationURL = request.destinationDirectory.appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: tempURL, to: destinationURL)
        return BackupExportResult(fileURL: destinationURL)
    }

    public func restoreReplacingCurrent(_ request: BackupRestoreRequest) async throws {
        let directory = StoreGenerationDirectory(rootURL: rootURL)
        let oldUUID = try currentGenerationUUID(in: directory)
        try FileFlowJanitor.cleanupOrphans(
            rootURL: rootURL,
            currentGenerationUUID: oldUUID,
            restoreIntent: try RestoreGenerationSwitcher.readIntent(from: directory),
            keepingFlowIDs: []
        )

        let header = try fileAdapter.inspectContainerHeader(at: request.sourceFileURL)
        let expected = try BackupContainerReader.expectedContainerByteCount(header: header)
        let candidateEstimate = header.plaintextLength
        let extra = expected.addingReportingOverflow(candidateEstimate)
        if extra.overflow {
            throw BackupError.limitExceeded
        }
        try Self.requireTempBudget(directory: directory, additional: extra.partialValue)
        try SecurityScopedFileAdapter.ensureFreeBytes(
            BackupSecurityCeiling.requiredFreeBytes(plaintextLength: header.plaintextLength),
            near: directory.flowURL
        )

        let flowID = UUID()
        let relativePath = "flows/\(flowID.uuidString.lowercased())/staging.fcbackup"
        let lease = FileFlowLease(
            flowID: flowID,
            kind: .restoreImport,
            phase: "staging",
            managedRelativePaths: [relativePath],
            byteBudget: extra.partialValue
        )
        try FileFlowLeaseStore.acquire(lease, in: directory)
        defer { try? FileFlowLeaseStore.release(in: directory) }

        let flowDirectory = directory.flowURL.appendingPathComponent(
            flowID.uuidString.lowercased(),
            isDirectory: true
        )
        try protectedFileStore.prepareDirectory(at: flowDirectory, policy: .business)
        let stagingURL = flowDirectory.appendingPathComponent("staging.fcbackup", isDirectory: false)
        var candidateUUID: UUID?
        defer {
            try? FileManager.default.removeItem(at: flowDirectory)
        }

        let inventory: BackupInventory
        do {
            let copied = try fileAdapter.copyBounded(
                from: request.sourceFileURL,
                to: stagingURL,
                maximumBytes: min(BackupSecurityCeiling.maxAppManagedTempBytes, expected)
            )
            let staged = try Data(contentsOf: stagingURL)
            guard UInt64(staged.count) == copied else {
                throw BackupError.invalidHeader
            }
            let stagedHeader = try BackupContainerReader.inspectHeader(staged)
            try BackupSecurityCeiling.validateHeader(stagedHeader)
            try BackupContainerReader.rejectTrailingOrReorderedChunks(header: stagedHeader, container: staged)
            let password = request.password
            let plaintext = try await Task.detached {
                try BackupContainerCodec.decrypt(container: staged, password: password)
            }.value
            inventory = try await Task.detached {
                try BackupInventoryMapper.decodeFrames(plaintext)
            }.value
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.authenticationFailed
        }

        // M2-FR-051: capture the current archive identity before the candidate exists, so a
        // failure here leaves no candidate generation behind.
        let carryOver = try await writer.read { context in
            try ArchiveIdentityCarryOver.capture(in: context)
        }
        let candidateInventory = carryOver.applying(to: inventory)

        let newUUID = ids.makeID()
        candidateUUID = newUUID
        try protectedFileStore.prepareDirectory(
            at: directory.generationURL(for: newUUID),
            policy: .backupCandidate
        )
        let metadataStore = StoreGenerationMetadataStore(directory: directory)
        try metadataStore.write(
            try StoreGenerationMetadata(
                generationUUID: newUUID,
                createdAtUTC: clock.nowUTC(),
                validationState: .candidate
            )
        )

        let candidate = try PersistenceController(
            storeURL: directory.databaseURL(for: newUUID),
            protectedFileStore: protectedFileStore
        )
        do {
            let active = try await candidate.writer.transaction { context in
                try CandidateGenerationBuilder.apply(candidateInventory, in: context)
            }
            try candidate.detachPersistentStores()
            try writeRecovery(active: active, generationUUID: newUUID, at: directory.recoveryURL(for: newUUID))
            var metadata = try metadataStore.validate(generationUUID: newUUID)
            metadata.validationState = .validated
            try metadataStore.write(metadata)

            try RestoreGenerationSwitcher.writeIntent(
                RestoreIntent(oldGenerationUUID: oldUUID, newGenerationUUID: newUUID, phase: .prepared),
                to: directory
            )
            try CurrentGenerationPointerStore(url: directory.currentPointerURL).replace(
                with: try CurrentGenerationPointer(generationUUID: newUUID)
            )
            try RestoreGenerationSwitcher.writeIntent(
                RestoreIntent(oldGenerationUUID: oldUUID, newGenerationUUID: newUUID, phase: .switched),
                to: directory
            )

            let verified = try PersistenceController(
                storeURL: directory.databaseURL(for: newUUID),
                protectedFileStore: protectedFileStore
            )
            _ = try await verified.writer.read { context in
                try BackupInventoryMapper.collect(in: context)
            }
            try verified.detachPersistentStores()
            try promoteRecovery(from: newUUID, directory: directory)

            metadata.validationState = .current
            try metadataStore.write(metadata)
            try RestoreGenerationSwitcher.writeIntent(
                RestoreIntent(oldGenerationUUID: oldUUID, newGenerationUUID: newUUID, phase: .committed),
                to: directory
            )
        } catch {
            try? candidate.detachPersistentStores()
            var restoredPointer = false
            do {
                try CurrentGenerationPointerStore(url: directory.currentPointerURL).replace(
                    with: try CurrentGenerationPointer(generationUUID: oldUUID)
                )
                restoredPointer = true
            } catch {
                restoredPointer = false
            }
            if restoredPointer {
                try? RestoreGenerationSwitcher.clearIntent(in: directory)
                if let candidateUUID {
                    try? FileManager.default.removeItem(at: directory.generationURL(for: candidateUUID))
                }
            }
            if let backupError = error as? BackupError {
                throw backupError
            }
            throw BackupError.invalidState
        }
    }

    private static func requireTempBudget(directory: StoreGenerationDirectory, additional: UInt64) throws {
        let occupied = try FileFlowLeaseStore.occupiedByteBudget(in: directory)
        let total = occupied.addingReportingOverflow(additional)
        if total.overflow || total.partialValue > BackupSecurityCeiling.maxAppManagedTempBytes {
            throw BackupError.limitExceeded
        }
    }

    private func currentGenerationUUID(in directory: StoreGenerationDirectory) throws -> UUID {
        guard let pointer = try CurrentGenerationPointerStore(url: directory.currentPointerURL).read() else {
            throw BackupError.invalidState
        }
        return pointer.generationUUID
    }

    private func writeRecovery(active: Session?, generationUUID: UUID, at url: URL) throws {
        let store = ActiveSessionRecoveryStore(url: url)
        if let active, active.state == .inProgress, active.revision >= 1 {
            try store.replace(try ActiveSessionRecoverySnapshot(storeGenerationUUID: generationUUID, session: active))
        } else {
            try store.remove()
        }
    }

    private func promoteRecovery(from generationUUID: UUID, directory: StoreGenerationDirectory) throws {
        let staged = directory.recoveryURL(for: generationUUID)
        let live = directory.activeRecoveryURL
        if FileManager.default.fileExists(atPath: staged.path) {
            let data = try Data(contentsOf: staged)
            try protectedFileStore.atomicReplace(data: data, at: live, policy: .business)
        } else if FileManager.default.fileExists(atPath: live.path) {
            try FileManager.default.removeItem(at: live)
        }
    }
}
