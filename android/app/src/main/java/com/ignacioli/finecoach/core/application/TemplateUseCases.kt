package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.core.domain.training.*

class TemplateUseCases(
    private val repository: TemplateRepositoryPort,
    private val clock: AppClock,
) {
    suspend fun list() = repository.list()
    suspend fun load(id: TemplateID) = repository.loadContent(id)
    suspend fun save(command: SaveTemplateCommand) = repository.save(command)
    suspend fun retry(command: SaveTemplateCommand) = repository.save(command)
    suspend fun retry(command: SaveTemplateContentCommand) = repository.saveContent(command)
    suspend fun delete(id: TemplateID) = repository.delete(id)
    suspend fun apply(command: ApplyTemplateSnapshotCommand) = repository.applySnapshot(command)
    suspend fun mutate(id: TemplateID, revision: Revision, change: (TrainingTemplate) -> TrainingTemplate): ApplicationResult<TemplateContentRecord> =
        trainingValidation {
            when (val loaded = repository.loadContent(id)) {
                is ApplicationResult.Failure -> loaded
                is ApplicationResult.Success -> {
                    val content = loaded.value ?: trainingFailure(ApplicationErrorCode.notFound)
                    if (content.template.revision != revision) trainingFailure(ApplicationErrorCode.staleRevision)
                    val original = content.toDomain()
                    val changed = change(original)
                    if (original == changed) ApplicationResult.Success(content) else {
                        if (changed.copy(sections = original.sections, exercises = original.exercises,
                                updatedAtUTC = original.updatedAtUTC) != original) trainingFailure(ApplicationErrorCode.incompatibleInput)
                        repository.saveContent(SaveTemplateContentCommand(id, revision, changed.sections.map { it.toRecord() },
                            changed.exercises.map { it.toRecord() }))
                    }
                }
            }
        }
    suspend fun deleteSection(id: TemplateID, revision: Revision, section: SectionID,
        disposition: SessionSectionDeletionDisposition?) = mutate(id, revision) {
        it.deletingSection(section, disposition, clock.now())
    }
}

internal fun TemplatePlannedSetRecord.toDomain() = TemplatePlannedSet(recordMode, weightValue.optionalDecimal(),
    repetitionCount.optionalDecimal(), durationSeconds.optionalDecimal(), unit, side, leftValue.optionalDecimal(),
    rightValue.optionalDecimal(), distanceValue.optionalDecimal(), speedValue.optionalDecimal(), resistanceValue.optionalDecimal())
internal fun TemplatePlannedSet.toRecord() = TemplatePlannedSetRecord(recordMode, weightValue?.decimal, repetitionCount?.decimal,
    durationSeconds?.decimal, unit, side, leftValue?.decimal, rightValue?.decimal, distanceValue?.decimal, speedValue?.decimal, resistanceValue?.decimal)
internal fun TemplateExerciseRecord.toDomain() = TemplateExercise(templateExerciseID, templateID, sectionID, orderIndex,
    sourceKind, sourceID, NormalizedName.parse(displayNameSnapshot), recordModeSnapshot, plannedSets.map {
        if (it.recordMode != recordModeSnapshot) trainingFailure(ApplicationErrorCode.invalidMode)
        it.toDomain()
    })
internal fun TemplateExercise.toRecord() = TemplateExerciseRecord(templateExerciseID, templateID, sectionID, orderIndex,
    sourceKind, sourceID, displayNameSnapshot.value, recordModeSnapshot, plannedSets.map { it.toRecord() })
internal fun TemplateContentRecord.toDomain(): TrainingTemplate = TrainingTemplate(template.templateID,
    NormalizedName.parse(template.name), template.trainingFocus.toSet(), template.createdAtUTC, template.updatedAtUTC,
    sections.map { it.toDomain() }, exercises.map { it.toDomain() }).also {
    // Validate ownership, shared order indices, and section membership without changing the candidate.
    it.reordering((it.sections.map { h -> h.orderIndex to SessionSectionAxisItem.Section(h.sectionID) } +
        it.exercises.map { e -> e.orderIndex to SessionSectionAxisItem.Exercise(e.templateExerciseID.value) })
        .sortedBy { pair -> pair.first }.map { pair -> pair.second }, it.updatedAtUTC)
}
internal fun TrainingTemplate.toRecord(revision: Revision) = TemplateContentRecord(TemplateRecord(templateID, name.value,
    trainingFocus.toSet(), revision, createdAtUTC, updatedAtUTC), sections.map { it.toRecord() }, exercises.map { it.toRecord() })
