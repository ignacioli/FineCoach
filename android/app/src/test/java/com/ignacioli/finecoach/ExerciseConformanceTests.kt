// fictional-data: approved synthetic screen examples; no real coach/student data.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.LayoutInfo
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.session.ActiveSessionScreen
import com.ignacioli.finecoach.storage.repository.StudentRepository
import java.io.File
import java.security.MessageDigest
import org.junit.*
import org.junit.runner.RunWith
import org.json.JSONArray
import org.json.JSONObject
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode


import com.ignacioli.finecoach.features.exercises.*

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ExerciseConformanceTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: TrainingConformanceFixture? = null
    private var fixtureBindings = emptyMap<String, String>()
    private var capture: JSONObject? = null
    private var library: ExerciseConformanceFixture? = null
    @After fun close() {
        compose.runOnUiThread { compose.activity.setContent {} }
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        fixture?.close(); fixture = null
        library?.close(); library = null
    }
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun render(sheet: Boolean, out: File): JSONArray {
        compose.mainClock.autoAdvance = true
        val f = if (sheet) TrainingConformanceFixture().also { fixture = it } else null
        if (f != null) fixtureBindings = seedConformanceTemplates(f)
        val state = if (f != null) f.exercises else ExerciseConformanceFixture().also { library = it }.state
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { Box(Modifier.requiredSize(390.dp, 844.dp).testTag("conformance-viewport")) {
                    if (f == null) ExerciseLibraryScreen(state, {}) else ActiveSessionScreen(f.state,
                        f.content.session.sessionID, state, f.templates, {}, {}, students = StudentRepository(f.room.db, f.room.clock))
                } }
            }
        } }
        compose.waitUntil(15_000) { exists(if (sheet) "session-add-exercise" else "exercise-library-muscle-胸") }
        val baseline = node("conformance-viewport").captureToImage().asAndroidBitmap()
        val baselineFile = File(out, "before.png")
        baselineFile.outputStream().use { baseline.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        if (sheet) {
            node("session-add-exercise").performClick()
            node("session-apply-template").performClick()
            compose.waitUntil(15_000) { exists("template-apply-content") }
        } else {
            node("exercise-library-muscle-胸").performClick()
            compose.waitUntil(15_000) { exists("exercise-library-section-胸") && !state.entries.isEmpty() }
            Assert.assertTrue(state.recentEntries.isEmpty())
        }
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1000)
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        check(image.width == 780 && image.height == 1688) { "Wrong viewport "+image.width+"x"+image.height }
        File(out, (if (sheet) "D8c-add-exercise" else "D2b-exercise-library") + ".android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        val all = compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes().flatMap { root ->
            fun descendants(node: SemanticsNode): List<SemanticsNode> = listOf(node) + node.children.flatMap(::descendants)
            descendants(root)
        }.distinctBy { it.id }
        val nodes = JSONArray()
        for (n in all) {
            val texts = n.config.getOrNull(SemanticsProperties.Text)?.map { it.text }.orEmpty()
            val editable = n.config.getOrNull(SemanticsProperties.EditableText)?.text
            val layouts = mutableListOf<TextLayoutResult>()
            n.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            val color = layouts.firstOrNull()?.layoutInput?.style?.color
            val argb = if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) color.toArgbHex() else null
            val bounds = n.boundsInRoot
            val unclipped = JSONObject().put("x", n.positionInRoot.x / 2).put("y", n.positionInRoot.y / 2)
                .put("w", n.size.width / 2.0).put("h", n.size.height / 2.0)
            val scrollAncestors = JSONArray()
            generateSequence(n.parent) { it.parent }.filter { it.config.contains(SemanticsActions.ScrollBy) }.forEach { parent ->
                val b = parent.boundsInRoot
                scrollAncestors.put(JSONObject().put("tag", parent.config.getOrNull(SemanticsProperties.TestTag) ?: "")
                    .put("x", b.left / 2).put("y", b.top / 2).put("w", b.width / 2).put("h", b.height / 2))
            }
            val ancestors = generateSequence(n.parent) { it.parent }.mapNotNull { it.config.getOrNull(SemanticsProperties.TestTag) }.toList()
            nodes.put(JSONObject().put("id", n.id).put("tag", n.config.getOrNull(SemanticsProperties.TestTag) ?: "")
                .put("ancestors", JSONArray(ancestors)).put("text", editable ?: texts.joinToString("\n"))
                .put("placed", n.layoutInfo.isPlaced).put("attached", n.layoutInfo.isAttached)
                .put("unclipped", unclipped).put("scrollAncestors", scrollAncestors)
                .put("hex", argb ?: JSONObject.NULL).put("alpha", if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) color.alpha.toDouble() else 1.0)
                .put("x", bounds.left / 2).put("y", bounds.top / 2).put("w", bounds.width / 2).put("h", bounds.height / 2))
        }

        if (sheet) {
            val windows = compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes()
                .filter { root -> all.any { n -> n.config.contains(SemanticsProperties.IsDialog) && generateSequence(n) { it.parent }.any { it.id == root.id } } }
                .map { root ->
                    val bitmap = compose.onNode(isRoot() and SemanticsMatcher("root id") { it.id == root.id }, useUnmergedTree = true).captureToImage().asAndroidBitmap()
                    val file = File(out, "window-${root.id}.png")
                    file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                    ConformanceCapture.Window(javax.imageio.ImageIO.read(file), (root.boundsInWindow.left).toInt(), (root.boundsInWindow.top).toInt())
                }
            val activityImage = javax.imageio.ImageIO.read(File(out, "D8c-add-exercise.android.png"))
            val composed = ConformanceCapture.composite(activityImage, windows)
            javax.imageio.ImageIO.write(composed, "png", File(out, "D8c-add-exercise.android.png"))
            val panels = (0 until nodes.length()).map { nodes.getJSONObject(it) }.filter { it.optString("tag") == "template-apply-content" }
            capture = ConformanceCapture.validate(javax.imageio.ImageIO.read(baselineFile), composed, panels, windows.size, activityImage, (0 until nodes.length()).map { nodes.getJSONObject(it) }.filter { !it.isNull("hex") && it.optString("text").isNotEmpty() })
        }
        return nodes
    }
    private fun compare(name: String, png: String, sheet: Boolean) {
        val app = File(System.getProperty("finecoach.storageProjectDirectory"))
        val android = app.parentFile
        val out = File(app, "build/outputs/conformance/"+name).apply { mkdirs() }
        val hashes = mutableListOf<String>()
        var nodes = JSONArray()
        for (run in 1..2) {
            nodes = render(sheet, out)
            val bytes = File(out, name+".android.png").readBytes()
            File(out, name+".run"+run+".png").writeBytes(bytes)
            hashes += MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            File(out, name+".run"+run+".nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
            close()
        }
        File(out, name+".nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
        val bindings = fixtureBindings
        val result = ConformanceComparison.run(android, out, nodes, bindings, name, png, if (sheet) capture else null)
        val stability = JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1)
        result.put("stability", stability)
        if (!stability.getBoolean("stable") && result.getString("artifactStatus") != "INVALID_CAPTURE") result.put("artifactStatus", "INVALID_FIXTURE_UNSTABLE")
        result.put("humanReadSummary", "仅一次查看批准 PNG；未打开 Android 截图。节点几何与稳定性见本报告；负责人视觉验收 PENDING。")
        ConformanceComparison.writeReports(out, result)
        println("S0_CONFORMANCE "+name+" total="+result.getInt("total")+" passed="+result.getInt("passed")+" failed="+result.getInt("failed"))
        // Diagnostic task: page failures are data, not a gate. Invalid captures must remain failures in the report.
        if (result.getString("artifactStatus") == "INVALID_CAPTURE") Assert.assertTrue(result.getInt("failed") > 0)
        Assert.assertEquals(2, hashes.size)
    }
    @Test fun exerciseLibraryConformance() = compare("D2b-exercise-library", "design/m1-b-hifi/screens/20-exercise-library.png", false)
    @Test fun addExerciseTemplateConformance() = compare("D8c-add-exercise", "design/m1-b-hifi/screens/31-add-exercise-sheet.png", true)
}

private fun androidx.compose.ui.graphics.Color.toArgbHex(): String = "#%06x".format(toArgb() and 0xffffff)
