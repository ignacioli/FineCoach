package com.ignacioli.finecoach

import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

internal object ScopeBoundaryPolicy {
    // Deliberately scans imports, aliases, calls and resource declarations, not
    // business words in text. Generic DS demonstration text is permitted.
    private val forbidden = mapOf(
        "static-shortcut" to Regex("<\\s*shortcuts?\\b|android\\.app\\.shortcuts", RegexOption.IGNORE_CASE),
        "dynamic-shortcut" to Regex("\\b(?:ShortcutManager(?:Compat)?|ShortcutInfo(?:Compat)?|setDynamicShortcuts|addDynamicShortcuts|pushDynamicShortcut)\\b"),
        "pinned-shortcut" to Regex("\\b(?:requestPinShortcut|createShortcutResultIntent|ACTION_CREATE_SHORTCUT|INSTALL_SHORTCUT)\\b"),
        "assistant" to Regex("actions\\.intent\\.|com\\.google\\.android\\.actions|<\\s*(?:capability|capability-binding|app-actions)\\b|VoiceInteraction(?:Service|Session)|AppActions", RegexOption.IGNORE_CASE),
        // S1-D08: notification capability relaxation is owned by T013c, not T001.
        "notifications" to Regex("\\b(?:NotificationManager(?:Compat)?|NotificationChannel|NotificationCompat|AlarmManager|POST_NOTIFICATIONS|SCHEDULE_EXACT_ALARM|USE_EXACT_ALARM)\\b"),
        "widgets" to Regex("\\b(?:AppWidgetProvider|AppWidgetManager|GlanceAppWidget|RemoteViews|LiveActivity)\\b|android\\.appwidget"),
        "containers-and-sharing" to Regex("\\b(?:FcbkCodec|FcpaCodec|BackupFileCodec|ArchiveFileCodec|ShareReport|FileProvider|ACTION_SEND|ACTION_SEND_MULTIPLE|ACTION_OPEN_DOCUMENT|ACTION_CREATE_DOCUMENT)\\b", RegexOption.IGNORE_CASE),
        "deferred-business-entry" to Regex("\\b(?:Appointment|Trend|Insight|Backup|Archive|ShareReport)(?:Screen|Route|Activity)\\b"),
    )
    private fun isMainActivity(path: String): Boolean = path.endsWith("MainActivity.kt")

    private data class ParsedCall(val signature: String, val arguments: String)

    internal fun stripCommentsPreservingStrings(source: String): String {
        val out = StringBuilder(source.length)
        var index = 0
        var mode = Mode.CODE
        var escaped = false
        var blockDepth = 0

        fun startsWithAt(token: String): Boolean = source.regionMatches(index, token, 0, token.length)

        while (index < source.length) {
            val current = source[index]
            when (mode) {
                Mode.CODE -> {
                    when {
                        startsWithAt("//") -> {
                            mode = Mode.LINE_COMMENT
                            index += 2
                        }
                        startsWithAt("/*") -> {
                            mode = Mode.BLOCK_COMMENT
                            blockDepth = 1
                            index += 2
                        }
                        startsWithAt("\"\"\"") -> {
                            mode = Mode.TRIPLE_QUOTED_STRING
                            out.append("\"\"\"")
                            index += 3
                        }
                        current == '"' -> {
                            mode = Mode.STRING
                            escaped = false
                            out.append(current)
                            index += 1
                        }
                        current == '\'' -> {
                            mode = Mode.CHAR_LITERAL
                            escaped = false
                            out.append(current)
                            index += 1
                        }
                        else -> {
                            out.append(current)
                            index += 1
                        }
                    }
                }
                Mode.LINE_COMMENT -> {
                    if (current == '\n') {
                        out.append('\n')
                        mode = Mode.CODE
                    }
                    index += 1
                }
                Mode.BLOCK_COMMENT -> {
                    when {
                        startsWithAt("/*") -> {
                            blockDepth += 1
                            index += 2
                        }
                        startsWithAt("*/") -> {
                            blockDepth -= 1
                            index += 2
                            if (blockDepth == 0) mode = Mode.CODE
                        }
                        current == '\n' -> {
                            out.append('\n')
                            index += 1
                        }
                        else -> index += 1
                    }
                }
                Mode.STRING -> {
                    out.append(current)
                    if (escaped) {
                        escaped = false
                    } else {
                        when (current) {
                            '\\' -> escaped = true
                            '"' -> mode = Mode.CODE
                        }
                    }
                    index += 1
                }
                Mode.TRIPLE_QUOTED_STRING -> {
                    if (startsWithAt("\"\"\"")) {
                        out.append("\"\"\"")
                        mode = Mode.CODE
                        index += 3
                    } else {
                        out.append(current)
                        index += 1
                    }
                }
                Mode.CHAR_LITERAL -> {
                    out.append(current)
                    if (escaped) {
                        escaped = false
                    } else {
                        when (current) {
                            '\\' -> escaped = true
                            '\'' -> mode = Mode.CODE
                        }
                    }
                    index += 1
                }
            }
        }
        return out.toString()
    }

