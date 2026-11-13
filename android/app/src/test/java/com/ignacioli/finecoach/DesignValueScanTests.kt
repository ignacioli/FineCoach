// fictional-data: scanner fixtures contain code strings only, no student records.
package com.ignacioli.finecoach

import java.io.File
import org.junit.Assert.*
import org.junit.Test

/** Small lexical scanner, like the iOS regex gate; not a Kotlin type checker. */
internal object DesignValueScanner {
    data class Violation(val path: String, val line: Int, val category: String, val raw: String)
    data class Result(val files: List<File>, val violations: List<Violation>)
    private val numeric = Regex("(?<![\\w.])(?:0[xX][0-9a-fA-F]+|[-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)[fFuUlL]*\\b")
    private val unitExtension = Regex("\\.\\s*(dp|sp)\\b")
    private val directValues = listOf(
        "colorLiteral" to Regex("\\bColor\\s*(?:\\(|\\.\\s*\\w+)|\\bandroid\\s*\\.\\s*graphics\\s*\\.\\s*Color\\b"),
        "dimensionConstructor" to Regex("\\b(?:Dp|TextUnit|dimensionResource)\\s*\\("),
        "colorResource" to Regex("\\bcolorResource\\s*\\("),
        "systemFont" to Regex("\\bFontWeight\\s*\\(|\\bFontFamily\\s*\\."),
        "materialTheme" to Regex("\\bMaterialTheme\\s*\\.\\s*(?:typography|colorScheme)\\b"),
    )
    // Preserve offsets/newlines while excluding comments and string literals.
    internal fun code(source: String): String {
        val ignored = Regex("\"\"\"[\\s\\S]*?\"\"\"|\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|//[^\\n]*|/\\*[\\s\\S]*?\\*/")
        return ignored.replace(source) { m -> m.value.map { if (it == '\n') '\n' else ' ' }.joinToString("") }
    }
    fun scan(path: String, source: String): List<Violation> {
        val text = code(source)
        val result = mutableListOf<Violation>()
        fun add(offset: Int, category: String, raw: String) {
            result += Violation(path, text.take(offset).count { it == '\n' } + 1, category, raw)
        }
        data class Call(val name: String, val open: Int)
        fun context(offset: Int): List<Call> {
            val stack = mutableListOf<Call>()
            for (i in 0 until offset) when (text[i]) {
                '(' -> stack += Call(Regex("[\\w.]+\\s*$").find(text.substring(0, i))?.value?.trim()?.substringAfterLast('.').orEmpty(), i)
                ')' -> if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex)
            }
            return stack
        }
        fun argumentStart(call: Call?, offset: Int): Int =
            maxOf((call?.open ?: -1) + 1, text.lastIndexOf(',', offset - 1) + 1)
        fun isSpacing(call: Call?, prefix: String): Boolean =
            call?.name in setOf("padding", "absolutePadding", "PaddingValues", "spacedBy") ||
                Regex("\\b(?:spacing|space|horizontalSpacing|verticalSpacing)\\s*=\\s*$").containsMatchIn(prefix)
        fun argumentValue(prefix: String) = prefix.substringAfterLast('=').trim()
        fun endsArgument(end: Int) = text.substring(end).trimStart().firstOrNull() in listOf(',', ')')

