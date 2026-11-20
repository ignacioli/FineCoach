// fictional-data: approved synthetic screen examples; no real coach/student data.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
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
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
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
class AddExerciseConformanceTests {
    // Queue IO resumptions on the test UI scheduler instead of resuming on IO workers.
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: TrainingConformanceFixture? = null
    private var fixtureBindings = emptyMap<String, String>()
    private var capture: JSONObject? = null
    private var addFixture: AddExerciseConformanceFixture? = null
    @After fun close() {
        compose.mainClock.autoAdvance = true
        if (exists("exercise-picker-cancel")) {
            node("exercise-picker-cancel").performSemanticsAction(SemanticsActions.OnClick) { it() }
            compose.waitForIdle()
            compose.mainClock.advanceTimeBy(1000)
            compose.waitForIdle()
        }
        compose.runOnUiThread { compose.activity.setContent {} }
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        fixture?.close(); fixture = null
        addFixture?.close(); addFixture = null
    }
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun render(sheet: Boolean, out: File): JSONArray {
        compose.mainClock.autoAdvance = true
        val added = AddExerciseConformanceFixture().also { addFixture = it }
        val f = added.training
        val state = added.state
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { ConformanceViewport {
                    Box(Modifier.fillMaxSize().background(com.ignacioli.finecoach.designsystem.FcColors.surfacePage).testTag("conformance:Rectangle")) {
                    Box(Modifier.fillMaxSize().background(com.ignacioli.finecoach.designsystem.FcColors.surfacePage).testTag("conformance:背景 · 训练中（遮罩下）")) {
                    ActiveSessionScreen(f.state,
                        f.content.session.sessionID, state, f.templates, {}, {}, students = StudentRepository(f.room.db, f.room.clock))
                    } }
                } }
            }
        } }
        compose.waitUntil(15_000) { exists("session-add-exercise") }
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        node("platform-content").assertTopPositionInRootIsEqualTo(52.dp)
        val baseline = node("conformance-viewport").captureToImage().asAndroidBitmap()
        val baselineFile = File(out, "before.png")
        baselineFile.outputStream().use { baseline.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        if (sheet) {
            node("session-add-exercise").performClick()
            node("session-add-library").performClick()
            compose.waitUntil(15_000) { exists("exercise-picker-recent") && state.recentEntries.size == 5 }
        }
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        check(image.width == 780 && image.height == 1688) { "Wrong viewport "+image.width+"x"+image.height }
        File(out, "C2b-B-add-exercise" + ".android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
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
            // S1-D64: project the existing dismiss semantics into the selector vocabulary.
            // This aliases the real node, preserving its geometry and raw content description.
            val dismissScrim = n.config.getOrNull(SemanticsProperties.ContentDescription) == listOf("关闭工作表") &&
                n.config.contains(SemanticsActions.OnClick)
            nodes.put(JSONObject().put("id", n.id).put("tag", n.config.getOrNull(SemanticsProperties.TestTag)
                ?: if (dismissScrim) "semantics:关闭工作表" else "")
                .put("ancestors", JSONArray(ancestors)).put("contentDescriptions", JSONArray(n.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty())).put("clickable", n.config.contains(SemanticsActions.OnClick)).put("text", editable ?: texts.joinToString("\n"))
                .put("placed", n.layoutInfo.isPlaced).put("attached", n.layoutInfo.isAttached)
                .put("unclipped", unclipped).put("scrollAncestors", scrollAncestors)
                .put("textAlign", layouts.firstOrNull()?.layoutInput?.style?.textAlign?.toString() ?: "Start").put("hex", argb ?: JSONObject.NULL).put("alpha", if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) color.alpha.toDouble() else 1.0)
                .put("x", bounds.left / 2).put("y", bounds.top / 2).put("w", bounds.width / 2).put("h", bounds.height / 2))
        }

        if (sheet) {
            val windows = compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes()
                .filter { root -> all.any { n -> n.config.contains(SemanticsProperties.IsDialog) && generateSequence(n) { it.parent }.any { it.id == root.id } } }
                .map { root ->
                    val dialog = all.single { n -> n.config.contains(SemanticsProperties.IsDialog) && generateSequence(n) { it.parent }.any { it.id == root.id } }
                    // captureToImage(root) has no IsDialog ancestor and falls back to the activity window.
                    val bitmap = compose.onNode(SemanticsMatcher("dialog id") { it.id == dialog.id }, useUnmergedTree = true).captureToImage().asAndroidBitmap()
                    val file = File(out, "window-${root.id}.png")
                    file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                    ConformanceCapture.Window(javax.imageio.ImageIO.read(file), (dialog.boundsInWindow.left).toInt(), (dialog.boundsInWindow.top).toInt())
                }
            val activityImage = javax.imageio.ImageIO.read(File(out, "C2b-B-add-exercise.android.png"))
            val composed = ConformanceCapture.composite(activityImage, windows)
            javax.imageio.ImageIO.write(composed, "png", File(out, "C2b-B-add-exercise.android.png"))
            val panels = (0 until nodes.length()).map { nodes.getJSONObject(it) }.filter { it.optString("tag") == "exercise-picker-content" }
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
        ConformanceSsimAlignment.evaluate(File(System.getProperty("finecoach.storageProjectDirectory")), out.parentFile)
        println("S0_CONFORMANCE "+name+" total="+result.getInt("total")+" passed="+result.getInt("passed")+" failed="+result.getInt("failed"))
        writeProposal(android, out, result, nodes)
        Assert.assertEquals("Capture must contain the real panel", "VALID_FIXTURE", result.getString("artifactStatus"))
        Assert.assertTrue("Fixture must be stable", stability.getBoolean("stable"))
        // Strict comparison against the approved current board.
        Assert.assertTrue("C2b-B strict current-board comparison: " + result.toString(), result.getBoolean("gatePassed"))
        Assert.assertEquals(2, hashes.size)
    }
    private fun writeProposal(android: File, out: File, result: JSONObject, nodes: JSONArray) {
        val layers = JSONObject(File(android, "design-assets/conformance/C2b-B-add-exercise.layers.json").readText()).getJSONArray("layers")
        val board = (0 until layers.length()).map { layers.getJSONObject(it) }
        val observed = (0 until nodes.length()).map { nodes.getJSONObject(it) }
        fun box(n: JSONObject) = n.optJSONObject("unclipped") ?: n
        fun recent(n: JSONObject) = (0 until n.getJSONArray("ancestors").length()).any {
            n.getJSONArray("ancestors").getString(it).startsWith("exercise-picker-recent-")
        }
        val recentRows = observed.filter { it.optString("tag").startsWith("exercise-picker-recent-") }
        fun measured(layer: JSONObject): JSONObject? {
            val name = layer.getString("name")
            var candidates = observed.filter { if (layer.getString("type") == "text") it.optString("text") == layer.optString("text")
                else it.optString("tag") == "conformance:$name" }
            if (name == "Scrim") candidates = observed.filter { it.optBoolean("clickable") &&
                it.getJSONArray("contentDescriptions").length() > 0 && box(it).getDouble("w") == 390.0 && box(it).getDouble("h") == 844.0 }
            if (candidates.any(::recent)) candidates = candidates.filter(::recent)
            if (name == "Divider" && recentRows.size == 5) {
                val top = recentRows.minOf { box(it).getDouble("y") } - 1.0
                val bottom = recentRows.maxOf { box(it).let { b -> b.getDouble("y") + b.getDouble("h") } } + 1.0
                candidates = candidates.filter { box(it).getDouble("y") in top..bottom }
            }
            val peers = board.filter { it.getString("name") == name && it.getString("type") != "path" }
                .sortedWith(compareBy({ it.getDouble("y") }, { it.getDouble("x") }))
            val index = peers.indexOfFirst { it.getString("path") == layer.getString("path") }
            return candidates.sortedWith(compareBy({ box(it).getDouble("y") }, { box(it).getDouble("x") })).getOrNull(index)
        }
        val proposal = JSONArray()
        for (layer in board.filter { it.getString("type") != "board" }) {
            val path = layer.getString("path")
            val entry = JSONObject().put("path", path).put("name", layer.getString("name"))
                .put("coordinateSpace", "390×844 board dp; measured dialog coordinates")
            val direct = if (!path.contains('/')) measured(layer) else null
            if (direct != null) {
                val actual = box(direct)
                val delta = JSONObject()
                for (key in listOf("x", "y", "w", "h")) {
                    entry.put(key, actual.getDouble(key)); delta.put(key, actual.getDouble(key) - layer.getDouble(key))
                }
                entry.put("source", "production Compose semantics; S1-D60 tokens; recent rows scoped by real row ancestry")
                    .put("measurement", "DIRECT_LAYOUT").put("box", if (layer.getString("type") == "text") "TOKEN_LINE_BOX" else "VISIBLE_SHAPE_LAYOUT")
                    .put("deltaFromOldBoard", delta)
            } else if (path.contains('/')) {
                val parent = board.single { it.getString("path") == path.substringBefore('/') }
                measured(parent)?.let { node ->
                    val actual = box(node)
                    val delta = JSONObject()
                    for (key in listOf("x", "y", "w", "h")) {
                        val value = layer.getDouble(key) + if (key == "x" || key == "y") actual.getDouble(key) - parent.getDouble(key) else 0.0
                        entry.put(key, value); delta.put(key, value - layer.getDouble(key))
                    }
                    entry.put("source", "measured parent icon; retained original local vector geometry")
                        .put("measurement", "DERIVED_PARENT_TRANSLATION_NOT_INDEPENDENT_PATH_MEASUREMENT")
                        .put("deltaFromOldBoard", delta)
                }
            }
            if (!entry.has("x")) entry.put("source", "UNCONFIRMED").put("measurement", "No unique measured shape; dispatcher decision required")
            proposal.put(entry)
        }
        val target = File(android, "build/outputs/conformance/C2b-B-add-exercise").apply { mkdirs() }
        File(target, "proposed-board.json").writeText(JSONObject().put("screen", "C2b-B-add-exercise")
            .put("status", "PROPOSAL_ONLY_NOT_APPROVED_BOARD").put("decision", "S1-D60/S1-D63/S1-D64").put("units", "dp")
            .put("sourceReport", "android/app/build/outputs/conformance/C2b-B-add-exercise/C2b-B-add-exercise.report.json")
            .put("sourceSha256", result.getString("sha256")).put("layerCount", proposal.length()).put("layers", proposal).toString(2))
    }
@Test fun addExerciseLibraryConformance() = compare("C2b-B-add-exercise", "design/experience-t2/screens/C2b-B-add-exercise-library.png", true)
}

private fun androidx.compose.ui.graphics.Color.toArgbHex(): String = "#%06x".format(toArgb() and 0xffffff)
