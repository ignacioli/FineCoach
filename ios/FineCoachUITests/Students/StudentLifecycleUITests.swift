import XCTest

@MainActor
final class StudentLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchExplainsLocalBoundaryAndAllowsSkipCreate() {
        let app = launchIsolatedApp()
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["onboarding.lead"].exists)
        XCTAssertTrue(app.staticTexts["onboarding.local"].exists)
        XCTAssertTrue(app.staticTexts["onboarding.share"].exists)
        XCTAssertFalse(springboard.alerts.element.exists)

        app.buttons["onboarding.skip"].tap()
        waitForStudentList(in: app)
        XCTAssertTrue(
            app.staticTexts["还没有学员"].waitForExistence(timeout: 5)
                || app.buttons["添加学员"].exists
        )

        app.buttons["studentList.add"].tap()
        XCTAssertTrue(element(in: app, identifier: "studentEditor.root").waitForExistence(timeout: 5))
        fillEditor(in: app, name: "林青", sexIdentifier: "studentEditor.sex.female")
        app.buttons["studentEditor.save"].tap()
        XCTAssertTrue(app.staticTexts["林青"].waitForExistence(timeout: 8))
    }

    func testSearchArchiveRestoreAndConfirmedDelete() {
        let app = launchIsolatedApp()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 8))
        app.buttons["onboarding.skip"].tap()
        waitForStudentList(in: app)

        createStudent(in: app, name: "林林", sexIdentifier: "studentEditor.sex.other", note: "工作室午班")
        createStudent(in: app, name: "林林", sexIdentifier: "studentEditor.sex.female", note: "晚间私教")

        let search = app.textFields["studentList.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("林林")
        XCTAssertTrue(app.staticTexts["林林"].waitForExistence(timeout: 5))

        app.staticTexts["林林"].firstMatch.tap()
        XCTAssertTrue(app.buttons["studentDetail.archive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["studentDetail.injuryNotesFold"].exists)
        XCTAssertFalse(app.staticTexts["studentDetail.injuryNotesBody"].exists)

        app.revealLowerContent()
        tapVisible(in: app, identifier: "studentDetail.archive")
        XCTAssertTrue(app.buttons["archive.confirm"].waitForExistence(timeout: 5))
        tapVisible(in: app, identifier: "archive.confirm")
        XCTAssertTrue(
            app.buttons["studentDetail.restore"].waitForExistence(timeout: 8)
                || app.otherElements["studentDetail.archivedStatus"].waitForExistence(timeout: 2)
        )
        app.navigationBars.buttons.element(boundBy: 0).tap()

        if search.waitForExistence(timeout: 2) {
            let clear = app.buttons["Clear text"]
            if clear.exists {
                clear.tap()
            }
        }

        XCTAssertTrue(app.buttons["studentList.archived"].waitForExistence(timeout: 5))
        app.buttons["studentList.archived"].tap()
        XCTAssertTrue(app.staticTexts["林林"].waitForExistence(timeout: 8))
        app.staticTexts["林林"].firstMatch.tap()
        XCTAssertTrue(app.buttons["studentDetail.restore"].waitForExistence(timeout: 5))
        app.buttons["studentDetail.restore"].tap()
        XCTAssertTrue(app.buttons["studentDetail.startTraining"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitForStudentList(in: app)
        XCTAssertTrue(app.staticTexts["林林"].waitForExistence(timeout: 8))

        app.staticTexts["林林"].firstMatch.tap()
        XCTAssertTrue(app.buttons["studentDetail.delete"].waitForExistence(timeout: 5))
        app.revealLowerContent()
        tapVisible(in: app, identifier: "studentDetail.delete")
        let nameField = app.textFields["deleteStudent.confirmName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["永久删除"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["deleteStudent.backup"].exists)
        XCTAssertTrue(
            app.staticTexts["删除后无法从本页恢复。已分享的旧图片和你保存的备份不会被远程改写或删除。"].exists
        )
        nameField.tap()
        nameField.typeText("林林")
        tapVisible(in: app, identifier: "deleteStudent.confirm")
        XCTAssertTrue(app.staticTexts["学员已永久删除"].waitForExistence(timeout: 8))
    }

    func testInProgressSessionBlocksPermanentDelete() {
        let app = launchIsolatedApp(extraArguments: ["-FineCoachSeedInProgressSession"])
        XCTAssertTrue(app.buttons["studentList.row.11111111-1111-4111-8111-111111111111"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["studentList.inProgress"].waitForExistence(timeout: 5))
        app.buttons["studentList.row.11111111-1111-4111-8111-111111111111"].tap()
        XCTAssertTrue(app.buttons["studentDetail.delete"].waitForExistence(timeout: 5))
        app.revealLowerContent()
        tapVisible(in: app, identifier: "studentDetail.delete")
        XCTAssertTrue(app.staticTexts["deleteStudent.blocked"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["deleteStudent.confirmName"].exists)
    }

    func testOnboardingAndListRemainUsableWithAccessibilityContentSize() {
        let app = launchIsolatedApp(
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXL",
            ]
        )
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        tapVisible(in: app, identifier: "onboarding.skip")
        waitForStudentList(in: app)
        XCTAssertTrue(app.buttons["studentList.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["studentList.add"].isHittable)
        XCTAssertTrue(
            app.staticTexts["还没有学员"].exists || app.buttons["添加学员"].exists
        )
    }

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
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

    private func createStudent(
        in app: XCUIApplication,
        name: String,
        sexIdentifier: String,
        note: String
    ) {
        XCTAssertTrue(app.buttons["studentList.add"].waitForExistence(timeout: 5))
        app.buttons["studentList.add"].tap()
        XCTAssertTrue(element(in: app, identifier: "studentEditor.root").waitForExistence(timeout: 5))
        fillEditor(in: app, name: name, sexIdentifier: sexIdentifier, note: note)
        app.buttons["studentEditor.save"].tap()
        waitForStudentList(in: app)
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
        app.revealLowerContent()
        let noteField = app.textFields["studentEditor.privateCoachNote"]
        if noteField.waitForExistence(timeout: 2) {
            noteField.tap()
            noteField.typeText(note)
        }
    }
}