    private enum class Mode {
        CODE,
        LINE_COMMENT,
        BLOCK_COMMENT,
        STRING,
        TRIPLE_QUOTED_STRING,
        CHAR_LITERAL,
    }

    private fun splitTopLevelArguments(arguments: String): List<String> {
        val values = mutableListOf<String>()
        var depthParen = 0
        var depthBrace = 0
        var depthBracket = 0
        var inString = false
        var escaped = false
        var start = 0
        for (index in arguments.indices) {
            val current = arguments[index]
            if (inString) {
                if (current == '"' && !escaped) inString = false
                escaped = current == '\\' && !escaped
                if (current != '\\') escaped = false
                continue
            }
            when (current) {
                '"' -> inString = true
                '(' -> depthParen += 1
                ')' -> depthParen = maxOf(0, depthParen - 1)
                '{' -> depthBrace += 1
                '}' -> depthBrace = maxOf(0, depthBrace - 1)
                '[' -> depthBracket += 1
                ']' -> depthBracket = maxOf(0, depthBracket - 1)
                ',' -> if (depthParen == 0 && depthBrace == 0 && depthBracket == 0) {
                    values += arguments.substring(start, index).trim()
                    start = index + 1
                }
            }
        }
        val tail = arguments.substring(start).trim()
        if (tail.isNotEmpty()) values += tail
        return values
    }

    private fun collectCalls(source: String, name: String): List<ParsedCall> {
        val calls = mutableListOf<ParsedCall>()
        var index = 0
        while (index < source.length) {
            val found = source.indexOf(name, index)
            if (found < 0) break
            val before = found - 1
            val after = found + name.length
            val isWordBoundaryBefore = before < 0 || !(source[before].isLetterOrDigit() || source[before] == '_')
            val isWordBoundaryAfter = after >= source.length || !(source[after].isLetterOrDigit() || source[after] == '_')
            if (!isWordBoundaryBefore || !isWordBoundaryAfter) {
                index = found + name.length
                continue
            }
            var cursor = found + name.length
            while (cursor < source.length && source[cursor].isWhitespace()) cursor += 1
            if (cursor >= source.length) break
            if (source[cursor] == '<') {
                var genericDepth = 1
                cursor += 1
                while (cursor < source.length && genericDepth > 0) {
                    when (source[cursor]) {
                        '<' -> genericDepth += 1
                        '>' -> genericDepth -= 1
                    }
                    cursor += 1
                }
                while (cursor < source.length && source[cursor].isWhitespace()) cursor += 1
            }
            if (cursor >= source.length || source[cursor] != '(') {
                index = found + name.length
                continue
            }
            val signature = source.substring(found, cursor).trim()
            val argumentStart = cursor + 1
            var depth = 1
            var inString = false
            var escaped = false
            cursor = argumentStart
            while (cursor < source.length && depth > 0) {
                val current = source[cursor]
                if (inString) {
                    if (current == '"' && !escaped) inString = false
                    escaped = current == '\\' && !escaped
                    if (current != '\\') escaped = false
                    cursor += 1
                    continue
                }
                if (current == '"') {
                    inString = true
                    cursor += 1
                    continue
                }
                when (current) {
                    '(' -> depth += 1
                    ')' -> depth -= 1
                }
                cursor += 1
            }
            require(depth == 0) { "Unapproved product route: malformed call in $name" }
            val arguments = source.substring(argumentStart, cursor - 1)
            calls += ParsedCall(signature = signature, arguments = arguments)
            index = cursor
        }
        return calls
    }

