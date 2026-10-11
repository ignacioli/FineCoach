import XCTest

struct RecoveryProcessResult: Equatable, Codable, Sendable {
    var scenarioID: String
    var confirmedSetCount: Int
    var draftOrPendingVisible: Bool
    var saveStatus: String
    var sessionCompleted: Bool
    var confirmedSetLoss: Int
    var draftPromotedToCompleted: Bool
}

enum RecoveryProcessDriver {
    private static let resetStoreArgument = "-FineCoachResetStore"
    private static let uiTestingArguments = [
        "-AppleLanguages", "(zh-Hans)",
        "-AppleLocale", "zh_CN",
        "-FineCoachUITesting",
    ]

    @MainActor
    static func launchIsolatedApp(extraArguments: [String] = []) -> XCUIApplication {
        launch(app: XCUIApplication(), extraArguments: [resetStoreArgument] + extraArguments)
    }

    @MainActor
    static func terminate(_ app: XCUIApplication) {
        app.terminate()
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 8),
            "app process must stop before relaunch so the same store can be reopened"
        )
    }

    @MainActor
    static func relaunch(_ app: XCUIApplication, extraArguments: [String] = []) -> XCUIApplication {
        if app.state != .notRunning {
            terminate(app)
        }
        let survivingArguments = extraArguments.filter { $0 != resetStoreArgument }
        return launch(app: app, extraArguments: survivingArguments)
    }

    @MainActor
    static func skipOnboardingAndStartLinQingSession(in app: XCUIApplication) {
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)
    }

    @MainActor
    static func addCompletedSquatSet(in app: XCUIApplication) {
        addExercise(in: app, name: "杠铃深蹲", modeIdentifier: "activeSession.mode.weightReps")
        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        addConfirmedWeightRepsSet(in: app, weight: "0", reps: "5")
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "activeSession.set.at.0").waitForExistence(timeout: 8))
    }

    @MainActor
    static func addUnconfirmedDraft(in app: XCUIApplication) {
        tapControl(in: app, identifier: "activeSession.addSet", label: "添加组")
        typeInto(in: app, identifier: "activeSession.weight", text: "40")
        XCTAssertTrue(
            element(in: app, identifier: "activeSession.setState.draft").waitForExistence(timeout: 8)
                || element(in: app, identifier: "activeSession.weight").exists
        )
    }

    @MainActor
    static func observe(
        in app: XCUIApplication,
        scenarioID: String,
        expectedConfirmed: Int
    ) -> RecoveryProcessResult {
        _ = element(in: app, identifier: "activeSession.root").waitForExistence(timeout: 8)
        if expectedConfirmed > 0 {
            _ = element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8)
        }
        _ =
            element(in: app, identifier: "activeSession.setState.draft").waitForExistence(timeout: 2)
            || element(in: app, identifier: "activeSession.setState.pending").waitForExistence(timeout: 2)

        let confirmedSetCount = app.descendants(matching: .any)
            .matching(identifier: "activeSession.setState.completed")
            .count
        let draftOrPendingVisible =
            element(in: app, identifier: "activeSession.setState.draft").exists
            || element(in: app, identifier: "activeSession.setState.pending").exists
        let sessionCompleted = element(in: app, identifier: "activeSession.completedStatus").exists
        let confirmedSetLoss = max(0, expectedConfirmed - confirmedSetCount)

        return RecoveryProcessResult(
            scenarioID: scenarioID,
            confirmedSetCount: confirmedSetCount,
            draftOrPendingVisible: draftOrPendingVisible,
            saveStatus: readSaveStatus(in: app),
            sessionCompleted: sessionCompleted,
            confirmedSetLoss: confirmedSetLoss,
            draftPromotedToCompleted: confirmedSetCount > expectedConfirmed
        )
    }

    static func encodeResult(_ result: RecoveryProcessResult) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(result)
    }

    static func decodeResult(_ data: Data) throws -> RecoveryProcessResult {
        try JSONDecoder().decode(RecoveryProcessResult.self, from: data)
    }

    @MainActor
    static func skipOnboardingIfPresented(in app: XCUIApplication) {
        if app.buttons["firstLaunch.coach"].waitForExistence(timeout: 8) { app.buttons["firstLaunch.coach"].tap() }
        if app.buttons["onboarding.skip"].waitForExistence(timeout: 3) {
            app.buttons["onboarding.skip"].tap()
            waitForStudentList(in: app)
        }
    }

    @MainActor
    static func continueInProgressSession(in app: XCUIApplication) {
        if element(in: app, identifier: "activeSession.root").waitForExistence(timeout: 2) {
            return
        }
        if element(in: app, identifier: "studentList.inProgress").waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: "studentList.inProgress")
            assertActiveSession(in: app)
            return
        }
        if app.buttons["继续训练"].waitForExistence(timeout: 2) {
            app.buttons["继续训练"].tap()
            assertActiveSession(in: app)
            return
        }
        if app.staticTexts["林青"].waitForExistence(timeout: 8) {
            app.staticTexts["林青"].firstMatch.tap()
        }
        tapControl(in: app, identifier: "studentDetail.continueTraining", label: "继续训练")
        assertActiveSession(in: app)
    }

    @MainActor
    static func addConfirmedWeightRepsSet(in app: XCUIApplication, weight: String, reps: String) {
        tapControl(in: app, identifier: "activeSession.addSet", label: "添加组")
        typeInto(in: app, identifier: "activeSession.weight", text: weight)
        typeInto(in: app, identifier: "activeSession.reps", text: reps)
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")
    }

    @MainActor
    static func addExercise(in app: XCUIApplication, name: String, modeIdentifier: String) {
        tapControl(in: app, identifier: "activeSession.addExercise", label: "添加动作")
        typeInto(in: app, identifier: "activeSession.exerciseName", text: name)
        let catalogMatch = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "activeSession.catalogRow.",
                name
            )
        ).firstMatch
        if catalogMatch.waitForExistence(timeout: 3) {
            catalogMatch.tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8))
            return
        }
        tapVisible(in: app, identifier: modeIdentifier)
        tapControl(in: app, identifier: "activeSession.saveExercise", label: "保存动作")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8))
    }

    @MainActor
    static func tapControl(in app: XCUIApplication, identifier: String, label: String?) {
        let byID = app.descendants(matching: .any).matching(identifier: identifier)
        if byID.firstMatch.waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: identifier)
            return
        }
        if let label {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 8), "missing \(identifier) / \(label)")
            if !button.isHittable {
                app.revealLowerContent()
            }
            button.tap()
            return
        }
        XCTFail("missing \(identifier)")
    }

    @MainActor
    static func typeInto(in app: XCUIApplication, identifier: String, text: String) {
        let field = app.textFields[identifier]
        let target = field.waitForExistence(timeout: 2) ? field : element(in: app, identifier: identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 8), "missing field \(identifier)")
        if !target.isHittable {
            app.revealLowerContent()
        }
        target.tap()
        target.typeText(text)
    }

    @MainActor
    static func tapVisible(in app: XCUIApplication, identifier: String) {
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5))
        let elements = matches.allElementsBoundByIndex
        if let hittable = elements.last(where: \.isHittable) {
            hittable.tap()
            return
        }
        elements.last?.tap()
    }

    @MainActor
    static func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private static func launch(app: XCUIApplication, extraArguments: [String]) -> XCUIApplication {
        app.launchArguments = uiTestingArguments + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private static func readSaveStatus(in app: XCUIApplication) -> String {
        if element(in: app, identifier: "activeSession.saveStatus.saving").exists {
            return "saving"
        }
        if element(in: app, identifier: "activeSession.saveStatus.saved").exists {
            return "saved"
        }
        if element(in: app, identifier: "activeSession.saveStatus.failed").exists
            || element(in: app, identifier: "activeSession.retry").exists
        {
            return "failed"
        }
        if app.staticTexts["保存中"].exists {
            return "saving"
        }
        if app.staticTexts["已保存"].exists {
            return "saved"
        }
        if app.staticTexts["保存失败"].exists {
            return "failed"
        }
        return "unknown"
    }

    @MainActor
    private static func skipOnboarding(in app: XCUIApplication) {
        if app.buttons["firstLaunch.coach"].waitForExistence(timeout: 8) { app.buttons["firstLaunch.coach"].tap() }
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 8))
        app.buttons["onboarding.skip"].tap()
        waitForStudentList(in: app)
    }

    @MainActor
    private static func addStudentLinQing(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["studentList.add"].waitForExistence(timeout: 8))
        app.buttons["studentList.add"].tap()
        XCTAssertTrue(element(in: app, identifier: "studentEditor.root").waitForExistence(timeout: 8))
        fillEditor(in: app, name: "林青", sexIdentifier: "studentEditor.sex.female")
        dismissKeyboard(in: app)
        app.buttons["studentEditor.save"].tap()
        waitForStudentList(in: app)
        XCTAssertTrue(app.staticTexts["林青"].waitForExistence(timeout: 8))
    }

    @MainActor
    private static func fillEditor(
        in app: XCUIApplication,
        name: String,
        sexIdentifier: String,
        note: String = "晚班"
    ) {
        let nameField = app.textFields["studentEditor.displayName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.buttons[sexIdentifier].tap()
        app.revealLowerContent()
        let noteField = app.textFields["studentEditor.privateCoachNote"]
        if noteField.waitForExistence(timeout: 2) {
            noteField.tap()
            noteField.typeText(note)
        }
    }

    @MainActor
    private static func dismissKeyboard(in app: XCUIApplication) {
        if app.keyboards.element.exists {
            app.swipeDown()
        }
    }

    @MainActor
    private static func openStudentDetail(in app: XCUIApplication) {
        waitForStudentList(in: app)
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "studentList.row.")
        ).firstMatch
        if row.waitForExistence(timeout: 2) {
            row.tap()
        } else {
            XCTAssertTrue(app.staticTexts["林青"].waitForExistence(timeout: 8))
            app.staticTexts["林青"].firstMatch.tap()
        }
        XCTAssertTrue(element(in: app, identifier: "studentDetail.root").waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.buttons["studentDetail.startTraining"].waitForExistence(timeout: 8)
                || app.buttons["开始训练"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    private static func waitForStudentList(in app: XCUIApplication) {
        let addByID = app.buttons["studentList.add"]
        let addByLabel = app.buttons["添加学员"]
        let empty = app.staticTexts["还没有学员"]
        let nav = app.navigationBars["学员"]
        XCTAssertTrue(
            addByID.waitForExistence(timeout: 8)
                || addByLabel.waitForExistence(timeout: 2)
                || empty.waitForExistence(timeout: 2)
                || nav.waitForExistence(timeout: 2)
        )
    }

    @MainActor
    private static func assertActiveSession(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "activeSession.root").waitForExistence(timeout: 8))
        XCTAssertFalse(element(in: app, identifier: "placeholder.training").exists)
        XCTAssertFalse(app.staticTexts["此入口已保留，具体内容不在本里程碑展开。"].exists)
    }
}

