import XCTest

@MainActor
final class CoreTrainingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStartTrainingRecordsModesCopyAndPendingExcludedFromStats() {
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

        tapControl(in: app, identifier: "activeSession.copyPrevious", label: "复制上一组")
        XCTAssertTrue(element(in: app, identifier: "activeSession.set.at.1").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.pending").waitForExistence(timeout: 8))

        let stats = element(in: app, identifier: "activeSession.stats")
        XCTAssertTrue(stats.waitForExistence(timeout: 8))
        let statsText = resolvedText(of: stats)
        XCTAssertTrue(
            statsText.contains("1"),
            "pending copy must not count as completed; stats=\(statsText)"
        )
        XCTAssertFalse(
            statsText.contains("2"),
            "pending copy must not raise completed count to 2; stats=\(statsText)"
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "activeSession.setState.completed").count,
            1
        )

        addExercise(in: app, name: "引体向上", modeIdentifier: "activeSession.mode.reps")
        tapVisible(in: app, identifier: "activeSession.exercise.at.1")
        tapControl(in: app, identifier: "activeSession.addSet", label: "添加组")
        typeInto(in: app, identifier: "activeSession.reps", text: "8")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))

        addExercise(in: app, name: "平板支撑", modeIdentifier: "activeSession.mode.duration")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["平板支撑"].waitForExistence(timeout: 8))
        app.staticTexts["平板支撑"].firstMatch.tap()
        tapControl(in: app, identifier: "activeSession.addSet", label: "添加组")
        typeInto(in: app, identifier: "activeSession.duration", text: "30")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")

        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        tapControl(in: app, identifier: "activeSession.addSet", label: "添加组")
        typeInto(in: app, identifier: "activeSession.weight", text: "0")
        typeInto(in: app, identifier: "activeSession.reps", text: "5")
        tapVisible(in: app, identifier: "activeSession.sideBilateral")
        typeInto(in: app, identifier: "activeSession.left", text: "20")
        typeInto(in: app, identifier: "activeSession.right", text: "22")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))
    }

    func testContinueTrainingReorderDeleteAndUndo() {
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
        tapControl(in: app, identifier: "activeSession.addSet", label: "添加组")
        typeInto(in: app, identifier: "activeSession.duration", text: "30")
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")

        let firstBefore = element(in: app, identifier: "activeSession.exercise.at.0")
        XCTAssertTrue(firstBefore.waitForExistence(timeout: 8))
        let labelBefore = firstBefore.label
        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        tapVisible(in: app, identifier: "activeSession.moveDown")
        var labelAfter = element(in: app, identifier: "activeSession.exercise.at.0").label
        if labelAfter == labelBefore {
            tapVisible(in: app, identifier: "activeSession.exercise.at.1")
            tapVisible(in: app, identifier: "activeSession.moveUp")
            labelAfter = element(in: app, identifier: "activeSession.exercise.at.0").label
        }
        XCTAssertNotEqual(labelAfter, labelBefore)

        tapExerciseNamed(in: app, "杠铃深蹲", fallbackIdentifier: "activeSession.exercise.at.0")
        tapControl(in: app, identifier: "activeSession.deleteExercise", label: nil)
        XCTAssertTrue(
            element(in: app, identifier: "activeSession.deleteExerciseConfirm").waitForExistence(timeout: 8),
            "deleting an exercise with a completed set must require confirmation"
        )
        XCTAssertTrue(app.staticTexts["杠铃深蹲"].exists)
        tapVisible(in: app, identifier: "activeSession.deleteExerciseConfirm")
        XCTAssertTrue(app.staticTexts["平板支撑"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["杠铃深蹲"].exists)

        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        if element(in: app, identifier: "activeSession.set.at.0").waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: "activeSession.set.at.0")
        }
        tapControl(in: app, identifier: "activeSession.undoSet", label: "撤销")
        XCTAssertTrue(
            element(in: app, identifier: "activeSession.setState.pending").waitForExistence(timeout: 8)
                || element(in: app, identifier: "activeSession.setState.draft").waitForExistence(timeout: 2)
        )
        XCTAssertFalse(element(in: app, identifier: "activeSession.setState.completed").exists)
    }

    func testEmptySessionAbandonAndDraftFinishGate() {
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

        tapControl(in: app, identifier: "activeSession.addSet", label: "添加组")
        typeInto(in: app, identifier: "activeSession.weight", text: "40")
        XCTAssertTrue(
            element(in: app, identifier: "activeSession.setState.draft").waitForExistence(timeout: 8)
                || element(in: app, identifier: "activeSession.weight").exists
        )

        tapControl(in: app, identifier: "activeSession.finish", label: "结束训练")
        let discard = element(in: app, identifier: "activeSession.discardDrafts")
        let returnToDrafts = element(in: app, identifier: "activeSession.returnToDrafts")
        XCTAssertTrue(
            discard.waitForExistence(timeout: 8) || returnToDrafts.waitForExistence(timeout: 2),
            "unfinished drafts must block finish until discard or return"
        )
        XCTAssertFalse(element(in: app, identifier: "activeSession.completedStatus").exists)

        if !discard.exists, returnToDrafts.exists {
            tapControl(in: app, identifier: "activeSession.returnToDrafts", label: "返回处理")
            XCTAssertTrue(element(in: app, identifier: "activeSession.root").waitForExistence(timeout: 8))
            tapControl(in: app, identifier: "activeSession.finish", label: "结束训练")
        }
        XCTAssertTrue(element(in: app, identifier: "activeSession.discardDrafts").waitForExistence(timeout: 8))
        XCTAssertFalse(element(in: app, identifier: "activeSession.completedStatus").exists)
        tapControl(in: app, identifier: "activeSession.discardDrafts", label: "丢弃未完成")

        if element(in: app, identifier: "activeSession.root").waitForExistence(timeout: 2),
            element(in: app, identifier: "activeSession.finish").exists
        {
            tapControl(in: app, identifier: "activeSession.finish", label: "结束训练")
        }

        XCTAssertTrue(
            element(in: app, identifier: "activeSession.completedStatus").waitForExistence(timeout: 8)
                || app.buttons["studentDetail.startTraining"].waitForExistence(timeout: 2)
                || element(in: app, identifier: "studentDetail.root").waitForExistence(timeout: 2)
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
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists {
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
        tapVisible(in: app, identifier: modeIdentifier)
        tapControl(in: app, identifier: "activeSession.saveExercise", label: "保存动作")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8))
    }

    private func addConfirmedWeightRepsSet(in app: XCUIApplication, weight: String, reps: String) {
        tapControl(in: app, identifier: "activeSession.addSet", label: "添加组")
        typeInto(in: app, identifier: "activeSession.weight", text: weight)
        typeInto(in: app, identifier: "activeSession.reps", text: reps)
        tapControl(in: app, identifier: "activeSession.confirmSet", label: "确认")
    }

    private func tapExerciseNamed(in app: XCUIApplication, _ name: String, fallbackIdentifier: String) {
        let labeled = app.staticTexts[name]
        if labeled.waitForExistence(timeout: 2), labeled.firstMatch.isHittable {
            labeled.firstMatch.tap()
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
                app.swipeUp()
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
            app.swipeUp()
        }
        target.tap()
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
            app.swipeUp()
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
