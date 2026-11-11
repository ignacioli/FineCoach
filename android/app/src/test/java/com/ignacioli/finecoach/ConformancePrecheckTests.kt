package com.ignacioli.finecoach

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ConformancePrecheckTests {
    private val root get() = File(System.getProperty("finecoach.storageProjectDirectory")).parentFile.parentFile
    @Test fun producesSevenReadOnlyReportsWithExerciseRowConflict() {
        val summary = ConformancePrecheck.generate(root, File(root, ".handoff/design/core-raw/core-exports.json"), File(root, "android/build/outputs/conformance/precheck"))
        assertEquals(7, summary.getInt("totalReports"))
        val library = JSONObject(File(root, "android/build/outputs/conformance/precheck/D2b.json").readText())
        val rows = (0 until library.getJSONArray("findings").length()).map { library.getJSONArray("findings").getJSONObject(it) }.filter { it.getString("rule") == "ANATOMY_ROW_PITCH" }
        assertTrue(rows.isNotEmpty()); assertEquals(56.0, rows.first().getDouble("actual"), 0.01)
        assertEquals(69.7, rows.first().getDouble("expected"), 0.01)
    }
    @Test fun tokenTypographyAndColorPassWhileNonTokensAreReported() {
        fun inspect(size: Int, weight: Int, lineHeight: Double, color: String) = ConformancePrecheck.inspect(JSONObject().put("boardName", "fictional").put("layers", JSONArray().put(
            JSONObject().put("path", "a").put("name", "Text").put("type", "text").put("x", 0).put("y", 0).put("w", 50).put("h", 24)
                .put("fontSize", size).put("fontWeight", weight).put("lineHeight", lineHeight).put("fill", color))),
            File(root, "design/design-system/README.md").readText(), File(root, "design/design-system/components.md").readText())
        assertEquals(0, inspect(17, 600, 1.4, "#211f1b").getInt("conflictCount"))
        assertEquals(2, inspect(19, 600, 1.4, "#123456").getInt("conflictCount"))
        assertEquals(1, inspect(17, 900, 1.4, "#211f1b").getInt("conflictCount"))
        assertEquals(1, inspect(17, 600, 1.2, "#211f1b").getInt("conflictCount"))
    }
    @Test fun rowAtAnatomyMinimumDoesNotProducePitchConflict() {
        val raw = JSONObject(File(root, ".handoff/design/core-raw/core-exports.json").readText())
        val board = raw.keys().asSequence().map { raw.getJSONObject(it) }.single { it.getString("boardName") == "D2b 动作库" }
        val layers = board.getJSONArray("layers")
        // Keep one real row, extend only its closing divider to the derived anatomy minimum.
        val sample = (0 until layers.length()).map { layers.getJSONObject(it) }.filter { it.getString("path") in setOf("18", "19", "20", "21", "23") }
        sample.single { it.getString("path") == "23" }.put("y", 303.7)
        val result = ConformancePrecheck.inspect(JSONObject().put("layers", JSONArray(sample)), File(root, "design/design-system/README.md").readText(), File(root, "design/design-system/components.md").readText())
        assertFalse(result.getJSONArray("findings").toString().contains("ANATOMY_ROW_PITCH"))
    }
}
