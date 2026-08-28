import FineCoach
import XCTest

final class StudentDomainTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let firstID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private let secondID = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)

    func testRequiredFieldsRejectEmptyDisplayNameAndMissingSex() {
        XCTAssertThrowsError(
            try StudentDraft(displayName: "   ", sex: .female).makeStudent(id: firstID, now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .emptyText)
        }

        XCTAssertThrowsError(
            try StudentDraft(displayName: "林青").makeStudent(id: firstID, now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
    }

    func testOptionalFieldsPersistWhenFilledAndClearWhenBlank() throws {
        let filled = try StudentDraft(
            displayName: " 林青 ",
            sex: .female,
            trainingGoal: " 提升基础力量 ",
            injuryNotes: " 合成测试备注：保持动作节奏。 ",
            privateCoachNote: " 晚班 ",
            phone: " 13800001111 ",
            wechatID: " linqing_test "
        ).makeStudent(id: firstID, now: now)

        XCTAssertEqual(filled.displayName.value, "林青")
        XCTAssertEqual(filled.sex, .female)
        XCTAssertEqual(filled.trainingGoal?.value, "提升基础力量")
        XCTAssertEqual(filled.injuryNotes?.value, "合成测试备注：保持动作节奏。")
        XCTAssertEqual(filled.privateCoachNote?.value, "晚班")
        XCTAssertEqual(filled.phone?.value, "13800001111")
        XCTAssertEqual(filled.wechatID?.value, "linqing_test")
        XCTAssertEqual(filled.lifecycle, .active)

        let cleared = try filled.updating(
            from: StudentDraft(displayName: "林青", sex: .undisclosed),
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(cleared.id, filled.id)
        XCTAssertEqual(cleared.sex, .undisclosed)
        XCTAssertNil(cleared.trainingGoal)
        XCTAssertNil(cleared.injuryNotes)
        XCTAssertNil(cleared.privateCoachNote)
        XCTAssertNil(cleared.phone)
        XCTAssertNil(cleared.wechatID)
        XCTAssertEqual(cleared.createdAtUTC, filled.createdAtUTC)
        XCTAssertEqual(cleared.updatedAtUTC, now.addingTimeInterval(60))
    }

    func testSameDisplayNameCanCoexistWithStableDistinctIDs() throws {
        let first = try StudentDraft(displayName: "林林", sex: .other, privateCoachNote: "工作室午班")
            .makeStudent(id: firstID, now: now)
        let second = try StudentDraft(displayName: "林林", sex: .female, privateCoachNote: "晚间私教")
            .makeStudent(id: secondID, now: now)

        XCTAssertEqual(first.displayName, second.displayName)
        XCTAssertNotEqual(first.id, second.id)

        let renamed = try first.updating(
            from: StudentDraft(displayName: "小林", sex: .other, privateCoachNote: "工作室午班"),
            now: now.addingTimeInterval(10)
        )
        XCTAssertEqual(renamed.id, first.id)
        XCTAssertEqual(renamed.displayName.value, "小林")
    }

    func testTextOverUTF8CeilingIsRejectedBeforeSave() {
        let oversized = String(repeating: "测", count: (64 * 1024) + 1)
        XCTAssertThrowsError(
            try StudentDraft(displayName: oversized, sex: .male).makeStudent(id: firstID, now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .textTooLong(maximumBytes: ValidatedText.maximumUTF8Bytes))
        }
        XCTAssertThrowsError(
            try StudentDraft(displayName: "林青", sex: .male, injuryNotes: oversized)
                .makeStudent(id: firstID, now: now)
        ) { error in
            XCTAssertEqual(error as? DomainError, .textTooLong(maximumBytes: ValidatedText.maximumUTF8Bytes))
        }
    }

    func testAllSexCasesAreAccepted() throws {
        for sex in StudentSex.allCases {
            let student = try StudentDraft(displayName: "周宁", sex: sex).makeStudent(id: firstID, now: now)
            XCTAssertEqual(student.sex, sex)
        }
        XCTAssertEqual(StudentSex.allCases.map(\.rawValue), ["male", "female", "other", "undisclosed"])
    }

    func testArchiveRestoreAndIllegalTransitions() throws {
        let active = try StudentDraft(displayName: "周宁", sex: .male).makeStudent(id: firstID, now: now)
        XCTAssertTrue(active.canStartSession())

        let archived = try active.archived(now: now.addingTimeInterval(5))
        XCTAssertEqual(archived.lifecycle, .archived)
        XCTAssertFalse(archived.canStartSession())
        XCTAssertEqual(archived.id, active.id)

        XCTAssertThrowsError(try archived.archived(now: now)) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }

        let restored = try archived.restored(now: now.addingTimeInterval(10))
        XCTAssertEqual(restored.lifecycle, .active)
        XCTAssertTrue(restored.canStartSession())

        XCTAssertThrowsError(try active.restored(now: now)) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
    }

    func testDeletionRequiresMatchingDisplayNameAndNoInProgressSession() throws {
        let student = try StudentDraft(displayName: "林青", sex: .female).makeStudent(id: firstID, now: now)

        XCTAssertThrowsError(
            try StudentDeletionPolicy.ensureCanDelete(hasInProgressSession: true)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertNoThrow(try StudentDeletionPolicy.ensureCanDelete(hasInProgressSession: false))

        XCTAssertThrowsError(
            try StudentDeletionPolicy.confirmDisplayName(expected: student.displayName, typed: "林 青")
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertThrowsError(
            try StudentDeletionPolicy.confirmDisplayName(expected: student.displayName, typed: "")
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidState)
        }
        XCTAssertNoThrow(
            try StudentDeletionPolicy.confirmDisplayName(expected: student.displayName, typed: " 林青 ")
        )
    }

    func testNFCNormalizationDoesNotChangeStableIdentity() throws {
        let composed = try StudentDraft(displayName: "林青", sex: .female).makeStudent(id: firstID, now: now)
        let decomposed = try composed.updating(
            from: StudentDraft(displayName: "林青".decomposedStringWithCanonicalMapping, sex: .female),
            now: now.addingTimeInterval(1)
        )
        XCTAssertEqual(composed.id, decomposed.id)
        XCTAssertEqual(composed.displayName, decomposed.displayName)
        XCTAssertEqual(decomposed.displayName.value, decomposed.displayName.value.precomposedStringWithCanonicalMapping)
    }
}
