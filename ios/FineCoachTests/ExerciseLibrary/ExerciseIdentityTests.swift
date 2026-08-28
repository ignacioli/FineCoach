import FineCoach
import XCTest

final class ExerciseIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let builtInID = StableExerciseID(rawValue: "fc.placeholder.squat")!
    private let customID = StableExerciseID(rawValue: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let secondCustomID = StableExerciseID(rawValue: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let sessionOnlyID = StableExerciseID(rawValue: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!

    func testNFCTrimRejectsEmptyAndOversizedNames() throws {
        let paddedDecomposed = "  深蹲\u{0301}  "
        let precomposed = "深蹲\u{0301}".precomposedStringWithCanonicalMapping
        XCTAssertEqual(try ExerciseNameNormalizer.normalized(paddedDecomposed), precomposed)
        XCTAssertEqual(try NormalizedName(paddedDecomposed).value, precomposed)
        XCTAssertEqual(try NormalizedName(paddedDecomposed), try NormalizedName(precomposed))

        XCTAssertThrowsError(try ExerciseNameNormalizer.normalized("   ")) { error in
            XCTAssertEqual(error as? DomainError, .emptyText)
        }
        XCTAssertThrowsError(try NormalizedName("")) { error in
            XCTAssertEqual(error as? DomainError, .emptyText)
        }

        let oversized = String(repeating: "测", count: (64 * 1024) + 1)
        XCTAssertThrowsError(try ExerciseNameNormalizer.normalized(oversized)) { error in
            XCTAssertEqual(error as? DomainError, .textTooLong(maximumBytes: ValidatedText.maximumUTF8Bytes))
        }
        XCTAssertThrowsError(try NormalizedName(oversized)) { error in
            XCTAssertEqual(error as? DomainError, .textTooLong(maximumBytes: ValidatedText.maximumUTF8Bytes))
        }
    }

    func testUnifiedUniquenessRejectsCrossScopeCollisionsWithoutRenaming() throws {
        var table = ExerciseNameClaimTable()
        let name = "占位深蹲"
        let normalized = try ExerciseNameNormalizer.normalized(name)
        let builtInClaim = try ExerciseNameClaim(
            normalizedName: name,
            ownerKind: .builtIn,
            ownerID: builtInID,
            scope: .activeCatalog
        )
        try table.acquire(builtInClaim)
        XCTAssertEqual(table.claim(matchingNormalizedName: normalized)?.ownerID, builtInID)

        XCTAssertThrowsError(
            try table.acquire(
                ExerciseNameClaim(
                    normalizedName: "  \(name)  ",
                    ownerKind: .custom,
                    ownerID: customID,
                    scope: .activeCatalog
                )
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .conflict)
        }
        XCTAssertEqual(table.claims.count, 1)
        XCTAssertEqual(table.claims[0].normalizedName, normalized)
        XCTAssertEqual(table.claims[0].ownerID, builtInID)

        XCTAssertThrowsError(
            try table.acquire(
                ExerciseNameClaim(
                    normalizedName: name,
                    ownerKind: .sessionOnly,
                    ownerID: sessionOnlyID,
                    scope: .currentSession
                )
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .conflict)
        }
        XCTAssertEqual(table.claims.map(\.normalizedName), [normalized])

        var customThenSession = ExerciseNameClaimTable()
        try customThenSession.acquire(
            ExerciseNameClaim(
                normalizedName: "自定义推举",
                ownerKind: .custom,
                ownerID: customID,
                scope: .activeCatalog
            )
        )
        XCTAssertThrowsError(
            try customThenSession.acquire(
                ExerciseNameClaim(
                    normalizedName: "自定义推举",
                    ownerKind: .sessionOnly,
                    ownerID: sessionOnlyID,
                    scope: .currentSession
                )
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .conflict)
        }
        XCTAssertEqual(customThenSession.claims.count, 1)
        XCTAssertEqual(customThenSession.claims[0].ownerKind, .custom)
    }

    func testArchivedCustomReleaseAllowsNameReuse() throws {
        var table = ExerciseNameClaimTable()
        let name = "自定义推举"
        try table.acquire(
            ExerciseNameClaim(
                normalizedName: name,
                ownerKind: .custom,
                ownerID: customID,
                scope: .activeCatalog
            )
        )
        table.release(ownerID: customID)
        XCTAssertNil(table.claim(matchingNormalizedName: try ExerciseNameNormalizer.normalized(name)))

        try table.acquire(
            ExerciseNameClaim(
                normalizedName: name,
                ownerKind: .custom,
                ownerID: secondCustomID,
                scope: .activeCatalog
            )
        )
        XCTAssertEqual(table.claims.count, 1)
        XCTAssertEqual(table.claims[0].ownerID, secondCustomID)
    }

    func testSessionEndReleaseFreesSessionOnlyNamesAndKeepsCatalogClaims() throws {
        var table = ExerciseNameClaimTable()
        try table.acquire(
            ExerciseNameClaim(
                normalizedName: "占位深蹲",
                ownerKind: .builtIn,
                ownerID: builtInID,
                scope: .activeCatalog
            )
        )
        try table.acquire(
            ExerciseNameClaim(
                normalizedName: "课次动作",
                ownerKind: .sessionOnly,
                ownerID: sessionOnlyID,
                scope: .currentSession
            )
        )
        try table.acquire(
            ExerciseNameClaim(
                normalizedName: "自定义推举",
                ownerKind: .custom,
                ownerID: customID,
                scope: .activeCatalog
            )
        )

        table.release(scope: .currentSession)
        XCTAssertNotNil(
            table.claim(matchingNormalizedName: try ExerciseNameNormalizer.normalized("占位深蹲"))
        )
        XCTAssertNotNil(
            table.claim(matchingNormalizedName: try ExerciseNameNormalizer.normalized("自定义推举"))
        )
        XCTAssertNil(table.claim(matchingNormalizedName: try ExerciseNameNormalizer.normalized("课次动作")))

        try table.acquire(
            ExerciseNameClaim(
                normalizedName: "课次动作",
                ownerKind: .custom,
                ownerID: secondCustomID,
                scope: .activeCatalog
            )
        )
        try table.acquire(
            ExerciseNameClaim(
                normalizedName: "新课次动作",
                ownerKind: .sessionOnly,
                ownerID: sessionOnlyID,
                scope: .currentSession
            )
        )
        XCTAssertEqual(table.claims.count, 4)
    }

    func testCustomRenameKeepsStableIDAndBuiltInRejectsUpdatingCustom() throws {
        let custom = try ExerciseCatalogItem.makeCustom(
            id: customID,
            canonicalName: "自定义推举",
            recordMode: .weightReps,
            now: now
        )
        let renamed = try custom.updatingCustom(
            canonicalName: "俯身划船",
            recordMode: .reps,
            now: now.addingTimeInterval(10)
        )
        XCTAssertEqual(renamed.id, custom.id)
        XCTAssertEqual(renamed.id, customID)
        XCTAssertEqual(renamed.canonicalName.value, "俯身划船")
        XCTAssertEqual(renamed.createdAtUTC, now)
        XCTAssertEqual(renamed.updatedAtUTC, now.addingTimeInterval(10))

        let builtIn = try ExerciseCatalogItem.makeBuiltIn(
            id: builtInID,
            canonicalName: "占位深蹲",
            recordMode: .weightReps,
            metadataVersion: "placeholder.1",
            provenanceRef: "placeholder.squat",
            now: now
        )
        XCTAssertEqual(builtIn.id.rawValue, "fc.placeholder.squat")
        XCTAssertFalse(builtIn.id.rawValue.contains(builtIn.canonicalName.value))
        XCTAssertFalse(builtIn.id.rawValue.contains("1700000000"))
        XCTAssertFalse(builtIn.id.rawValue.contains(String(Int(now.timeIntervalSince1970))))
        XCTAssertThrowsError(
            try builtIn.updatingCustom(canonicalName: "其他动作", recordMode: .weightReps, now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
    }

    func testSameOwnerReacquireOfIdenticalClaimIsIdempotent() throws {
        var table = ExerciseNameClaimTable()
        let claim = try ExerciseNameClaim(
            normalizedName: "占位深蹲",
            ownerKind: .builtIn,
            ownerID: builtInID,
            scope: .activeCatalog
        )
        try table.acquire(claim)
        try table.acquire(claim)
        XCTAssertEqual(table.claims.count, 1)
        XCTAssertEqual(table.claims[0].ownerID, builtInID)
        XCTAssertEqual(table.claims[0].scope, .activeCatalog)
    }
}
