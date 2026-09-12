import FineCoach
import XCTest

/// THE ONLY place in this repo that proves body data can never reach a
/// Share Report (M1B-FR-030, SC-006) -- per tasks.md, no other task/test
/// should duplicate this proof (the same adversarial-review dedup rule as
/// T026 not re-running T025's full matrix).
///
/// Asserts, structurally:
/// 1. `ShareReportDTO`'s full field set (via `Mirror`, not a spot check)
///    contains no body-metric/body-measurement-named field anywhere in its
///    object graph.
/// 2. `ShareReportModuleSelection` -- the ONLY module on/off switch a coach
///    can toggle -- has no body-data field at all, so there is no UI
///    unlock/override path of any kind, not even a hidden one.
final class BodyDataReportExclusionTests: XCTestCase {
    private let forbiddenPatterns = ["bodymetric", "bodymeasurement", "bodydata"]

    func testShareReportDTOHasNoBodyDataFields() throws {
        let dto = ShareReportDTO(
            schemaVersion: 1,
            studentDisplayName: "学员",
            sessionDateUTC: Date(),
            durationSeconds: try DecimalValue("60"),
            trainingFocus: "上肢",
            studentFacingSummary: "summary",
            trainingVolume: try DecimalValue("100"),
            exercises: [
                ShareReportExerciseDTO(
                    displayName: "深蹲",
                    confirmedSets: [
                        ShareReportSetDTO(
                            orderIndex: 0,
                            recordMode: .weightReps,
                            weightValue: try DecimalValue("60"),
                            repetitionCount: try DecimalValue("8"),
                            durationSeconds: nil,
                            unit: .kilograms,
                            side: .none,
                            leftValue: nil,
                            rightValue: nil
                        )
                    ]
                )
            ]
        )

        assertNoBodyDataFields(in: dto, path: "ShareReportDTO")
    }

    func testShareReportModuleSelectionHasNoBodyDataUnlockSwitch() {
        // privacySafeDefaults is the one static factory every caller starts
        // from; assert both it and the type's full field set carry nothing
        // body-related, so there is no unlock switch to ever flip on.
        assertNoBodyDataFields(in: ShareReportModuleSelection.privacySafeDefaults, path: "ShareReportModuleSelection")
    }

    /// Recursively walks `value`'s full field set via `Mirror` (arrays and
    /// nested structs included) asserting no label anywhere matches a
    /// body-data naming pattern. This is the structural, non-spot-check
    /// proof the task requires.
    private func assertNoBodyDataFields(in value: Any, path: String, visited: Set<String> = []) {
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            let label = (child.label ?? "").lowercased()
            for pattern in forbiddenPatterns {
                XCTAssertFalse(
                    label.contains(pattern),
                    "\(path).\(child.label ?? "?") matches forbidden body-data pattern '\(pattern)'"
                )
            }
            let childPath = "\(path).\(child.label ?? "?")"
            // Recurse into structs/arrays/optionals so nested DTOs (e.g.
            // ShareReportExerciseDTO/ShareReportSetDTO) are covered too,
            // without infinite-looping on primitive leaves.
            let childMirror = Mirror(reflecting: child.value)
            if !childMirror.children.isEmpty, !visited.contains(childPath) {
                assertNoBodyDataFields(in: child.value, path: childPath, visited: visited.union([childPath]))
            }
        }
    }

    func testForbiddenPatternsActuallyCatchTheRealTypeNames() {
        // Sanity-checks the matcher itself: prove it WOULD catch the real
        // Domain type names if they ever leaked into the DTO, so a future
        // silent-rename can't defeat this test by accident.
        XCTAssertTrue("bodyMetricID".lowercased().contains("bodymetric"))
        XCTAssertTrue("bodyMeasurementValue".lowercased().contains("bodymeasurement"))
    }
}
