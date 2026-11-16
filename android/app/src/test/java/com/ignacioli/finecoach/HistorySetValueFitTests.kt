// fictional-data: synthetic weights and repetitions; isolated Room database.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.history.*
import com.ignacioli.finecoach.storage.repository.StudentRepository
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HistorySetValueFitTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var f: T009Fixture
    @Before fun prepare() { f = T009Fixture() }
    @After fun close() {
        compose.runOnUiThread { compose.activity.setContent {} }
        compose.waitForIdle()
        f.close()
    }

    @Test fun valuesAtNormalFontScale() = verify(1f)
    @Test fun valuesAtFontScaleOnePointThree() = verify(1.3f)
    @Test fun valuesAtFontScaleTwo() = verify(2f)
    @Test fun durationAtNormalFontScale() = verify(1f, RecordMode.duration)
    @Test fun durationAtFontScaleOnePointThree() = verify(1.3f, RecordMode.duration)
    @Test fun durationAtFontScaleTwo() = verify(2f, RecordMode.duration)
    @Test fun cardioAtNormalFontScale() = verify(1f, RecordMode.cardio)
    @Test fun cardioAtFontScaleOnePointThree() = verify(1.3f, RecordMode.cardio)
    @Test fun cardioAtFontScaleTwo() = verify(2f, RecordMode.cardio)

    private fun verify(scale: Float, mode: RecordMode = RecordMode.weightReps) {
        lateinit var saved: SessionContentRecord
        lateinit var state: HistoryUiState
        lateinit var sets: List<TrainingSet>
        f.test {
            val content = f.content()
            val exercise = content.exercises.single()
            fun input(weight: String, reps: String, side: SetSide = SetSide.none) = TrainingSetInput(
                RecordMode.weightReps, weightValue = weight, repetitionCount = reps,
                unit = MeasurementUnit.kilograms, side = side,
                leftValue = weight.takeIf { side == SetSide.left || side == SetSide.bilateral },
                rightValue = weight.takeIf { side == SetSide.right || side == SetSide.bilateral })
            val inputs = if (mode == RecordMode.weightReps) listOf(input("60", "12"), input("102.5", "12"), input("142.5", "15"),
                input("147.5", "10", SetSide.left), input("102.5", "12", SetSide.right),
                input("102.5", "12", SetSide.bilateral), input("1000", "1"),
                input("60", "12"), input("142.5", "15"),
                input("147.5", "10", SetSide.left), input("102.5", "12", SetSide.right))
            else listOf(TrainingSetInput(mode, durationSeconds = "1425", unit = MeasurementUnit.seconds,
                distanceValue = "12.5".takeIf { mode == RecordMode.cardio }))
            sets = inputs.mapIndexed { index, input -> TrainingSet.makeDraft(f.ids.newTrainingSetID(),
                exercise.sessionExerciseID, index.toUInt(), input, f.now).confirmed(f.now) }
            saved = f.ok(f.sessions.saveContent(SaveSessionContentCommand(content.session.sessionID,
                content.session.revision, emptyList(), listOf(exercise.copy(recordModeSnapshot = mode,
                    sets = sets.map { it.toRecord() })))))
            f.now = f.now.plusSeconds(90)
            f.finish(saved)
            state = HistoryUiState(f.historyCases, f.studentID,
                StudentUseCases(StudentRepository(f.db, f.clock), f.clock, f.ids))
        }
        lateinit var tokenStyle: TextStyle
        lateinit var textMeasurer: TextMeasurer
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, scale)) {
                FineCoachTheme { ConformanceViewport {
                    tokenStyle = FcTypography.style("callout", 400)
                    textMeasurer = rememberTextMeasurer()
                    HistoryDetailScreen(state, saved.session.sessionID, f.zone, {})
                } }
            }
        }
        compose.waitUntil(15_000) { state.detail != null && !state.busy }
        compose.waitForIdle()
        val baselines = mutableListOf<Float>()
        val layouts = mutableListOf<TextLayoutResult>()
        // Semantics restores the caller's style in layoutInput; compare the actual glyph
        // intrinsics with independent token-sized measurements to verify the rendered size.
        fun widthAt(layout: TextLayoutResult, factor: Float) = textMeasurer.measure(
            layout.layoutInput.text, style = tokenStyle.copy(fontSize = tokenStyle.fontSize * factor)
        ).multiParagraph.intrinsics.maxIntrinsicWidth
        sets.forEachIndexed { index, set ->
            val cell = compose.onNodeWithTag("history-set-${set.trainingSetID.value}", useUnmergedTree = true)
            val value = cell.onChildren()[1]
            val results = mutableListOf<TextLayoutResult>()
            value.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
            val layout = results.single()
            layouts += layout
            val label = "scale=$scale index=${index + 1} ${set.displaySummary()}"
            assertFalse(label, layout.hasVisualOverflow)
            for (line in 0 until layout.lineCount) {
                assertFalse(label, layout.isLineEllipsized(line))
                assertTrue("$label line=$line right=${layout.getLineRight(line)} width=${layout.size.width}",
                    layout.getLineRight(line) <= layout.size.width)
            }
            fun compact(text: String) = text.replace(Regex("[ \\u00a0\\r\\n]"), "")
            val laidOutText = (0 until layout.lineCount).joinToString("\n") { line ->
                layout.layoutInput.text.text.substring(layout.getLineStart(line), layout.getLineEnd(line))
            }
            assertEquals(label, compact(set.displaySummary()), compact(laidOutText))
            assertEquals(label, set.displaySummary().replace(" kg", "\u00a0kg").replace(" 分", "\u00a0分")
                .replace(" 秒", "\u00a0秒").replace(" km", "\u00a0km").replace("× ", "×\u00a0"),
                layout.layoutInput.text.text)
            val baseline = value.getUnclippedBoundsInRoot().top.value + value.getAlignmentLinePosition(FirstBaseline).value
            val indexText = cell.onChildren()[0]
            assertEquals(label, baseline, indexText.getUnclippedBoundsInRoot().top.value +
                indexText.getAlignmentLinePosition(FirstBaseline).value, if (scale == 1f) 0f else 1f)
            baselines += baseline
            if (scale == 1f && set.displaySummary() == "60 kg × 12") {
                assertEquals(label, 1, layout.lineCount)
                assertEquals(label, widthAt(layout, 1f), layout.multiParagraph.intrinsics.maxIntrinsicWidth, 0f)
            }
        }
        baselines.chunked(3).forEach { row -> row.forEach {
            assertEquals("row baseline at scale=$scale", row.first(), it, if (scale == 1f) 0f else 1f)
        } }
        if (scale == 1.3f && mode == RecordMode.weightReps) assertTrue("Shrink before wrapping", layouts.any {
            it.lineCount == 1 && it.multiParagraph.intrinsics.maxIntrinsicWidth < widthAt(it, 1f)
        })
        if (scale == 2f) assertTrue("Wrap at the minimum size", layouts.any { it.lineCount > 1 })
        layouts.filter { it.lineCount > 1 }.forEach {
            assertEquals(widthAt(it, 0.8f), it.multiParagraph.intrinsics.maxIntrinsicWidth, 0f)
        }
    }
}
