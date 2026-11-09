package com.ignacioli.finecoach.features.templates

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.features.exercises.ExerciseSelection

class TemplateUiState(val useCases: TemplateUseCases, val clock: AppClock, val ids: StableIDGenerator) {
    var templates by mutableStateOf<List<TemplateRecord>>(emptyList())
        private set
    var content by mutableStateOf<TemplateContentRecord?>(null)
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
    suspend fun list() = perform({ useCases.list() }) { templates = it }
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
}
