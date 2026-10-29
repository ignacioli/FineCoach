import XCTest

@testable import FineCoach

final class SessionActivityContentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private typealias Content = SessionActivityAttributes.ContentState

    func testZeroSetsHasNoSecondaryLineAndUsesGenericTitleForNoExercise() {
        let content = Content(exerciseName: "", completedSetCount: 0, restEndsAt: nil)
        XCTAssertEqual(SessionActivityContent.title(content), "训练中")
        XCTAssertNil(SessionActivityContent.secondaryText(content, now: now))
        XCTAssertEqual(SessionActivityContent.compactTrailingText(content, now: now), "0 组")
        XCTAssertNil(
            SessionActivityContent.secondaryText(
                Content(exerciseName: "深蹲", completedSetCount: 0, restEndsAt: now.addingTimeInterval(30)), now: now))
    }

    func testNotRestingShowsCompletedCount() {
        let content = Content(exerciseName: "深蹲", completedSetCount: 3, restEndsAt: nil)
        XCTAssertEqual(SessionActivityContent.title(content), "深蹲")
        XCTAssertEqual(SessionActivityContent.secondaryText(content, now: now), "已完成 3 组")
        XCTAssertEqual(SessionActivityContent.compactTrailingText(content, now: now), "3 组")
        XCTAssertFalse(SessionActivityContent.isOverdue(content, now: now))
    }

    func testRestingUsesJustConfirmedCountAndInjectedNow() {
        let content = Content(exerciseName: "深蹲", completedSetCount: 3, restEndsAt: now.addingTimeInterval(105))
        XCTAssertEqual(SessionActivityContent.secondaryText(content, now: now), "第 3 组 · 休息")
        XCTAssertEqual(SessionActivityContent.compactTrailingText(content, now: now), "1:45")
        XCTAssertFalse(SessionActivityContent.isOverdue(content, now: now))
    }

    func testOverdueAndExactDeadlineShowRestEndedAndCountUp() {
        let content = Content(exerciseName: "深蹲", completedSetCount: 3, restEndsAt: now.addingTimeInterval(-32))
        XCTAssertEqual(SessionActivityContent.secondaryText(content, now: now), "第 3 组 · 休息结束")
        XCTAssertEqual(SessionActivityContent.compactTrailingText(content, now: now), "+0:32")
        XCTAssertEqual(SessionActivityContent.overdueLabel, "已超时")
        XCTAssertTrue(SessionActivityContent.isOverdue(content, now: now))
        XCTAssertEqual(SessionActivityContent.compactTrailingText(content, now: now.addingTimeInterval(-32)), "+0:00")
    }

    func testAttributesAndContentJSONKeysExactlyMatchAllowlistAndExcludeSensitiveTrainingValues() throws {
        let studentID = StableUUID(UUID())
        let student = try StudentDraft(displayName: "虚构学员甲", sex: .female).makeStudent(id: studentID, now: now)
        var session = Session.start(
            id: StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!),
            studentID: student.id, trainingFocus: [], now: now)
        let exerciseID = StableUUID(UUID())
        session = try session.addingSessionOnlyExercise(
            id: exerciseID, displayName: "深蹲", recordMode: .weightReps, now: now)
        let setID = StableUUID(UUID())
        session = try session.addingSet(
            exerciseID: exerciseID, setID: setID,
            input: TrainingSetInput(
                recordMode: .weightReps, weightValue: "876.543", repetitionCount: "97", unit: .kilograms),
            now: now)
        session = try session.confirmingSet(setID: setID, now: now)
        let body = try BodyMeasurement(
            id: StableUUID(UUID()), studentID: studentID, metricID: StableUUID(UUID()),
            localCalendarDay: LocalDate(date: now, calendar: .current), value: DecimalValue("654.321"),
            enteredUnit: "虚构身体指标", createdAtUTC: now, updatedAtUTC: now)
        let exercise = try XCTUnwrap(session.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        let forbidden = [
            student.displayName.value, studentID.rawValue.uuidString,
            set.weightValue!.canonicalString, set.repetitionCount!.canonicalString, body.value.canonicalString,
            body.enteredUnit,
        ]
        let attributes = SessionActivityAttributes(sessionID: session.id.rawValue.uuidString.lowercased())
        let encodedAttributes = try JSONEncoder().encode(attributes)
        XCTAssertEqual(try keys(encodedAttributes), ["sessionID"])
        for end: Date? in [nil, now.addingTimeInterval(105), now.addingTimeInterval(-32)] {
            let content = Content(
                exerciseName: exercise.displayNameSnapshot.value,
                completedSetCount: exercise.sets.filter { $0.state == .completed }.count, restEndsAt: end)
            let data = try JSONEncoder().encode(content)
            XCTAssertEqual(try keys(data), ["exerciseName", "completedSetCount", "restEndsAt"])
            XCTAssertEqual(try JSONDecoder().decode(Content.self, from: data), content)
            let output = [
                String(decoding: data, as: UTF8.self), String(decoding: encodedAttributes, as: UTF8.self),
                SessionActivityContent.title(content), SessionActivityContent.secondaryText(content, now: now) ?? "",
                SessionActivityContent.compactTrailingText(content, now: now), SessionActivityContent.overdueLabel,
            ]
            for value in forbidden {
                for text in output { XCTAssertFalse(text.contains(value), value) }
            }
        }
    }

    func testClickURLIsLowercaseAndRoutesBackToSameSession() throws {
        let id = UUID(uuidString: "ABCDEFAB-1234-4567-8ABC-ABCDEFABCDEF")!
        let url = try XCTUnwrap(SessionActivityContent.url(sessionID: id.uuidString))
        XCTAssertEqual(url.absoluteString, "finecoach://session/\(id.uuidString.lowercased())")
        XCTAssertEqual(SystemEntryRouteRequest(url: url), .session(StableUUID(id)))
        XCTAssertNil(SessionActivityContent.url(sessionID: "invalid"))
    }

    private func keys(_ data: Data) throws -> Set<String> {
        Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
    }
}
