package com.ignacioli.finecoach.features.history

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.progress.SessionGains
import java.time.ZoneId

class HistoryUiState(val useCases: HistoryUseCases, val studentID: StudentID?, private val students: StudentUseCases? = null,
    private val progress: ProgressUseCases? = null, private val zone: ZoneId = ZoneId.systemDefault()) {
    var gains by mutableStateOf(SessionGains()); private set
    var studentName by mutableStateOf(""); private set
    var query by mutableStateOf(HistoryQuery(studentID = studentID)); private set
    var records by mutableStateOf<List<SessionHistoryRecord>>(emptyList()); private set
    var emptyState by mutableStateOf<HistoryEmptyState?>(null); private set
    var detail by mutableStateOf<HistoryDetail?>(null); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    var busy by mutableStateOf(false); private set
    var focus by mutableStateOf<Set<BodyPart>>(emptySet())
    var listDetails by mutableStateOf<Map<SessionID, HistoryDetail>>(emptyMap()); private set
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
                val details = linkedMapOf<SessionID, HistoryDetail>()
                for (row in all.value.records) when (val loaded = useCases.detail(row.sessionID)) {
                    is ApplicationResult.Failure -> { error = loaded.error; break }
                    is ApplicationResult.Success -> {
                        details[row.sessionID] = loaded.value
                        loaded.value.content.exercises.forEach { exercise -> exercise.sourceID?.let { options[it] = exercise.displayNameSnapshot } }
                    }
                }
                listDetails = details
                exerciseOptions = options
            }
        }
        if (error == null && studentID != null) loadStudentName(studentID)
        busy = false
    }
    suspend fun load(id: SessionID) {
        if (busy) return
        busy = true
        gains = SessionGains()
        when (val result = useCases.detail(id)) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> {
                detail = result.value; focus = result.value.content.session.trainingFocus; error = null
                loadStudentName(result.value.content.session.studentID)
                when (val loaded = loadSessionGains(result.value, progress, zone)) {
                    is ApplicationResult.Failure -> error = loaded.error
                    is ApplicationResult.Success -> gains = loaded.value
                }
            }
        }; busy = false
    }
    private suspend fun loadStudentName(id: StudentID) {
        studentName = ""
        val useCases = students ?: return
        when (val found = useCases.find(id)) {
            is ApplicationResult.Failure -> error = found.error
            is ApplicationResult.Success -> {
                studentName = found.value?.displayName.orEmpty()
                if (found.value == null) error = ApplicationError(ApplicationErrorCode.notFound)
            }
        }
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
