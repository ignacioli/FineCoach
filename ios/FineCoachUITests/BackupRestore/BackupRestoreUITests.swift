import XCTest

/// US6 backup/restore UI contract (T098).
/// T108 must add `studentDetail.backup` (visible 备份与恢复 or 备份) on Student Detail and replace
/// `placeholder(.backup)` so that tap presents `backup.root`. T109 must honor the DEBUG launch args
/// used here for export/restore completion, cancel, and failure.
@MainActor
final class BackupRestoreUITests: XCTestCase {
    private let exportPassword = "备份口令甲乙丙丁"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExportRequiresPasswordCreateAndConfirmThenHandsFileToSystem() {
        assertExportCancelOrFailureKeepsRetry(extraArguments: ["-FineCoachSimulateBackupExportCancel"])
        assertExportCancelOrFailureKeepsRetry(extraArguments: ["-FineCoachSimulateBackupExportFailure"])

        let app = launchIsolatedApp(extraArguments: ["-FineCoachSimulateBackupExportCompletion"])
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openBackupFromStudentDetail(in: app)

        XCTAssertTrue(element(in: app, identifier: "backup.password").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "backup.passwordConfirm").waitForExistence(timeout: 8))
        assertPasswordHintUnrecoverable(in: app)
        fillMatchingExportPasswords(in: app)
        tapControl(in: app, identifier: "backup.export", label: "导出完整备份")

