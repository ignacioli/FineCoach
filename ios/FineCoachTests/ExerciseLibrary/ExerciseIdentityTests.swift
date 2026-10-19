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

    func testBrowseSectionsKeepCustomSeparateAndHonorFilters() throws {
        let squat = try ExerciseCatalogItem.makeBuiltIn(
            id: builtInID,
            canonicalName: "杠铃深蹲",
            recordMode: .weightReps,
            metadataVersion: "placeholder.1",
            provenanceRef: "placeholder.squat",
            now: now
        )
        let bench = try ExerciseCatalogItem.makeBuiltIn(
            id: StableExerciseID(rawValue: "fc.placeholder.bench")!,
            canonicalName: "杠铃平板卧推",
            recordMode: .weightReps,
            metadataVersion: "placeholder.1",
            provenanceRef: "placeholder.bench",
            now: now
        )
        let custom = try ExerciseCatalogItem.makeCustom(
            id: customID,
            canonicalName: "我的分组动作",
            recordMode: .weightReps,
            now: now
        )
        let squatEntry = ExerciseLibraryEntry(
            item: squat,
            preference: nil,
            primaryMuscleGroup: "大腿",
            equipmentClass: "杠铃"
        )
        let benchEntry = ExerciseLibraryEntry(
            item: bench,
            preference: nil,
            primaryMuscleGroup: "胸",
            equipmentClass: "杠铃"
        )
        let customEntry = ExerciseLibraryEntry(item: custom, preference: nil)
        let all = [benchEntry, squatEntry, customEntry]

        let unfiltered = ExerciseCatalogBrowse.sections(
            from: all,
            muscleFilter: nil,
            equipmentFilter: nil
        )
        XCTAssertEqual(unfiltered.map(\.id), ["custom", "胸", "大腿"])
        XCTAssertEqual(unfiltered[0].entries.map(\.id), [customID])

        let thigh = ExerciseCatalogBrowse.sections(
            from: all,
            muscleFilter: "大腿",
            equipmentFilter: nil
        )
        XCTAssertEqual(thigh.map(\.id), ["大腿"])
        XCTAssertEqual(thigh.first?.entries.map(\.displayedName), ["杠铃深蹲"])

        let barbellChest = ExerciseCatalogBrowse.sections(
            from: all,
            muscleFilter: "胸",
            equipmentFilter: "杠铃"
        )
        XCTAssertEqual(barbellChest.map(\.id), ["胸"])
        XCTAssertEqual(barbellChest.first?.entries.map(\.displayedName), ["杠铃平板卧推"])
    }

    func testRecentExercisesDeduplicateAndSortByCompletedTime() throws {
        let first = try makeCatalogEntry(id: "fc.recent.first", name: "卧推")
        let second = try makeCatalogEntry(id: "fc.recent.second", name: "深蹲")
        let history = [
            makeCompletedSession(
                studentID: StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!),
                completedAt: now,
                exercises: [first.id, second.id]
            ),
            makeCompletedSession(
                studentID: StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!),
                completedAt: now.addingTimeInterval(60),
                exercises: [first.id]
            ),
        ]

        let result = RecentExerciseSelection.entries(
            from: history,
            availableEntries: [first, second]
        )

        XCTAssertEqual(result.map(\.id), [first.id, second.id])
    }

    func testRecentExercisesSkipUnavailableAndSessionOnlyAndFillLimit() throws {
        let hiddenID = StableExerciseID(rawValue: "fc.recent.hidden")!
        let retiredID = StableExerciseID(rawValue: "fc.recent.retired")!
        let hiddenItem = try ExerciseCatalogItem.makeBuiltIn(
            id: hiddenID,
            canonicalName: "隐藏动作",
            recordMode: .weightReps,
            metadataVersion: "test",
            provenanceRef: "test.hidden",
            now: now
        )
        let retiredItem = try ExerciseCatalogItem.makeBuiltIn(
            id: retiredID,
            canonicalName: "停用动作",
            recordMode: .weightReps,
            metadataVersion: "test",
            provenanceRef: "test.retired",
            now: now,
            isRetired: true
        )
        let hidden = ExerciseLibraryEntry(
            item: hiddenItem,
            preference: ExercisePreference(exerciseID: hiddenID, isHidden: true)
        )
        let retired = ExerciseLibraryEntry(item: retiredItem, preference: nil)
        let visible = try (0..<6).map { index in
            try makeCatalogEntry(id: "fc.recent.visible-\(index)", name: "可选动作\(index)")
        }
        let sessionOnlyID = StableExerciseID(rawValue: "fc.recent.session-only")!
        let session = makeCompletedSession(
            studentID: StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!),
            completedAt: now,
            exercises: [hiddenID, retiredID, sessionOnlyID] + visible.map(\.id),
            sessionOnlyIDs: [sessionOnlyID]
        )

        let result = RecentExerciseSelection.entries(
            from: [session],
            availableEntries: [hidden, retired] + visible
        )

        XCTAssertEqual(result.map(\.id), visible.prefix(5).map(\.id))
    }

    func testRecentExercisesCanScopeToStudentOrAllStudentsAndEmptyHistoryIsEmpty() throws {
        let first = try makeCatalogEntry(id: "fc.recent.student-one", name: "学员一动作")
        let second = try makeCatalogEntry(id: "fc.recent.student-two", name: "学员二动作")
        let one = StableUUID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
        let two = StableUUID(UUID(uuidString: "44444444-4444-4444-8444-444444444444")!)
        let history = [
            makeCompletedSession(studentID: one, completedAt: now, exercises: [first.id]),
            makeCompletedSession(studentID: two, completedAt: now.addingTimeInterval(60), exercises: [second.id]),
        ]

        XCTAssertEqual(
            RecentExerciseSelection.entries(from: history, studentID: one, availableEntries: [first, second]).map(\.id),
            [first.id]
        )
        XCTAssertEqual(
            RecentExerciseSelection.entries(from: history, availableEntries: [first, second]).map(\.id),
            [second.id, first.id]
        )
        XCTAssertTrue(RecentExerciseSelection.entries(from: [], availableEntries: [first]).isEmpty)
    }

    private func makeCatalogEntry(id: String, name: String) throws -> ExerciseLibraryEntry {
        let stableID = try StableExerciseID(id)
        let item = try ExerciseCatalogItem.makeBuiltIn(
            id: stableID,
            canonicalName: name,
            recordMode: .weightReps,
            metadataVersion: "test",
            provenanceRef: "test.\(id)",
            now: now
        )
        return ExerciseLibraryEntry(item: item, preference: nil)
    }

    private func makeCompletedSession(
        studentID: StableUUID,
        completedAt: Date,
        exercises: [StableExerciseID],
        sessionOnlyIDs: Set<StableExerciseID> = []
    ) -> CompletedSession {
        let sessionExercises = exercises.enumerated().map { index, sourceID in
            SessionExercise(
                id: StableUUID(UUID()),
                sessionID: StableUUID(UUID()),
                orderIndex: UInt32(index),
                sourceKind: sessionOnlyIDs.contains(sourceID) ? .sessionOnly : .builtIn,
                sourceID: sessionOnlyIDs.contains(sourceID) ? nil : sourceID,
                displayNameSnapshot: try! NormalizedName("动作\(index)"),
                recordModeSnapshot: .weightReps,
                actionPrivateNote: nil,
                sets: []
            )
        }
        return CompletedSession(
            id: StableUUID(UUID()),
            studentID: studentID,
            studentDisplayName: try! NormalizedName("测试学员"),
            startedAtUTC: completedAt.addingTimeInterval(-60),
            completedAtUTC: completedAt,
            trainingFocus: [],
            notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
            exercises: sessionExercises,
            statistics: SessionStatistics(
                completedSetCount: 1,
                displayedDurationSeconds: .zero,
                ordinaryTrainingVolume: nil
            ),
            revision: 1,
            latestReport: nil
        )
    }
}
