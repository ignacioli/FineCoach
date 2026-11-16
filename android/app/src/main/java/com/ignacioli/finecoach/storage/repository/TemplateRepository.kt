package com.ignacioli.finecoach.storage.repository

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.TrainingTemplate
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.entity.*
import java.util.UUID

class TemplateRepository(
    private val database: FineCoachDatabase,
    private val clock: AppClock,
    private val ids: StableIDGenerator,
    private val expectedGeneration: UUID,
) : TemplateRepositoryPort {
    private val dao get() = database.s1Dao()
    private val writes get() = database.t008SessionDao()
    override suspend fun exerciseCounts(): ApplicationResult<Map<TemplateID, Int>> = transaction {
        dao.templateExerciseCounts().associate { TemplateID.fromUUID(it.templateID) to it.exerciseCount }
    }
    override suspend fun list(): ApplicationResult<List<TemplateRecord>> = transaction {
        writes.templates().map(::record).sortedWith(compareByDescending<TemplateRecord> { it.updatedAtUTC }.thenBy { it.templateID.value })
    }
    override suspend fun find(templateID: TemplateID): ApplicationResult<TemplateRecord?> = transaction {
        dao.findTrainingTemplate(templateID.t008UUID())?.let(::record)
    }
    override suspend fun save(command: SaveTemplateCommand): ApplicationResult<TemplateRecord> = transaction {
        val now = clock.now()
        val current = command.templateID?.let { dao.findTrainingTemplate(it.t008UUID()) ?: trainingFailure(ApplicationErrorCode.notFound) }
        if (current == null && command.expectedRevision != null) trainingFailure(ApplicationErrorCode.staleRevision)
        if (current != null && command.expectedRevision?.value?.toString() != current.revision) trainingFailure(ApplicationErrorCode.staleRevision)
        val template = TrainingTemplate.blank(command.templateID ?: ids.newTemplateID(), command.name, command.trainingFocus, now)
        val revision = current?.let { nextRevision(Revision(it.revision.toULong())) } ?: Revision(1uL)
        val row = TrainingTemplateEntity(template.templateID.t008UUID(), template.name.value, revision.value.toString(), current?.createdAtUTC ?: now, now)
        if (current == null) dao.insert(row) else check(writes.update(row) == 1)
        writes.deleteTemplateFocus(row.id)
        template.trainingFocus.forEach { dao.insert(TemplateTrainingFocusEntity(row.id, it)) }
        record(requireNotNull(dao.findTrainingTemplate(row.id)))
    }
    override suspend fun loadContent(templateID: TemplateID): ApplicationResult<TemplateContentRecord?> = transaction { load(templateID) }
    override suspend fun saveContent(command: SaveTemplateContentCommand): ApplicationResult<TemplateContentRecord> = transaction {
        val current = requireTemplate(command.templateID, command.expectedRevision)
        val candidate = TemplateContentRecord(record(current).copy(revision = nextRevision(command.expectedRevision),
            updatedAtUTC = clock.now()), command.sections, command.exercises).toDomain().toRecord(nextRevision(command.expectedRevision))
        replace(candidate)
        check(writes.update(TrainingTemplateEntity(current.id, current.name, candidate.template.revision.value.toString(),
            current.createdAtUTC, candidate.template.updatedAtUTC)) == 1)
        requireNotNull(load(command.templateID))
    }
    override suspend fun delete(templateID: TemplateID): ApplicationResult<Unit> = transaction {
        if (dao.findTrainingTemplate(templateID.t008UUID()) == null) trainingFailure(ApplicationErrorCode.notFound)
        val id = templateID.t008UUID()
        writes.deletePlannedSets(id)
        writes.deleteTemplateExercises(id)
        writes.deleteSections(SessionSectionOwnerKind.template, id)
        writes.deleteTemplateFocus(id)
        writes.deleteTemplate(id)
    }
    override suspend fun applySnapshot(command: ApplyTemplateSnapshotCommand): ApplicationResult<SessionContentRecord> = transaction {
        validateSessionPointers(database)
        requireTemplate(command.templateID, command.expectedTemplateRevision)
        val source = requireNotNull(load(command.templateID)).toDomain()
        val target = loadSessionContent(database, command.targetSessionID) ?: trainingFailure(ApplicationErrorCode.notFound)
        if (target.session.revision != command.expectedSessionRevision) trainingFailure(ApplicationErrorCode.staleRevision)
        val pointer = dao.findActiveSessionPointer(target.session.studentID.value)
        if (pointer != null && pointer.sessionID != command.targetSessionID.t008UUID()) trainingFailure(ApplicationErrorCode.invalidState)
        val result = source.applying(target.toDomain(), ids::newSessionExerciseID, ids::newTrainingSetID, ids::newSectionID,
            command.appliedAtUTC).toRecord()
        // Persist one CAS increment even though the pure aggregate may perform several transformations.
        val content = result.copy(session = result.session.copy(revision = nextRevision(command.expectedSessionRevision)))
        replaceSessionContent(database, content)
        updateSession(database, content.session)
        requireNotNull(loadSessionContent(database, command.targetSessionID))
    }
    private fun record(row: TrainingTemplateEntity) = TemplateRecord(TemplateID.fromUUID(row.id), row.name,
        dao.templateFocus(row.id).map { it.bodyPart }.toSet(), Revision(row.revision.toULong()), row.createdAtUTC, row.updatedAtUTC)
    private fun requireTemplate(id: TemplateID, revision: Revision): TrainingTemplateEntity {
        val row = dao.findTrainingTemplate(id.t008UUID()) ?: trainingFailure(ApplicationErrorCode.notFound)
        if (row.revision != revision.value.toString()) trainingFailure(ApplicationErrorCode.staleRevision)
        return row
    }
    private fun load(id: TemplateID): TemplateContentRecord? {
        val row = dao.findTrainingTemplate(id.t008UUID()) ?: return null
        return TemplateContentRecord(record(row), dao.sections(SessionSectionOwnerKind.template, row.id).map { it.toRecord() },
            dao.templateExercises(row.id).map { e -> TemplateExerciseRecord(TemplateExerciseID.fromUUID(e.id), id,
                e.sectionID?.let(SectionID::fromUUID), e.orderIndex.toUInt(), e.sourceKind, e.sourceID?.let(StableExerciseID::parse),
                e.displayNameSnapshot, e.recordModeSnapshot, dao.plannedSets(e.id).map { s -> TemplatePlannedSetRecord(s.recordMode,
                    s.weightValue, s.repetitionCount, s.durationSeconds, s.unit, s.side, s.leftValue, s.rightValue,
                    s.distanceValue, s.speedValue, s.resistanceValue) }) }).let { it.toDomain().toRecord(it.template.revision) }
    }
    private fun replace(content: TemplateContentRecord) {
        val id = content.template.templateID.t008UUID()
        writes.deletePlannedSets(id)
        writes.deleteTemplateExercises(id)
        writes.deleteSections(SessionSectionOwnerKind.template, id)
        content.sections.forEach { dao.insert(it.toEntity()) }
        content.exercises.forEach { e ->
            dao.insert(TemplateExerciseEntity(e.templateExerciseID.t008UUID(), id, e.sectionID?.t008UUID(), e.orderIndex.toLong(),
                e.sourceKind, e.sourceID?.value, e.displayNameSnapshot, e.recordModeSnapshot))
            e.plannedSets.forEachIndexed { index, s -> dao.insert(TemplatePlannedSetEntity(e.templateExerciseID.t008UUID(), index.toLong(),
                s.recordMode, s.unit, s.side, s.weightValue, s.repetitionCount, s.durationSeconds, s.leftValue, s.rightValue,
                s.distanceValue, s.speedValue, s.resistanceValue)) }
        }
    }
    private suspend fun <T> transaction(action: () -> T) = trainingTransaction(database, expectedGeneration, action)
}
