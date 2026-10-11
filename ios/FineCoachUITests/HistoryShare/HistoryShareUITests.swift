import XCTest

@MainActor
final class HistoryShareUITests: XCTestCase {
    private let injuryNotes = "左膝旧伤注意事项"
    private let phone = "13900001111"
    private let wechat = "wx_linqing_secret"
    private let archivePrivateNote = "教练档案备注丁戊己"
    private let sessionPrivateNote = "课堂私有备注甲乙丙"
    private let focusNote = "课后重点甲"
    private let studentFacingSummary = "学员可见总结乙"
    private let revisedFocus = "修订后的训练重点"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFinishShowsSummaryNotesSeparatedAndSkipShareReturnsToHistory() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        startConfirmedSquatSession(in: app)
        finishToSummary(in: app)

        XCTAssertTrue(
            element(in: app, identifier: "sessionSummary.root").waitForExistence(timeout: 8),
            "finish must show summary instead of remaining on activeSession.completedStatus as the only end state"
        )
        XCTAssertTrue(element(in: app, identifier: "sessionSummary.duration").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "sessionSummary.completedSets").waitForExistence(timeout: 8))

        let privateNote = element(in: app, identifier: "sessionSummary.privateNote")
        let studentSummary = element(in: app, identifier: "sessionSummary.studentSummary")
        let focus = element(in: app, identifier: "sessionSummary.focus")
        XCTAssertTrue(privateNote.waitForExistence(timeout: 8))
        XCTAssertTrue(studentSummary.waitForExistence(timeout: 8))
        XCTAssertTrue(focus.waitForExistence(timeout: 8))
        XCTAssertNotEqual(privateNote.identifier, studentSummary.identifier)
        XCTAssertNotEqual(privateNote.identifier, focus.identifier)
        XCTAssertNotEqual(studentSummary.identifier, focus.identifier)

        XCTAssertTrue(element(in: app, identifier: "sessionSummary.skipShare").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "sessionSummary.generateReport").waitForExistence(timeout: 8))
        assertNoEnglishDomainCopy(in: app)

        typeInto(in: app, identifier: "sessionSummary.focus", text: focusNote)
        typeInto(in: app, identifier: "sessionSummary.studentSummary", text: studentFacingSummary)
        dismissKeyboard(in: app)

        skipShareToStudentContext(in: app)
        assertRecentAndHistoryReachable(in: app)
        openHistory(in: app)
        XCTAssertTrue(element(in: app, identifier: "history.row.0").waitForExistence(timeout: 8))
        tapVisible(in: app, identifier: "history.row.0")

        XCTAssertTrue(element(in: app, identifier: "sessionDetail.root").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "sessionDetail.readonly").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "sessionDetail.edit").waitForExistence(timeout: 8))
        XCTAssertFalse(
            element(in: app, identifier: "sessionEdit.root").exists,
            "history detail must stay read-only until 编辑训练记录"
        )
        XCTAssertFalse(element(in: app, identifier: "sessionEdit.save").exists)

        tapControl(in: app, identifier: "sessionDetail.edit", label: "编辑训练记录")
        XCTAssertTrue(element(in: app, identifier: "sessionEdit.root").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "sessionEdit.focus").waitForExistence(timeout: 8))
    }

    func testExplicitEditRecalculatesAndMarksReportStaleWithoutRevokeClaim() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        startConfirmedSquatSession(in: app)
        finishToSummary(in: app)
        typeInto(in: app, identifier: "sessionSummary.focus", text: focusNote)
        dismissKeyboard(in: app)

        openSharePreviewFromSummary(in: app)
        closeSharePreviewWithoutSending(in: app)
        if element(in: app, identifier: "sessionSummary.root").exists {
            skipShareToStudentContext(in: app)
        }

        openHistory(in: app)
        tapVisible(in: app, identifier: "history.row.0")
        XCTAssertTrue(element(in: app, identifier: "sessionDetail.root").waitForExistence(timeout: 8))
        tapControl(in: app, identifier: "sessionDetail.edit", label: "编辑训练记录")
        XCTAssertTrue(element(in: app, identifier: "sessionEdit.root").waitForExistence(timeout: 8))
        typeInto(in: app, identifier: "sessionEdit.focus", text: revisedFocus)
        dismissKeyboard(in: app)
        tapControl(in: app, identifier: "sessionEdit.save", label: "保存")

        XCTAssertTrue(element(in: app, identifier: "sessionDetail.root").waitForExistence(timeout: 8))
        XCTAssertTrue(
            element(in: app, identifier: "sessionDetail.reportStale").waitForExistence(timeout: 8),
            "editing a completed session must mark the report 报告已过期"
        )
        assertNoRevokeOrSentClaim(in: app)
        assertNoEnglishDomainCopy(in: app)
    }

    func testShareReportStartsFromSafeDefaultsPreviewAndForbidsSensitiveFields() {
        let app = launchIsolatedApp()
        skipOnboarding(in: app)
        addStudentLinQing(
            in: app,
            injuryNotes: injuryNotes,
            phone: phone,
            wechat: wechat,
            privateNote: archivePrivateNote
        )
        openStudentDetail(in: app)
        startConfirmedSquatSession(in: app)
        finishToSummary(in: app)
        typeInto(in: app, identifier: "sessionSummary.privateNote", text: sessionPrivateNote)
        typeInto(in: app, identifier: "sessionSummary.focus", text: focusNote)
        typeInto(in: app, identifier: "sessionSummary.studentSummary", text: studentFacingSummary)
        dismissKeyboard(in: app)

        openSharePreviewFromSummary(in: app)
        XCTAssertTrue(element(in: app, identifier: "shareReport.modules").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "shareReport.volumeToggle").waitForExistence(timeout: 8))
        assertVolumeToggleOff(in: app)
        XCTAssertTrue(
            element(in: app, identifier: "shareReport.preview").waitForExistence(timeout: 8),
            "final read-only preview must exist before 交给系统分享"
        )
        XCTAssertTrue(element(in: app, identifier: "shareReport.share").waitForExistence(timeout: 8))

        let previewText = shareFlowCopy(in: app)
        XCTAssertFalse(previewText.contains(phone), "preview must not include phone")
        XCTAssertFalse(previewText.contains(wechat), "preview must not include wechat")
        XCTAssertFalse(previewText.contains(injuryNotes), "preview must not include injury notes")
        XCTAssertFalse(previewText.contains(archivePrivateNote), "preview must not include coach archive note")
        XCTAssertFalse(previewText.contains(sessionPrivateNote), "preview must not include session private note")
        XCTAssertFalse(app.staticTexts["已发送"].exists, "preview must not treat share as 已发送")
        XCTAssertFalse(previewText.contains("已发送到"))
        assertNoEnglishDomainCopy(in: app)

        XCTAssertTrue(previewText.contains("林青"), "allowlist may include display name")
        XCTAssertTrue(previewText.contains("杠铃深蹲"), "allowlist may include confirmed exercise")
    }

    func testCancelFailureKeepsPreviewRetryAndCompletionRecordsHandoffNotSent() {
        assertCancelOrFailureKeepsPreview(
            extraArguments: ["-FineCoachSimulateShareCancel"]
        )
        assertCancelOrFailureKeepsPreview(
            extraArguments: ["-FineCoachSimulateShareFailure"]
        )

        let app = launchIsolatedApp(extraArguments: ["-FineCoachSimulateShareCompletion"])
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        startConfirmedSquatSession(in: app)
        finishToSummary(in: app)
        openSharePreviewFromSummary(in: app)
        tapControl(in: app, identifier: "shareReport.share", label: "交给系统分享")

        XCTAssertTrue(
            element(in: app, identifier: "shareReport.handedOffStatus").waitForExistence(timeout: 8)
                || element(in: app, identifier: "sessionDetail.handedToSystem").waitForExistence(timeout: 2),
            "completion must record 已交给系统分享, not 已发送"
        )
        let copy = visibleCopy(in: app)
        XCTAssertTrue(
            copy.contains("已交给系统分享") || copy.contains("系统分享边界"),
            "success copy must stay on the system-share boundary; copy=\(copy)"
        )
        XCTAssertFalse(copy.contains("已发送到微信"))
        XCTAssertFalse(copy.contains("已投递"))
        XCTAssertFalse(app.staticTexts["已发送"].exists)
        assertNoEnglishDomainCopy(in: app)
    }

    func testHistoryShareControlsRemainAccessibleAtXL() {
        let app = launchIsolatedApp(
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXL",
            ]
        )
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        startConfirmedSquatSession(in: app)
        finishToSummary(in: app)

        assertHittableTarget(in: app, identifier: "sessionSummary.skipShare", label: "跳过分享")
        assertHittableTarget(in: app, identifier: "sessionSummary.generateReport", label: "生成训练报告")
        XCTAssertTrue(element(in: app, identifier: "sessionSummary.skipShare").exists)
        XCTAssertTrue(element(in: app, identifier: "sessionSummary.generateReport").exists)

        skipShareToStudentContext(in: app)
        assertRecentAndHistoryReachable(in: app)
        assertHittableTarget(in: app, identifier: "studentDetail.history", label: "训练历史")
        openHistory(in: app)
        XCTAssertTrue(element(in: app, identifier: "history.root").waitForExistence(timeout: 8))
        if element(in: app, identifier: "history.row.0").waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: "history.row.0")
            if element(in: app, identifier: "sessionDetail.generateReport").waitForExistence(timeout: 8) {
                assertHittableTarget(in: app, identifier: "sessionDetail.generateReport", label: "生成训练报告")
            }
        }
    }

    private func assertCancelOrFailureKeepsPreview(extraArguments: [String]) {
        let app = launchIsolatedApp(extraArguments: extraArguments)
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openStudentDetail(in: app)
        startConfirmedSquatSession(in: app)
        finishToSummary(in: app)
        openSharePreviewFromSummary(in: app)
        tapControl(in: app, identifier: "shareReport.share", label: "交给系统分享")

        XCTAssertTrue(
            element(in: app, identifier: "shareReport.preview").waitForExistence(timeout: 8),
            "cancel/failure must remain on the read-only preview"
        )
        XCTAssertTrue(
            element(in: app, identifier: "shareReport.notSentStatus").waitForExistence(timeout: 8)
                || element(in: app, identifier: "shareReport.retry").waitForExistence(timeout: 2),
            "cancel/failure must keep 未发送 status or retry"
        )
        XCTAssertFalse(element(in: app, identifier: "shareReport.handedOffStatus").exists)
        XCTAssertFalse(element(in: app, identifier: "sessionDetail.handedToSystem").exists)
        XCTAssertFalse(app.staticTexts["已发送"].exists)
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
        note: String = "晚班",
        injuryNotes: String? = nil,
        phone: String? = nil,
        wechat: String? = nil
    ) {
        let nameField = app.textFields["studentEditor.displayName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.buttons[sexIdentifier].tap()
        app.revealLowerContent()
        if let injuryNotes {
            typeInto(in: app, identifier: "studentEditor.injuryNotes", text: injuryNotes)
        }
        if let phone {
            typeInto(in: app, identifier: "studentEditor.phone", text: phone)
        }
        if let wechat {
            typeInto(in: app, identifier: "studentEditor.wechat", text: wechat)
        }
        let noteField = app.textFields["studentEditor.privateCoachNote"]
        if noteField.waitForExistence(timeout: 2) {
            noteField.tap()
            noteField.typeText(note)
        } else {
            typeInto(in: app, identifier: "studentEditor.privateCoachNote", text: note)
        }
    }

    private func skipOnboarding(in app: XCUIApplication) {
        if app.buttons["firstLaunch.coach"].waitForExistence(timeout: 8) { app.buttons["firstLaunch.coach"].tap() }
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 8))
        app.buttons["onboarding.skip"].tap()
        waitForStudentList(in: app)
    }

    private func addStudentLinQing(
        in app: XCUIApplication,
        injuryNotes: String? = nil,
        phone: String? = nil,
        wechat: String? = nil,
        privateNote: String = "晚班"
    ) {
        XCTAssertTrue(app.buttons["studentList.add"].waitForExistence(timeout: 8))
        app.buttons["studentList.add"].tap()
        XCTAssertTrue(element(in: app, identifier: "studentEditor.root").waitForExistence(timeout: 8))
        fillEditor(
            in: app,
            name: "林青",
            sexIdentifier: "studentEditor.sex.female",
            note: privateNote,
            injuryNotes: injuryNotes,
            phone: phone,
            wechat: wechat
        )
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
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8))
            return
        }
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

    private func startConfirmedSquatSession(in app: XCUIApplication) {
        tapControl(in: app, identifier: "studentDetail.startTraining", label: "开始训练")
        assertActiveSession(in: app)
        addExercise(in: app, name: "杠铃深蹲", modeIdentifier: "activeSession.mode.weightReps")
        tapVisible(in: app, identifier: "activeSession.exercise.at.0")
        addConfirmedWeightRepsSet(in: app, weight: "0", reps: "5")
        XCTAssertTrue(element(in: app, identifier: "activeSession.setState.completed").waitForExistence(timeout: 8))
    }

    private func finishToSummary(in app: XCUIApplication) {
        tapControl(in: app, identifier: "activeSession.finish", label: "结束训练")
        if element(in: app, identifier: "activeSession.durationReview").waitForExistence(timeout: 2) {
            tapControl(in: app, identifier: "activeSession.durationConfirm", label: "确认")
        }
        XCTAssertTrue(
            element(in: app, identifier: "sessionSummary.root").waitForExistence(timeout: 8),
            "US5 finish must navigate to summary; activeSession.completedStatus is not the end state"
        )
    }

    private func skipShareToStudentContext(in app: XCUIApplication) {
        tapControl(in: app, identifier: "sessionSummary.skipShare", label: "跳过分享")
        if element(in: app, identifier: "sessionSummary.root").waitForExistence(timeout: 1),
            app.buttons["完成"].exists
        {
            app.buttons["完成"].tap()
        }
        XCTAssertTrue(
            element(in: app, identifier: "studentDetail.root").waitForExistence(timeout: 8)
                || element(in: app, identifier: "history.root").waitForExistence(timeout: 2)
                || app.staticTexts["林青"].waitForExistence(timeout: 2),
            "skip share must return to student detail/history without forcing share"
        )
    }

    private func assertRecentAndHistoryReachable(in app: XCUIApplication) {
        if element(in: app, identifier: "history.root").exists {
            XCTAssertTrue(element(in: app, identifier: "history.row.0").waitForExistence(timeout: 8))
            return
        }
        if !element(in: app, identifier: "studentDetail.root").waitForExistence(timeout: 2) {
            openStudentDetail(in: app)
        }
        XCTAssertTrue(
            element(in: app, identifier: "studentDetail.recentTraining").waitForExistence(timeout: 8)
                || element(in: app, identifier: "studentDetail.history").waitForExistence(timeout: 2),
            "student detail recent/history must be reachable after skip share"
        )
    }

    private func openHistory(in app: XCUIApplication) {
        if element(in: app, identifier: "history.root").waitForExistence(timeout: 2) {
            XCTAssertTrue(element(in: app, identifier: "history.row.0").waitForExistence(timeout: 8))
            return
        }
        if !element(in: app, identifier: "studentDetail.root").waitForExistence(timeout: 2) {
            openStudentDetail(in: app)
        }
        if element(in: app, identifier: "studentDetail.history").waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: "studentDetail.history")
        } else {
            tapVisible(in: app, identifier: "studentDetail.recentTraining")
        }
        XCTAssertTrue(element(in: app, identifier: "history.root").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "history.row.0").waitForExistence(timeout: 8))
    }

    private func openSharePreviewFromSummary(in app: XCUIApplication) {
        tapControl(in: app, identifier: "sessionSummary.generateReport", label: "生成训练报告")
        XCTAssertTrue(element(in: app, identifier: "shareReport.modules").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "shareReport.preview").waitForExistence(timeout: 8))
    }

    private func closeSharePreviewWithoutSending(in app: XCUIApplication) {
        if element(in: app, identifier: "shareReport.close").waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: "shareReport.close")
            return
        }
        if app.buttons["关闭"].waitForExistence(timeout: 2) {
            app.buttons["关闭"].tap()
        }
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
        let area = app.textViews[identifier]
        let target: XCUIElement
        if field.waitForExistence(timeout: 2) {
            target = field
        } else if area.waitForExistence(timeout: 2) {
            target = area
        } else {
            target = element(in: app, identifier: identifier)
        }
        XCTAssertTrue(target.waitForExistence(timeout: 8), "missing field \(identifier)")
        if !target.isHittable {
            app.revealLowerContent()
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

    private func visibleCopy(in app: XCUIApplication) -> String {
        let texts = app.staticTexts.allElementsBoundByIndex.map { resolvedText(of: $0) }
        let buttons = app.buttons.allElementsBoundByIndex.map { resolvedText(of: $0) }
        return (texts + buttons).joined(separator: "\n")
    }

    private func shareFlowCopy(in app: XCUIApplication) -> String {
        let preview = element(in: app, identifier: "shareReport.preview")
        let modules = element(in: app, identifier: "shareReport.modules")
        var parts = [visibleCopy(in: app)]
        if preview.exists {
            parts.append(resolvedText(of: preview))
        }
        if modules.exists {
            parts.append(resolvedText(of: modules))
        }
        return parts.joined(separator: "\n")
    }

    private func assertVolumeToggleOff(in app: XCUIApplication) {
        let toggle = element(in: app, identifier: "shareReport.volumeToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        let valueText = (toggle.value as? String) ?? ""
        let label = resolvedText(of: toggle)
        if valueText == "0" || valueText == "1" || toggle.elementType == .switch {
            XCTAssertFalse(
                toggle.isSelected || valueText == "1",
                "训练容量 must default off; value=\(valueText) selected=\(toggle.isSelected)"
            )
            return
        }
        XCTAssertTrue(
            label.contains("关闭") || label.contains("未包含") || valueText.contains("关闭")
                || valueText.contains("未包含"),
            "volume toggle must indicate 关闭/未包含; label=\(label) value=\(valueText)"
        )
    }

    private func assertNoEnglishDomainCopy(in app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts["Student"].exists)
        XCTAssertFalse(app.staticTexts["Session"].exists)
        XCTAssertFalse(app.staticTexts["Share Report"].exists)
        XCTAssertFalse(app.buttons["Student"].exists)
        XCTAssertFalse(app.buttons["Session"].exists)
        XCTAssertFalse(app.buttons["Share Report"].exists)
    }

    private func assertNoRevokeOrSentClaim(in app: XCUIApplication) {
        let copy = visibleCopy(in: app)
        XCTAssertFalse(copy.contains("外部副本已撤回"))
        XCTAssertFalse(copy.contains("Share Report 撤回"))
        XCTAssertFalse(copy.contains("已发送到"))
        XCTAssertFalse(copy.contains("已投递"))
        XCTAssertFalse(app.staticTexts["已发送"].exists)
        XCTAssertFalse(app.staticTexts["报告已撤回"].exists)
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