        XCTAssertTrue(
            element(in: app, identifier: "backup.exportStatus").waitForExistence(timeout: 8),
            "SimulateBackupExportCompletion must show backup.exportStatus"
        )
        let copy = backupFlowCopy(in: app)
        XCTAssertFalse(copy.contains("已发送"), "export success must not claim 已发送; copy=\(copy)")
        XCTAssertFalse(app.staticTexts["已发送"].exists)
        XCTAssertFalse(copy.contains("林青"), "backup flow visible copy must not include 林青")
        assertNoEnglishDomainCopy(in: app)
    }

    func testRestoreShowsReplaceWarningSuggestsBackupAndFailedKeepsRetry() {
        let app = launchIsolatedApp(extraArguments: ["-FineCoachSimulateRestoreFailure"])
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openBackupFromStudentDetail(in: app)
        revealRestoreRoot(in: app)

        XCTAssertTrue(element(in: app, identifier: "restore.root").waitForExistence(timeout: 8))
        let warning = element(in: app, identifier: "restore.warning")
        XCTAssertTrue(warning.waitForExistence(timeout: 8))
        let warningText = resolvedText(of: warning)
        XCTAssertTrue(
            warningText.contains("完整替换") || warningText.contains("将替换本机数据"),
            "restore.warning must mention 完整替换 / 将替换本机数据; copy=\(warningText)"
        )

        let suggest = element(in: app, identifier: "restore.suggestBackup")
        XCTAssertTrue(suggest.waitForExistence(timeout: 8))
        let suggestText = resolvedText(of: suggest)
        XCTAssertTrue(
            suggestText.contains("建议先备份") || visibleCopy(in: app).contains("建议先备份"),
            "restore.suggestBackup must mention 建议先备份; copy=\(suggestText)"
        )

        if element(in: app, identifier: "restore.password").waitForExistence(timeout: 2) {
            typeInto(in: app, identifier: "restore.password", text: exportPassword)
            dismissKeyboard(in: app)
        }
        tapControl(in: app, identifier: "restore.confirm", label: "恢复")

        XCTAssertTrue(
            element(in: app, identifier: "restore.failed").waitForExistence(timeout: 8)
                || element(in: app, identifier: "restore.retry").waitForExistence(timeout: 2),
            "SimulateRestoreFailure must keep restore.failed or restore.retry"
        )
        XCTAssertTrue(
            element(in: app, identifier: "restore.retry").waitForExistence(timeout: 8),
            "failed restore must keep 重试"
        )
        assertNoEnglishDomainCopy(in: app)

        returnToStudentListPreservingStore(in: app)
        XCTAssertTrue(
            app.staticTexts["林青"].waitForExistence(timeout: 8),
            "failed restore must leave current data unchanged (林青 still in the list)"
        )
    }

    func testBackupControlsAccessibleAtXL() {
        let app = launchIsolatedApp(
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXL",
            ]
        )
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openBackupFromStudentDetail(in: app)
        fillMatchingExportPasswords(in: app)

        XCTAssertTrue(element(in: app, identifier: "backup.export").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "backup.cancel").waitForExistence(timeout: 8))
        assertHittableTarget(in: app, identifier: "backup.export", label: "导出完整备份")
        assertHittableTarget(in: app, identifier: "backup.cancel", label: "取消")
        assertNoEnglishDomainCopy(in: app)
    }

    private func assertExportCancelOrFailureKeepsRetry(extraArguments: [String]) {
        let app = launchIsolatedApp(extraArguments: extraArguments)
        skipOnboarding(in: app)
        addStudentLinQing(in: app)
        openBackupFromStudentDetail(in: app)
        fillMatchingExportPasswords(in: app)
        tapControl(in: app, identifier: "backup.export", label: "导出完整备份")

        XCTAssertTrue(
            element(in: app, identifier: "backup.retry").waitForExistence(timeout: 8),
            "cancel/failure must keep backup.retry"
        )
        XCTAssertTrue(element(in: app, identifier: "backup.root").exists)
        XCTAssertFalse(app.staticTexts["已发送"].exists)
        assertNoEnglishDomainCopy(in: app)
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
        app.revealLowerContent()
        let noteField = app.textFields["studentEditor.privateCoachNote"]
        if noteField.waitForExistence(timeout: 2) {
            noteField.tap()
            noteField.typeText(note)
        } else {
            typeInto(in: app, identifier: "studentEditor.privateCoachNote", text: note)
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

    /// T108 must add this control on Student Detail. Current production navigates
    /// `placeholder(.backup)` from delete-flow backup only; that placeholder must be replaced.
    private func openBackupFromStudentDetail(in app: XCUIApplication) {
        openStudentDetail(in: app)
        if !element(in: app, identifier: "studentDetail.backup").waitForExistence(timeout: 2) {
            app.revealLowerContent()
        }
        tapBackupEntry(in: app)
        XCTAssertTrue(
            element(in: app, identifier: "backup.root").waitForExistence(timeout: 8),
            "T108 must replace placeholder(.backup) so studentDetail.backup presents backup.root"
        )
        assertNoEnglishDomainCopy(in: app)
    }

    private func tapBackupEntry(in app: XCUIApplication) {
        let byID = app.descendants(matching: .any).matching(identifier: "studentDetail.backup")
        if byID.firstMatch.waitForExistence(timeout: 8) {
            tapVisible(in: app, identifier: "studentDetail.backup")
            return
        }
        if app.buttons["备份与恢复"].waitForExistence(timeout: 2) {
            app.buttons["备份与恢复"].tap()
            return
        }
        if app.buttons["备份"].waitForExistence(timeout: 2) {
            app.buttons["备份"].tap()
            return
        }
        XCTFail(
            "missing studentDetail.backup / 备份与恢复. T108 must add this control on Student Detail."
        )
    }

    private func fillMatchingExportPasswords(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "backup.password").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: "backup.passwordConfirm").waitForExistence(timeout: 8))
        typeInto(in: app, identifier: "backup.password", text: exportPassword)
        typeInto(in: app, identifier: "backup.passwordConfirm", text: exportPassword)
        dismissKeyboard(in: app)
    }

    private func assertPasswordHintUnrecoverable(in app: XCUIApplication) {
        let hint = element(in: app, identifier: "backup.passwordHint")
        XCTAssertTrue(hint.waitForExistence(timeout: 8))
        let text = resolvedText(of: hint)
        XCTAssertTrue(
            text.contains("不可恢复") || text.contains("无法找回"),
            "backup.passwordHint must mention 不可恢复/无法找回; copy=\(text)"
        )
        XCTAssertFalse(text.contains("Keychain"), "hint must not claim Keychain storage of the password")
        XCTAssertFalse(text.contains("钥匙串"), "hint must not claim 钥匙串 storage of the password")
    }

    private func revealRestoreRoot(in app: XCUIApplication) {
        if element(in: app, identifier: "restore.root").waitForExistence(timeout: 2) {
            return
        }
        tapControl(in: app, identifier: "restore.importer", label: "从备份恢复")
        XCTAssertTrue(
            element(in: app, identifier: "restore.root").waitForExistence(timeout: 8),
            "T109 must present restore.root after restore.importer"
        )
    }

    private func returnToStudentListPreservingStore(in app: XCUIApplication) {
        for _ in 0..<8 {
            if app.buttons["studentList.add"].exists || app.staticTexts["林青"].exists {
                waitForStudentList(in: app)
                return
            }
            if element(in: app, identifier: "backup.cancel").waitForExistence(timeout: 1) {
                tapVisible(in: app, identifier: "backup.cancel")
                continue
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists {
                back.tap()
                continue
            }
            break
        }
        waitForStudentList(in: app)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        if app.keyboards.element.exists {
            app.swipeDown()
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
        let secure = app.secureTextFields[identifier]
        let field = app.textFields[identifier]
        let area = app.textViews[identifier]
        let target: XCUIElement
        if secure.waitForExistence(timeout: 2) {
            target = secure
        } else if field.waitForExistence(timeout: 2) {
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

    private func backupFlowCopy(in app: XCUIApplication) -> String {
        var parts = [visibleCopy(in: app)]
        for identifier in ["backup.root", "backup.exportStatus", "backup.passwordHint"] {
            let item = element(in: app, identifier: identifier)
            if item.exists {
                parts.append(resolvedText(of: item))
            }
        }
        return parts.joined(separator: "\n")
    }

    private func assertNoEnglishDomainCopy(in app: XCUIApplication) {
        for word in ["Student", "Session", "Share Report", "Backup", "Restore"] {
            XCTAssertFalse(app.staticTexts[word].exists, "visible copy must not be English \(word)")
            XCTAssertFalse(app.buttons[word].exists, "visible copy must not be English \(word)")
            XCTAssertFalse(app.navigationBars[word].exists, "visible copy must not be English \(word)")
        }
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