        directValues.forEach { (category, pattern) ->
            pattern.findAll(text).forEach { add(it.range.first, category, it.value) }
        }
        unitExtension.findAll(text).forEach { match ->
            // Imports declare access to an extension, not a use of it.
            val linePrefix = text.substring(text.lastIndexOf('\n', match.range.first) + 1, match.range.first)
            if (linePrefix.trimStart().startsWith("import ")) return@forEach
            val calls = context(match.range.first)
            val call = calls.lastOrNull()
            val start = argumentStart(call, match.range.first)
            val prefix = text.substring(start, match.range.first)
            val spacing = isSpacing(call, prefix.substringBeforeLast('=', "") + if ('=' in prefix) "=" else "")
            val unit = match.groupValues[1]
            val zeroGap = spacing && unit == "dp" && argumentValue(prefix) == "0" && endsArgument(match.range.last + 1)
            if (!zeroGap) {
                val category = when {
                    unit == "sp" -> "fontLiteral"
                    calls.any { it.name.endsWith("CornerShape") } -> "cornerRadiusLiteral"
                    spacing -> "spacingLiteral"
                    else -> "dimensionLiteral"
                }
                add(match.range.first, category, text.substring(start, match.range.last + 1).trim())
            }
        }
        numeric.findAll(text).forEach { match ->
            // Unit expressions are already checked above, including float receivers.
            if (Regex("^\\s*\\.\\s*(?:dp|sp)\\b").containsMatchIn(text.substring(match.range.last + 1))) return@forEach
            val calls = context(match.range.first)
            val call = calls.lastOrNull()
            val prefix = text.substring(argumentStart(call, match.range.first), match.range.first)
            val category = when {
                calls.any { it.name.endsWith("CornerShape") } -> "cornerRadiusLiteral"
                Regex("\\b(?:lineHeight|letterSpacing|fontSize)\\s*=\\s*$").containsMatchIn(prefix) -> "fontLiteral"
                isSpacing(call, prefix) -> if (match.value == "0" && argumentValue(prefix).isEmpty() && endsArgument(match.range.last + 1)) null else "spacingLiteral"
                else -> null
            }
            if (category != null) add(match.range.first, category, match.value)
        }
        return result.sortedBy { it.line }
    }
    fun scanRoot(root: File): Result {
        check(root.isDirectory) { "missing source root: $root" }
        val main = root.resolve("main/java/com/ignacioli/finecoach")
        val debug = root.resolve("debug")
        check(main.isDirectory && debug.isDirectory) { "missing main/debug scan root" }
        // main designsystem/** defines tokens/components: deliberately excluded. Debug composition stays included.
        // Main shell, all features/navigation and future package UI are included, not an app-wide exclusion.
        val files = (main.walkTopDown() + debug.walkTopDown()).filter {
            it.isFile && it.extension == "kt" && !it.toPath().startsWith(main.resolve("designsystem").toPath())
        }.sortedBy { it.path }.toList()
        check(files.isNotEmpty()) { "empty design value scan" }
        return Result(files, files.flatMap { scan(it.relativeTo(root).invariantSeparatorsPath, it.readText()) })
    }
}

/**
 * S1-D40 R5 line-box guard (G3). Scans all of main (design system included) and debug:
 * - `rawText`: material3 `Text(` or `BasicText(` outside the allowlist; text goes through `FcText`.
 * - `offset`: `.offset` / `.absoluteOffset` (argument or lambda form) outside the allowlist; alignment comes from tokens or anatomy.
 * Each allowlist entry is file + category + exact count + reason, so a new use fails until reviewed.
 */
internal object LineBoxScanner {
    data class Allowed(val path: String, val category: String, val count: Int, val reason: String)
    private val rules = listOf(
        "rawText" to Regex("""(?<![\w])(?:Basic)?Text\s*\("""),
        "offset" to Regex("""\.\s*(?:absoluteOffset|offset)\s*[({]"""),
    )
    val allowlist = listOf(
        Allowed("main/java/com/ignacioli/finecoach/designsystem/FcText.kt", "rawText", 2, "FcText wraps the platform Text with the line box"),
        Allowed("main/java/com/ignacioli/finecoach/designsystem/FcSetRow.kt", "rawText", 1, "set values use BasicText auto-size with fcLineBox"),
        Allowed("debug/java/com/ignacioli/finecoach/S0DebugApplication.kt", "rawText", 1, "S0 debug sample text, not a design screen"),
        Allowed("main/java/com/ignacioli/finecoach/features/session/SessionChrome.kt", "offset", 1, "back button 44dp hit area extends outward from the visible glyph"),
    )
    fun scan(path: String, source: String): Map<String, Int> {
        val text = DesignValueScanner.code(source)
        return rules.associate { (category, pattern) -> category to pattern.findAll(text).count() }.filterValues { it > 0 }
    }
    fun violations(root: File): List<String> {
        val files = (root.resolve("main").walkTopDown() + root.resolve("debug").walkTopDown()).filter { it.isFile && it.extension == "kt" }.toList()
        check(files.isNotEmpty()) { "empty line-box scan" }
        val found = files.flatMap { file -> val path = file.relativeTo(root).invariantSeparatorsPath
            scan(path, file.readText()).map { (category, count) -> Triple(path, category, count) } }
        val unexpected = found.filter { (path, category, count) -> allowlist.none { it.path == path && it.category == category && it.count == count } }
            .map { (path, category, count) -> "$path: $category x$count (not on the S1-D40 R5 allowlist)" }
        val stale = allowlist.filter { a -> found.none { it.first == a.path && it.second == a.category && it.third == a.count } }
            .map { "${it.path}: ${it.category} allowlist entry is stale" }
        return unexpected + stale
    }
}

