import XCTest

@testable import FineCoach

final class SystemEntryInfrastructureTests: XCTestCase {
    func testWidgetSnapshotPolicyUsesFirstAuthenticationAndExcludesBackup() {
        XCTAssertEqual(ProtectedFilePolicy.widgetSnapshot.fileProtection, .completeUntilFirstUserAuthentication)
        XCTAssertTrue(ProtectedFilePolicy.widgetSnapshot.isExcludedFromBackup)
        XCTAssertEqual(ProtectedFilePolicy.business.fileProtection, .completeUnlessOpen)
        XCTAssertEqual(ProtectedFilePolicy.backupCandidate.fileProtection, .completeUnlessOpen)
        XCTAssertEqual(ProtectedFilePolicy.ephemeralReport.fileProtection, .complete)
        for policy in ProtectedFilePolicy.allCases {
            XCTAssertTrue(policy.isExcludedFromBackup)
        }
    }

    func testSharedSnapshotUsesFixedFilenameWithoutIdentifiers() throws {
        let container = URL(fileURLWithPath: "/shared-container", isDirectory: true)
        let url = try XCTUnwrap(SharedContainer.snapshotURL(in: container))
        XCTAssertEqual(SharedContainer.appGroupIdentifier, "group.com.finecoach.app")
        XCTAssertEqual(url, container.appendingPathComponent("widget-today.json"))
        XCTAssertEqual(url.lastPathComponent, "widget-today.json")
        XCTAssertNil(UUID(uuidString: url.deletingPathExtension().lastPathComponent))
    }

    func testUnavailableSharedContainerHasNoFallback() {
        XCTAssertNil(SharedContainer.snapshotURL(in: nil))
    }

    func testSystemEntryLogEventsMatchTheFixedAllowlist() {
        XCTAssertEqual(
            Set(AppLogEvent.allCases.filter { $0.rawValue.hasPrefix("system_entry.") }.map(\.rawValue)),
            Set([
                "system_entry.snapshot_written", "system_entry.snapshot_failed",
                "system_entry.activity_started", "system_entry.activity_ended",
                "system_entry.activity_unavailable", "system_entry.shortcut_opened",
            ])
        )
        XCTAssertEqual(AppLogOperation.systemEntry.rawValue, "system_entry")
    }
}
