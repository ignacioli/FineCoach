import XCTest

@MainActor
final class CoreTrainingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStartTrainingRecordsModesAndUnconfirmedInputDoesNotCount() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)

        addExercise(in: app, name: "杠铃深蹲", modeIdentifier: "activeSession.mode.weightReps")
        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        XCTAssertFalse(
            element(in: app, identifier: "activeSession.splitSides").exists,
            "ordinary exercises must not show unilateral side controls (P0-D8)"
        )
        addConfirmedWeightRepsSet(in: app, weight: "0", reps: "5")
        XCTAssertTrue(element(in: app, identifier: "activeSession.set.at.0").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))

        let stats = element(in: app, identifier: "activeSession.stats")
        XCTAssertTrue(stats.waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "activeSession.rest").waitForExistence(timeout: 8))
        let statsBeforeUnconfirmedInput = resolvedText(of: stats)
        typeInto(in: app, identifier: "activeSession.weight", text: "40")
        typeInto(in: app, identifier: "activeSession.reps", text: "6")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(element(in: app, identifier: "activeSession.rest").waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["activeSession.finish"].isHittable, "B-D9 keeps finish available with the keyboard")
        XCTAssertEqual(
            resolvedText(of: stats),
            statsBeforeUnconfirmedInput,
            "unconfirmed input must not change completed stats (P0-D11)"
        )
        XCTAssertFalse(
            element(in: app, identifier: "activeSession.setState.draft").exists,
            "unconfirmed input is not a persisted draft row"
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "activeSession.setState.completed").count,
            1
        )

        addExercise(in: app, name: "引体向上", modeIdentifier: "activeSession.mode.reps")
        tapVisible(in: app, identifier: "activeSession.exercise.at.1")
        typeInto(in: app, identifier: "activeSession.reps", text: "8")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))

        addExercise(in: app, name: "平板支撑", modeIdentifier: "activeSession.mode.duration")
        tapExerciseNamed(in: app, "平板支撑", fallbackIdentifier: "activeSession.exercise.at.2")
        typeInto(in: app, identifier: "activeSession.duration", text: "30")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")

        addUnilateralExercise(in: app, name: "单侧测试动作")
        tapExerciseNamed(in: app, "单侧测试动作", fallbackIdentifier: "activeSession.exercise.at.3")
        XCTAssertTrue(element(in: app, identifier: "activeSession.splitSides").waitForExistence(timeout: 8))
        tapControl(in: app, identifier: "activeSession.splitSides", label: nil)
        typeInto(in: app, identifier: "activeSession.left", text: "20")
        typeInto(in: app, identifier: "activeSession.right", text: "22")
        typeInto(in: app, identifier: "activeSession.reps", text: "8")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))
    }

    func testContinueTrainingDeleteAndUndo() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)

        addExercise(in: app, name: "杠铃深蹲", modeIdentifier: "activeSession.mode.weightReps")
        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        addConfirmedWeightRepsSet(in: app, weight: "0", reps: "5")
        XCTAssertTrue(element(in: app, identifier: "activeSession.set.at.0").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))

        popToStudentList(in: app)
        resumeInProgressSession(in: app)
        assertActiveSession(in: app)
        XCTAssertTrue(app.staticTexts["杠铃深蹲"].waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "activeSession.set.at.0").exists)
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").exists)

        addExercise(in: app, name: "平板支撑", modeIdentifier: "activeSession.mode.duration")
        tapVisible(in: app, identifier: "activeSession.exercise.at.1")
        typeInto(in: app, identifier: "activeSession.duration", text: "30")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")

        XCTAssertEqual(
            exerciseNames(in: app),
            ["杠铃深蹲", "平板支撑"],
            "exercises remain in add order (P0-D9)"
        )

        tapExerciseNamed(in: app, "杠铃深蹲", fallbackIdentifier: "activeSession.exercise.at.0")
        let deleteRow = element(in: app, identifier: "activeSession.exercise.at.0")
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 8))
        deleteRow.swipeLeft()
        tapControl(in: app, identifier: "activeSession.deleteExercise", label: nil)
        XCTAssertTrue(
            element(in: app, identifier: "activeSession.deleteExerciseConfirm").waitForExistence(timeout: 8),
            "deleting an exercise with a completed set must require confirmation"
        )
        XCTAssertTrue(app.staticTexts["杠铃深蹲"].exists)
        tapVisible(in: app, identifier: "activeSession.deleteExerciseConfirm")
        assertExerciseListed(in: app, name: "平板支撑")
        XCTAssertFalse(app.staticTexts["杠铃深蹲"].exists)

        let remainingStats = element(in: app, identifier: "activeSession.stats")
        XCTAssertTrue(remainingStats.waitForExistence(timeout: 8))
        let statsBeforeUndo = resolvedText(of: remainingStats)
        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        typeInto(in: app, identifier: "activeSession.duration", text: "45")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")
        let undoRow = element(in: app, identifier: "activeSession.set.at.1")
        XCTAssertTrue(undoRow.waitForExistence(timeout: 8))
        let statsAfterConfirm = resolvedText(of: remainingStats)
        XCTAssertNotEqual(statsAfterConfirm, statsBeforeUndo)
        tapUndo(row: undoRow)
        XCTAssertTrue(
            undoRow.waitForNonExistence(timeout: 8),
            "undo removes the just-confirmed group (P0-D11)"
        )
        XCTAssertEqual(
            resolvedText(of: remainingStats),
            statsBeforeUndo,
            "undo removes the group from completed stats"
        )
        XCTAssertTrue(
            resolvedText(of: element(in: app, identifier: "activeSession.duration")).contains("45"),
            "undo returns the removed value to the input form"
        )

        let completedRow = element(in: app, identifier: "activeSession.set.at.0")
        completedRow.swipeLeft()
        tapVisible(in: app, identifier: "activeSession.set.delete.at.0")
        let deletionUndo = app.buttons["activeSession.set.undo.at.0"]
        XCTAssertTrue(deletionUndo.waitForExistence(timeout: 3), "B2 deletion must expose FCUndoRow")
        deletionUndo.tap()
        XCTAssertTrue(completedRow.waitForExistence(timeout: 8))
        XCTAssertEqual(resolvedText(of: remainingStats), statsBeforeUndo, "undo restores the completed group")

        app.revealLowerContent()
        tapControl(in: app, identifier: "activeSession.createSection", label: nil)
        typeInto(in: app, identifier: "activeSession.sectionName", text: "B1分区")
        tapControl(in: app, identifier: "activeSession.createSection.submit", label: nil)

        tapExerciseNamed(in: app, "平板支撑", fallbackIdentifier: "activeSession.exercise.at.0")
        let moveRow = element(in: app, identifier: "activeSession.exercise.at.0")
        XCTAssertTrue(moveRow.waitForExistence(timeout: 8))
        moveRow.swipeLeft()
        tapControl(in: app, identifier: "activeSession.moveToSection", label: nil)
        let sectionChoice = app.buttons["B1分区"]
        XCTAssertTrue(sectionChoice.waitForExistence(timeout: 8))
        sectionChoice.tap()
        XCTAssertTrue(
            app.staticTexts["B1分区"].waitForExistence(timeout: 8),
            "moved exercise must render under the created section (P0-D13)"
        )

        let sectionMenu = app.buttons["更多操作"]
        XCTAssertTrue(sectionMenu.waitForExistence(timeout: 8))
        sectionMenu.tap()
        let deleteSection = app.buttons["删除分区"]
        XCTAssertTrue(deleteSection.waitForExistence(timeout: 8))
        deleteSection.tap()
        tapVisible(in: app, identifier: "activeSession.deleteSection.moveOut")
        XCTAssertTrue(app.staticTexts["B1分区"].waitForNonExistence(timeout: 8))
        assertExerciseListed(in: app, name: "平板支撑")
        XCTAssertTrue(completedRow.exists, "deleting a section must keep its exercise and completed group")
    }

    func testEmptySessionAbandonAndUnconfirmedInputDoesNotBlockFinish() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)

        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)
        XCTAssertTrue(element(in: app, identifier: "activeSession.emptyHint").waitForExistence(timeout: 8))

        tapControl(in: app, identifier: "activeSession.finish", label: "结束训练")
        XCTAssertTrue(
            element(in: app, identifier: "activeSession.abandonConfirm").waitForExistence(timeout: 8),
            "empty session finish must require abandon confirmation"
        )
        XCTAssertTrue(element(in: app, identifier: "activeSession.root").exists)
        tapControl(in: app, identifier: "activeSession.abandonConfirm", label: "放弃训练")
        assertNotInTraining(in: app)

        if !app.buttons["studentDetail.startTraining"].waitForExistence(timeout: 2) {
            XCTAssertTrue(app.staticTexts["林青"].waitForExistence(timeout: 8))
            app.staticTexts["林青"].firstMatch.tap()
        }
        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)

        addExercise(in: app, name: "杠铃深蹲", modeIdentifier: "activeSession.mode.weightReps")
        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        addConfirmedWeightRepsSet(in: app, weight: "0", reps: "5")
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))

        let stats = element(in: app, identifier: "activeSession.stats")
        XCTAssertTrue(stats.waitForExistence(timeout: 8))
        let statsBeforeUnconfirmedInput = resolvedText(of: stats)
        typeInto(in: app, identifier: "activeSession.weight", text: "40")
        XCTAssertFalse(element(in: app, identifier: "activeSession.setState.draft").exists)
        XCTAssertTrue(element(in: app, identifier: "activeSession.weight").exists)
        XCTAssertEqual(resolvedText(of: stats), statsBeforeUnconfirmedInput)

        tapControl(in: app, identifier: "activeSession.finish", label: "结束训练")
        XCTAssertTrue(
            element(in: app, identifier: "sessionSummary.root").waitForExistence(timeout: 8),
            "unconfirmed input must not create a draft gate; finish reaches the summary"
        )
        XCTAssertFalse(element(in: app, identifier: "studentList.inProgress").exists)
        XCTAssertFalse(element(in: app, identifier: "studentDetail.continueTraining").exists)
    }

    func testTrainingFlowRemainsUsableWithAccessibilityContentSize() {
        let app = launchIsolatedApp(
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXL",
            ]
        )
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)

        assertHittableTarget(in: app, identifier: "activeSession.addExercise", label: "添加动作")
        assertHittableTarget(in: app, identifier: "activeSession.finish", label: "结束训练")
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
        let emptyAddByID = app.buttons["studentList.emptyAdd"]
        let addByLabel = app.buttons["添加学员"]
        let empty = app.staticTexts["还没有学员"]
        let nav = app.navigationBars["学员"]
        if !addByID.exists, !emptyAddByID.exists, !addByLabel.exists, !empty.exists {
            let studentsTab = app.buttons["学员"]
            if studentsTab.waitForExistence(timeout: 2) {
                studentsTab.tap()
            }
        }
        XCTAssertTrue(
            emptyAddByID.waitForExistence(timeout: 2)
                || addByID.waitForExistence(timeout: 8)
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
        app.revealLowerContent()
        let noteField = app.textFields["studentEditor.privateCoachNote"]
        if noteField.waitForExistence(timeout: 2) {
            noteField.tap()
            noteField.typeText(note)
        }
    }

    private func skipOnboarding(in app: XCUIApplication) {
        if app.buttons["firstLaunch.coach"].waitForExistence(timeout: 8) { app.buttons["firstLaunch.coach"].tap() }
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 8))
        app.buttons["onboarding.skip"].tap()
        waitForStudentList(in: app)
    }

    private func addStudentLinQing(in app: XCUIApplication) {
        let emptyAdd = app.buttons["studentList.emptyAdd"]
        let add = app.buttons["studentList.add"]
        if emptyAdd.waitForExistence(timeout: 2) {
            emptyAdd.tap()
        } else {
            XCTAssertTrue(add.waitForExistence(timeout: 8))
            add.tap()
        }
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
        XCTAssertFalse(app.staticTexts["此入口已保留，具体内容不在本里程碑展开。"].exists)
    }

    private func assertNotInTraining(in app: XCUIApplication) {
        XCTAssertFalse(element(in: app, identifier: "activeSession.root").waitForExistence(timeout: 2))
        XCTAssertFalse(element(in: app, identifier: "studentList.inProgress").exists)
        XCTAssertFalse(element(in: app, identifier: "studentDetail.continueTraining").exists)
        XCTAssertFalse(app.buttons["继续训练"].exists)
    }

    private func popToStudentList(in app: XCUIApplication) {
        for _ in 0..<5 {
            if app.buttons["studentList.add"].exists || app.buttons["studentList.inProgress"].exists {
                waitForStudentList(in: app)
                return
            }
            let back = app.buttons["返回"]
            if back.waitForExistence(timeout: 2) {
                back.tap()
            } else {
                break
            }
        }
        waitForStudentList(in: app)
    }

    private func resumeInProgressSession(in app: XCUIApplication) {
        if element(in: app, identifier: "studentList.inProgress").waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: "studentList.inProgress")
            return
        }
        if app.buttons["继续训练"].waitForExistence(timeout: 2) {
            app.buttons["继续训练"].tap()
            return
        }
        if app.staticTexts["林青"].waitForExistence(timeout: 8) {
            app.staticTexts["林青"].firstMatch.tap()
        }
        tapControl(in: app, identifier: "studentDetail.continueTraining", label: "继续训练")
    }

    private func addExercise(in app: XCUIApplication, name: String, modeIdentifier: String) {
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
            assertExerciseListed(in: app, name: name)
            return
        }
        tapVisible(in: app, identifier: modeIdentifier)
        tapControl(in: app, identifier: "activeSession.saveExercise", label: "保存动作")
        assertExerciseListed(in: app, name: name)
    }

    private func addUnilateralExercise(in app: XCUIApplication, name: String) {
        tapControl(in: app, identifier: "activeSession.addExercise", label: "添加动作")
        typeInto(in: app, identifier: "activeSession.exerciseName", text: name)
        tapVisible(in: app, identifier: "activeSession.mode.weightReps")
        let unilateralRow = element(in: app, identifier: "activeSession.newExercise.unilateral")
        XCTAssertTrue(unilateralRow.waitForExistence(timeout: 8))
        let unilateralToggle = app.switches.firstMatch
        XCTAssertTrue(unilateralToggle.waitForExistence(timeout: 8))
        unilateralToggle.tap()
        tapControl(in: app, identifier: "activeSession.saveExercise", label: "保存动作")
        assertExerciseListed(in: app, name: name)
    }

    private func assertExerciseListed(in app: XCUIApplication, name: String) {
        app.revealLowerContent()
        let byText = app.staticTexts[name]
        let byLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", name)
        ).firstMatch
        XCTAssertTrue(
            byText.waitForExistence(timeout: 8) || byLabel.waitForExistence(timeout: 8),
            "exercise \(name) must appear in the session list"
        )
    }

    private func exerciseNames(in app: XCUIApplication) -> [String] {
        XCTAssertFalse(
            element(in: app, identifier: "activeSession.exercise.at.2").exists, "expected exactly two exercises")
        // Use the same exact identifier matcher as tapVisible for each
        // expected index, preserving both the name and order assertions.
        return (0..<2).map { index in
            let header = element(in: app, identifier: "activeSession.exercise.at.\(index)")
            XCTAssertTrue(header.waitForExistence(timeout: 8), "missing exercise at index \(index)")
            return String(header.label.split(separator: "，", maxSplits: 1, omittingEmptySubsequences: true).first ?? "")
        }
    }

    private func addConfirmedWeightRepsSet(in app: XCUIApplication, weight: String, reps: String) {
        typeInto(in: app, identifier: "activeSession.weight", text: weight)
        typeInto(in: app, identifier: "activeSession.reps", text: reps)
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")
    }

    private func tapUndo(row: XCUIElement) {
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        let undoButton = row.buttons["撤销"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 3), "the row undo must be a visible control")
        undoButton.tap()
    }

    private func tapExerciseNamed(in app: XCUIApplication, _ name: String, fallbackIdentifier: String) {
        app.revealLowerContent()
        let labeled = app.staticTexts[name]
        if labeled.waitForExistence(timeout: 2), labeled.firstMatch.isHittable {
            labeled.firstMatch.tap()
            return
        }
        let byLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", name)
        ).firstMatch
        if byLabel.waitForExistence(timeout: 2), byLabel.isHittable {
            byLabel.tap()
            return
        }
        tapVisible(in: app, identifier: fallbackIdentifier)
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
                app.revealLowerContent()
            }
            button.tap()
            return
        }
        XCTFail("missing \(identifier)")
    }

    private func typeInto(in app: XCUIApplication, identifier: String, text: String) {
        let field = app.textFields[identifier]
        let target = field.waitForExistence(timeout: 2) ? field : element(in: app, identifier: identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 8), "missing field \(identifier)")
        if !target.isHittable {
            app.revealLowerContent()
        }
        target.tap()
        // P0-D1/D2 auto-fill the previous values. Backspace the complete
        // field before typing so this helper never appends to the prefill.
        target.typeText(String(repeating: "\u{8}", count: 32))
        target.typeText(text)
    }

    private func resolvedText(of item: XCUIElement) -> String {
        var parts = [item.label]
        if let value = item.value as? String {
            parts.append(value)
        }
        return parts.joined(separator: " ")
    }

    private func assertHittableTarget(in app: XCUIApplication, identifier: String, label: String) {
        var target = element(in: app, identifier: identifier)
        if !target.waitForExistence(timeout: 8) {
            target = app.buttons[label]
            XCTAssertTrue(target.waitForExistence(timeout: 8), "missing \(identifier) / \(label)")
        }
        if !target.isHittable {
            app.revealLowerContent()
        }
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        let hittable = matches.allElementsBoundByIndex.last(where: \.isHittable) ?? (target.isHittable ? target : nil)
        XCTAssertNotNil(hittable, "\(identifier) must remain hittable at Accessibility XL")
        if let frame = hittable?.frame {
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertGreaterThanOrEqual(frame.width, 44)
        }
    }
}
