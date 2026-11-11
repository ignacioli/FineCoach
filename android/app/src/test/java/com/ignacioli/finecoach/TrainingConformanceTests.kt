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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TrainingConformanceTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var fixture: TrainingConformanceFixture
    private var fixtureOpen = false
    @After fun close() {
        if (fixtureOpen) {
            compose.runOnUiThread { compose.activity.setContent {} }
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle(); fixture.close(); fixtureOpen = false
        }
    }
    private fun renderOnce(out: File, run: Int): Pair<JSONArray, Map<String, String>> {
        org.robolectric.Shadows.shadowOf(androidx.test.core.app.ApplicationProvider.getApplicationContext<android.app.Application>()).grantPermissions(android.Manifest.permission.POST_NOTIFICATIONS)
        fixture = TrainingConformanceFixture()
        fixtureOpen = true
        val f = fixture
        compose.mainClock.autoAdvance = false
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { ConformanceViewport {
                    ActiveSessionScreen(f.state, f.content.session.sessionID, f.exercises, f.templates, {}, {},
                        students = StudentRepository(f.room.db, f.room.clock))
                } }
            }
        }
        }
        fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
        fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        compose.waitUntil(15_000) {
            compose.mainClock.advanceTimeByFrame()
            exists("session-add-exercise") && !f.state.busy
        }
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        node("platform-content").assertTopPositionInRootIsEqualTo(52.dp)
        f.confirmSecondAndReferences()
        compose.mainClock.advanceTimeBy(320)
        node("session-exercise-${f.squat.sessionExerciseID.value}").performClick()
        // The add editor needs a few frames to prefill and settle below the exercise header.
        compose.waitUntil(5_000) {
            compose.mainClock.advanceTimeByFrame()
            exists("set-weight-input") && node("set-weight-input").fetchSemanticsNode()
                .config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.EditableText)?.text == "120"
        }
        compose.mainClock.advanceTimeBy(500)
        // Follow the real visible stepper path once; never inject SetText or IME.
        // A paused clock cannot complete a tap inside the scroll container, so run the real gesture on the live clock.
        compose.mainClock.autoAdvance = true
        node("set-weight-plus").assertIsDisplayed().assertIsEnabled().performClick()
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        node("set-weight-input").assertTextEquals("122.5")
        // S1-D37: assert actual rendered glyphs, not just EditableText semantics.
        for (tag in listOf("set-weight-input", "set-reps-input")) {
            val layouts = mutableListOf<TextLayoutResult>()
            node(tag).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { Assert.assertTrue(it(layouts)) }
            Assert.assertEquals(1, layouts.size)
            val bounds = node(tag).fetchSemanticsNode().boundsInRoot
            val layout = layouts.single()
            val glyphs = layout.layoutInput.text.indices.map { layout.getBoundingBox(it) }
            Assert.assertTrue("Numeric glyphs must fit the visible editor", glyphs.all {
                it.left >= 0 && it.top >= 0 && it.right <= bounds.width && it.bottom <= bounds.height
            })
        }
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        File(out, "P0-a2-training.android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        File(out, "P0-a2-training.run$run.png").writeBytes(File(out, "P0-a2-training.android.png").readBytes())
        check(image.width == 780 && image.height == 1688) { "Wrong viewport ${image.width}x${image.height}" }
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
        // Test-side observation of a real layout with no semantics. Never infer
        // Row bounds from target dimensions or the union of child hit targets.
        val map = JSONObject(File(System.getProperty("finecoach.storageProjectDirectory"), "../design-assets/conformance/P0-a2-training.map.json").readText())
        val entries = map.getJSONArray("elements")
        fun parents(info: LayoutInfo?) = generateSequence(info) { it.parentInfo }.toList()
        for (index in 0 until entries.length()) {
            val entry = entries.getJSONObject(index)
            val tags = entry.optJSONArray("commonLayoutParentOfTags") ?: continue
            val children = (0 until tags.length()).map { tagIndex -> all.singleOrNull { it.config.getOrNull(SemanticsProperties.TestTag) == tags.getString(tagIndex) } }
            if (children.any { it == null } || children.isEmpty()) continue
            val chains = children.map { parents(it!!.layoutInfo.parentInfo) }
            val common = chains.first().firstOrNull { candidate -> chains.all { chain -> chain.any { it === candidate } } } ?: continue
            val input = all.singleOrNull { it.config.getOrNull(SemanticsProperties.TestTag) == entry.getString("containsTag") } ?: continue
            if (parents(input.layoutInfo.parentInfo).none { it === common } || !common.isAttached || !common.isPlaced) continue
            val bounds = common.coordinates.boundsInRoot()
            val position = common.coordinates.positionInRoot()
            val source = (0 until nodes.length()).map { nodes.getJSONObject(it) }.single { it.getInt("id") == children.first()!!.id }
            nodes.put(JSONObject().put("id", -1000 - index).put("tag", "").put("text", "").put("hex", JSONObject.NULL)
                .put("geometrySource", "LayoutInfo nearest common parent; input ancestry verified")
                .put("commonLayoutParentOfTags", tags).put("containsTag", entry.getString("containsTag"))
                .put("ancestors", source.getJSONArray("ancestors")).put("scrollAncestors", source.getJSONArray("scrollAncestors"))
                .put("placed", common.isPlaced).put("attached", common.isAttached)
                .put("x", bounds.left / 2).put("y", bounds.top / 2).put("w", bounds.width / 2).put("h", bounds.height / 2)
                .put("unclipped", JSONObject().put("x", position.x / 2).put("y", position.y / 2)
                    .put("w", common.coordinates.size.width / 2.0).put("h", common.coordinates.size.height / 2.0)))
        }
        File(out, "P0-a2-training.nodes.json").writeText(JSONObject().put("nodes", nodes).put("viewport", "390x844@2").toString(2))
        val bindings = f.bindings()
        return nodes to bindings
    }

    @Test fun realTrainingPageProducesConformanceReport() {
        compose.mainClock.autoAdvance = false
        val out = File(System.getProperty("finecoach.storageProjectDirectory"), "build/outputs/conformance").apply { mkdirs() }
        val hashes = mutableListOf<String>()
        var snapshot: Pair<JSONArray, Map<String, String>>? = null
        for (run in 1..2) {
            snapshot = renderOnce(out, run)
            hashes += MessageDigest.getInstance("SHA-256").digest(File(out, "P0-a2-training.run$run.png").readBytes()).joinToString("") { "%02x".format(it) }
            // A new composition and Room store on the next iteration; no cached Bitmap.
            close()
        }
        val stability = JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1)
        File(out, "P0-a2-training.stability.json").writeText(stability.toString(2))
        val (nodes, bindings) = checkNotNull(snapshot)
        val result = ConformanceComparison.run(File(System.getProperty("finecoach.storageProjectDirectory")).parentFile, out, nodes, bindings)
        result.put("stability", stability)
        result.put("ssimCalibration", ConformanceSsimCalibration.evaluate(File(checkNotNull(System.getProperty("finecoach.storageProjectDirectory"))), out))
        ConformanceComparison.writeReports(out, result)
        ConformanceSsimAlignment.evaluate(File(System.getProperty("finecoach.storageProjectDirectory")), out)
        println("S0_CONFORMANCE total=${result.getInt("total")} passed=${result.getInt("passed")} failed=${result.getInt("failed")} missing=${result.getInt("missing")} invisible=${result.getInt("invisible")} hashes=$hashes")
        Assert.assertTrue("Two fresh fixture renders must have identical PNG hashes: $hashes", stability.getBoolean("stable"))
        ConformanceSsimCalibration.assertDiagnostics(result.getJSONObject("ssimCalibration"))
        Assert.assertTrue("Capture and comparison must both pass", result.getBoolean("gatePassed"))
        Assert.assertEquals("Conformance deviations; see build/outputs/conformance/P0-a2-training.report.md", 0, result.getInt("failed"))
    }
}

private fun androidx.compose.ui.graphics.Color.toArgbHex(): String {
    val argb = this.toArgb()
    return "#%06x".format(argb and 0xffffff)
}
