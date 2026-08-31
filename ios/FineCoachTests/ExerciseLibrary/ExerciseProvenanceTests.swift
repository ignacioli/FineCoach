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

    func testBundledCatalogPassesDistributableAndFailsDevelopmentPlaceholder() throws {
        let catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(
            Bundle(for: PersistenceController.self)
        )
        XCTAssertEqual(catalog.metadataVersion, "m1a.wger.2026-08-30")
        XCTAssertEqual(catalog.provenance.catalogID, "fc.m1a.wger")
        XCTAssertEqual(catalog.exercises.count, 146)
        XCTAssertEqual(catalog.provenance.records.count, 146)
        XCTAssertFalse(catalog.provenance.isFictionalPlaceholder)
        XCTAssertTrue(catalog.provenance.records.allSatisfy(\.redistributionAllowed))

        let squat = try XCTUnwrap(
            catalog.exercises.first { $0.id == "a2f5b6ef-b780-49c0-8d96-fdaff23e27ce" }
        )
        XCTAssertEqual(squat.canonicalName, "杠铃深蹲")
        XCTAssertEqual(squat.recordMode, .weightReps)
        XCTAssertEqual(squat.primaryMuscleGroup, "大腿")
        XCTAssertEqual(squat.equipmentClass, "杠铃")
        let pullUp = try XCTUnwrap(
            catalog.exercises.first { $0.id == "8e420408-0682-4ab6-89f5-2681e54c7ce0" }
        )
        XCTAssertEqual(pullUp.canonicalName, "引体向上")
        XCTAssertEqual(pullUp.recordMode, .reps)
        let plank = try XCTUnwrap(
            catalog.exercises.first { $0.id == "c9e57bbe-e839-44c6-861d-1c8dd2845e36" }
        )
        XCTAssertEqual(plank.canonicalName, "平板支撑")
        XCTAssertEqual(plank.recordMode, .duration)

        let vBar = try XCTUnwrap(
            catalog.exercises.first { $0.id == "ea63d85c-8579-4dda-b99f-c4c8930f9af6" }
        )
        XCTAssertEqual(vBar.canonicalName, "V把下压")
        let straightBar = try XCTUnwrap(
            catalog.exercises.first { $0.id == "6ebb138e-bb0a-402e-84e5-68fe0896e897" }
        )
        XCTAssertEqual(straightBar.canonicalName, "直杆下压")

        let development = ExerciseProvenanceValidator.validate(
            catalog.provenance,
            gate: .developmentPlaceholder
        )
        XCTAssertFalse(development.isAccepted)
        XCTAssertTrue(development.issues.contains { $0.field == "isFictionalPlaceholder" })

        let distributable = ExerciseProvenanceValidator.validate(
            catalog.provenance,
            gate: .distributable
        )
        XCTAssertTrue(distributable.isAccepted)
        XCTAssertTrue(distributable.issues.isEmpty)

        XCTAssertTrue(
            catalog.exercises.allSatisfy {
                $0.primaryMuscleGroup != nil && $0.equipmentClass != nil
            }
        )
        XCTAssertEqual(
            Set(catalog.exercises.compactMap(\.primaryMuscleGroup)),
            Set(ExerciseCatalogBrowse.muscleGroupOrder)
        )
        XCTAssertEqual(
            Set(catalog.exercises.compactMap(\.equipmentClass)),
            Set(ExerciseCatalogBrowse.equipmentClassOrder)
        )
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
