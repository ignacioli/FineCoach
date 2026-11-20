// fictional-data: invented sessions for 杠铃深蹲, 杠铃平板卧推 and 平板支撑; no real coach or student.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.trends.TrendMetric
import com.ignacioli.finecoach.features.trends.TrendsScreen
import com.ignacioli.finecoach.features.trends.TrendsState
import com.ignacioli.finecoach.storage.repository.ExerciseRepository
import java.io.File
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TrendsConformanceTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: T009Fixture? = null
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    @After fun close() {
        compose.mainClock.autoAdvance = true
        compose.runOnUiThread { compose.activity.setContent {} }
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        fixture?.close(); fixture = null
    }

    private data class Item(val source: com.ignacioli.finecoach.core.domain.common.StableExerciseID, val name: String, val mode: RecordMode, val weight: String?, val reps: String?, val duration: String?)

    private fun render(out: File): JSONArray {
        val f = T009Fixture().also { fixture = it }
        val zone = ZoneId.of("Asia/Shanghai")
        lateinit var state: TrendsState
        f.test {
            val repo = ExerciseRepository(f.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets), f.clock)
            repo.prepareCatalog()
            val catalog = f.ok(repo.listCatalog())
            fun id(name: String) = catalog.single { it.canonicalName == name }.exerciseID
            val squat = id("杠铃深蹲")
            val bench = id("杠铃平板卧推")
            val plank = id("平板支撑")
            suspend fun session(day: LocalDate, items: List<Item>, hour: Int = 0, minute: Int = 0, second: Int = 0) {
                val at = day.atTime(hour, minute, second).atZone(zone).toInstant()
                f.now = at
                val opened = f.ok(f.sessions.startOrOpen(StartOrOpenSessionCommand(f.studentID, nowUTC = at)))
                val rows = items.mapIndexed { index, item ->
                    val exerciseID = f.ids.newSessionExerciseID()
                    val set = TrainingSet.makeDraft(f.ids.newTrainingSetID(), exerciseID, 0u, TrainingSetInput(item.mode,
                        weightValue = item.weight, repetitionCount = item.reps, durationSeconds = item.duration,
                        unit = if (item.mode == RecordMode.duration) MeasurementUnit.seconds else MeasurementUnit.kilograms), at).confirmed(at)
                    SessionExercise(exerciseID, opened.sessionID, index.toUInt(), ExerciseSourceKind.builtIn, item.source,
                        NormalizedName.parse(item.name), item.mode, null, null, listOf(set)).toRecord()
                }
                f.finish(f.ok(f.sessions.saveContent(SaveSessionContentCommand(opened.sessionID, opened.revision, emptyList(), rows))))
            }
            val year = 2025
            // Point dates and loads follow the board fractions through the existing date axis and Epley formula.
            session(LocalDate.of(year, 8, 7), listOf(Item(squat, "杠铃深蹲", RecordMode.weightReps, "36", "7", null), Item(bench, "杠铃平板卧推", RecordMode.weightReps, "40", "5", null)))
            session(LocalDate.of(year, 8, 15), listOf(Item(squat, "杠铃深蹲", RecordMode.weightReps, "45", "6", null)))
            session(LocalDate.of(year, 8, 24), listOf(Item(squat, "杠铃深蹲", RecordMode.weightReps, "44", "9", null)))
            session(LocalDate.of(year, 9, 2), listOf(Item(squat, "杠铃深蹲", RecordMode.weightReps, "61", "6", null)))
            session(LocalDate.of(year, 9, 11), listOf(Item(squat, "杠铃深蹲", RecordMode.weightReps, "69", "6", null), Item(plank, "平板支撑", RecordMode.duration, null, null, "1920")))
            session(LocalDate.of(year, 9, 20), listOf(Item(squat, "杠铃深蹲", RecordMode.weightReps, "81", "6", null)))
            session(LocalDate.of(year, 9, 25), listOf(Item(squat, "杠铃深蹲", RecordMode.weightReps, "90", "4", null), Item(bench, "杠铃平板卧推", RecordMode.weightReps, "70", "6", null)),
                hour = 15, minute = 16, second = 22)
            state = TrendsState(f.studentID, ProgressUseCases(f.history, f.sessions), zone)
            state.load()
        }
        val metric = state.content!!.metrics.indexOf(TrendMetric.estimatedOneRepMax)
        state.selectMetric(metric)
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { Box(Modifier.requiredSize(390.dp, 900.dp).background(FcColors.surfacePage).testTag("conformance-viewport")) {
                    TrendsScreen(state) {}
                } }
            }
        } }
        compose.waitUntil(15_000) { exists("trends-caption") && exists("trends-best-2") }
        compose.waitForIdle()
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        node("platform-content").assertTopPositionInRootIsEqualTo(52.dp)
        node("trends-exercise-name").assertTextEquals("杠铃深蹲")
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        check(image.width == 780 && image.height == 1800)
        File(out, "trends-s3.android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        val all = compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes().flatMap { root ->
            fun descendants(n: SemanticsNode): List<SemanticsNode> = listOf(n) + n.children.flatMap(::descendants)
            descendants(root)
        }.distinctBy { it.id }
        val nodes = JSONArray()
        for (n in all) {
            val texts = n.config.getOrNull(SemanticsProperties.Text)?.map { it.text }.orEmpty()
            val editable = n.config.getOrNull(SemanticsProperties.EditableText)?.text
            val layouts = mutableListOf<TextLayoutResult>()
            n.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            val color = layouts.firstOrNull()?.layoutInput?.style?.color
            val argb = if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) "#%06x".format(color.toArgb() and 0xffffff) else null
            val bounds = n.boundsInRoot
            val unclipped = JSONObject().put("x", n.positionInRoot.x / 2).put("y", n.positionInRoot.y / 2).put("w", n.size.width / 2.0).put("h", n.size.height / 2.0)
            val scrollAncestors = JSONArray()
            generateSequence(n.parent) { it.parent }.filter { it.config.contains(SemanticsActions.ScrollBy) }.forEach { parent ->
                val b = parent.boundsInRoot
                scrollAncestors.put(JSONObject().put("tag", parent.config.getOrNull(SemanticsProperties.TestTag) ?: "").put("x", b.left / 2).put("y", b.top / 2).put("w", b.width / 2).put("h", b.height / 2))
            }
            val ancestors = generateSequence(n.parent) { it.parent }.mapNotNull { it.config.getOrNull(SemanticsProperties.TestTag) }.toList()
            nodes.put(JSONObject().put("id", n.id).put("tag", n.config.getOrNull(SemanticsProperties.TestTag) ?: "")
                .put("heading", n.config.contains(SemanticsProperties.Heading)).put("ancestors", JSONArray(ancestors))
                .put("contentDescriptions", JSONArray(n.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty()))
                .put("clickable", n.config.contains(SemanticsActions.OnClick)).put("text", editable ?: texts.joinToString("\n"))
                .put("placed", n.layoutInfo.isPlaced).put("attached", n.layoutInfo.isAttached)
                .put("unclipped", unclipped).put("scrollAncestors", scrollAncestors)
                .put("textAlign", layouts.firstOrNull()?.layoutInput?.style?.textAlign?.toString() ?: "Start")
                .put("hex", argb ?: JSONObject.NULL)
                .put("alpha", if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) color.alpha.toDouble() else 1.0)
                .put("x", bounds.left / 2).put("y", bounds.top / 2).put("w", bounds.width / 2).put("h", bounds.height / 2))
        }
        return nodes
    }

    @Test fun trendsConformance() {
        val app = File(System.getProperty("finecoach.storageProjectDirectory"))
        val android = app.parentFile
        val out = File(app, "build/outputs/conformance/trends-s3").apply { mkdirs() }
        val hashes = mutableListOf<String>()
        var nodes = JSONArray()
        for (run in 1..2) {
            nodes = render(out)
            val bytes = File(out, "trends-s3.android.png").readBytes()
            hashes += MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            File(out, "trends-s3.run$run.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
            close()
        }
        File(out, "trends-s3.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
        val result = ConformanceComparison.run(android, out, nodes, emptyMap(), "trends-s3", "design/insights/screens/trends-s3.png")
        result.put("stability", JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1))
        result.put("humanReadSummary", "批准 PNG 查看一次；未打开 Android capture。负责人视觉验收 PENDING。")
        ConformanceComparison.writeReports(out, result)
        File(out, "proposed-board.json").writeText(proposal(android, result).toString(2))
        Assert.assertEquals("VALID_FIXTURE", result.getString("artifactStatus"))
        Assert.assertEquals("Fixture must be stable", 1, hashes.distinct().size)
        Assert.assertTrue("Trends strict board diagnostic: see trends-s3.report.json", result.getBoolean("gatePassed"))
    }

    private fun proposal(android: File, result: JSONObject): JSONObject {
        val board = JSONObject(File(android, "design-assets/conformance/trends-s3.layers.json").readText()).getJSONArray("layers")
        val rows = result.getJSONArray("elements")
        val layers = JSONArray()
        for (i in 0 until board.length()) {
            val layer = board.getJSONObject(i)
            val row = (0 until rows.length()).map { rows.getJSONObject(it) }.singleOrNull { it.getString("path") == layer.getString("path") }
            val entry = JSONObject().put("path", layer.getString("path")).put("name", layer.getString("name"))
            val observed = row?.optJSONObject("actual")
            val layout = observed?.let { it.optJSONObject("unclipped") ?: it }
            if (layout != null) {
                val delta = JSONObject()
                for (key in listOf("x", "y", "w", "h")) {
                    entry.put(key, layout.getDouble(key)); delta.put(key, layout.getDouble(key) - layer.getDouble(key))
                }
                entry.put("source", "production Compose semantics; DS-PAGE-FLOW / DS-PAGE-HEADER / DS-SEGMENTED / FcTrendChart")
                    .put("deltaFromOldBoard", delta)
                if (layer.has("text")) entry.put("text", observed.getString("text"))
            }
            layers.put(entry)
        }
        return JSONObject().put("screen", "trends-s3").put("status", "PROPOSAL_ONLY_NOT_APPROVED_BOARD").put("layers", layers)
    }
}
