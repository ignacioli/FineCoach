package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.*

/** The UI must call createCustom explicitly; session-only creation only acquires a claim. */
class ExerciseUseCases(
    private val repository: ExerciseRepositoryPort,
    private val clock: AppClock,
    private val ids: StableIDGenerator,
) {
    suspend fun search(query: String) = repository.search(query)

    suspend fun createCustom(name: String, mode: RecordMode): ApplicationResult<ExerciseRecord> {
        val now = clock.now()
        return repository.saveCustom(ExerciseRecord(ids.newExerciseID(), ExerciseKind.custom, name, mode,
            "custom.1", ExerciseLifecycle.active, false, null, now, now))
    }

    suspend fun updateCustom(id: StableExerciseID, name: String, mode: RecordMode): ApplicationResult<ExerciseRecord> =
        change(id) { it.copy(canonicalName = name, recordMode = mode, updatedAtUTC = clock.now()) }

    suspend fun archiveCustom(id: StableExerciseID): ApplicationResult<ExerciseRecord> = change(id) {
        if (it.lifecycle != ExerciseLifecycle.active) return@change null
        it.copy(lifecycle = ExerciseLifecycle.archived, updatedAtUTC = clock.now())
    }

    suspend fun restoreCustom(id: StableExerciseID): ApplicationResult<ExerciseRecord> = change(id) {
        if (it.lifecycle != ExerciseLifecycle.archived) return@change null
        it.copy(lifecycle = ExerciseLifecycle.active, updatedAtUTC = clock.now())
    }

    suspend fun claimSessionOnly(id: StableExerciseID, name: String) =
        repository.renameClaim(id, name, ExerciseClaimScope.currentSession)

    /** Complete replacement per the frozen command contract; retain other fields when toggling one. */
    suspend fun updatePreference(command: UpdateExercisePreferenceCommand) = repository.updatePreference(command)

    private suspend fun change(
        id: StableExerciseID, transform: (ExerciseRecord) -> ExerciseRecord?,
    ): ApplicationResult<ExerciseRecord> {
        val result = repository.listCatalog()
        if (result is ApplicationResult.Failure) return result
        val item = (result as ApplicationResult.Success).value.firstOrNull { it.exerciseID == id }
            ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.notFound))
        if (item.kind != ExerciseKind.custom) return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        val updated = transform(item) ?: return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.invalidState))
        return repository.saveCustom(updated)
    }
}
