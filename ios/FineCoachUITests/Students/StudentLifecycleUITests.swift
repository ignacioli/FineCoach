import XCTest

@MainActor
final class StudentLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchExplainsLocalBoundaryAndAllowsSkipCreate() {
        let app = launchIsolatedApp()
        if app.buttons["firstLaunch.coach"].waitForExistence(timeout: 8) { app.buttons["firstLaunch.coach"].tap() }
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["onboarding.lead"].exists)
        // The full local/share explanation lives in the data sheet opened from the link.
        app.buttons["onboarding.dataLink"].tap()
        XCTAssertTrue(app.buttons["onboarding.sheet.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: "onboarding.local").exists)
        XCTAssertTrue(element(in: app, identifier: "onboarding.share").exists)
        app.buttons["onboarding.sheet.close"].tap()
        XCTAssertFalse(springboard.alerts.element.exists)

        app.buttons["onboarding.skip"].tap()
        waitForStudentList(in: app)
        XCTAssertTrue(
            app.staticTexts["还没有学员"].waitForExistence(timeout: 5)
                || app.buttons["添加学员"].exists
        )

        print("DBG-TREE-START\n" + app.debugDescription + "\nDBG-TREE-END")
        tapAddStudent(in: app)
        XCTAssertTrue(element(in: app, identifier: "studentEditor.root").waitForExistence(timeout: 5))
        fillEditor(in: app, name: "林青", sexIdentifier: "studentEditor.sex.female")
        app.buttons["studentEditor.save"].tap()
        XCTAssertTrue(app.staticTexts["林青"].waitForExistence(timeout: 8))
    }

    func testSearchArchiveRestoreAndConfirmedDelete() throws {
        throw XCTSkip(
            "Stale since D6 (T069g): 归档 / 永久删除 moved from 学员详情 to the bottom of 编辑资料; rewrite the flow through 编辑资料 (tracked in tasks.md T081)."
        )

        let app = launchIsolatedApp()
        if app.buttons["firstLaunch.coach"].waitForExistence(timeout: 8) { app.buttons["firstLaunch.coach"].tap() }
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

    func testInProgressSessionBlocksPermanentDelete() throws {
        throw XCTSkip(
            "Stale since D6 (T069g): 归档 / 永久删除 moved from 学员详情 to the bottom of 编辑资料; rewrite the flow through 编辑资料 (tracked in tasks.md T081)."
        )

        let app = launchIsolatedApp(extraArguments: ["-FineCoachSeedInProgressSession"])
        openStudentsTab(in: app)
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
        if app.buttons["firstLaunch.coach"].waitForExistence(timeout: 8) { app.buttons["firstLaunch.coach"].tap() }
        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 8))
        if app.buttons["firstLaunch.coach"].waitForExistence(timeout: 8) { app.buttons["firstLaunch.coach"].tap() }
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        tapVisible(in: app, identifier: "onboarding.skip")
        waitForStudentList(in: app)
        let add = addStudentButton(in: app)
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isHittable)
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

    /// 新学员 is `studentList.add` once the list has students and `studentList.emptyAdd` in the empty state.
    private func addStudentButton(in app: XCUIApplication) -> XCUIElement {
        let withStudents = app.buttons["studentList.add"]
        return withStudents.exists ? withStudents : app.buttons["studentList.emptyAdd"]
    }

    private func tapAddStudent(in app: XCUIApplication) {
        let predicate = NSPredicate(format: "identifier IN %@", ["studentList.add", "studentList.emptyAdd"])
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), "新学员 button")
        button.tap()
    }

    /// The app now lands on 今日 (T069a); the student list is behind the 今日 / 学员 switch.
    private func openStudentsTab(in app: XCUIApplication) {
        let segment = app.buttons["学员"].firstMatch
        if segment.waitForExistence(timeout: 8), !segment.isSelected {
            segment.tap()
        }
    }

    private func waitForStudentList(in app: XCUIApplication) {
        openStudentsTab(in: app)
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
        tapAddStudent(in: app)
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
