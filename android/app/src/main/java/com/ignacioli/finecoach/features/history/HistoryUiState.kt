package com.ignacioli.finecoach.features.history

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*

class HistoryUiState(val useCases: HistoryUseCases, val studentID: StudentID?) {
    var query by mutableStateOf(HistoryQuery(studentID = studentID)); private set
    var records by mutableStateOf<List<SessionHistoryRecord>>(emptyList()); private set
    var emptyState by mutableStateOf<HistoryEmptyState?>(null); private set
    var detail by mutableStateOf<HistoryDetail?>(null); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    var busy by mutableStateOf(false); private set
    var focus by mutableStateOf<Set<BodyPart>>(emptySet())
    var exerciseOptions by mutableStateOf<Map<StableExerciseID, String>>(emptyMap()); private set
    suspend fun list(value: HistoryQuery = query) {
        if (busy) return
        busy = true; query = value
        when (val result = useCases.list(value)) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> { records = result.value.records; emptyState = result.value.emptyState; error = null }
        }
        if (error == null) when (val all = useCases.clearFilters(studentID)) {
            is ApplicationResult.Failure -> error = all.error
            is ApplicationResult.Success -> {
                val options = linkedMapOf<StableExerciseID, String>()
                for (row in all.value.records) when (val loaded = useCases.detail(row.sessionID)) {
                    is ApplicationResult.Failure -> { error = loaded.error; break }
                    is ApplicationResult.Success -> loaded.value.content.exercises.forEach { exercise -> exercise.sourceID?.let { options[it] = exercise.displayNameSnapshot } }
                }
                exerciseOptions = options
            }
        }
        busy = false
    }
    suspend fun load(id: SessionID) {
        if (busy) return
        busy = true
        when (val result = useCases.detail(id)) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> { detail = result.value; focus = result.value.content.session.trainingFocus; error = null }
        }; busy = false
    }
    suspend fun saveFocus(onSaved: () -> Unit) {
        val session = detail?.content?.session ?: return
        if (busy) return
        busy = true
        when (val result = useCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(session.sessionID, session.revision, focus))) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> { error = null; busy = false; load(session.sessionID); if (error == null) onSaved() }
        }; busy = false
    }
}
