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
import java.io.File
import java.security.MessageDigest
import org.junit.*
import org.junit.runner.RunWith
import org.json.JSONArray
import org.json.JSONObject
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode



@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StudentListConformanceTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: StudentListConformanceFixture? = null
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
        val f = StudentListConformanceFixture().also { fixture = it }
        val routes = mutableListOf<String>()
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { ConformanceViewport {
                    Box(Modifier.fillMaxSize().background(com.ignacioli.finecoach.designsystem.FcColors.surfacePage).testTag("conformance:Rectangle")) {
                        com.ignacioli.finecoach.features.students.StudentListScreen(f.state, routes::add, showRootSwitch = true, autoLoad = false)
                    }
                } }
            }
        } }
        compose.waitUntil(15_000) { exists(com.ignacioli.finecoach.features.students.StudentTestTags.STUDENT_LIST_ADD) }
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        node("platform-content").assertTopPositionInRootIsEqualTo(52.dp)
        for (text in listOf("王小明", "张伟", "李娜", "课包剩余 12 课时", "课包剩余 8 课时", "已归档 · 2")) {
            compose.onNodeWithText(text, useUnmergedTree = true).assertIsDisplayed()
        }
        compose.onAllNodesWithText("未设重点", useUnmergedTree = true).assertCountEquals(3)
        compose.onNodeWithText("王小明 训练中 · 已训练 32 分钟", useUnmergedTree = true).assertIsDisplayed()
        val width = node("platform-content").getUnclippedBoundsInRoot().width
        for (tag in listOf(com.ignacioli.finecoach.features.students.StudentTestTags.STUDENT_LIST_ADD,
            com.ignacioli.finecoach.features.students.StudentTestTags.STUDENT_LIST_ARCHIVED,
            com.ignacioli.finecoach.features.students.StudentTestTags.STUDENT_LIST_IN_PROGRESS)) {
            node(tag).assertIsDisplayed().assertHasClickAction()
            Assert.assertEquals(width, node(tag).getUnclippedBoundsInRoot().width)
        }
        val expectedRoutes = mutableListOf<String>()
        for (student in f.state.uiState.students) {
            val row = node(com.ignacioli.finecoach.features.students.StudentTestTags.studentRow(student.studentID))
            row.assertIsDisplayed().assertHasClickAction()
            Assert.assertEquals(width, row.getUnclippedBoundsInRoot().width)
            row.performSemanticsAction(SemanticsActions.OnClick) { it() }
            expectedRoutes += com.ignacioli.finecoach.navigation.S1Routes.studentDetail(student.studentID)
        }
        for ((tag, route) in listOf(
            "student-list-resource-hub" to com.ignacioli.finecoach.navigation.S1Routes.RESOURCE_HUB,
            "studentList.segment-0" to com.ignacioli.finecoach.navigation.S1Routes.TODAY,
            "studentList.inProgress" to com.ignacioli.finecoach.navigation.S1Routes.activeSession(f.sessionID),
            "studentList.add" to com.ignacioli.finecoach.navigation.S1Routes.STUDENT_CREATE)) {
            node(tag).assertIsDisplayed().assertHasClickAction().performSemanticsAction(SemanticsActions.OnClick) { it() }
            expectedRoutes += route
        }
        Assert.assertEquals(expectedRoutes, routes)
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        check(image.width == 780 && image.height == 1688)
        File(out, "21-student-list-s1.android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
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
    @Test fun studentListConformance() {
        val app = File(System.getProperty("finecoach.storageProjectDirectory"))
        val android = app.parentFile
        val out = File(app, "build/outputs/conformance/21-student-list-s1").apply { mkdirs() }
        val hashes = mutableListOf<String>()
        var nodes = JSONArray()
        for (run in 1..2) {
            nodes = render(out)
            val bytes = File(out, "21-student-list-s1.android.png").readBytes()
            hashes += MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            File(out, "21-student-list-s1.run$run.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
            close()
        }
        File(out, "21-student-list-s1.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
        val result = try {
            ConformanceComparison.run(android, out, nodes, emptyMap(), "21-student-list-s1", "design/m1-b-hifi/screens/21-student-list-s1.png")
        } catch (error: IllegalStateException) {
            // Persist the diagnostic without inventing comparison results or bypassing the gate.
            File(out, "21-student-list-s1.blocked.json").writeText(JSONObject()
                .put("screen", "21-student-list-s1").put("gatePassed", false)
                .put("artifactStatus", "COMPARISON_BLOCKED").put("reason", error.message)
                .put("perCheckCounts", JSONObject.NULL).put("layerCount", JSONObject(File(android, "design-assets/conformance/21-student-list-s1.layers.json").readText()).getJSONArray("layers").length())
                .put("stability", JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1))
                .toString(2))
            throw error
        }
        result.put("stability", JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1))
        result.put("humanReadSummary", "批准 PNG 查看一次；未打开 Android capture。负责人视觉验收 PENDING。")
        ConformanceComparison.writeReports(out, result)
        Assert.assertEquals("VALID_FIXTURE", result.getString("artifactStatus"))
        Assert.assertEquals("Fixture must be stable", 1, hashes.distinct().size)
        Assert.assertTrue("Student list strict current-board diagnostic: " + result, result.getBoolean("gatePassed"))
    }

}

private fun androidx.compose.ui.graphics.Color.toArgbHex(): String = "#%06x".format(toArgb() and 0xffffff)
