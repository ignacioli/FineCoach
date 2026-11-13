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
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h885dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StudentDetailConformanceTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: StudentDetailConformanceFixture? = null
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
        val f = StudentDetailConformanceFixture().also { fixture = it }
        val routes = mutableListOf<String>()
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { Box(Modifier.requiredSize(390.dp, 885.dp).background(com.ignacioli.finecoach.designsystem.FcColors.surfacePage).testTag("conformance-viewport")) {
                    Box(Modifier.fillMaxSize().background(com.ignacioli.finecoach.designsystem.FcColors.surfacePage).testTag("conformance:Rectangle")) {
                        com.ignacioli.finecoach.features.students.StudentDetailScreen(f.state, routes::add, {}, autoLoad = false)
                    }
                } }
            }
        } }
        compose.waitUntil(15_000) { exists("studentDetail.startTraining") }
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        node("platform-content").assertTopPositionInRootIsEqualTo(52.dp)
        for (text in listOf("王小明", "训练目标 · 增肌", "9月25日 · 大腿、臀 · 12 组", "开始训练")) {
            compose.onNodeWithText(text, useUnmergedTree = true).assertIsDisplayed()
        }
        for (tag in listOf("studentDetail.coursePackages", "studentDetail.recentTraining", "studentDetail.history", "studentDetail.injuryNotesFold", "studentDetail.startTraining")) {
            node(tag).assertIsDisplayed().assertHasClickAction()
            Assert.assertEquals(node("platform-content").getUnclippedBoundsInRoot().width, node(tag).getUnclippedBoundsInRoot().width)
        }
        // Match the shipped default state; sensitive cautions remain in the repository fixture.
        Assert.assertFalse(f.state.uiState.notesExpanded)
        compose.onNodeWithText("已隐藏 · 点击查看", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("此内容不是医疗诊断或医疗建议。仅教练可见，不进入分享报告。", useUnmergedTree = true).assertDoesNotExist()
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        check(image.width == 780 && image.height == 1770)
        File(out, "26-student-detail-s1.android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
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
    @Test fun studentDetailConformance() {
        val app = File(System.getProperty("finecoach.storageProjectDirectory"))
        val android = app.parentFile
        val out = File(app, "build/outputs/conformance/26-student-detail-s1").apply { mkdirs() }
        val hashes = mutableListOf<String>()
        var nodes = JSONArray()
        for (run in 1..2) {
            nodes = render(out)
            val bytes = File(out, "26-student-detail-s1.android.png").readBytes()
            hashes += MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            File(out, "26-student-detail-s1.run$run.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
            close()
        }
        File(out, "26-student-detail-s1.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
        val result = ConformanceComparison.run(android, out, nodes, emptyMap(), "26-student-detail-s1", "design/m1-b-hifi/screens/26-student-detail-s1.png")
        result.put("stability", JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1))
        result.put("humanReadSummary", "批准 PNG 查看一次；未打开 Android capture。负责人视觉验收 PENDING。")
        ConformanceComparison.writeReports(out, result)
        writeProposal(android, result, nodes)

        Assert.assertEquals("VALID_FIXTURE", result.getString("artifactStatus"))
        Assert.assertEquals("Fixture must be stable", 1, hashes.distinct().size)
        Assert.assertTrue("Student detail strict current-board diagnostic: " + result, result.getBoolean("gatePassed"))
    }
    private fun writeProposal(android: File, result: JSONObject, nodes: JSONArray) {
        val board = JSONObject(File(android, "design-assets/conformance/26-student-detail-s1.layers.json").readText()).getJSONArray("layers")
        val rows = result.getJSONArray("elements")
        val proposal = JSONArray()
        for (i in 0 until board.length()) {
            val layer = board.getJSONObject(i)
            val row = (0 until rows.length()).map { rows.getJSONObject(it) }.single { it.getString("path") == layer.getString("path") }
            val entry = JSONObject().put("path", layer.getString("path")).put("name", layer.getString("name"))
                .put("coordinateSpace", "390×885 board dp; measured production layout")
            // Proposal only: preserve identities when rough board positions make the strict
            // automatic pairing ambiguous. This does not affect the comparison or its result.
            val allNodes = (0 until nodes.length()).map { nodes.getJSONObject(it) }
            val sameKind = (0 until board.length()).map { board.getJSONObject(it) }.filter {
                if (layer.has("text")) it.optString("text") == layer.getString("text")
                else it.getString("name") == layer.getString("name")
            }
            val candidates = allNodes.filter {
                if (layer.has("text")) it.optString("text") == layer.getString("text") && !it.isNull("hex")
                else it.optString("tag") == "conformance:${layer.getString("name")}"
            }.sortedBy { it.getJSONObject("unclipped").getDouble("y") }
            val rowScope = when (layer.getString("path")) {
                "11" -> "studentDetail.coursePackages"
                "15" -> "studentDetail.recentTraining"
                "20" -> "studentDetail.history"
                else -> null
            }
            val observed = if (rowScope != null) candidates.singleOrNull {
                val ancestors = it.getJSONArray("ancestors")
                (0 until ancestors.length()).any { index -> ancestors.getString(index) == rowScope }
            } else if (candidates.size == sameKind.size) candidates[sameKind.indexOf(layer)]
                else row.optJSONObject("actual")
            val actual = observed?.let { it.optJSONObject("unclipped") ?: it }
            if (actual != null) {
                val delta = JSONObject()
                for (key in listOf("x", "y", "w", "h")) {
                    entry.put(key, actual.getDouble(key)); delta.put(key, actual.getDouble(key) - layer.getDouble(key))
                }
                entry.put("source", "production Compose semantics; DS-PAGE-FLOW / DS-PAGE-HEADER / DS-AVATAR / DS-LABEL-VALUE-ROW tokens")
                    .put("measurement", "DIRECT_LAYOUT").put("box", if (layer.getString("type") == "text") "TOKEN_LINE_BOX" else "VISIBLE_SHAPE_LAYOUT")
                    .put("deltaFromOldBoard", delta)
                    .put("clipped", observed!!.getDouble("w") == 0.0 || observed.getDouble("h") == 0.0)
                if (layer.has("text")) entry.put("text", observed!!.getString("text"))
            } else entry.put("source", "UNCONFIRMED").put("measurement", "No unique measured shape")
            proposal.put(entry)
        }
        val target = File(android, "build/outputs/conformance/26-student-detail-s1").apply { mkdirs() }
        File(target, "proposed-board.json").writeText(JSONObject().put("screen", "26-student-detail-s1")
            .put("status", "PROPOSAL_ONLY_NOT_APPROVED_BOARD").put("decision", "S1-D53/S1-D66/S1-D77")
            .put("units", "dp").put("sourceReport", "android/app/build/outputs/conformance/26-student-detail-s1/26-student-detail-s1.report.json")
            .put("sourceSha256", result.getString("sha256")).put("layerCount", proposal.length()).put("layers", proposal).toString(2))
    }
}

private fun androidx.compose.ui.graphics.Color.toArgbHex(): String = "#%06x".format(toArgb() and 0xffffff)
