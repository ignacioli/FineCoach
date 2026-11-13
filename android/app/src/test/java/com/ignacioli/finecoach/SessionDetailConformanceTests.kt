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
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import androidx.compose.ui.unit.height
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.session.ActiveSessionScreen
import com.ignacioli.finecoach.storage.repository.StudentRepository
import java.io.File
import android.graphics.RectF
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
class SessionDetailConformanceTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: SessionDetailConformanceFixture? = null
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    @After fun close() {
        compose.mainClock.autoAdvance = true
        compose.runOnUiThread { compose.activity.setContent {} }
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        fixture?.close(); fixture = null
    }
    private fun render(out: File): JSONArray {
        val f = SessionDetailConformanceFixture().also { fixture = it }
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { ConformanceViewport {
                    com.ignacioli.finecoach.features.history.HistoryDetailScreen(f.state, f.sessionID, f.zone, {}, f.templates)
                } }
            }
        } }
        // load() publishes detail/name before clearing busy; wait for the real settled state.
        compose.waitUntil(15_000) { exists("history-save-template") && f.state.studentName == "王小明" && !f.state.busy }
        compose.waitForIdle()
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        node("platform-content").assertTopPositionInRootIsEqualTo(52.dp)
        node("history-record-date").assertTextEquals("9月25日 周四")
        node("history-record-title").assertTextEquals("大腿、臀训练")
        node("history-student-name").assertTextEquals("王小明")
        node("history-total-reps").assertTextEquals("139")
        compose.onNodeWithText("58", useUnmergedTree = true).assertIsDisplayed()
        for (tag in listOf("history-edit-focus-entry", "history-save-template")) {
            val action = node(tag)
            action.assertIsDisplayed().assertHasClickAction().assertIsEnabled()
            Assert.assertEquals(node("history-actions").getUnclippedBoundsInRoot().width, action.getUnclippedBoundsInRoot().width)
        }
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        check(image.width == 780 && image.height == 1688)
        File(out, "35-session-detail-s1.android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
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
                .put("heading", n.config.contains(SemanticsProperties.Heading)).put("ancestors", JSONArray(ancestors)).put("contentDescriptions", JSONArray(n.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty())).put("clickable", n.config.contains(SemanticsActions.OnClick)).put("text", editable ?: texts.joinToString("\n"))
                .put("placed", n.layoutInfo.isPlaced).put("attached", n.layoutInfo.isAttached)
                .put("unclipped", unclipped).put("scrollAncestors", scrollAncestors)
                .put("hex", argb ?: JSONObject.NULL).put("alpha", if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) color.alpha.toDouble() else 1.0)
                .put("x", bounds.left / 2).put("y", bounds.top / 2).put("w", bounds.width / 2).put("h", bounds.height / 2))
        }
        return nodes
    }
    @Test fun sessionDetailConformance() {
        val app = File(System.getProperty("finecoach.storageProjectDirectory"))
        val android = app.parentFile
        val out = File(app, "build/outputs/conformance/35-session-detail-s1").apply { mkdirs() }
        val hashes = mutableListOf<String>()
        var nodes = JSONArray()
        for (run in 1..2) {
            nodes = render(out)
            val bytes = File(out, "35-session-detail-s1.android.png").readBytes()
            hashes += MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            File(out, "35-session-detail-s1.run$run.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
            close()
        }
        File(out, "35-session-detail-s1.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
        val result = ConformanceComparison.run(android, out, nodes, emptyMap(), "35-session-detail-s1", "design/m1-b-hifi/screens/35-session-detail-s1.png")
        result.put("stability", JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1))
        result.put("humanReadSummary", "批准 PNG 查看一次；未打开 Android capture。负责人视觉验收 PENDING。")
        ConformanceComparison.writeReports(out, result)
        writeProposal(android, result)
        ConformanceSsimAlignment.evaluate(app, out.parentFile)
        Assert.assertEquals("VALID_FIXTURE", result.getString("artifactStatus"))
        Assert.assertEquals("Fixture must be stable", 1, hashes.distinct().size)
        // Preserve all measured diagnostics before enforcing the strict gate.
        Assert.assertEquals(57, result.getJSONArray("elements").length())
        Assert.assertTrue("Session detail strict board diagnostic: see report.json", result.getBoolean("gatePassed"))
    }
    private fun writeProposal(android: File, result: JSONObject) {
        val board = JSONObject(File(android, "design-assets/conformance/35-session-detail-s1.layers.json").readText()).getJSONArray("layers")
        val rows = result.getJSONArray("elements")
        val proposal = JSONArray()
        for (i in 0 until board.length()) {
            val layer = board.getJSONObject(i)
            val row = (0 until rows.length()).map { rows.getJSONObject(it) }.single { it.getString("path") == layer.getString("path") }
            val entry = JSONObject().put("path", layer.getString("path")).put("name", layer.getString("name"))
                .put("coordinateSpace", "390×844 board dp; measured production layout")
            val observed = row.optJSONObject("actual")
            val layout = observed?.let { it.optJSONObject("unclipped") ?: it }
            val vectorPath = layer.getString("type") == "path"
            val actual = if (vectorPath && layout != null) {
                // Proposal only: actual parent layout + canonical vector path, never board child bounds.
                val name = checkNotNull(observed).getString("tag").substringAfter("conformance:icon / ")
                val svg = File(android.parentFile, "design/m1-b-hifi/icons/$name.svg").readText()
                val pathData = Regex("""\bd="([^"]+)"""").find(svg)!!.groupValues[1]
                val path = androidx.core.graphics.PathParser.createPathFromPathData(pathData)!!
                val bounds = RectF()
                path.computeBounds(bounds, true)
                JSONObject().put("x", layout.getDouble("x") + bounds.left * layout.getDouble("w") / 24)
                    .put("y", layout.getDouble("y") + bounds.top * layout.getDouble("h") / 24)
                    .put("w", bounds.width() * layout.getDouble("w") / 24)
                    .put("h", bounds.height() * layout.getDouble("h") / 24)
            } else layout
            if (actual != null) {
                val delta = JSONObject()
                for (key in listOf("x", "y", "w", "h")) {
                    entry.put(key, actual.getDouble(key)); delta.put(key, actual.getDouble(key) - layer.getDouble(key))
                }
                entry.put("source", "production Compose semantics; DS-PAGE-FLOW / DS-PAGE-HEADER / iOS page-style blocks / equipment SVG tokens")
                    .put("measurement", if (vectorPath) "MEASURED_PARENT_AND_CANONICAL_VECTOR_PATH" else "DIRECT_LAYOUT")
                    .put("box", if (vectorPath) "VECTOR_PATH_BOUNDS_WITHOUT_STROKE" else if (layer.getString("type") == "text") "TOKEN_LINE_BOX" else "VISIBLE_SHAPE_LAYOUT")
                    .put("deltaFromOldBoard", delta)
                if (layer.has("text")) entry.put("text", observed!!.getString("text"))
            } else {
                for (key in listOf("x", "y", "w", "h")) entry.put(key, JSONObject.NULL)
                entry.put("source", "UNCONFIRMED: automatic mapping found no unique observable node")
                    .put("measurement", "BLOCKED_NODE_MAPPING").put("deltaFromOldBoard", JSONObject.NULL)
            }
            proposal.put(entry)
        }
        val target = File(android, "build/outputs/conformance/35-session-detail-s1").apply { mkdirs() }
        File(target, "proposed-board.json").writeText(JSONObject().put("screen", "35-session-detail-s1")
            .put("status", "PROPOSAL_ONLY_NOT_APPROVED_BOARD").put("decision", "S1-D53/S1-D66/S1-D78")
            .put("units", "dp").put("sourceReport", "android/app/build/outputs/conformance/35-session-detail-s1/35-session-detail-s1.report.json")
            .put("sourceSha256", result.getString("sha256")).put("layerCount", proposal.length()).put("layers", proposal).toString(2))
    }
}

private fun androidx.compose.ui.graphics.Color.toArgbHex(): String = "#%06x".format(toArgb() and 0xffffff)
