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

    /// B-D9 / Δ12: hide the bar for the keyboard, then clear an ended rest
    /// through the view model on dismissal; an active rest can reappear.
    func testRestBarHidesForKeyboardAndDismissesEndedRestOnKeyboardHide() throws {
        let text = try source("Features/ActiveSession/ActiveSessionView.swift").joined(separator: "\n")
        XCTAssertTrue(text.contains("@State private var isKeyboardVisible = false"))
        XCTAssertFalse(text.contains("keyboardDismissedAt"))
        XCTAssertTrue(text.contains("UIResponder.keyboardWillShowNotification"))
        XCTAssertTrue(text.contains("UIResponder.keyboardWillHideNotification"))
        XCTAssertTrue(text.contains("if !isKeyboardVisible,"))
        XCTAssertTrue(text.contains("let restTimer = viewModel.restTimer"))
        XCTAssertTrue(text.contains("!isKeyboardVisible && viewModel.restTimer != nil"))
        XCTAssertFalse(text.contains("!restTimer.isFinished(at: Date())"))

        let showStart = try XCTUnwrap(text.range(of: "UIResponder.keyboardWillShowNotification"))
        let hideStart = try XCTUnwrap(text.range(of: "UIResponder.keyboardWillHideNotification"))
        let showHandler = text[showStart.lowerBound..<hideStart.lowerBound]
        let afterHide = text[hideStart.lowerBound...]
        let hideEnd = afterHide.range(of: "\n        .onDisappear")?.lowerBound ?? afterHide.endIndex
        let hideHandler = afterHide[..<hideEnd]
        XCTAssertTrue(showHandler.contains("isKeyboardVisible = true"))
        XCTAssertTrue(
            hideHandler.contains(
                "if viewModel.restTimer?.isFinished(at: Date()) == true {\n                viewModel.dismissRest()\n            }"
            )
        )
        XCTAssertTrue(hideHandler.contains("isKeyboardVisible = false"))
        XCTAssertFalse(showHandler.contains("restTimer = nil"))
        XCTAssertFalse(showHandler.contains("dismissRest()"))
        XCTAssertFalse(hideHandler.contains("restTimer = nil"))

        let safeAreaStart = try XCTUnwrap(text.range(of: ".safeAreaInset(edge: .bottom)"))
        let finishMarker = try XCTUnwrap(
            text.range(of: "FCAccessibilityID.activeSessionFinish", range: safeAreaStart.upperBound..<text.endIndex)
        )
        let restBranchEnd = try XCTUnwrap(
            text.range(
                of: "\n                    }\n                    FCButton(",
                range: safeAreaStart.upperBound..<finishMarker.lowerBound)
        )
        XCTAssertLessThan(restBranchEnd.lowerBound, finishMarker.lowerBound)
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
        XCTAssertTrue(list.contains("templateEditor.deleteExercise"))

        XCTAssertFalse(list.contains("Button(String(localized: \"templateEditor.removeExercise\"))"))
        XCTAssertTrue(text.contains("templateEditor.moveToUnsectioned"), "the move menu remains available")
    }

    /// B-D2 keeps the pre-existing full-screen typed-name student deletion;
    /// every other destructive action row must first set its shared-dialog binding.
    func testDestructiveActionRowsOnlyPresentTheirConfirmation() throws {
        let features = appRoot().appendingPathComponent("Features")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: features, includingPropertiesForKeys: nil))
        let pattern = try NSRegularExpression(
            pattern: #"FCActionRow\([^{}]*?role:\s*\.destructive[^{}]*?\)\s*\{([^}]+)\}"#
        )
        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let actionRange = try XCTUnwrap(Range(match.range(at: 1), in: text))
                let action = text[actionRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if url.lastPathComponent == "StudentEditorView.swift" {
                    XCTAssertEqual(action, "cover = .delete")
                    XCTAssertTrue(text.contains("DeleteStudentFlow"))
                } else {
                    XCTAssertTrue(action.hasSuffix(" = true"), "\(url.lastPathComponent): \(action)")
                    let binding = String(action.dropLast(" = true".count))
                    XCTAssertTrue(
                        text.contains(".fcConfirmationDialog(isPresented: $\(binding))"),
                        "\(url.lastPathComponent) must present the shared dialog bound to \(binding)"
                    )
                }
                count += 1
            }
        }
        XCTAssertEqual(count, 7, "audit new destructive rows rather than silently allowing them")
    }

    func testBodyHistoryKeepsUndoVisibleAndUsesDestructiveSwipes() throws {
        let text = try source("Features/BodyData/BodyMeasurementEntryView.swift").joined(separator: "\n")
        XCTAssertTrue(text.contains("FCUndoRow("))
        XCTAssertTrue(text.contains("bodyMeasurementUndo(pending.measurement.id)"))
        XCTAssertTrue(text.contains(".swipeActions(edge: .trailing"))
        XCTAssertTrue(text.contains(".tint(FCSemanticColors.statusDestructive)"))
        XCTAssertFalse(text.contains("bodyMeasurementDeleteConfirm"))
        XCTAssertFalse(text.contains("pendingDeleteID"))
        XCTAssertTrue(text.contains("FCMoreMenu(accessibilityIdentifier: FCAccessibilityID.bodyMeasurementMore)"))
    }

    /// B-D7 / Δ11: every translated zh-Hans value follows the approved direct,
    /// specific tone. The catalog is intentionally scanned without a whitelist.
    func testChineseLocalizationsUseB7Tone() throws {
        let url = appRoot().appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        var scannedValues = 0
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            let zhHans = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any], key)
            let values = Self.localizedValues(in: zhHans)
            XCTAssertFalse(values.isEmpty, "missing zh-Hans value for \(key)")
            for value in values {
                assertB7Tone(value, source: "Localizable.xcstrings:\(key)")
                scannedValues += 1
            }
        }
        XCTAssertGreaterThan(scannedValues, 0)

    }

    /// B-D7 / Δ11: direct Chinese string literals in the application are
    /// scanned separately from the catalog. Comments and synthetic DebugSeed
    /// fixtures are excluded because they are not user-facing copy.
    func testChineseAppStringLiteralsUseB7Tone() throws {
        let appDirectory = appRoot()
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: appDirectory, includingPropertiesForKeys: nil)
        )
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !url.lastPathComponent.hasSuffix("DebugSeed.swift") else { continue }
            var blockCommentDepth = 0
            let text = try String(contentsOf: url, encoding: .utf8)
            let literals = Self.extractSwiftStringLiterals(
                from: text,
                blockCommentDepth: &blockCommentDepth
            )
            XCTAssertEqual(blockCommentDepth, 0, "unclosed block comment in \(url.path)")
            for literal in literals where literal.range(of: "[一-龥]", options: .regularExpression) != nil {
                assertB7Tone(literal, source: url.path)
            }
        }
    }

    func testStringLiteralScannerKeepsURLsRawAndMultilineButSkipsComments() {
        let sample =
            "// \"请\"\n"
            + "let url = \"https://example.com/*请*/\"\n"
            + "let raw = #\"原始 // 请 /* 请 */\"#\n"
            + "let multiline = \"\"\"\n多行请\n\"\"\"\n"
            + "let rawMultiline = #\"\"\"原始多行请\"\"\"#\n"
            + "/* \"请\" */\n"
        var blockCommentDepth = 0
        let literals = Self.extractSwiftStringLiterals(
            from: sample,
            blockCommentDepth: &blockCommentDepth
        )

        XCTAssertEqual(blockCommentDepth, 0)
        XCTAssertTrue(literals.contains("https://example.com/*请*/"))
        XCTAssertTrue(literals.contains("原始 // 请 /* 请 */"))
        XCTAssertTrue(literals.contains("\n多行请\n"))
        XCTAssertTrue(literals.contains("原始多行请"))
        XCTAssertFalse(literals.contains("请"), "comment text must not be extracted")
    }

    // MARK: - Helpers

    /// Include plural and device variations as well as top-level string units.
    private static func localizedValues(in node: [String: Any]) -> [String] {
        var values: [String] = []
        if let unit = node["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            values.append(value)
        }
        for (key, child) in node where key != "stringUnit" {
            if let dictionary = child as? [String: Any] {
                values += localizedValues(in: dictionary)
            }
        }
        return values
    }

    private func assertB7Tone(_ value: String, source: String) {
        let forbidden: [(String, String)] = [
            ("您", "称呼必须使用「你」或省略人称"),
            ("请", "避免使用「请」"),
            ("操作失败", "说明具体失败结果，不使用「操作失败」"),
            ("！", "避免使用感叹号"),
            ("!", "避免使用感叹号"),
        ]
        for (needle, rule) in forbidden where value.contains(needle) {
            XCTFail("\(source) contains \(needle): \(rule); value=\(value)")
        }
        if let particle = Self.toneParticle(in: value) {
            XCTFail("\(source) contains \(particle): 避免语气词; value=\(value)")
        }
    }

    /// Sentence-final particles only: a particle followed by the end of the
    /// text, whitespace or punctuation. Words such as 哈克机 stay legal.
    private static func toneParticle(in value: String) -> String? {
        let pattern = "[吧呢哦啦呀哈](?=$|[\\s。，、；：？！?!,.;:）)」』…~])"
        guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
        return String(value[range])
    }

    func testToneParticleScanIgnoresWordsLikeHackMachine() {
        XCTAssertNil(Self.toneParticle(in: "哈克机提踵"))
        XCTAssertNil(Self.toneParticle(in: "哈克深蹲，4 组"))
        XCTAssertEqual(Self.toneParticle(in: "开始记录第一堂课吧"), "吧")
        XCTAssertEqual(Self.toneParticle(in: "已保存哦。"), "哦")
        XCTAssertEqual(Self.toneParticle(in: "好了呢 再看看"), "呢")
    }

    private static func extractSwiftStringLiterals(
        from source: String,
        blockCommentDepth: inout Int
    ) -> [String] {
        let characters = Array(source)
        var literals: [String] = []
        var index = 0

        while index < characters.count {
            if blockCommentDepth > 0 {
                if hasToken("/*", at: index, in: characters) {
                    blockCommentDepth += 1
                    index += 2
                } else if hasToken("*/", at: index, in: characters) {
                    blockCommentDepth -= 1
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            if hasToken("//", at: index, in: characters) {
                while index < characters.count, characters[index] != "\n" {
                    index += 1
                }
                continue
            }
            if hasToken("/*", at: index, in: characters) {
                blockCommentDepth = 1
                index += 2
                continue
            }

            var hashCount = 0
            while index + hashCount < characters.count, characters[index + hashCount] == "#" {
                hashCount += 1
            }
            let quoteIndex = index + hashCount
            guard quoteIndex < characters.count, characters[quoteIndex] == "\"" else {
                index += 1
                continue
            }

            let isMultiline = hasToken("\"\"\"", at: quoteIndex, in: characters)
            let openingLength = isMultiline ? 3 : 1
            let contentStart = quoteIndex + openingLength
            var cursor = contentStart
            var closingIndex: Int?
            while cursor < characters.count {
                if isMultiline,
                    hasToken("\"\"\"", at: cursor, in: characters),
                    hasHashes(hashCount, at: cursor + 3, in: characters)
                {
                    closingIndex = cursor
                    break
                }
                if !isMultiline,
                    characters[cursor] == "\"",
                    hasHashes(hashCount, at: cursor + 1, in: characters),
                    hashCount > 0 || !isEscaped(cursor, in: characters)
                {
                    closingIndex = cursor
                    break
                }
                cursor += (characters[cursor] == "\\" && hashCount == 0) ? 2 : 1
            }

            guard let closingIndex else {
                literals.append(String(characters[contentStart..<characters.count]))
                index = characters.count
                continue
            }
            literals.append(String(characters[contentStart..<closingIndex]))
            index = closingIndex + (isMultiline ? 3 : 1) + hashCount
        }

        return literals
    }

    private static func hasToken(_ token: String, at index: Int, in characters: [Character]) -> Bool {
        let tokenCharacters = Array(token)
        guard index >= 0, index + tokenCharacters.count <= characters.count else { return false }
        return tokenCharacters.indices.allSatisfy { characters[index + $0] == tokenCharacters[$0] }
    }

    private static func hasHashes(_ count: Int, at index: Int, in characters: [Character]) -> Bool {
        guard index >= 0, index + count <= characters.count else { return false }
        return (0..<count).allSatisfy { characters[index + $0] == "#" }
    }

    private static func isEscaped(_ index: Int, in characters: [Character]) -> Bool {
        var backslashes = 0
        var cursor = index - 1
        while cursor >= 0, characters[cursor] == "\\" {
            backslashes += 1
            cursor -= 1
        }
        return backslashes.isMultiple(of: 2) == false
    }

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