    private fun routeExpression(arguments: String, named: String): String? {
        val topLevel = splitTopLevelArguments(arguments)
        val namedArgument = topLevel.firstOrNull { it.startsWith("$named =") }
        return if (namedArgument != null) namedArgument.substringAfter('=').trim() else null
    }

    private fun isApprovedRouteExpression(path: String, expression: String): Boolean {
        val candidate = expression.trim()
        if (Regex("S1Routes\\.[A-Z][A-Z0-9_]*").matches(candidate)) return true
        if (isMainActivity(path) && candidate == "\"placeholder\"") return true
        return false
    }

    private fun isApprovedNavigateExpression(expression: String): Boolean {
        val candidate = expression.trim()
        if (Regex("^S1Routes\\.[A-Z][A-Z0-9_]*$").matches(candidate)) return true
        if (Regex("^S1Routes\\.[a-z][A-Za-z0-9_]*\\s*\\(.*\\)$").matches(candidate)) return true
        return false
    }

    private fun ensureComposableRoutesUseS1Contracts(path: String, sourceWithoutComments: String) {
        require(!Regex("\\bcomposable\\s*<").containsMatchIn(sourceWithoutComments)) { "Unapproved product route: $path" }
        collectCalls(sourceWithoutComments, "composable").forEach { call ->
            require(!call.signature.contains('<')) { "Unapproved product route: $path" }
            val route = routeExpression(call.arguments, "route")
                ?: splitTopLevelArguments(call.arguments).firstOrNull()
                ?: ""
            require(isApprovedRouteExpression(path, route)) { "Unapproved product route: $path" }
        }
    }

    private fun ensureNavigationRoutesUseS1Contracts(path: String, sourceWithoutComments: String) {
        collectCalls(sourceWithoutComments, "navigation").forEach { call ->
            val route = routeExpression(call.arguments, "route")
                ?: splitTopLevelArguments(call.arguments).firstOrNull()
                ?: ""
            require(isApprovedRouteExpression(path, route)) { "Unapproved product route: $path" }
            routeExpression(call.arguments, "startDestination")?.let { start ->
                require(isApprovedRouteExpression(path, start)) { "Unapproved product route: $path" }
            }
        }
        collectCalls(sourceWithoutComments, "NavHost").forEach { call ->
            val start = routeExpression(call.arguments, "startDestination") ?: ""
            require(start.isNotEmpty() && isApprovedRouteExpression(path, start)) { "Unapproved product route: $path" }
        }
        collectCalls(sourceWithoutComments, "navigate").forEach { call ->
            val route = routeExpression(call.arguments, "route")
                ?: splitTopLevelArguments(call.arguments).firstOrNull()
                ?: ""
            require(route.isNotEmpty() && isApprovedNavigateExpression(route)) { "Unapproved product route: $path" }
        }
        require(!Regex("\\bnavDeepLink\\s*[({<]").containsMatchIn(sourceWithoutComments)) { "Unapproved product route: $path" }
        require(!Regex("\\bdeepLinks\\s*=").containsMatchIn(sourceWithoutComments)) { "Unapproved product route: $path" }
    }

