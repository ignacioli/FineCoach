import FineCoach
import XCTest

final class ExerciseProvenanceTests: XCTestCase {
    func testMissingRequiredFieldIsRejectedWithNamedIssue() throws {
        var missingLicense = validPlaceholderManifest()
        missingLicense.records[0].licenseText = "   "
        let licenseResult = ExerciseProvenanceValidator.validate(
            missingLicense,
            gate: .developmentPlaceholder
        )
        XCTAssertFalse(licenseResult.isAccepted)
        XCTAssertTrue(licenseResult.issues.contains { $0.field == "licenseText" })

        var missingSource = validPlaceholderManifest()
        missingSource.records[0].sourceIdentifier = ""
        let sourceResult = ExerciseProvenanceValidator.validate(
            missingSource,
            gate: .developmentPlaceholder
        )
        XCTAssertFalse(sourceResult.isAccepted)
        XCTAssertTrue(sourceResult.issues.contains { $0.field == "sourceIdentifier" })

        let encoded = try JSONEncoder().encode(validPlaceholderManifest())
        let droppedLicense = try mutatingJSON(encoded) { object in
            var records = try XCTUnwrap(object["records"] as? [Any])
            XCTAssertFalse(records.isEmpty)
            var first = try XCTUnwrap(records[0] as? [String: Any])
            first.removeValue(forKey: "licenseText")
            records[0] = first
            object["records"] = records
        }
        let jsonResult = try ExerciseProvenanceValidator.validateJSONData(
            droppedLicense,
            gate: .developmentPlaceholder
        )
        XCTAssertFalse(jsonResult.isAccepted)
        XCTAssertTrue(jsonResult.issues.contains { $0.field == "licenseText" })
    }

    func testRedistributionDeniedFailsDistributableAndMayPassDevelopmentPlaceholder() throws {
        let notRedistributable = validPlaceholderManifest(
            isFictionalPlaceholder: false,
            redistributionAllowed: false
        )
        let distributable = ExerciseProvenanceValidator.validate(
            notRedistributable,
            gate: .distributable
        )
        XCTAssertFalse(distributable.isAccepted)
        XCTAssertTrue(distributable.issues.contains { $0.field == "redistributionAllowed" })

        let fictional = validPlaceholderManifest(
            isFictionalPlaceholder: true,
            redistributionAllowed: false
        )
        let development = ExerciseProvenanceValidator.validate(
            fictional,
            gate: .developmentPlaceholder
        )
        XCTAssertTrue(development.isAccepted)
        XCTAssertTrue(development.issues.isEmpty)
    }

    func testFictionalPlaceholderFailsDistributableGate() throws {
        let fictional = validPlaceholderManifest(
            isFictionalPlaceholder: true,
            redistributionAllowed: true
        )
        let result = ExerciseProvenanceValidator.validate(fictional, gate: .distributable)
        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.issues.contains { $0.field == "isFictionalPlaceholder" })
        XCTAssertFalse(result.issues.contains { $0.field == "redistributionAllowed" })
    }

    func testBundledPlaceholderCatalogPassesDevelopmentAndFailsDistributable() throws {
        let catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(
            Bundle(for: PersistenceController.self)
        )
        XCTAssertEqual(catalog.metadataVersion, "placeholder.1")
        XCTAssertEqual(
            catalog.exercises.map(\.id),
            ["fc.placeholder.squat", "fc.placeholder.pullup", "fc.placeholder.plank"]
        )
        XCTAssertEqual(catalog.exercises.map(\.canonicalName), ["占位深蹲", "占位引体", "占位支撑"])
        XCTAssertEqual(catalog.exercises.map(\.recordMode), [.weightReps, .reps, .duration])
        XCTAssertTrue(catalog.provenance.isFictionalPlaceholder)
        XCTAssertTrue(catalog.provenance.records.allSatisfy { !$0.redistributionAllowed })

        let development = ExerciseProvenanceValidator.validate(
            catalog.provenance,
            gate: .developmentPlaceholder
        )
        XCTAssertTrue(development.isAccepted)

        let distributable = ExerciseProvenanceValidator.validate(
            catalog.provenance,
            gate: .distributable
        )
        XCTAssertFalse(distributable.isAccepted)
        XCTAssertTrue(distributable.issues.contains { $0.field == "isFictionalPlaceholder" })
    }

    func testInvalidJSONDataThrowsIncompatibleInput() {
        XCTAssertThrowsError(
            try ExerciseProvenanceValidator.validateJSONData(
                Data("not-json".utf8),
                gate: .developmentPlaceholder
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .incompatibleInput)
        }
        XCTAssertThrowsError(
            try ExerciseProvenanceValidator.validateJSONData(
                Data("{".utf8),
                gate: .developmentPlaceholder
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .incompatibleInput)
        }
    }

    private func validPlaceholderManifest(
        isFictionalPlaceholder: Bool = true,
        redistributionAllowed: Bool = false
    ) -> ExerciseProvenanceManifest {
        ExerciseProvenanceManifest(
            catalogID: "fc.placeholder",
            contentVersion: "placeholder.1",
            isFictionalPlaceholder: isFictionalPlaceholder,
            records: [
                ExerciseProvenanceRecord(
                    recordID: "placeholder.squat",
                    sourceIdentifier: "fc.fictional.source.placeholder",
                    authorOrOwner: "FineCoach fictional placeholder — not for redistribution",
                    licenseIdentifier: "fc.fictional.license.placeholder",
                    licenseText: "FineCoach fictional placeholder — not for redistribution",
                    redistributionAllowed: redistributionAllowed,
                    attributionRequirement: "FineCoach fictional placeholder — not for redistribution",
                    contentVersion: "placeholder.1",
                    reviewDate: "1970-01-01",
                    reviewerEvidence: "FineCoach fictional placeholder — not for redistribution"
                )
            ]
        )
    }

    private func mutatingJSON(_ data: Data, mutate: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try mutate(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }
}
