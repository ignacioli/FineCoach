package com.ignacioli.finecoach.features.templates

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.exercises.ExerciseSelection

class TemplateUiState(private val useCases: TemplateUseCases, private val clock: AppClock, private val ids: StableIDGenerator) {
    var templates by mutableStateOf<List<TemplateRecord>>(emptyList())
        private set
    var content by mutableStateOf<TemplateContentRecord?>(null)
        private set
    var exerciseCounts by mutableStateOf<Map<TemplateID, Int>>(emptyMap())
        private set
    var error by mutableStateOf<ApplicationError?>(null)
        private set
    var busy by mutableStateOf(false)
        private set

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
    suspend fun list() = perform({ loadList() }) {
        templates = it.first
        exerciseCounts = it.second
    }

    private suspend fun loadList(): ApplicationResult<Pair<List<TemplateRecord>, Map<TemplateID, Int>>> {
        val listed = when (val result = useCases.list()) {
            is ApplicationResult.Failure -> return result
            is ApplicationResult.Success -> result.value
        }
        val counts = when (val result = useCases.exerciseCounts()) {
            is ApplicationResult.Failure -> return result
            is ApplicationResult.Success -> result.value
        }
        return ApplicationResult.Success(listed to listed.associate { it.templateID to (counts[it.templateID] ?: 0) })
    }
    suspend fun load(id: TemplateID) = perform({ useCases.load(id) }) {
        content = it
        if (it == null) error = ApplicationError(ApplicationErrorCode.notFound)
    }
    suspend fun mutate(change: (TrainingTemplate) -> TrainingTemplate): ApplicationResult<Unit> {
        if (busy) return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        val current = content ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        var outcome: ApplicationResult<Unit> = ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        perform({ useCases.mutate(current.template.templateID, current.template.revision, change) }) {
            content = it; outcome = ApplicationResult.Success(Unit)
        }
        return error?.let { ApplicationResult.Failure(it) } ?: outcome
    }
    suspend fun addExercise(selection: ExerciseSelection): ApplicationResult<Unit> = mutate {
        it.addingExercise(ids.newTemplateExerciseID(), selection.name, selection.mode, sourceKind = selection.sourceKind,
            sourceID = selection.sourceID, nowUTC = clock.now())
    }
    suspend fun saveMetadata(name: String, focus: Set<BodyPart>, onSaved: () -> Unit = {}) {
        val current = content ?: return
        perform({ useCases.save(SaveTemplateCommand(current.template.templateID, name, focus, current.template.revision)) }) {
            content = current.copy(template = it); onSaved()
        }
    }

    suspend fun create(name: String, onCreated: (TemplateRecord) -> Unit = {}) =
        perform({ useCases.save(SaveTemplateCommand(null, name, emptySet(), null)) }, onCreated)

    suspend fun apply(template: TemplateRecord, target: SessionRecord, onApplied: (SessionContentRecord) -> Unit = {}) =
        perform({ useCases.apply(ApplyTemplateSnapshotCommand(template.templateID, target.sessionID,
            template.revision, target.revision, clock.now())) }, onApplied)

    suspend fun delete(id: TemplateID, onDeleted: () -> Unit = {}) =
        perform({ useCases.delete(id) }) { onDeleted() }

    suspend fun saveSection(section: SectionID?, name: String): ApplicationResult<Unit> = mutate { template ->
        section?.let { template.renamingSection(it, name, clock.now()) }
            ?: template.addingSection(ids.newSectionID(), name, clock.now())
    }

    suspend fun reorder(snapshot: TemplateContentRecord, key: String, delta: Int): ApplicationResult<Unit> = mutate {
        it.reordering(shiftAxis(snapshot, key, delta), clock.now())
    }

    suspend fun deleteSection(section: SectionID, disposition: SessionSectionDeletionDisposition): ApplicationResult<Unit> = mutate {
        it.deletingSection(section, disposition, clock.now())
    }

    suspend fun moveExercise(exercise: TemplateExerciseID, target: SectionID?): ApplicationResult<Unit> = mutate {
        it.movingExercise(exercise, target, clock.now())
    }

    suspend fun removeExercise(exercise: TemplateExerciseID): ApplicationResult<Unit> = mutate {
        it.removingExercise(exercise, clock.now())
    }

    internal suspend fun savePlannedSets(row: TemplateExerciseRecord, drafts: List<PlannedInput>): ApplicationResult<Unit> = mutate { template ->
        val values = drafts.map { draft -> TemplatePlannedSet.copyingValuesFrom(TrainingSet.makeDraft(
            ids.newTrainingSetID(), ids.newSessionExerciseID(), 0u, draft.input(row.recordModeSnapshot), clock.now())) }
        template.replacingPlannedSets(row.templateExerciseID, values, clock.now())
    }
}

internal fun templateListMeta(focus: Set<BodyPart>, count: Int?): String? {
    if (count == null) return null
    val description = if (focus.isEmpty()) "未设重点" else "训练重点 · " +
        focus.sortedBy { it.ordinal }.joinToString("、") { com.ignacioli.finecoach.designsystem.FcBodyParts[it.ordinal] }
    return "$description · $count 个动作"
}

/** Drafts contain only input values; no completion state or training identity is written. */
internal data class PlannedInput(
    val weight: String = "", val reps: String = "", val duration: String = "", val left: String = "",
    val right: String = "", val distance: String = "", val speed: String = "", val resistance: String = "",
    val unit: MeasurementUnit, val side: SetSide = SetSide.none,
) {
    fun input(mode: RecordMode) = TrainingSetInput(mode, weight.ifBlank { null }, reps.ifBlank { null },
        duration.ifBlank { null }, unit, side, left.ifBlank { null }, right.ifBlank { null },
        distance.ifBlank { null }, speed.ifBlank { null }, resistance.ifBlank { null })
}

/** Move a section as a block; member moves stay inside their current section. */
private fun shiftAxis(content: TemplateContentRecord, key: String, delta: Int): List<SessionSectionAxisItem> {
    val blocks = (content.sections.map { section -> section.orderIndex to
        (listOf<SessionSectionAxisItem>(SessionSectionAxisItem.Section(section.sectionID)) + content.exercises
            .filter { it.sectionID == section.sectionID }.sortedBy { it.orderIndex }.map { SessionSectionAxisItem.Exercise(it.templateExerciseID.value) }) } +
        content.exercises.filter { it.sectionID == null }.map { it.orderIndex to listOf<SessionSectionAxisItem>(SessionSectionAxisItem.Exercise(it.templateExerciseID.value)) })
        .sortedBy { it.first }.map { it.second.toMutableList() }.toMutableList()
    val section = content.sections.firstOrNull { it.sectionID.value == key }
    val row = content.exercises.firstOrNull { it.templateExerciseID.value == key }
    if (section != null || row?.sectionID == null) {
        val index = blocks.indexOfFirst { block -> block.first().let { when (it) {
            is SessionSectionAxisItem.Section -> it.id.value == key
            is SessionSectionAxisItem.Exercise -> it.id == key
        } } }
        val target = index + delta
        if (index >= 0 && target in blocks.indices) java.util.Collections.swap(blocks, index, target)
    } else {
        val block = blocks.firstOrNull { it.first() == SessionSectionAxisItem.Section(row.sectionID) }
        if (block != null) {
            val index = block.indexOf(SessionSectionAxisItem.Exercise(key)); val target = index + delta
            if (index > 0 && target in 1 until block.size) java.util.Collections.swap(block, index, target)
        }
    }
    return blocks.flatten()
}
