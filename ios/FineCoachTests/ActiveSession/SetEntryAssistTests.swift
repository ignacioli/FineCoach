import XCTest

@testable import FineCoach

/// Experience P0-D3/D4: weight steps ±2.5 kg and reps ±1 without leaving the
/// valid range, and the rest countdown starts at 120 s, adjusts by 15 s and
/// never runs below zero.
final class SetEntryAssistTests: XCTestCase {
    // MARK: - SetValueStepping

    func testWeightStepsByTwoPointFive() {
        XCTAssertEqual(SetValueStepping.stepped("120", field: .weight, up: true), "122.5")
        XCTAssertEqual(SetValueStepping.stepped("122.5", field: .weight, up: false), "120")
        XCTAssertEqual(SetValueStepping.stepped("0.5", field: .weight, up: true), "3")
    }

    func testWeightClampsAtZero() {
        XCTAssertEqual(SetValueStepping.stepped("1", field: .weight, up: false), "0")
        XCTAssertEqual(SetValueStepping.stepped("0", field: .weight, up: false), "0")
        XCTAssertFalse(SetValueStepping.canStepDown("0", field: .weight))
        XCTAssertTrue(SetValueStepping.canStepDown("2.5", field: .weight))
    }

    func testRepsStepByOneAndStayAtLeastOne() {
        XCTAssertEqual(SetValueStepping.stepped("8", field: .reps, up: true), "9")
        XCTAssertEqual(SetValueStepping.stepped("8", field: .reps, up: false), "7")
        XCTAssertEqual(SetValueStepping.stepped("1", field: .reps, up: false), "1")
        XCTAssertFalse(SetValueStepping.canStepDown("1", field: .reps))
    }

    func testEmptyOnlyStepsUpAndInvalidTextIsLeftAlone() {
        XCTAssertEqual(SetValueStepping.stepped("", field: .weight, up: true), "2.5")
        XCTAssertEqual(SetValueStepping.stepped("", field: .reps, up: true), "1")
        XCTAssertEqual(SetValueStepping.stepped("", field: .weight, up: false), "")
        XCTAssertEqual(SetValueStepping.stepped("abc", field: .weight, up: true), "abc")
        XCTAssertFalse(SetValueStepping.canStepDown("", field: .weight))
    }