class DesignValueScanTests {
    @Test fun lineBoxRulesHoldInSource() {
        val root = File(requireNotNull(System.getProperty("finecoach.sourceRoot")))
        val violations = LineBoxScanner.violations(root)
        violations.forEach { println("G3 lineBox $it") }
        assertEquals("S1-D40 R5: raw Text or offset outside the allowlist", emptyList<String>(), violations)
    }
    @Test fun lineBoxScannerRecognizesRawTextAndOffset() {
        assertEquals(mapOf("rawText" to 3), LineBoxScanner.scan("f.kt", "Text(\"a\"); androidx.compose.material3.Text(\"b\"); BasicText(\"c\")"))
        assertEquals(emptyMap<String, Int>(), LineBoxScanner.scan("f.kt", "FcText(\"a\"); BasicTextField(v, f); RichText(x) // Text(\"d\")"))
        assertEquals(mapOf("offset" to 2), LineBoxScanner.scan("f.kt", "Modifier.offset(y = FcSpacing.space1 - FcSpacing.hairline).offset { IntOffset(0, 0) }"))
    }
    @Test fun lineBoxScannerRecognizesQualifiedPrimitivesAndAbsoluteOffset() {
        listOf("androidx.compose.foundation.text.BasicText", "androidx.compose.material.Text", "androidx.compose.material3.Text").forEach {
            assertEquals(it, mapOf("rawText" to 1), LineBoxScanner.scan("f.kt", "$it(value)"))
        }
        assertEquals(mapOf("offset" to 2), LineBoxScanner.scan("f.kt",
            "Modifier.absoluteOffset(x = value).absoluteOffset { IntOffset(0, 0) }"))
    }
    @Test fun lineBoxScannerIgnoresOtherNamesCommentsAndStrings() {
        assertEquals(emptyMap<String, Int>(), LineBoxScanner.scan("f.kt", """
            FcText(value); BasicTextField(value, changed); RichText(value)
            androidx.compose.foundation.text.BasicTextField(value, changed)
            // androidx.compose.foundation.text.BasicText(value); Modifier.absoluteOffset(x)
            /* androidx.compose.material.Text(value); Modifier.offset { x } */
            val example = "androidx.compose.material3.Text(value); Modifier.absoluteOffset(x)"
            val multiline = ${'"'}${'"'}${'"'}BasicText(value); Modifier.offset(x)${'"'}${'"'}${'"'}
            Modifier.myabsoluteOffset(x); Modifier.offsetSomething(x)
        """.trimIndent()))
    }
    @Test fun actualSourceUsesTokens() {
        val root = File(requireNotNull(System.getProperty("finecoach.sourceRoot")))
        val result = DesignValueScanner.scanRoot(root)
        val groups = result.files.groupBy {
            val path = it.relativeTo(root).invariantSeparatorsPath
            when {
                path.startsWith("debug/") -> "debug"
                "/features/" in path -> "features/" + path.substringAfter("/features/").substringBefore('/')
                "/navigation/" in path -> "navigation"
                else -> "shell/other"
            }
        }
        println("G3 scanned files=${result.files.size}; violations=${result.violations.size}")
        groups.toSortedMap().forEach { (group, files) ->
            val paths = files.map { it.relativeTo(root).invariantSeparatorsPath }.toSet()
            println("G3 $group files=${files.size} violations=${result.violations.count { it.path in paths }}")
        }
        result.violations.forEach { println("${it.path}:${it.line}: ${it.category}: ${it.raw}") }
        assertEquals("source bypasses design tokens; see complete G3 output", 0, result.violations.size)
    }
    private fun rejected(source: String, category: String) {
        assertTrue("must detect $category", DesignValueScanner.scan("fixture.kt", source).any { it.category == category })
    }
    @Test fun hexColorRejected() = rejected("Text(color = Color(0xFFFFFFFF))", "colorLiteral")
    @Test fun namedColorRejected() = rejected("Text(color = Color.White)", "colorLiteral")
    @Test fun fontRejectedIncludingZero() { rejected("Text(fontSize = 17.sp)", "fontLiteral"); rejected("Text(fontSize = 0.sp)", "fontLiteral") }
    @Test fun dimensionsRejectedIncludingZero() { rejected("Modifier.width(44.dp)", "dimensionLiteral"); rejected("Modifier.height(0.dp)", "dimensionLiteral") }
    @Test fun radiusRejectedIncludingZero() { rejected("RoundedCornerShape(14.dp)", "cornerRadiusLiteral"); rejected("RoundedCornerShape(0.dp)", "cornerRadiusLiteral") }
    @Test fun nonzeroSpacingRejected() { rejected("Modifier.padding(horizontal = 16.dp)", "spacingLiteral"); rejected("Arrangement.spacedBy(8.dp)", "spacingLiteral"); rejected("Row(spacing = 8)", "spacingLiteral") }
    @Test fun zeroSpacingAllowed() {
        assertTrue(DesignValueScanner.scan("fixture.kt", "Modifier.padding(0.dp).padding(horizontal = 0, vertical = 0.dp); Arrangement.spacedBy(0.dp); Row(spacing = 0)").isEmpty())
    }
    @Test fun zeroSpacingDoesNotExemptNestedDimensions() = rejected("Modifier.padding(foo(0.dp))", "dimensionLiteral")
    @Test fun tokenCompositionAllowed() { assertTrue(DesignValueScanner.scan("fixture.kt", "FcButton(title, Modifier.padding(FcSpacing.space4)); Text(style = FcTypography.body, color = FcColors.textPrimary)").isEmpty()) }
    @Test fun commentsAndStringsIgnored() { assertTrue(DesignValueScanner.scan("fixture.kt", "// Color.White\n/* 17.sp */ val label = \"16.dp\"").isEmpty()) }
    @Test fun multilineSpacingRejected() = rejected("Modifier.padding(\n horizontal = 16.dp\n)", "spacingLiteral")
    @Test fun floatDpRejected() = rejected("Modifier.width(16f.dp)", "dimensionLiteral")
    @Test fun floatSpRejected() = rejected("Text(fontSize = 17f.sp)", "fontLiteral")
    @Test fun arithmeticDpRejected() = rejected("Modifier.width((8 * 2).dp)", "dimensionLiteral")
    @Test fun variableDpRejected() = rejected("Modifier.width(x.dp)", "dimensionLiteral")
    @Test fun fractionalFloatDpIsNotZeroSpacing() = rejected("Modifier.padding(0.5f.dp)", "spacingLiteral")
    @Test fun computedZeroIsNotLiteralGap() = rejected("Modifier.padding((0).dp)", "spacingLiteral")
    @Test fun zeroInArithmeticIsNotLiteralGap() = rejected("Modifier.padding(0.dp + x)", "spacingLiteral")
    @Test fun dpConstructorRejected() = rejected("Modifier.width(Dp(x))", "dimensionConstructor")
    @Test fun textUnitConstructorRejected() = rejected("TextUnit(value, kind)", "dimensionConstructor")
    @Test fun namedColorConstructorRejected() = rejected("Color(red = x, green = y, blue = z)", "colorLiteral")
    @Test fun variableColorConstructorRejected() = rejected("Color(value)", "colorLiteral")
    @Test fun parseColorRejected() = rejected("Color.parseColor(value)", "colorLiteral")
    @Test fun androidGraphicsColorRejected() = rejected("android.graphics.Color.rgb(r, g, b)", "colorLiteral")
    @Test fun colorResourceRejected() = rejected("colorResource(R.color.custom)", "colorResource")
    @Test fun dimensionResourceRejected() = rejected("dimensionResource(R.dimen.custom)", "dimensionConstructor")
    @Test fun fontWeightConstructorRejected() = rejected("FontWeight(600)", "systemFont")
    @Test fun systemFontFamilyRejected() = rejected("FontFamily.SansSerif", "systemFont")
    @Test fun materialTypographyRejected() = rejected("MaterialTheme.typography.bodyLarge", "materialTheme")
    @Test fun materialColorSchemeRejected() = rejected("MaterialTheme.colorScheme.primary", "materialTheme")
    @Test fun cornerPercentRejected() = rejected("CutCornerShape(percent = 50)", "cornerRadiusLiteral")
    @Test fun cornerIntegerRejected() = rejected("AbsoluteRoundedCornerShape(12)", "cornerRadiusLiteral")
    @Test fun roundedCornerPercentRejected() = rejected("RoundedCornerShape(percent = 50)", "cornerRadiusLiteral")
    @Test fun bareFontSizeRejected() = rejected("Text(fontSize = 17)", "fontLiteral")
    @Test fun bareLineHeightRejected() = rejected("Text(lineHeight = 20f)", "fontLiteral")
    @Test fun bareLetterSpacingRejected() = rejected("Text(letterSpacing = 0)", "fontLiteral")
    @Test fun missingRootFails() {
        val root = File(System.getProperty("java.io.tmpdir"), "missing-g3-${java.util.UUID.randomUUID()}")
        val failure = assertThrows(IllegalStateException::class.java) { DesignValueScanner.scanRoot(root) }
        assertTrue(failure.message.orEmpty().contains("missing source root"))
    }
}
