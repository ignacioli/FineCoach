package com.ignacioli.finecoach.features.exercises

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.repository.ExerciseRepository
import com.ignacioli.finecoach.storage.repository.HistoryRepository

/** A draft selection; the consuming feature owns its session/template transaction and claim. */
data class ExerciseSelection(
    val name: String,
    val mode: RecordMode,
    val sourceKind: ExerciseSourceKind,
    val sourceID: StableExerciseID?,
)

class ExerciseUiState(val useCases: ExerciseUseCases, private val repository: ExerciseRepository,
    private val history: HistoryRepository? = null, private val sessions: SessionRepositoryPort? = null) {
    var metadataUnavailable by mutableStateOf(false)
        private set
    var metadata by mutableStateOf<Map<StableExerciseID, ExerciseCatalogMetadata>>(emptyMap())
        private set
    var recentEntries by mutableStateOf<List<ExerciseRecord>>(emptyList())
        private set
    var historyError by mutableStateOf<ApplicationError?>(null)
        private set
    private var historyGeneration = 0
    private var reloadGeneration = 0

    suspend fun reload(query: String, includeHidden: Boolean = false, studentID: StudentID? = null,
        recentEnabled: Boolean = true) {
        val generation = ++reloadGeneration
        ++historyGeneration
        recentEntries = emptyList()
        historyError = null
        search(query, includeHidden)
        if (generation == reloadGeneration && error == null && recentEnabled && query.isBlank()) loadRecent(studentID)
    }

    private suspend fun loadRecent(studentID: StudentID?) {
        val generation = ++historyGeneration
        val source = history ?: return
        val contentSource = sessions ?: return
        val available = ExerciseBrowse.availableRecent(entries, preferences)
        if (available.isEmpty()) return
        val result = mutableListOf<ExerciseRecord>()
        val seen = mutableSetOf<StableExerciseID>()
        when (val candidates = source.recentSessionIDs(studentID)) {
            is ApplicationResult.Failure -> { if (generation == historyGeneration) historyError = candidates.error; return }
            is ApplicationResult.Success -> for (id in candidates.value) {
                if (generation != historyGeneration) return
                when (val content = contentSource.loadContent(id)) {
                    is ApplicationResult.Failure -> { if (generation == historyGeneration) historyError = content.error; return }
                    is ApplicationResult.Success -> content.value?.let {
                        ExerciseBrowse.collectRecent(it, available, seen, result, studentID)
                    }
                }
                if (result.size == 5) break
            }
        }
        if (generation == historyGeneration) recentEntries = result.toList()
    }

    fun sections(muscle: String?, equipment: String?): List<ExerciseBrowse.Section> {
        // With no successful facets, show the unavailable message instead of a fabricated uncategorized catalog.
        val source = if (metadataUnavailable && metadata.isEmpty()) entries.filter { it.kind == ExerciseKind.custom } else entries
        return ExerciseBrowse.sections(source, metadata, muscle, equipment)
    }
    fun subtitle(item: ExerciseRecord): String = buildList {
        val facet = metadata[item.exerciseID].takeIf { item.kind == ExerciseKind.builtIn }
        add(if (item.kind == ExerciseKind.custom) "自定义" else facet?.equipmentClass ?: "内置")
        if (!facet?.secondaryMuscleGroups.isNullOrEmpty()) add("次要：${facet!!.secondaryMuscleGroups.joinToString("、")}")
        if (preference(item.exerciseID).isHidden || item.lifecycle == ExerciseLifecycle.archived) add("已隐藏")
    }.joinToString(" · ")

    val catalogUnavailable get() = repository.catalogUnavailable || metadataUnavailable
    var entries by mutableStateOf<List<ExerciseRecord>>(emptyList())
        private set
    var preferences by mutableStateOf<Map<StableExerciseID, ExercisePreferenceRecord>>(emptyMap())
        private set
    var error by mutableStateOf<ApplicationError?>(null)
        private set
    var busy by mutableStateOf(false)
        private set
    private var searchGeneration = 0
    internal var openPreferenceID: StableExerciseID? = null

    suspend fun search(query: String, includeHidden: Boolean = false) {
        val generation = ++searchGeneration
        val result = repository.searchWithPreferences(query, includeHidden)
        if (generation == searchGeneration) metadataUnavailable = repository.browseMetadataUnavailable
        if (generation != searchGeneration) return
        when (result) {
            is ApplicationResult.Failure -> { error = result.error; entries = emptyList() }
            is ApplicationResult.Success -> {
                val prefs = result.value.preferences.toMutableMap()
                if (generation != searchGeneration) return
                // Only the open sheet may retain a filtered-out exercise's saved preference.
                openPreferenceID?.takeIf { it !in prefs }?.let { id ->
                    preferences[id]?.let { prefs[id] = it }
                }
                preferences = prefs
                metadata = repository.browseMetadata
                entries = result.value.entries
                error = null
            }
        }
    }

    internal suspend fun updateLibraryPreference(command: UpdateExercisePreferenceCommand, onSaved: () -> Unit) {
        perform({ useCases.updatePreference(command) }) { saved ->
            ++searchGeneration
            preferences = preferences + (saved.exerciseID to saved)
            onSaved()
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