    // MARK: - RestTimerState

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testStartsAtTwoMinutesAndCountsDown() {
        let timer = RestTimerState(startedAt: start)
        XCTAssertEqual(timer.remainingSeconds(at: start), 120)
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(15.2)), 105)
        XCTAssertFalse(timer.isFinished(at: start.addingTimeInterval(119.5)))
        XCTAssertTrue(timer.isFinished(at: start.addingTimeInterval(120)))
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(500)), 0)
    }

    func testAdjustsByFifteenSecondsButNotIntoThePast() {
        var timer = RestTimerState(startedAt: start)
        timer.adjust(by: RestTimerState.adjustmentStep, now: start)
        XCTAssertEqual(timer.remainingSeconds(at: start), 135)
        timer.adjust(by: -RestTimerState.adjustmentStep * 2, now: start)
        XCTAssertEqual(timer.remainingSeconds(at: start), 105)

        let late = start.addingTimeInterval(110)
        timer.adjust(by: -RestTimerState.adjustmentStep, now: late)
        XCTAssertEqual(timer.remainingSeconds(at: late), 0)
    }

    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(RestTimerState.text(seconds: 105), "1:45")
        XCTAssertEqual(RestTimerState.text(seconds: 7), "0:07")
        XCTAssertEqual(RestTimerState.text(seconds: 120), "2:00")
    }

    func testStaysUpForThreeSecondsAfterItEnds() {
        let timer = RestTimerState(startedAt: start)
        XCTAssertEqual(timer.autoDismissDelay(at: start), 123, accuracy: 0.001)
        let end = start.addingTimeInterval(RestTimerState.defaultDuration)
        XCTAssertEqual(timer.autoDismissDelay(at: end), RestTimerState.finishedHold, accuracy: 0.001)
        XCTAssertEqual(timer.autoDismissDelay(at: end.addingTimeInterval(1)), 2, accuracy: 0.001)
        XCTAssertEqual(timer.autoDismissDelay(at: end.addingTimeInterval(3)), 0, accuracy: 0.001)
        XCTAssertEqual(timer.autoDismissDelay(at: end.addingTimeInterval(10)), 0, accuracy: 0.001)
    }

    func testOverdueSecondsAndTimerFormat() {
        let timer = RestTimerState(startedAt: start)
        XCTAssertEqual(timer.overdueSeconds(at: start), 0)
        XCTAssertEqual(timer.overdueSeconds(at: timer.endsAt), 0)
        XCTAssertEqual(timer.overdueSeconds(at: timer.endsAt.addingTimeInterval(0.9)), 0)
        XCTAssertEqual(timer.overdueSeconds(at: timer.endsAt.addingTimeInterval(1)), 1)
        let seconds = timer.overdueSeconds(at: timer.endsAt.addingTimeInterval(80))
        XCTAssertEqual(seconds, 80)
        XCTAssertEqual(RestTimerState.text(seconds: seconds), "1:20")
    }

    func testOverdueAppearanceStartsExactlyAtEndOfHold() {
        let timer = RestTimerState(startedAt: start)
        let threshold = timer.endsAt.addingTimeInterval(RestTimerState.finishedHold)
        XCTAssertFalse(timer.showsOverdueOnAppearance(at: start))
        XCTAssertFalse(timer.showsOverdueOnAppearance(at: timer.endsAt))
        XCTAssertFalse(timer.showsOverdueOnAppearance(at: threshold.addingTimeInterval(-0.001)))
        XCTAssertTrue(timer.showsOverdueOnAppearance(at: threshold))
        XCTAssertTrue(timer.showsOverdueOnAppearance(at: threshold.addingTimeInterval(80)))
        XCTAssertEqual(timer.autoDismissDelay(at: threshold), 0)
    }

    @MainActor
    func testRestStoreKeepsSessionsAndExerciseNamesIndependent() {
        let store = RestTimerStore()
        let firstID = StableUUID(UUID())
        let secondID = StableUUID(UUID())
        let first = RestTimerState(startedAt: start)
        let second = RestTimerState(startedAt: start.addingTimeInterval(30))
        store.set(first, exerciseName: "杠铃深蹲", for: firstID)
        store.set(second, exerciseName: "哑铃卧推", for: secondID)
        XCTAssertEqual(store.entry(for: firstID), .init(timer: first, exerciseName: "杠铃深蹲"))
        XCTAssertEqual(store.entry(for: secondID), .init(timer: second, exerciseName: "哑铃卧推"))
        store.clear(for: firstID)
        XCTAssertNil(store.entry(for: firstID))
        XCTAssertEqual(store.entry(for: secondID), .init(timer: second, exerciseName: "哑铃卧推"))
        XCTAssertNil(RestTimerStore().entry(for: secondID), "a fresh process store has no countdown")
    }

    func testTrainingScreenPlacesTheRestBarAboveFinish() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FineCoachApp/Features/ActiveSession/ActiveSessionView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("RestTimerBar("))
        XCTAssertTrue(source.contains("activeSessionRestMinus"))
        XCTAssertTrue(source.contains("activeSessionRestPlus"))
        XCTAssertTrue(source.contains("activeSessionRestSkip"))
        XCTAssertTrue(source.contains("activeSessionRestClose"))
        XCTAssertTrue(source.contains("session.rest.ended"))
        XCTAssertTrue(source.contains("activeSessionRestOverdue"))
        XCTAssertTrue(source.contains("session.rest.overdueFormat"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(source.contains("guard delay > 0 else { return }"))
        let bar = try XCTUnwrap(source.range(of: "RestTimerBar("))
        let finish = try XCTUnwrap(source.range(of: "session.action.finish"))
        XCTAssertLessThan(bar.lowerBound, finish.lowerBound)
    }

    func testRestEndNotificationTracksTheEndAndKeepsCopyRedacted() {
        XCTAssertNil(RestEndNotification.scheduler(arguments: ["-FineCoachUITesting"]))
        XCTAssertNotNil(RestEndNotification.scheduler(arguments: []))

        XCTAssertEqual(
            RestEndNotification.plan(endsAt: nil, now: start),
            .remove(identifier: RestEndNotification.identifier)
        )
        let ended = start.addingTimeInterval(120)
        XCTAssertEqual(
            RestEndNotification.plan(endsAt: ended, now: ended),
            .remove(identifier: RestEndNotification.identifier)
        )

        let plan = RestEndNotification.plan(endsAt: ended, now: start)
        guard case .schedule(let descriptor) = plan else {
            return XCTFail("expected a scheduled notification")
        }
        XCTAssertEqual(descriptor.identifier, RestEndNotification.identifier)
        XCTAssertNil(descriptor.threadIdentifier, "legacy requests without a Session keep default grouping")
        XCTAssertEqual(descriptor.fireDate, ended)
        XCTAssertEqual(descriptor.title, String(localized: "session.rest.notificationTitle"))
        XCTAssertEqual(descriptor.body, String(localized: "session.rest.notificationBody"))
        XCTAssertTrue(descriptor.userInfo.isEmpty)
        XCTAssertFalse(descriptor.title.contains("%"))
        XCTAssertFalse(descriptor.body.contains("%"))
        XCTAssertFalse(descriptor.identifier.localizedCaseInsensitiveContains("student"))
    }

    func testRestEndNotificationBodyNamesTheExerciseButNoStudent() {
        XCTAssertEqual(
            RestEndNotification.body(exerciseName: "杠铃深蹲"),
            String(
                format: String(localized: "session.rest.notificationBodyExercise"),
                "杠铃深蹲"
            )
        )
        XCTAssertTrue(RestEndNotification.body(exerciseName: "杠铃深蹲").contains("杠铃深蹲"))
        XCTAssertEqual(
            RestEndNotification.body(exerciseName: nil),
            String(localized: "session.rest.notificationBody")
        )
        XCTAssertEqual(
            RestEndNotification.body(exerciseName: ""),
            String(localized: "session.rest.notificationBody")
        )

        let body = RestEndNotification.body(exerciseName: "杠铃深蹲")
        for sentinel in ["林青", "女", "男", "60", "8 次", "第 3 组"] {
            XCTAssertFalse(body.contains(sentinel), "notification body leaked sentinel: \(sentinel)")
        }
    }

    func testRestEndNotificationUserInfoCarriesOnlyRoutingIdentifiers() throws {
        let studentID = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let fire = start.addingTimeInterval(120)
        let plan = RestEndNotification.plan(
            endsAt: fire,
            now: start,
            sessionID: sessionID,
            studentID: studentID,
            exerciseName: "杠铃深蹲"
        )
        guard case .schedule(let descriptor) = plan else {
            return XCTFail("expected a scheduled notification")
        }

        XCTAssertEqual(
            descriptor.userInfo,
            [
                RestNotificationPayload.kindKey: RestNotificationPayload.kindRestEnded,
                RestNotificationPayload.studentIDKey: studentID.rawValue.uuidString.lowercased(),
                RestNotificationPayload.sessionIDKey: sessionID.rawValue.uuidString.lowercased(),
            ]
        )
        XCTAssertTrue(descriptor.body.contains("杠铃深蹲"))
        XCTAssertFalse(descriptor.body.contains("林青"))
        XCTAssertEqual(descriptor.identifier, RestEndNotification.notificationIdentifier(for: sessionID))
        XCTAssertEqual(descriptor.threadIdentifier, descriptor.identifier)
        XCTAssertEqual(descriptor.threadIdentifier, "active-session.rest-ended.aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")

        let request = try XCTUnwrap(RestNotificationRouteRequest(userInfo: descriptor.userInfo))
        XCTAssertEqual(request.studentID, studentID)
        XCTAssertEqual(request.sessionID, sessionID)
    }

    func testRestEndNotificationRescheduleKeepsTheSameExerciseName() {
        let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let fire = start.addingTimeInterval(120)
        let first = RestEndNotification.plan(
            endsAt: fire,
            now: start,
            sessionID: sessionID,
            exerciseName: "杠铃深蹲"
        )
        let second = RestEndNotification.plan(
            endsAt: fire.addingTimeInterval(RestTimerState.adjustmentStep),
            now: start,
            sessionID: sessionID,
            exerciseName: "杠铃深蹲"
        )

        guard case .schedule(let firstDescriptor) = first,
            case .schedule(let secondDescriptor) = second
        else {
            return XCTFail("expected two scheduled notifications")
        }
        XCTAssertEqual(firstDescriptor.body, secondDescriptor.body)
        XCTAssertTrue(secondDescriptor.body.contains("杠铃深蹲"))
        XCTAssertEqual(secondDescriptor.fireDate, fire.addingTimeInterval(RestTimerState.adjustmentStep))
    }

    func testRestEndNotificationRemovesThisSessionsIdentifierOnly() async {
        let center = RecordingNotificationCenter()
        let firstSession = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let secondSession = StableUUID(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        let firstStudent = StableUUID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        let secondStudent = StableUUID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        let firstID = RestEndNotification.notificationIdentifier(for: firstSession)
        let secondID = RestEndNotification.notificationIdentifier(for: secondSession)
        let fire = start.addingTimeInterval(120)

        await RestEndNotification.apply(
            RestEndNotification.plan(
                endsAt: fire,
                now: start,
                sessionID: firstSession,
                studentID: firstStudent,
                exerciseName: "杠铃深蹲"
            ),
            with: center
        )
        await RestEndNotification.apply(
            RestEndNotification.plan(
                endsAt: fire,
                now: start,
                sessionID: secondSession,
                studentID: secondStudent,
                exerciseName: "哑铃卧推"
            ),
            with: center
        )
        // Skipping the first rest removes only the first Session's request.
        await RestEndNotification.apply(
            RestEndNotification.plan(endsAt: nil, now: start, sessionID: firstSession),
            with: center
        )

        let pending = await center.pending
        XCTAssertEqual(pending, [secondID], "the other Session's pending notification must survive")
        let removed = await center.removed
        XCTAssertEqual(removed.last, [firstID])
    }

    func testRestEndNotificationReplacesThenRemoves() async {
        let center = RecordingNotificationCenter()
        let sessionID = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let identifier = RestEndNotification.notificationIdentifier(for: sessionID)
        let fire = start.addingTimeInterval(120)
        let plan = RestEndNotification.plan(endsAt: fire, now: start, sessionID: sessionID)
        await RestEndNotification.apply(plan, with: center)
        let scheduled = await center.scheduled
        let authorizationRequests = await center.authorizationRequests
        XCTAssertEqual(scheduled.map(\.fireDate), [fire])
        XCTAssertEqual(authorizationRequests, 1)

        await RestEndNotification.apply(.remove(identifier: identifier), with: center)
        let removed = await center.removed
        XCTAssertEqual(removed, [[identifier], [identifier]])
    }

    /// P0 motion table + README §14.4. The views are not rendered here; this
    /// pins the moments, the token values, and Reduce Motion to the approved
    /// table.
    func testMotionTableIsWiredAtTheApprovedMoments() throws {
        let circle = try source("FineCoachApp/DesignSystem/Components/FCSetStateCircle.swift")
        XCTAssertTrue(circle.contains("accessibilityReduceMotion"))
        XCTAssertTrue(circle.contains("FCMotion.curveSymmetric(duration: FCMotion.durationFast)"))

        let row = try source("FineCoachApp/DesignSystem/Components/FCSetRow.swift")
        // Round-2 fix: confirmation feedback no longer lives on the row, whose
        // state does not transition on the primary add-and-confirm path.
        XCTAssertFalse(row.contains("sensoryFeedback"))
        XCTAssertFalse(row.contains("isRecordImprovement"))

        let stepper = try source("FineCoachApp/DesignSystem/Components/FCStepper.swift")
        let fieldStart = try XCTUnwrap(stepper.range(of: "struct FCStepperField"))
        XCTAssertFalse(stepper[..<fieldStart.lowerBound].contains("sensoryFeedback"))
        let field = stepper[fieldStart.lowerBound...]
        XCTAssertTrue(field.contains(".sensoryFeedback(FCHaptic.selection, trigger: selectionTick)"))
        XCTAssertTrue(field.contains(".numericText(countsDown: true)"))
        XCTAssertTrue(field.contains("accessibilityReduceMotion"))

        let session = try source("FineCoachApp/Features/ActiveSession/ActiveSessionView.swift")
        XCTAssertTrue(session.contains(".sensoryFeedback(trigger: viewModel.confirmationFeedback)"))
        // §14.3/§14.4: plain, progress and record confirmations share one
        // light impact; the record is expressed by the value float.
        XCTAssertTrue(session.contains("return FCHaptic.confirm"))
        XCTAssertTrue(session.contains("guard let feedback else { return nil }"))
        XCTAssertEqual(
            session.components(separatedBy: ".sensoryFeedback(trigger: viewModel.confirmationFeedback)").count - 1, 1,
            "exactly one stable-ancestor confirmation haptic")
        XCTAssertTrue(session.contains(".move(edge: .bottom).combined(with: .opacity)"))
        XCTAssertTrue(session.contains("removal: .opacity"))
        XCTAssertTrue(session.contains("FCMotion.curveSymmetric(duration: FCMotion.durationStandard)"))
        XCTAssertTrue(session.contains(".sensoryFeedback(FCHaptic.attention, trigger: finished)"))
        XCTAssertTrue(session.contains(".numericText(countsDown: true)"))
        XCTAssertTrue(session.contains("accessibilityReduceMotion"))
    }

    /// README §14.2/§14.3 (2026-10-23): the training-page files use the motion
    /// and haptic tokens instead of raw curves and the retired `.success` /
    /// heavy impact. Scope is exactly these four files -- other pages keep
    /// their current values until their own migration (README §14.4).
    func testTrainingPageFilesHaveNoRawMotionOrConfirmHapticValues() throws {
        let paths = [
            "FineCoachApp/Features/ActiveSession/ActiveSessionView.swift",
            "FineCoachApp/DesignSystem/Components/FCSetRow.swift",
            "FineCoachApp/DesignSystem/Components/FCSetStateCircle.swift",
            "FineCoachApp/DesignSystem/Components/FCStepper.swift",
        ]
        let retired = [".easeOut(duration:", ".easeInOut(duration:", ".success", ".impact(weight: .heavy)"]
        for path in paths {
            let text = try source(path)
            for raw in retired {
                XCTAssertFalse(text.contains(raw), "\(path) still writes \(raw) instead of a README §14 token")
            }
        }
    }

    /// components.md `DS-SET-ROW` 新纪录数值浮起 / README §14.4: the copy is a
    /// decorative overlay of the value, tries/fades once, takes no tap, is
    /// hidden from accessibility, and does not float under Reduce Motion.
    func testRecordFloatCopyIsDecorativeAndHonoursReduceMotion() throws {
        let row = try source("FineCoachApp/DesignSystem/Components/FCSetRow.swift")
        XCTAssertTrue(row.contains("recordFloatDistance: FCMotion.recordFloatDistance"))
        XCTAssertTrue(row.contains("recordFloatDuration: FCMotion.durationEmphasis"))
        XCTAssertTrue(row.contains("FCMotion.curveStandard(duration: recordFloatDuration)"))
        XCTAssertTrue(row.contains(".overlay {"))
        XCTAssertEqual(
            row.components(separatedBy: ".offset(y: -recordFloatDistance").count - 1, 1,
            "one decorative copy, lifted by the float distance")
        XCTAssertTrue(row.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(row.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(row.contains("guard !reduceMotion else { return }"))
        XCTAssertTrue(row.contains("guard playedRecordFloatSequence != sequence else { return }"))
        // The float token comes from the page, never from the row's own state.
        XCTAssertTrue(row.contains(".task(id: recordFloatSequence)"))
        XCTAssertFalse(row.contains("onChange(of:"))
        XCTAssertFalse(row.contains(".onAppear {"))
    }

    /// The entry map has to name the real identifiers. A control that exists
    /// only in the view, or only in the map, is the defect this list exists
    /// to catch.
    func testEntryMapNamesTheNewControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("design/experience-p0/implementation-map.md"),
            encoding: .utf8
        )
        let identifiers = try String(
            contentsOf: root.appendingPathComponent("ios/FineCoachApp/App/FCAccessibilityID.swift"),
            encoding: .utf8
        )
        let keys = [
            "activeSession.weight",
            "activeSession.weight.decrement",
            "activeSession.weight.increment",
            "activeSession.reps",
            "activeSession.reps.decrement",
            "activeSession.reps.increment",
            "activeSession.weightStepHint",
            "activeSession.exercise.last.",
            "activeSession.exercise.mode.",
            "activeSession.rest",
            "activeSession.rest.minus",
            "activeSession.rest.plus",
            "activeSession.rest.skip",
            "activeSession.rest.ended",
            "activeSession.rest.close",
        ]
        for key in keys {
            XCTAssertTrue(map.contains(key), "map missing \(key)")
            XCTAssertTrue(identifiers.contains(key), "identifier missing \(key)")
        }
    }

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private actor RecordingNotificationCenter: LocalNotificationScheduling {
    private(set) var authorizationRequests = 0
    private(set) var scheduled: [NotificationRequestDescriptor] = []
    private(set) var removed: [[String]] = []
    private(set) var pending: Set<String> = []

    func requestAuthorizationIfNeeded() async {
        authorizationRequests += 1
    }

    func schedule(_ descriptor: NotificationRequestDescriptor) async throws {
        scheduled.append(descriptor)
        pending.insert(descriptor.identifier)
    }

    func removePending(identifiers: [String]) async {
        removed.append(identifiers)
        for identifier in identifiers {
            pending.remove(identifier)
        }
    }
}