extension XCUIApplication {
    /// Scrolls from mid-screen so the home indicator is not treated as a Home gesture.
    /// `swipeUp()` on physical iPhone X-class devices can background the app and SIGKILL the UI runner.
    func revealLowerContent() {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}

@MainActor
final class RecoveryProcessDriverTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testResultCodecRoundTrip() throws {
        let original = RecoveryProcessResult(
            scenarioID: "us3.terminate-relaunch.confirmed-plus-draft",
            confirmedSetCount: 1,
            draftOrPendingVisible: true,
            saveStatus: "saved",
            sessionCompleted: false,
            confirmedSetLoss: 0,
            draftPromotedToCompleted: false
        )
        let data = try RecoveryProcessDriver.encodeResult(original)
        let decoded = try RecoveryProcessDriver.decodeResult(data)
        XCTAssertEqual(decoded, original)
    }

    func testTerminateAndRelaunchRestoresConfirmedSetAndKeepsDraft() {
        var app = RecoveryProcessDriver.launchIsolatedApp()
        RecoveryProcessDriver.skipOnboardingAndStartLinQingSession(in: app)
        RecoveryProcessDriver.addCompletedSquatSet(in: app)
        RecoveryProcessDriver.addUnconfirmedDraft(in: app)

        RecoveryProcessDriver.terminate(app)
        app = RecoveryProcessDriver.relaunch(app)

        RecoveryProcessDriver.skipOnboardingIfPresented(in: app)
        RecoveryProcessDriver.continueInProgressSession(in: app)

        let result = RecoveryProcessDriver.observe(
            in: app,
            scenarioID: "us3.terminate-relaunch.confirmed-plus-draft",
            expectedConfirmed: 1
        )
        XCTAssertEqual(result.confirmedSetCount, 1, "confirmed 0x5 must survive terminate and relaunch")
        XCTAssertEqual(result.confirmedSetLoss, 0)
        XCTAssertTrue(
            result.draftOrPendingVisible,
            "unconfirmed draft must remain draft or pending after relaunch"
        )
        XCTAssertFalse(
            result.draftPromotedToCompleted,
            "draft must not be promoted to completed across terminate and relaunch"
        )
        XCTAssertFalse(result.sessionCompleted)
        XCTAssertTrue(
            RecoveryProcessDriver.element(in: app, identifier: "activeSession.setState.completed").exists
        )
        XCTAssertFalse(
            RecoveryProcessDriver.element(in: app, identifier: "activeSession.completedStatus").exists
        )
    }
}