    fun validateSource(path: String, source: String) {
        val sourceWithoutComments = stripCommentsPreservingStrings(source)
        require(!path.substringAfterLast('/').equals("shortcuts.xml", ignoreCase = true)) { "Static shortcuts resource: $path" }
        forbidden.forEach { (kind, pattern) -> require(!pattern.containsMatchIn(sourceWithoutComments)) { "$kind: $path" } }
        ensureComposableRoutesUseS1Contracts(path, sourceWithoutComments)
        ensureNavigationRoutesUseS1Contracts(path, sourceWithoutComments)
        // Extension members on S1Routes (in any file) would add route names outside the frozen object.
        require(!Regex("""\b(?:val|var|fun)\s+(?:<[^>]+>\s*)?S1Routes(?:\.Companion)?\.""").containsMatchIn(sourceWithoutComments)) {
            "S1Routes extension member: $path"
        }
    }
    fun validateManifest(manifest: Element) {
        fun Element.attr(name: String) = getAttributeNS(MergedPrivacyInputs.ANDROID, name)
        val nodes = manifest.getElementsByTagName("*")
        for (index in 0 until nodes.length) {
            val node = nodes.item(index) as Element
            require(!node.attr("name").contains("shortcuts", ignoreCase = true)) { "Shortcut metadata/entry" }
            require(!Regex("actions\\.intent|com\\.google\\.android\\.actions", RegexOption.IGNORE_CASE)
                .containsMatchIn(node.attr("name"))) { "Assistant metadata/entry" }
            if (node.tagName == "intent-filter") {
                val parent = node.parentNode as Element
                val entries = MergedPrivacyInputs.children(node)
                val pairs = entries.map { it.tagName to it.attr("name") }
                when (parent.attr("name")) {
                    "com.ignacioli.finecoach.MainActivity" -> require(pairs.size == 2 && pairs.toSet() == setOf(
                        "action" to "android.intent.action.MAIN", "category" to "android.intent.category.LAUNCHER"))
                    "androidx.profileinstaller.ProfileInstallReceiver" -> require(pairs.size == 1 &&
                        pairs.single().first == "action" && pairs.single().second in setOf(
                            "androidx.profileinstaller.action.INSTALL_PROFILE", "androidx.profileinstaller.action.SKIP_FILE",
                            "androidx.profileinstaller.action.SAVE_PROFILE", "androidx.profileinstaller.action.BENCHMARK_OPERATION"))
                    else -> require(false) { "Unapproved system intent-filter" }
                }
            }
        }
        CapabilityPolicy.validate(manifest, if (manifest.getElementsByTagName("activity").let { activities ->
            (0 until activities.length).any { (activities.item(it) as Element).attr("name") == "androidx.activity.ComponentActivity" }
        }) "debug" else "release")
    }
}

