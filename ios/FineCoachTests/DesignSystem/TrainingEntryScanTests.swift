import XCTest

/// P0 training-page simplification (implementation-map P0-D11, Δ1/Δ2/Δ6):
/// deterministic static scan of the set-entry area so the removed controls
/// do not come back.
///
/// - The entry area (`SetEditor`) and the set row (`FCSetRow`) use only
///   design-system buttons; a text-titled system `Button` renders system blue
///   (Δ2, Δ6). The only exception is `.accessibilityActions`, which renders
///   nothing.
/// - Outside edit mode the entry area has exactly one primary `FCButton`
///   (「确认」, Δ1); edit mode has 「保存」 plus an `FCLinkButton` 「取消」.
///
/// Dialog, toolbar and menu buttons elsewhere in `Features/` are system
/// chrome and are out of this scan's scope.
final class TrainingEntryScanTests: XCTestCase {
    func testEntryAreaAndSetRowUseOnlyDesignSystemButtons() throws {
        for path in ["Features/ActiveSession/SetEditor.swift", "DesignSystem/Components/FCSetRow.swift"] {
            let lines = try source(path)
            var inAccessibilityActions = false
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                if trimmed.hasPrefix(".accessibilityActions") {
                    inAccessibilityActions = true
                } else if trimmed.hasPrefix(".") || trimmed == "}" && line.hasPrefix("        }") {
                    inAccessibilityActions = false
                }
                let range = NSRange(line.startIndex..., in: line)
                if !inAccessibilityActions, Self.bareButton.firstMatch(in: line, range: range) != nil {
                    XCTFail("\(path):\(index + 1): bare system Button in the entry area: \(trimmed)")
                }
            }
        }
    }

    func testEntryAreaHasOneConfirmOutsideEditMode() throws {
        let text = try source("Features/ActiveSession/SetEditor.swift").joined(separator: "\n")
        let editStart = try XCTUnwrap(text.range(of: "if isEditMode {"))
        let elseStart = try XCTUnwrap(text.range(of: "} else {", range: editStart.upperBound..<text.endIndex))
        let editBranch = text[editStart.upperBound..<elseStart.lowerBound]
        let afterElse = text[elseStart.upperBound...]
        let confirmEnd = afterElse.range(of: "\n        }\n")?.lowerBound ?? afterElse.endIndex
        let confirmBranch = afterElse[..<confirmEnd]

        XCTAssertEqual(occurrences(of: "FCButton(", in: confirmBranch), 1, "entry area must offer only 「确认」")
        XCTAssertTrue(confirmBranch.contains("session.action.confirmSet"))
        XCTAssertEqual(occurrences(of: "FCButton(", in: editBranch), 1, "edit mode has one primary 「保存」")
        XCTAssertEqual(occurrences(of: "FCLinkButton(", in: editBranch), 1, "edit mode cancels with a link button")
        XCTAssertEqual(
            occurrences(of: "FCButton(", in: Substring(text)), 2,
            "no other primary button in the entry area"
        )
    }

    /// Section deletion uses shared confirmation; move-to-section remains a choice menu.
    func testOnlyMoveSectionSystemDialogRemains() throws {
        let expected: Set<String> = [
            #"Features/ActiveSession/ActiveSessionView.swift|String(localized: "activeSession.moveToSection")"#
        ]
        let features = appRoot().appendingPathComponent("Features")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: features, includingPropertiesForKeys: nil))
        var matches: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            let relativePath = url.path.replacingOccurrences(of: features.path + "/", with: "Features/")
            for (index, line) in lines.enumerated() where line.contains(".confirmationDialog(") {
                let titleLine = index + 1 < lines.count ? lines[index + 1].trimmingCharacters(in: .whitespaces) : ""
                let title = titleLine.hasSuffix(",") ? String(titleLine.dropLast()) : titleLine
                let match = "\(relativePath)|\(title)"
                matches.append(match)
                XCTAssertTrue(expected.contains(match), "unexpected system confirmation dialog at \(match)")
            }
        }
        XCTAssertEqual(matches.count, expected.count)
        XCTAssertEqual(Set(matches), expected)
    }

    func testSectionDeleteConfirmationOnlyMovesExercisesOut() throws {
        for path in ["Features/ActiveSession/ActiveSessionView.swift", "Features/Templates/TemplateEditorView.swift"] {
            let text = try source(path).joined(separator: "\n")
            XCTAssertTrue(text.contains("section.delete.title"))
            XCTAssertTrue(text.contains("section.delete.message"))
            XCTAssertTrue(text.contains(".moveExercisesTo(sectionID: nil)"))
            XCTAssertFalse(text.contains("DeleteSectionDeleteExercises"))
            XCTAssertFalse(text.contains("templateEditor.deleteSection.deleteExercises"))
        }
    }

    func testSectionHeadersOfferDeletionOnlyInsideMoreMenu() throws {
        for (path, function, identifier) in [
            (
                "Features/ActiveSession/ActiveSessionView.swift", "private func sectionHeaderIfNeeded",
                "activeSessionSectionMore"
            ),
            ("Features/Templates/TemplateEditorView.swift", "private func sectionBlock", "templateEditorSectionMore"),
        ] {
            let text = try source(path).joined(separator: "\n")
            let start = try XCTUnwrap(text.range(of: function)).lowerBound
            let end = text.range(of: "\n    private ", range: start..<text.endIndex)?.lowerBound ?? text.endIndex
            let header = text[start..<end]
            XCTAssertTrue(header.contains("FCMoreMenu(accessibilityIdentifier: FCAccessibilityID.\(identifier)"))
            XCTAssertTrue(header.contains("role: .destructive"))
            XCTAssertTrue(header.contains("viewModel.requestDeleteSection(section)"))
            XCTAssertFalse(header.contains("foregroundStyle(FCSemanticColors.statusDestructive)"))
        }
    }

    /// Template exercises are list items: deletion is exposed by the native
    /// trailing swipe action, while the move-to-section menu remains visible.
    func testTemplateExerciseRowsUseDestructiveSwipeDelete() throws {
        let text = try source("Features/Templates/TemplateEditorView.swift").joined(separator: "\n")
        let start = try XCTUnwrap(text.range(of: "private func exerciseList(")).lowerBound
        let end =
            text.range(
                of: "\n    private func estimatedExerciseListHeight", range: start..<text.endIndex
            )?.lowerBound ?? text.endIndex
        let list = text[start..<end]

        XCTAssertTrue(list.contains(".swipeActions(edge: .trailing, allowsFullSwipe: true)"))
        XCTAssertTrue(list.contains("Button(role: .destructive)"))
        XCTAssertTrue(list.contains(".tint(FCSemanticColors.statusDestructive)"))
        XCTAssertTrue(list.contains("FCAccessibilityID.templateEditorRemoveExercise(exercise.id)"))
        XCTAssertTrue(list.contains("viewModel.removeExercise(exercise.id)"))
        XCTAssertTrue(list.contains("templateEditor.removeExercise"))

        XCTAssertFalse(list.contains("Button(String(localized: \"templateEditor.removeExercise\"))"))
        XCTAssertTrue(text.contains("templateEditor.moveToUnsectioned"), "the move menu remains available")
    }

    // MARK: - Helpers

    /// A system `Button` with a text title (`Button("…")`,
    /// `Button(String(localized:…))`), which renders system blue. `FCButton(`
    /// and `FCLinkButton(` do not match, nor does a `Button(action:) { … }`
    /// whose label sets design-system colors itself.
    // swiftlint:disable:next force_try
    private static let bareButton = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])Button\((?:String\(localized|")"#
    )

    private func occurrences(of needle: String, in text: Substring) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func appRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp")
    }

    /// Lines of a file under `ios/FineCoachApp`, resolved from this file's
    /// `#filePath` like `NumberFormatScanTests`.
    private func source(_ relativePath: String) throws -> [String] {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
            .appendingPathComponent("FineCoachApp")
        let url = appDir.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("cannot resolve \(relativePath) from #filePath: \(url.path)")
        }
        return try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
    }
}
