package com.ignacioli.finecoach.features.trends

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.ProgressUseCases
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.training.CompletedSession
import java.time.ZoneId

class TrendsState(private val studentID: StudentID, private val progress: ProgressUseCases, private val zone: ZoneId) {
    var content by mutableStateOf<TrendsContent?>(null)
    var error by mutableStateOf(false)
    var busy by mutableStateOf(false)
    var pickerOpen by mutableStateOf(false)
    private var sessions = emptyList<CompletedSession>()
    private var assisted = emptySet<StableExerciseID>()
    private var selected: StableExerciseID? = null
    private var metric = TrendMetric.weight

    suspend fun load() {
        busy = true
        when (val result = progress.load(studentID)) {
            is ApplicationResult.Failure -> error = true
            is ApplicationResult.Success -> {
                error = false
                sessions = result.value.completed
                assisted = result.value.assisted
                if (selected == null) selected = TrendsPresentation.options(sessions, assisted).firstOrNull()?.id
                publish()
            }
        }
        busy = false
    }

    fun selectMetric(index: Int) {
        val metrics = content?.metrics.orEmpty()
        metric = metrics.getOrNull(index) ?: return
        publish()
    }

    fun selectExercise(id: StableExerciseID) {
        selected = id
        pickerOpen = false
        val metrics = TrendMetric.options(id)
        if (metric !in metrics) metric = TrendMetric.weight
        publish()
    }

    private fun publish() {
        content = TrendsPresentation.content(sessions, assisted, zone, selected, metric)
    }
}

object TrendsRoutes {
    const val PATTERN = "students/{studentID}/trends"
    fun open(studentID: StudentID) = "students/${studentID.value}/trends"
}
