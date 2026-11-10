package com.ignacioli.finecoach.features.exercises

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.repository.ExerciseRepository

/** A draft selection; the consuming feature owns its session/template transaction and claim. */
data class ExerciseSelection(
    val name: String,
    val mode: RecordMode,
    val sourceKind: ExerciseSourceKind,
    val sourceID: StableExerciseID?,
)

class ExerciseUiState(val useCases: ExerciseUseCases, private val repository: ExerciseRepository) {
    val catalogUnavailable get() = repository.catalogUnavailable
    var entries by mutableStateOf<List<ExerciseRecord>>(emptyList())
        private set
    var preferences by mutableStateOf<Map<StableExerciseID, ExercisePreferenceRecord>>(emptyMap())
        private set
    var error by mutableStateOf<ApplicationError?>(null)
        private set
    var busy by mutableStateOf(false)
        private set
    private var searchGeneration = 0

    suspend fun search(query: String, includeHidden: Boolean = false) {
        val generation = ++searchGeneration
        val result = if (includeHidden) repository.listCatalog() else useCases.search(query)
        if (generation != searchGeneration) return
        when (result) {
            is ApplicationResult.Failure -> { error = result.error; entries = emptyList() }
            is ApplicationResult.Success -> {
                val prefs = mutableMapOf<StableExerciseID, ExercisePreferenceRecord>()
                for (item in result.value) {
                    when (val preference = repository.preference(item.exerciseID)) {
                        is ApplicationResult.Failure -> { error = preference.error; entries = emptyList(); return }
                        is ApplicationResult.Success -> preference.value?.let { prefs[item.exerciseID] = it }
                    }
                }
                if (generation != searchGeneration) return
                preferences = prefs
                entries = result.value.filter { !includeHidden || query.isBlank() ||
                    it.canonicalName.contains(query.trim(), ignoreCase = true) ||
                    prefs[it.exerciseID]?.alias?.contains(query.trim(), ignoreCase = true) == true }
                error = null
            }
        }
    }

    suspend fun <T> perform(action: suspend () -> ApplicationResult<T>, success: (T) -> Unit = {}) {
        if (busy) return
        busy = true
        try {
            when (val result = action()) {
                is ApplicationResult.Failure -> error = result.error
                is ApplicationResult.Success -> { error = null; success(result.value) }
            }
        } finally { busy = false }
    }

    fun preference(id: StableExerciseID) = preferences[id] ?: ExercisePreferenceRecord(id, null, false, false, false, null)
    fun selection(item: ExerciseRecord): ExerciseSelection = ExerciseSelection(
        preferences[item.exerciseID]?.alias ?: item.canonicalName, item.recordMode,
        if (item.kind == ExerciseKind.builtIn) ExerciseSourceKind.builtIn else ExerciseSourceKind.custom, item.exerciseID)
}

fun exerciseModeTitle(mode: RecordMode) = when (mode) {
    RecordMode.weightReps -> "重量 × 次数"
    RecordMode.reps -> "次数"
    RecordMode.duration -> "时长"
    RecordMode.cardio -> "有氧"
}

fun exerciseErrorTitle(error: ApplicationError): String = when (error.code) {
    ApplicationErrorCode.conflict -> "名称已存在，请修改名称"
    ApplicationErrorCode.emptyText -> "请输入名称"
    ApplicationErrorCode.staleRevision -> "内容已更新，请返回重新载入"
    else -> "操作失败，请检查输入后重试"
}
