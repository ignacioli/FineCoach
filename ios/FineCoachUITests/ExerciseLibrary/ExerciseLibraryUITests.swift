import XCTest

@MainActor
final class ExerciseLibraryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSearchFavoriteHideUnhidePlaceholderSquat() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        openExerciseLibrary(in: app)

        typeInto(in: app, identifier: "exerciseLibrary.search", text: "占位深蹲")
        XCTAssertTrue(
            element(in: app, identifier: "exerciseLibrary.row.fc.placeholder.squat").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["内置"].waitForExistence(timeout: 8))

        tapVisible(in: app, identifier: "exerciseLibrary.favorite")
        tapVisible(in: app, identifier: "exerciseLibrary.hide")
        XCTAssertTrue(element(in: app, identifier: "exerciseLibrary.root").waitForExistence(timeout: 8))
        XCTAssertFalse(
            element(in: app, identifier: "exerciseLibrary.row.fc.placeholder.squat").waitForExistence(timeout: 2),
            "hidden placeholder must be omitted from the default list"
        )

        tapVisible(in: app, identifier: "exerciseLibrary.showHidden")
        XCTAssertTrue(
            element(in: app, identifier: "exerciseLibrary.row.fc.placeholder.squat").waitForExistence(timeout: 8))
        tapVisible(in: app, identifier: "exerciseLibrary.hide")
        XCTAssertTrue(
            element(in: app, identifier: "exerciseLibrary.row.fc.placeholder.squat").waitForExistence(timeout: 8))

        tapVisible(in: app, identifier: "exerciseLibrary.showHidden")
        XCTAssertTrue(
            element(in: app, identifier: "exerciseLibrary.row.fc.placeholder.squat").waitForExistence(timeout: 8))
    }

    func testCreateArchiveAndRecreateCustomExerciseReleasesClaim() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        openExerciseLibrary(in: app)

        createCustomExercise(in: app, name: "我的推举")
        XCTAssertTrue(app.staticTexts["我的推举"].waitForExistence(timeout: 8))

        popToStudentList(in: app)
        openExerciseLibrary(in: app)
        XCTAssertTrue(app.staticTexts["我的推举"].waitForExistence(timeout: 8))

        app.staticTexts["我的推举"].firstMatch.tap()
        XCTAssertTrue(element(in: app, identifier: "customExercise.root").waitForExistence(timeout: 8))
        tapVisible(in: app, identifier: "customExercise.archive")
        XCTAssertTrue(element(in: app, identifier: "customExercise.restore").waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(in: app, identifier: "exerciseLibrary.root").waitForExistence(timeout: 8))

        createCustomExercise(in: app, name: "我的推举")
        XCTAssertTrue(app.staticTexts["我的推举"].waitForExistence(timeout: 8))
        XCTAssertFalse(element(in: app, identifier: "exerciseLibrary.conflict").exists)
    }

    func testInSessionSessionOnlyAndSaveToLibraryConflict() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)

        addSessionOnlyExercise(in: app, name: "杠铃深蹲", modeIdentifier: "activeSession.mode.weightReps")
        XCTAssertTrue(app.staticTexts["杠铃深蹲"].waitForExistence(timeout: 8))

        addLibraryExercise(in: app, name: "课中自定义A", modeIdentifier: "activeSession.mode.weightReps")
        XCTAssertTrue(app.staticTexts["课中自定义A"].waitForExistence(timeout: 8))

        tapControl(in: app, identifier: "activeSession.addExercise", label: "添加动作")
        typeInto(in: app, identifier: "activeSession.exerciseName", text: "占位深蹲")
        tapVisible(in: app, identifier: "activeSession.mode.weightReps")
        tapControl(in: app, identifier: "activeSession.saveExerciseToLibrary", label: "保存到动作库")
        XCTAssertTrue(
            element(in: app, identifier: "activeSession.exerciseNameConflict").waitForExistence(timeout: 8)
        )
        let nameField = app.textFields["activeSession.exerciseName"]
        XCTAssertEqual(nameField.value as? String, "占位深蹲", "conflict must not silently rename")

        popToStudentList(in: app)
        openExerciseLibrary(in: app)
        XCTAssertTrue(app.staticTexts["课中自定义A"].waitForExistence(timeout: 8))
        typeInto(in: app, identifier: "exerciseLibrary.search", text: "占位深蹲")
        XCTAssertTrue(app.staticTexts["占位深蹲"].waitForExistence(timeout: 8))
        let squatMatches = app.staticTexts.matching(NSPredicate(format: "label == %@", "占位深蹲"))
        XCTAssertEqual(squatMatches.count, 1, "library must keep a single 占位深蹲 after conflict")
    }

    func testSessionOnlyExerciseDoesNotAppearInLibrary() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)

        addSessionOnlyExercise(in: app, name: "仅本次动作X", modeIdentifier: "activeSession.mode.weightReps")
        XCTAssertTrue(app.staticTexts["仅本次动作X"].waitForExistence(timeout: 8))

        popToStudentList(in: app)
        openExerciseLibrary(in: app)
        typeInto(in: app, identifier: "exerciseLibrary.search", text: "仅本次动作X")
        XCTAssertFalse(
            app.staticTexts["仅本次动作X"].waitForExistence(timeout: 2),
            "session-only exercises must not appear in the library"
        )
    }

    private func launchIsolatedApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-AppleLanguages", "(zh-Hans)",
                "-AppleLocale", "zh_CN",
                "-FineCoachUITesting",
                "-FineCoachResetStore",
            ] + extraArguments
        app.launch()
        return app
    }

    private func waitForStudentList(in app: XCUIApplication) {
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

    private func tapVisible(in app: XCUIApplication, identifier: String) {
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5))
        let elements = matches.allElementsBoundByIndex
        if let hittable = elements.last(where: \.isHittable) {
            hittable.tap()
            return
        }
        elements.last?.tap()
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func fillEditor(
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
        app.swipeUp()
        let noteField = app.textFields["studentEditor.privateCoachNote"]
        if noteField.waitForExistence(timeout: 2) {
            noteField.tap()
            noteField.typeText(note)
        }
    }

    private func skipOnboarding(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 8))
        app.buttons["onboarding.skip"].tap()
        waitForStudentList(in: app)
    }

    private func addStudentLinQing(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["studentList.add"].waitForExistence(timeout: 8))
        app.buttons["studentList.add"].tap()
        XCTAssertTrue(element(in: app, identifier: "studentEditor.root").waitForExistence(timeout: 8))
        fillEditor(in: app, name: "林青", sexIdentifier: "studentEditor.sex.female")
        dismissKeyboard(in: app)
        app.buttons["studentEditor.save"].tap()
        waitForStudentList(in: app)
        XCTAssertTrue(app.staticTexts["林青"].waitForExistence(timeout: 8))
    }

    private func openStudentDetail(in app: XCUIApplication) {
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

    private func dismissKeyboard(in app: XCUIApplication) {
        if app.keyboards.element.exists {
            app.swipeDown()
        }
    }

    private func assertActiveSession(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "activeSession.root").waitForExistence(timeout: 8))
        XCTAssertFalse(element(in: app, identifier: "placeholder.training").exists)
    }

    private func popToStudentList(in app: XCUIApplication) {
        for _ in 0..<6 {
            if app.buttons["studentList.add"].exists || app.buttons["exerciseLibrary.entry"].exists {
                waitForStudentList(in: app)
                return
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists {
                back.tap()
            } else {
                break
            }
        }
        waitForStudentList(in: app)
    }

    private func openExerciseLibrary(in app: XCUIApplication) {
        waitForStudentList(in: app)
        tapControl(in: app, identifier: "exerciseLibrary.entry", label: "动作库")
        XCTAssertTrue(element(in: app, identifier: "exerciseLibrary.root").waitForExistence(timeout: 8))
    }

    private func createCustomExercise(in app: XCUIApplication, name: String) {
        tapVisible(in: app, identifier: "exerciseLibrary.addCustom")
        XCTAssertTrue(element(in: app, identifier: "customExercise.root").waitForExistence(timeout: 8))
        typeInto(in: app, identifier: "customExercise.name", text: name)
        tapVisible(in: app, identifier: "customExercise.mode.weightReps")
        dismissKeyboard(in: app)
        tapVisible(in: app, identifier: "customExercise.save")
        XCTAssertTrue(element(in: app, identifier: "exerciseLibrary.root").waitForExistence(timeout: 8))
    }

    private func addSessionOnlyExercise(in app: XCUIApplication, name: String, modeIdentifier: String) {
        tapControl(in: app, identifier: "activeSession.addExercise", label: "添加动作")
        typeInto(in: app, identifier: "activeSession.exerciseName", text: name)
        tapVisible(in: app, identifier: modeIdentifier)
        tapControl(in: app, identifier: "activeSession.saveExercise", label: "仅本次")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8))
    }

    private func addLibraryExercise(in app: XCUIApplication, name: String, modeIdentifier: String) {
        tapControl(in: app, identifier: "activeSession.addExercise", label: "添加动作")
        typeInto(in: app, identifier: "activeSession.exerciseName", text: name)
        tapVisible(in: app, identifier: modeIdentifier)
        tapControl(in: app, identifier: "activeSession.saveExerciseToLibrary", label: "保存到动作库")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8))
    }

    private func tapControl(in app: XCUIApplication, identifier: String, label: String?) {
        let byID = app.descendants(matching: .any).matching(identifier: identifier)
        if byID.firstMatch.waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: identifier)
            return
        }
        if let label {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 8), "missing \(identifier) / \(label)")
            if !button.isHittable {
                app.swipeUp()
            }
            button.tap()
            return
        }
        XCTFail("missing \(identifier)")
    }

    private func typeInto(in app: XCUIApplication, identifier: String, text: String) {
        let byID = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(byID.waitForExistence(timeout: 8), "missing field \(identifier)")
        if !byID.isHittable {
            app.swipeUp()
        }
        byID.tap()
        let field = app.textFields[identifier].exists ? app.textFields[identifier] : app.textFields.firstMatch
        if field.exists {
            field.typeText(text)
        } else {
            byID.typeText(text)
        }
    }
}