class ScopeBoundaryTests {
    @Test fun allProductionSourcesAndMergedResourcesStayInsideS1Boundary() {
        val src = File(MergedPrivacyInputs.property("sourceRoot"))
        val roots = src.listFiles().orEmpty().filter { it.isDirectory && it.name !in setOf("test", "androidTest") } +
            MergedPrivacyInputs.variants.map { File(MergedPrivacyInputs.property("resources.$it")) }
        val files = roots.flatMap { root ->
            require(root.isDirectory)
            root.walkTopDown().filter { it.isFile && it.extension in setOf("kt", "java", "xml") }.toList()
        }
        assertTrue(files.isNotEmpty())
        files.forEach { ScopeBoundaryPolicy.validateSource(it.invariantSeparatorsPath, it.readText()) }
    }
    @Test fun bothMergedManifestsHaveOnlyShellAndApprovedLibraryEntries() {
        MergedPrivacyInputs.variants.forEach { ScopeBoundaryPolicy.validateManifest(MergedPrivacyInputs.manifest(it)) }
    }
    @Test fun rejectsStaticShortcutResource() = reject("<shortcuts><shortcut /></shortcuts>")
    @Test fun rejectsShortcutFileEvenWhenEmpty() {
        assertThrows(IllegalArgumentException::class.java) { ScopeBoundaryPolicy.validateSource("res/xml/shortcuts.xml", "<resources />") }
    }
    @Test fun rejectsDynamicShortcutRegistrationIncludingCompatAndAliases() {
        listOf("ShortcutManager", "ShortcutInfo.Builder", "ShortcutManagerCompat.pushDynamicShortcut()",
            "setDynamicShortcuts(items)", "addDynamicShortcuts(items)", "import android.content.pm.ShortcutManager as FictionalManager")
            .forEach(::reject)
    }
    @Test fun rejectsPinnedShortcutRegistration() {
        listOf("requestPinShortcut(item, callback)", "createShortcutResultIntent(item)", "ACTION_CREATE_SHORTCUT", "INSTALL_SHORTCUT").forEach(::reject)
    }
    @Test fun rejectsShortcutMetadataInMergedManifest() = mutateManifest("<meta-data android:name=\"android.app.shortcuts\" android:resource=\"@xml/fictional\" />")
    @Test fun rejectsDedicatedIntentFilter() = mutateManifest("<intent-filter><action android:name=\"fictional.START_SESSION\" /></intent-filter>", activity = true)
    @Test fun rejectsAssistantAndAppActionsSourceAndMetadata() {
        listOf("<capability android:name=\"actions.intent.START_EXERCISE\" />", "<capability-binding />", "<app-actions />",
            "VoiceInteractionService", "AppActions", "com.google.android.actions").forEach(::reject)
        mutateManifest("<meta-data android:name=\"com.google.android.actions\" android:resource=\"@xml/fictional\" />")
    }
    @Test fun rejectsDeferredS2ToS5RoutesIncludingIndirectRegistration() {
        listOf("appointment", "trend", "backup", "archive", "shareReport", "widget").forEach { reject("composable(\"$it\") {}") }
        reject("composable(/*x*/ \"appointment\") {}")
        reject("val q='\"'; val p='\\''; val b='\\\\'; val s=\"//\"; composable(\"appointment\") {}")
        reject("composable(route = fictionalRoute) {}")
        reject("composable<FictionalRoute> {}")
    }
    @Test fun allowsApprovedS1RouteConstantsOnly() {
        ScopeBoundaryPolicy.validateSource("FictionalNav.kt", "composable(S1Routes.TODAY) {}")
        ScopeBoundaryPolicy.validateSource(
            "FictionalNav.kt",
            "composable(route = S1Routes.STUDENT_DETAIL, arguments = fictionalArguments) {}",
        )
    }
    @Test fun rejectsDeferredCapabilitiesAndContainerCodecs() {
        listOf(
            "NotificationManager",
            "NotificationChannel",
            "NotificationCompat",
            "AlarmManager",
            "POST_NOTIFICATIONS",
            "SCHEDULE_EXACT_ALARM",
            "USE_EXACT_ALARM",
            "AppWidgetProvider",
            "GlanceAppWidget",
            "RemoteViews",
            "LiveActivity",
            "BackupFileCodec",
            "ArchiveFileCodec",
            "ShareReport",
            "FileProvider",
            "ACTION_SEND",
            "ACTION_OPEN_DOCUMENT",
            "ACTION_CREATE_DOCUMENT",
            "TrendRoute",
        ).forEach(::reject)
    }
    @Test fun routesAreFrozenToS1Whitelist() {
        val sourceRoot = File(MergedPrivacyInputs.property("sourceRoot"))
        val routesFile = File(sourceRoot, "main/java/com/ignacioli/finecoach/navigation/S1Routes.kt")
        assertTrue(routesFile.path, routesFile.isFile)
        val source = routesFile.readText()
        assertS1RoutesMembersAreFrozen(source)

        val expectedConstants = frozenS1RouteConstants()
        expectedConstants.filterKeys { !it.startsWith("ARG_") }.values.forEach { route ->
            assertFalse(route.contains("appointment", ignoreCase = true))
            assertFalse(route.contains("trend", ignoreCase = true))
            assertFalse(route.contains("backup", ignoreCase = true))
            assertFalse(route.contains("archive", ignoreCase = true))
            assertFalse(route.contains("share", ignoreCase = true))
            assertFalse(route.contains("widget", ignoreCase = true))
        }

        assertThrows(IllegalArgumentException::class.java) {
            assertS1RoutesMembersAreFrozen(insertMemberBeforeClosingBrace(source, "var S2 = \"appointment\""))
        }
        assertThrows(IllegalArgumentException::class.java) {
            assertS1RoutesMembersAreFrozen(insertMemberBeforeClosingBrace(source, "@JvmField val S3 = \"trend\""))
        }
        assertThrows(IllegalArgumentException::class.java) {
            assertS1RoutesMembersAreFrozen(insertMemberBeforeClosingBrace(source, "object Nested { const val X = \"backup\" }"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            assertS1RoutesMembersAreFrozen(insertMemberBeforeClosingBrace(source, "companion object { const val X = \"archive\" }"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            assertS1RoutesMembersAreFrozen(insertMemberBeforeClosingBrace(source, "private companion object Hidden { const val X = \"widget\" }"))
        }
    }
    @Test fun rejectsS1RoutesExtensionMembersInAnyFile() {
        reject("val S1Routes.APPOINTMENTS: String get() = \"appointment\"")
        reject("fun S1Routes.trend(): String = \"trend\"")
        reject("val S1Routes.Companion.X get() = \"backup\"")
        ScopeBoundaryPolicy.validateSource("FictionalNav.kt", "val route = S1Routes.TODAY")
    }
    @Test fun rejectsDeepLinkRegistration() {
        reject("navDeepLink { uriPattern = \"finecoach://session\" }")
        reject("composable(route = S1Routes.TODAY, deepLinks = fictionalLinks) {}")
        reject("navigate(\"appointment\")")
        reject("navigate(route = \"appointment\")")
    }
    @Test fun commentStripperKeepsDoubleSlashInsideStrings() {
        val stripped = ScopeBoundaryPolicy.stripCommentsPreservingStrings(
            "val route = \"finecoach://session\"\n// remove me\nval end = 1",
        )
        assertTrue(stripped.contains("\"finecoach://session\""))
        assertFalse(stripped.contains("remove me"))
        assertTrue(stripped.contains("val end = 1"))
    }
    @Test fun commentStripperKeepsBlockMarkersInsideStrings() {
        val stripped = ScopeBoundaryPolicy.stripCommentsPreservingStrings(
            "val marker = \"/*keep*/\"\n/* remove this */\nval end = 2",
        )
        assertTrue(stripped.contains("\"/*keep*/\""))
        assertFalse(stripped.contains("remove this"))
        assertTrue(stripped.contains("val end = 2"))
    }
    @Test fun commentStripperKeepsEscapedQuotesInStrings() {
        val stripped = ScopeBoundaryPolicy.stripCommentsPreservingStrings(
            "val text = \"\\\"quoted\\\" // keep\"\n// drop",
        )
        assertTrue(stripped.contains("\"\\\"quoted\\\" // keep\""))
        assertFalse(stripped.contains("drop"))
    }
    @Test fun genericComponentDemonstrationDoesNotBecomeABusinessEntry() {
        ScopeBoundaryPolicy.validateSource("FictionalCatalog.kt", "BasicText(\"预约 / 备份 / 学员\")")
        ScopeBoundaryPolicy.validateSource("MainActivity.kt", "composable(\"placeholder\") {}")
    }

    private fun frozenS1RouteConstants(): Map<String, String> = mapOf(
        "ARG_STUDENT_ID" to "studentID",
        "ARG_PACKAGE_ID" to "coursePackageID",
        "ARG_SESSION_ID" to "sessionID",
        "ARG_TEMPLATE_ID" to "templateID",
        "TODAY" to "today",
        "STUDENTS" to "students",
        "STUDENT_CREATE" to "students/create",
        "STUDENT_DETAIL" to "students/{\$ARG_STUDENT_ID}",
        "STUDENT_EDIT" to "students/{\$ARG_STUDENT_ID}/edit",
        "STUDENT_PACKAGES" to "students/{\$ARG_STUDENT_ID}/packages",
        "STUDENT_HISTORY" to "students/{\$ARG_STUDENT_ID}/history",
        "PACKAGE_DETAIL" to "packages/{\$ARG_PACKAGE_ID}",
        "SESSION_ACTIVE" to "session/{\$ARG_SESSION_ID}",
        "TEMPLATES" to "templates",
        "TEMPLATE_DETAIL" to "templates/{\$ARG_TEMPLATE_ID}",
        "EXERCISES" to "exercises",
        "HISTORY_DETAIL" to "history/{\$ARG_SESSION_ID}",
    )

    private fun assertS1RoutesMembersAreFrozen(source: String) {
        val stripped = ScopeBoundaryPolicy.stripCommentsPreservingStrings(source)
        val constants = Regex(
            """(?m)^\s*(?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^)]*\))?\s+)*(?:[A-Za-z_][A-Za-z0-9_]*\s+)*const\s+val\s+([A-Z][A-Z0-9_]*)\s*=\s*"([^"]+)"""",
        ).findAll(stripped).map { it.groupValues[1] to it.groupValues[2] }.toMap()
        assertEquals(frozenS1RouteConstants(), constants)

        val body = stripped.substringAfter("object S1Routes").substringAfter('{').substringBeforeLast('}')
        val declarations = collectTopLevelRouteDeclarations(body)
        val expectedDeclarations = buildSet {
            frozenS1RouteConstants().keys.forEach { add("const val:$it") }
            add("val:allPatterns")
            addAll(
                setOf(
                    "fun:studentDetail",
                    "fun:studentEdit",
                    "fun:studentPackages",
                    "fun:studentHistory",
                    "fun:packageDetail",
                    "fun:activeSession",
                    "fun:templateDetail",
                    "fun:historyDetail",
                ),
            )
        }
        require(declarations == expectedDeclarations) {
            "S1Routes members drifted: expected=$expectedDeclarations actual=$declarations"
        }
    }

    private fun collectTopLevelRouteDeclarations(objectBody: String): Set<String> {
        val declarations = linkedSetOf<String>()
        var braceDepth = 0
        objectBody.lineSequence().forEach { rawLine ->
            val trimmed = rawLine.trim()
            if (braceDepth == 0 && trimmed.isNotEmpty()) {
                parseTopLevelRouteDeclaration(trimmed)?.let { (kind, name) ->
                    declarations += "$kind:$name"
                }
            }
            braceDepth += braceDeltaOutsideLiterals(rawLine)
            require(braceDepth >= 0) { "S1Routes parse failed: invalid brace depth" }
        }
        require(braceDepth == 0) { "S1Routes parse failed: unbalanced braces" }
        return declarations
    }

    private fun parseTopLevelRouteDeclaration(line: String): Pair<String, String>? {
        val kindMatch = Regex(
            """^(?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^)]*\))?\s+)*(?:(?:public|private|internal|protected|open|final|abstract|override|inline|data|sealed|value|suspend|tailrec|external|operator|infix|lateinit|const|companion|enum|annotation|inner|fun)\s+)*(val|var|fun|object|class|interface|typealias)\b""",
        ).find(line) ?: return null
        val kind = kindMatch.groupValues[1]
        val prefix = line.substring(0, kindMatch.range.last + 1)
        val declarationKind = if (kind == "val" && Regex("""\bconst\b""").containsMatchIn(prefix)) "const val" else kind
        val name = when (kind) {
            "fun" -> Regex("""\bfun\s+(?:<[^>]+>\s*)?([A-Za-z_][A-Za-z0-9_]*)\b""").find(line)?.groupValues?.get(1)
            else -> Regex("""\b(?:val|var|object|class|interface|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)\b""")
                .find(line)?.groupValues?.get(1)
                ?: if (kind == "object" && Regex("""\bcompanion\s+object\b""").containsMatchIn(line)) "Companion" else null
        } ?: return null
        return declarationKind to name
    }

    private fun braceDeltaOutsideLiterals(line: String): Int {
        var delta = 0
        var inString = false
        var inChar = false
        var escaped = false
        line.forEach { ch ->
            when {
                inString -> {
                    if (!escaped && ch == '"') inString = false
                    escaped = ch == '\\' && !escaped
                    if (ch != '\\') escaped = false
                }
                inChar -> {
                    if (!escaped && ch == '\'') inChar = false
                    escaped = ch == '\\' && !escaped
                    if (ch != '\\') escaped = false
                }
                ch == '"' -> inString = true
                ch == '\'' -> inChar = true
                ch == '{' -> delta += 1
                ch == '}' -> delta -= 1
            }
        }
        return delta
    }

    private fun insertMemberBeforeClosingBrace(source: String, member: String): String {
        val closing = source.lastIndexOf('}')
        require(closing > 0) { "Invalid S1Routes source for mutation test" }
        return source.substring(0, closing) + "    $member\n" + source.substring(closing)
    }

    private fun reject(source: String) {
        assertThrows(IllegalArgumentException::class.java) { ScopeBoundaryPolicy.validateSource("fictional.kt", source) }
    }
    private fun mutateManifest(xml: String, activity: Boolean = false) {
        val manifest = MergedPrivacyInputs.manifest("debug")
        val parent = manifest.getElementsByTagName(if (activity) "activity" else "application").item(0)
        val fragment = MergedPrivacyInputs.parse("<root xmlns:android=\"${MergedPrivacyInputs.ANDROID}\">$xml</root>")
        parent.appendChild(manifest.ownerDocument.importNode(fragment.firstChild, true))
        assertThrows(IllegalArgumentException::class.java) { ScopeBoundaryPolicy.validateManifest(manifest) }
    }
}
