import FineCoach
import XCTest

/// Cheap, non-structural coverage for T047a's later assertions (spec §2.4 /
/// T047a): every documented status carries non-empty text and a non-empty
/// icon, and the case count matches the 5 named statuses this design system
/// version documents (逾期/冲突/课包异常/不可比较/权限拒绝). Does not render or
/// inspect any view.
final class FCStatusTests: XCTestCase {
    func testExactlyFiveStatuses() {
        XCTAssertEqual(FCStatus.allCases.count, 5)
    }

    func testEveryStatusHasNonEmptyTextAndSymbol() {
        for status in FCStatus.allCases {
            XCTAssertFalse(status.text.isEmpty, "\(status) must have display text")
            XCTAssertFalse(status.symbolName.isEmpty, "\(status) must have an SF Symbol name")
        }
    }

    /// T047a (c): where each of the 5 statuses is shown. The status must be
    /// rendered through `FCStatusLabel(.<case>)` (text + icon, NFR-005) in
    /// its registered Feature file. Plain source scan; no view inspection.
    func testEveryStatusIsShownThroughStatusLabelInItsRegisteredFile() throws {
        let locations: [(status: String, file: String)] = [
            ("overdue", "Features/Today/TodayView.swift"),
            ("conflict", "Features/Appointments/AppointmentEditorView.swift"),
            ("coursePackageInvalid", "Features/Today/TodayView.swift"),
            ("notComparable", "Features/History/HistoryListView.swift"),
            ("permissionDenied", "Features/Appointments/AppointmentEditorView.swift"),
            ("permissionDenied", "Features/Settings/SettingsView.swift"),
        ]
        XCTAssertEqual(Set(locations.map(\.status)).count, FCStatus.allCases.count, "every status needs a registered location")
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DesignSystem/
            .deletingLastPathComponent() // FineCoachTests/
            .deletingLastPathComponent() // ios/
            .appendingPathComponent("FineCoachApp")
        for location in locations {
            let url = appRoot.appendingPathComponent(location.file)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(
                source.contains("FCStatusLabel(.\(location.status))"),
                "\(location.file) must show .\(location.status) via FCStatusLabel"
            )
        }
    }
}
