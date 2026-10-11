import XCTest

/// The 「未扣课 · 无有效课包」 note is coach-only billing information (owner
/// decision 2026-10-11): it MUST NOT reach the Share Report, the M2 archive
/// export, the backup or any log. It lives only on `SessionMO`, outside the
/// `Session` / `CompletedSession` types those features consume; this source
/// scan pins that boundary.
final class CreditSettlementNoteIsolationTests: XCTestCase {
    /// The only app sources allowed to mention the note.
    private let allowed: Set<String> = [
        "App/FCAccessibilityID.swift",
        "Core/Domain/CreditLedger.swift",
        "Core/Application/CreditLedgerUseCases.swift",
        "Core/Application/HistoryUseCases.swift",
        "Core/Persistence/CoreDataSessionRepository.swift",
        "Core/Persistence/SessionManagedObject+Mapping.swift",
        "Features/History/HistoryListView.swift",
        "Features/History/SessionDetailView.swift",
    ]

    /// Share Report, archive export, archive viewer and backup code paths.
    private let forbiddenPrefixes = [
        "Core/Archive/",
        "Core/Application/Archive/",
        "Core/Domain/Archive/",
        "Core/Reporting/",
        "Core/Backup/",
        "Features/ShareReport/",
        "Features/ArchiveExport/",
        "Features/ArchiveViewer/",
        "Features/BackupRestore/",
        "Core/Domain/Session.swift",
        "Core/Domain/CompletedSession.swift",
    ]

    func testOnlyAllowlistedSourcesMentionTheNote() throws {
        let mentions = try sourcesMentioningNote()
        XCTAssertFalse(mentions.isEmpty, "found no mention at all; scan path is wrong")
        XCTAssertEqual(mentions.subtracting(allowed), [], "unexpected readers of the credit settlement note")
        for path in mentions {
            for prefix in forbiddenPrefixes {
                XCTAssertFalse(path.hasPrefix(prefix), "\(path) must not read the credit settlement note")
            }
        }
    }

    func testSessionMappingNeverCopiesTheNoteIntoSessionOrBackup() throws {
        // `apply`/`makeSession` (also used by backup export/restore) must not
        // touch the column: the key constant is declared once and never used there.
        let mapping = try source("Core/Persistence/SessionManagedObject+Mapping.swift")
        XCTAssertEqual(mapping.components(separatedBy: "creditSettlementNoteKey").count - 1, 1)
        XCTAssertTrue(mapping.contains("\"creditSettlementNote\""), "the key must be declared here")
    }

    func testFilesThatReadTheNoteDoNotLog() throws {
        for path in allowed {
            let text = try source(path)
            for call in ["Logger(", "os_log(", "NSLog(", "print(", "debugPrint("] {
                XCTAssertFalse(text.contains(call), "\(path) must not log (\(call))")
            }
        }
    }

    // MARK: - Sources

    private func sourcesMentioningNote() throws -> Set<String> {
        let root = appRoot()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var mentions: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8).lowercased()
            if text.contains("creditsettlementnote") || text.contains("creditnote") {
                mentions.insert(String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)))
            }
        }
        return mentions
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: appRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func appRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CoursePackages/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp")
    }
}
