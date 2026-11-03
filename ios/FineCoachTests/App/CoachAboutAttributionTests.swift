import Foundation
import XCTest

@testable import FineCoach

final class CoachAboutAttributionTests: XCTestCase {
    func testLicenseAliasesNormalizeBeforeDeduplicationAndUnknownNamesSurvive() {
        let cases = [
            "CC-BY-SA 4": "CC BY-SA 4.0", "CC-BY-SA-4.0": "CC BY-SA 4.0",
            "CC-BY-SA 3": "CC BY-SA 3.0", "CC-BY-SA-3.0": "CC BY-SA 3.0",
            "CC0": "CC0 1.0", "CC0-1.0": "CC0 1.0", "Unlicense": "Unlicense",
            "MIT": "MIT", "Unknown license": "Unknown license",
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(ExerciseLicensePresentation.displayName(raw), expected)
        }
        XCTAssertEqual(
            ArchiveViewerPresentation.licenseDisplayName("CC-BY-SA 4 / CC-BY-SA-4.0"),
            "CC\u{00A0}BY\u{2011}SA\u{00A0}4.0")
    }

    func testBundledSourceRowsCountExercisesAndNormalizeLicenses() throws {
        let catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(.main)
        let rows = try CoachAboutSource.rows(catalog: catalog)
        XCTAssertEqual(rows.map(\.id), ["free-exercise-db", "wger.de", "finecoach-built"])
        XCTAssertEqual(rows.map(\.count), [310, 226, 6])
        XCTAssertEqual(
            rows.map(\.text),
            [
                "free-exercise-db · 310 条 · Unlicense",
                "wger.de · 226 条 · CC BY-SA 3.0 / CC BY-SA 4.0 / CC0 1.0",
                "FineCoach 自建 · 6 条 · MIT",
            ])
        XCTAssertEqual(rows.reduce(0) { $0 + $1.count }, catalog.exercises.count)
    }

    func testMissingProvenanceIsRejectedRatherThanOmitted() throws {
        var catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(.main)
        catalog.provenance.records = []
        XCTAssertThrowsError(try CoachAboutSource.rows(catalog: catalog))
    }

    func testExternalLinksAreFixedApprovedURLs() {
        XCTAssertEqual(
            CoachAboutView.provenanceURL.absoluteString,
            "https://github.com/ignacioli/FineCoach/blob/main/ios/FineCoachApp/Resources/ExerciseCatalog/provenance.json"
        )
        XCTAssertEqual(CoachAboutView.ccBySA4URL.absoluteString, "https://creativecommons.org/licenses/by-sa/4.0/")
        XCTAssertEqual(CoachAboutView.ccBySA3URL.absoluteString, "https://creativecommons.org/licenses/by-sa/3.0/")
    }
}
