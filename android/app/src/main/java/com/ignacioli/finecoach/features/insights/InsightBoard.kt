package com.ignacioli.finecoach.features.insights

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.ExerciseRecord
import com.ignacioli.finecoach.core.application.InsightUseCases
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.insight.Insight
import java.time.LocalDate
import java.time.ZoneId

internal const val InsightUndoWindowMillis = 4_000L

data class InsightSnapshot(
    val insights: List<Insight>,
    val studentNames: Map<StudentID, String>,
    val exerciseNames: Map<StableExerciseID, String>,
    val nudgePlayed: Boolean,
    val failed: Boolean,
)

/** One published snapshot. The section stays out of the layout until this exists. */
class InsightBoardState(
    private val insights: InsightUseCases,
    private val students: StudentUseCases,
    private val catalog: suspend () -> ApplicationResult<List<ExerciseRecord>>,
    private val clock: AppClock,
    val zone: ZoneId,
    private val monotonicMillis: () -> Long = android.os.SystemClock::elapsedRealtime,
) {
    var snapshot by mutableStateOf<InsightSnapshot?>(null)
        private set
    var pending by mutableStateOf<Map<String, Insight>>(emptyMap())
        private set
    var nudgePhase by mutableStateOf("idle")
        private set

    private val undoDeadlines = mutableMapOf<String, Long>()

    fun undoRemainingMillis(key: String): Long = ((undoDeadlines[key] ?: 0L) - monotonicMillis()).coerceAtLeast(0L)

    suspend fun load(studentID: StudentID? = null) {
        val result = insights.load(clock.now(), zone, studentID)
        val names = when (val listed = students.list()) {
            is ApplicationResult.Failure -> emptyMap()
            is ApplicationResult.Success -> listed.value.associate { it.studentID to it.displayName }
        }
        val exercises = when (val listed = catalog()) {
            is ApplicationResult.Failure -> emptyMap()
            is ApplicationResult.Success -> listed.value.associate { it.exerciseID to it.canonicalName }
        }
        val played = insights.nudgePlayed()
        if (played) nudgePhase = "idle"
        val previous = snapshot?.insights.orEmpty()
        snapshot = when (result) {
            is ApplicationResult.Failure -> InsightSnapshot(emptyList(), names, exercises, played, true)
            is ApplicationResult.Success -> {
                val rows = result.value.toMutableList()
                pending.values.sortedBy { previous.indexOf(it) }.forEach { row ->
                    if (rows.none { it.snoozeKey == row.snoozeKey }) {
                        rows.add(previous.indexOf(row).coerceIn(0, rows.size), row)
                    }
                }
                InsightSnapshot(rows, names, exercises, played, false)
            }
        }
        pending.keys.filter { undoRemainingMillis(it) == 0L }.forEach(::commit)
    }

    fun visible(studentID: StudentID? = null): List<Insight> {
        val rows = (snapshot?.insights.orEmpty() + pending.values).distinctBy { it.snoozeKey }
        return if (studentID == null) rows else rows.filter { it.studentID == studentID }
    }

    suspend fun snooze(insight: Insight) {
        when (insights.snooze(insight, clock.now(), zone)) {
            is ApplicationResult.Failure -> snapshot = snapshot?.copy(failed = true)
            is ApplicationResult.Success -> {
                undoDeadlines[insight.snoozeKey] = monotonicMillis() + InsightUndoWindowMillis
                pending = pending + (insight.snoozeKey to insight)
            }
        }
    }

    suspend fun undo(insight: Insight) {
        if (undoRemainingMillis(insight.snoozeKey) == 0L) { commit(insight.snoozeKey); return }
        if (insights.unsnooze(insight) is ApplicationResult.Failure) {
            snapshot = snapshot?.copy(failed = true)
            return
        }
        snapshot = snapshot?.let { it.copy(insights = (it.insights + insight).distinctBy { row -> row.snoozeKey }) }
        pending = pending - insight.snoozeKey
        undoDeadlines.remove(insight.snoozeKey)
    }

    fun commit(key: String) {
        undoDeadlines.remove(key)
        pending = pending - key
        val current = snapshot ?: return
        snapshot = current.copy(insights = current.insights.filter { it.snoozeKey != key })
    }

    suspend fun markNudgePlayed() {
        if (insights.markNudgePlayed() is ApplicationResult.Success) {
            snapshot = snapshot?.copy(nudgePlayed = true)
        }
        nudgePhase = "done"
    }

    fun skipNudge() { nudgePhase = "skipped" }

    fun beginNudge() { if (nudgePhase == "idle") nudgePhase = "playing" }
}

object InsightRoutes {
    const val LIST = "insights"
    const val TREND = "students/{studentID}/trends/{exerciseID}"
    const val APPOINTMENT = "appointments/create/{date}/student/{studentID}"
    fun trend(studentID: StudentID, exerciseID: StableExerciseID) = "students/${studentID.value}/trends/${exerciseID.value}"
    fun appointment(date: LocalDate, studentID: StudentID) = "appointments/create/$date/student/${studentID.value}"
}

fun insightDestination(insight: Insight, today: LocalDate): String? = when (insight.kind) {
    Insight.Kind.packageExhausted, Insight.Kind.packageExpired, Insight.Kind.packageLow ->
        com.ignacioli.finecoach.navigation.S1Routes.studentPackages(insight.studentID)
    Insight.Kind.inactive -> InsightRoutes.appointment(today, insight.studentID)
    Insight.Kind.stagnant -> insight.exerciseID?.let { InsightRoutes.trend(insight.studentID, it) }
}
