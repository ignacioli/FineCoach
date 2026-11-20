// fictional-data: opaque synthetic identifiers, no real records.
package com.ignacioli.finecoach
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.insight.Insight
import com.ignacioli.finecoach.storage.local.InsightLocalStateStore
import java.io.File
import java.nio.file.Files
import java.time.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class InsightLocalStateStoreTests {
    private fun run(action: (File) -> Unit) { val dir = Files.createTempDirectory("s3-local-").toFile(); try { action(dir) } finally { dir.deleteRecursively() } }
    private val insight = Insight(Insight.Kind.inactive, S3Fixtures.student)
    @Test fun survivesReconstructionAndExpiresOnFourteenthLocalDay() = run { dir ->
        val store = InsightLocalStateStore(dir); assertFalse(store.firstNudgePlayed())
        assertTrue(store.snooze(insight, S3Fixtures.now, S3Fixtures.zone) is ApplicationResult.Success)
        assertTrue(store.markFirstNudgePlayed() is ApplicationResult.Success)
        val restarted = InsightLocalStateStore(dir)
        assertTrue(restarted.firstNudgePlayed()); assertEquals(setOf(insight.snoozeKey), restarted.activeKeys(S3Fixtures.now, S3Fixtures.zone))
        val until = S3Fixtures.now.atZone(S3Fixtures.zone).toLocalDate().plusDays(14).atStartOfDay(S3Fixtures.zone).toInstant()
        assertEquals(setOf(insight.snoozeKey), restarted.activeKeys(until.minusNanos(1), S3Fixtures.zone))
        assertTrue(restarted.activeKeys(until, S3Fixtures.zone).isEmpty())
        assertTrue(!File(dir, "Insights/local-state.json").readText().contains(insight.snoozeKey))
    }
    @Test fun undoAndCorruptionAreSafe() = run { dir ->
        val store = InsightLocalStateStore(dir)
        store.snooze(insight, S3Fixtures.now, S3Fixtures.zone)
        assertTrue(store.unsnooze(insight) is ApplicationResult.Success)
        assertTrue(store.activeKeys(S3Fixtures.now, S3Fixtures.zone).isEmpty())
        File(dir, "Insights/local-state.json").writeText("{broken")
        assertTrue(InsightLocalStateStore(dir).activeKeys(S3Fixtures.now, S3Fixtures.zone).isEmpty())
        assertFalse(InsightLocalStateStore(dir).firstNudgePlayed())
        assertTrue(store.snooze(insight, S3Fixtures.now, S3Fixtures.zone) is ApplicationResult.Success)
    }
    @Test fun onlyOpaqueKeysAndAllowlistedFieldsPersist() = run { dir ->
        val store = InsightLocalStateStore(dir)
        store.snooze(insight.copy(balance = 987654321, daysInactive = 987654321), S3Fixtures.now, S3Fixtures.zone)
        val root = org.json.JSONObject(File(dir, "Insights/local-state.json").readText())
        assertEquals(setOf("version", "entries", "firstNudgePlayed"), root.keys().asSequence().toSet())
        assertFalse(root.toString().contains("987654321"))
        val invalid = insight.copy(kind = Insight.Kind.stagnant, exerciseID = com.ignacioli.finecoach.core.domain.common.StableExerciseID.parse("not-opaque"))
        assertTrue(store.snooze(invalid, S3Fixtures.now, S3Fixtures.zone) is ApplicationResult.Failure)
        assertEquals(setOf(insight.snoozeKey), store.activeKeys(S3Fixtures.now, S3Fixtures.zone))
        assertTrue(File(dir, "Insights").listFiles()!!.none { it.name.endsWith(".tmp") })
    }
    @Test fun writeFailureDoesNotClaimSuccessOrReplaceValidState() = run { dir ->
        val store = InsightLocalStateStore(dir); store.snooze(insight, S3Fixtures.now, S3Fixtures.zone)
        val path = File(dir, "Insights/local-state.json"); val bytes = path.readBytes()
        path.delete(); path.mkdir()
        assertTrue(store.markFirstNudgePlayed() is ApplicationResult.Failure)
        path.delete(); path.writeBytes(bytes)
        assertFalse(store.firstNudgePlayed()); assertEquals(setOf(insight.snoozeKey), store.activeKeys(S3Fixtures.now, S3Fixtures.zone))
    }
}
