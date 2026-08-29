#if DEBUG
    import XCTest

    @testable import FineCoach

    private struct FakeSharePresenter: SystemSharePresenting {
        let outcome: SystemShareOutcome

        func present(fileURLs: [URL]) async -> SystemShareOutcome {
            outcome
        }
    }

    final class TempReportLifecycleTests: XCTestCase {
        private let activeFlowID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        private let orphanFlowID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        private let leftoverFlowID = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!
        private let reportID = StableUUID(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
        private let sessionID = StableUUID(UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!)
        private let now = Date(timeIntervalSince1970: 1_700_000_000)
        private let handoffDate = Date(timeIntervalSince1970: 1_700_000_060)
        private let firstPage = Data([0x89, 0x50, 0x4E, 0x47])
        private let secondPage = Data([0x0A, 0x1B, 0x2C, 0x3D])
        private let replacedPage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        private let leftoverPage = Data([0x11, 0x22, 0x33, 0x44])

        func testReplacePreviewWritesGenericFilenamesAndRemovesStalePages() throws {
            let directory = try TemporaryProtectedDirectory()
            var lease = try TempReportLease(rootURL: directory.url, flowID: activeFlowID)
            XCTAssertEqual(lease.flowID, activeFlowID)
            XCTAssertEqual(lease.fileURLs, [])
            XCTAssertEqual(
                lease.directoryURL.standardizedFileURL, expectedFlowDirectory(root: directory.url, flowID: activeFlowID)
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: lease.directoryURL.path))

            let singlePage = try lease.replacePreview(pages: [firstPage])
            XCTAssertEqual(singlePage.map(\.lastPathComponent), ["report-001.png"])
            XCTAssertEqual(lease.fileURLs, singlePage)
            XCTAssertEqual(try Data(contentsOf: singlePage[0]), firstPage)
            assertGenericReportPath(singlePage[0], flowID: activeFlowID)

            let twoPages = try lease.replacePreview(pages: [firstPage, secondPage])
            XCTAssertEqual(twoPages.map(\.lastPathComponent), ["report-001.png", "report-002.png"])
            XCTAssertEqual(lease.fileURLs, twoPages)
            XCTAssertEqual(try Data(contentsOf: twoPages[0]), firstPage)
            XCTAssertEqual(try Data(contentsOf: twoPages[1]), secondPage)
            for pageURL in twoPages {
                assertGenericReportPath(pageURL, flowID: activeFlowID)
            }
            XCTAssertEqual(try reportFileNames(in: lease.directoryURL), ["report-001.png", "report-002.png"])

            let leftoverURL = lease.directoryURL.appendingPathComponent("report-003.png")
            try leftoverPage.write(to: leftoverURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: leftoverURL.path))

            let shrunk = try lease.replacePreview(pages: [replacedPage])
            XCTAssertEqual(shrunk.map(\.lastPathComponent), ["report-001.png"])
            XCTAssertEqual(lease.fileURLs, shrunk)
            XCTAssertEqual(try Data(contentsOf: shrunk[0]), replacedPage)
            XCTAssertNotEqual(try Data(contentsOf: shrunk[0]), firstPage)
            XCTAssertEqual(try reportFileNames(in: lease.directoryURL), ["report-001.png"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: leftoverURL.path))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: lease.directoryURL.appendingPathComponent("report-002.png").path
                )
            )
            assertGenericReportPath(shrunk[0], flowID: activeFlowID)
        }

        func testRetainForRetryKeepsFilesAndCloseDeletesDirectory() async throws {
            let directory = try TemporaryProtectedDirectory()
            var lease = try TempReportLease(rootURL: directory.url, flowID: activeFlowID)
            let written = try lease.replacePreview(pages: [firstPage, secondPage])
            let directoryURL = lease.directoryURL

            let cancelled = await SystemShareAdapter(presenter: FakeSharePresenter(outcome: .cancelled))
                .share(fileURLs: written)
            XCTAssertEqual(cancelled, .cancelled)
            lease.retainForRetry()
            XCTAssertEqual(lease.fileURLs, written)
            XCTAssertEqual(try Data(contentsOf: written[0]), firstPage)
            XCTAssertEqual(try Data(contentsOf: written[1]), secondPage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.path))

            try lease.close()
            XCTAssertEqual(lease.fileURLs, [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: written[0].path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: written[1].path))
        }

        func testCompletedHandoffDeletesFilesWhileCancelledAndFailedLeaveFreshnessUnchanged() async throws {
            let directory = try TemporaryProtectedDirectory()
            let report = ShareReport.make(
                id: reportID,
                sessionID: sessionID,
                generatedForRevision: 1,
                now: now
            )
            XCTAssertEqual(report.freshness, .current)
            XCTAssertNil(report.handedToSystemAtUTC)

            XCTAssertEqual(
                ShareReportHandoffRecorder.applying(.cancelled, to: report, at: handoffDate),
                report
            )
            XCTAssertEqual(
                ShareReportHandoffRecorder.applying(.failed, to: report, at: handoffDate),
                report
            )

            let cancelledReport = ShareReportHandoffRecorder.applying(.cancelled, to: report, at: handoffDate)
            XCTAssertEqual(cancelledReport.freshness, .current)
            XCTAssertNil(cancelledReport.handedToSystemAtUTC)

            let failedReport = ShareReportHandoffRecorder.applying(.failed, to: report, at: handoffDate)
            XCTAssertEqual(failedReport.freshness, .current)
            XCTAssertNil(failedReport.handedToSystemAtUTC)

            let completedReport = ShareReportHandoffRecorder.applying(.completed, to: report, at: handoffDate)
            XCTAssertEqual(completedReport.freshness, .current)
            XCTAssertEqual(completedReport.handedToSystemAtUTC, handoffDate)
            XCTAssertNotEqual(completedReport, report)

            let stale = report.markingStale()
            XCTAssertEqual(stale.freshness, .stale)
            XCTAssertNil(stale.handedToSystemAtUTC)
            XCTAssertEqual(ShareReportHandoffRecorder.applying(.failed, to: stale, at: handoffDate), stale)
            let staleCompleted = ShareReportHandoffRecorder.applying(.completed, to: stale, at: handoffDate)
            XCTAssertEqual(staleCompleted.freshness, .stale)
            XCTAssertEqual(staleCompleted.handedToSystemAtUTC, handoffDate)

            var lease = try TempReportLease(rootURL: directory.url, flowID: activeFlowID)
            let written = try lease.replacePreview(pages: [firstPage])
            let failedOutcome = await SystemShareAdapter(presenter: FakeSharePresenter(outcome: .failed))
                .share(fileURLs: written)
            XCTAssertEqual(failedOutcome, .failed)
            lease.retainForRetry()
            XCTAssertTrue(FileManager.default.fileExists(atPath: written[0].path))

            let completedOutcome = await SystemShareAdapter(presenter: FakeSharePresenter(outcome: .completed))
                .share(fileURLs: lease.fileURLs)
            XCTAssertEqual(completedOutcome, .completed)
            try lease.completeSystemHandoff()
            XCTAssertEqual(lease.fileURLs, [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: written[0].path))
        }

        func testCleanupOrphansDeletesUnkeptFlowsAndClearsAllOnColdLaunch() throws {
            let directory = try TemporaryProtectedDirectory()
            var active = try TempReportLease(rootURL: directory.url, flowID: activeFlowID)
            var orphan = try TempReportLease(rootURL: directory.url, flowID: orphanFlowID)
            let activeFiles = try active.replacePreview(pages: [firstPage])
            let orphanFiles = try orphan.replacePreview(pages: [secondPage])

            try TempReportLease.cleanupOrphans(in: directory.url, keepingFlowIDs: [activeFlowID])
            XCTAssertTrue(FileManager.default.fileExists(atPath: active.directoryURL.path))
            XCTAssertEqual(try Data(contentsOf: activeFiles[0]), firstPage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.directoryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: orphanFiles[0].path))

            var leftover = try TempReportLease(rootURL: directory.url, flowID: leftoverFlowID)
            let leftoverFiles = try leftover.replacePreview(pages: [leftoverPage])
            try TempReportLease.cleanupOrphans(in: directory.url, keepingFlowIDs: [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: active.directoryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.directoryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: activeFiles[0].path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: leftoverFiles[0].path))
        }

        func testWrittenReportFilesAreExcludedFromBackup() throws {
            let directory = try TemporaryProtectedDirectory()
            var lease = try TempReportLease(rootURL: directory.url, flowID: activeFlowID)
            let store = ProtectedFileStore()
            let directoryAudit = try store.audit(url: lease.directoryURL)
            XCTAssertTrue(directoryAudit.isExcludedFromBackup)

            let written = try lease.replacePreview(pages: [firstPage, secondPage])
            for url in written {
                let audit = try store.audit(url: url)
                XCTAssertTrue(audit.isExcludedFromBackup)
            }
        }

        private func expectedFlowDirectory(root: URL, flowID: UUID) -> URL {
            root
                .appendingPathComponent("share-report-flows", isDirectory: true)
                .appendingPathComponent(flowID.uuidString, isDirectory: true)
                .standardizedFileURL
        }

        private func reportFileNames(in directoryURL: URL) throws -> [String] {
            try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
                .map(\.lastPathComponent)
                .filter { $0.hasPrefix("report-") && $0.hasSuffix(".png") }
                .sorted()
        }

        private func assertGenericReportPath(
            _ url: URL,
            flowID: UUID,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertTrue(url.lastPathComponent.hasPrefix("report-"), file: file, line: line)
            XCTAssertEqual(url.pathExtension, "png", file: file, line: line)
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, flowID.uuidString, file: file, line: line)
            XCTAssertEqual(
                url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
                "share-report-flows",
                file: file,
                line: line
            )
            XCTAssertFalse(url.path.contains("林青"), file: file, line: line)
            XCTAssertFalse(url.path.contains("周宁"), file: file, line: line)
            XCTAssertFalse(url.lastPathComponent.contains("1700000000"), file: file, line: line)
            XCTAssertFalse(url.lastPathComponent.contains(flowID.uuidString), file: file, line: line)
        }
    }
#else
    import XCTest
    import FineCoach

    final class TempReportLifecycleTests: XCTestCase {
        func testReleaseKeepsEphemeralReportPolicyWithoutFaultInjection() {
            XCTAssertEqual(ProtectedFilePolicy.ephemeralReport.rawValue, "ephemeralReport")
        }
    }
#endif
