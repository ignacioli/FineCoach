// fictional-data: invented template plans and students in temporary file databases only.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.core.domain.training.*
import java.math.BigDecimal
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class TemplateRepositoryTests {
    private lateinit var f: T008Fixture
    @Before fun prepare() { f = T008Fixture() }
    @After fun close() { f.close() }

    private suspend fun content(): TemplateContentRecord {
        val record = f.ok(f.templates.save(SaveTemplateCommand(null, "虚构模板", setOf(BodyPart.entries.first()), null)))
        val owner = SectionOwner.Template(record.templateID)
        val a = SessionSection.create(f.ids.newSectionID(), owner, "虚构分段甲", 0u)
        val b = SessionSection.create(f.ids.newSectionID(), owner, "虚构分段乙", 2u)
        fun exercise(order: UInt, section: SectionID): TemplateExercise = TemplateExercise(f.ids.newTemplateExerciseID(),
            record.templateID, section, order, ExerciseSourceKind.sessionOnly, null, NormalizedName.parse("虚构动作"),
            RecordMode.weightReps, listOf(TemplatePlannedSet(RecordMode.weightReps, DecimalValue.parse("12.125"),
                DecimalValue.parse("8"), unit = MeasurementUnit.kilograms)))
        return f.ok(f.templates.saveContent(SaveTemplateContentCommand(record.templateID, record.revision,
            listOf(a.toRecord(), b.toRecord()), listOf(exercise(1u, a.sectionID).toRecord(), exercise(3u, b.sectionID).toRecord()))))
    }
    private fun apply(template: TemplateContentRecord, session: SessionRecord) = ApplyTemplateSnapshotCommand(
        template.template.templateID, session.sessionID, template.template.revision, session.revision, f.now)

    @Test fun aggregateExerciseCountsMatchContentAcrossSectionsAndIncludeEmptyTemplates() = f.test {
        val original = content()
        val populated = f.ok(f.templates.saveContent(SaveTemplateContentCommand(original.template.templateID,
            original.template.revision, original.sections, original.exercises.map { it.copy(plannedSets = it.plannedSets + it.plannedSets) })))
        val empty = f.ok(f.templates.save(SaveTemplateCommand(null, "虚构空模板", emptySet(), null)))
        f.reopen()
        val counts = f.ok(f.templateUseCases.exerciseCounts())
        assertEquals(2, populated.sections.size)
        assertEquals(4, populated.exercises.sumOf { it.plannedSets.size })
        assertEquals(mapOf(populated.template.templateID to 2, empty.templateID to 0), counts)
        for (id in counts.keys) assertEquals(f.ok(f.templates.loadContent(id))!!.exercises.size, counts[id])
    }

    @Test fun blankCreateRenameFocusAndPlannedContentRoundtripAfterReopen() = f.test {
        val before = content()
        f.reopen()
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
        val renamed = f.ok(f.templates.save(SaveTemplateCommand(before.template.templateID, " 虚构新模板 ", emptySet(), before.template.revision)))
        assertEquals("虚构新模板", renamed.name)
        assertEquals(before.template.createdAtUTC, renamed.createdAtUTC)
        assertEquals(before.template.revision.value + 1u, renamed.revision.value)
        f.reopen()
        val loaded = f.ok(f.templates.loadContent(renamed.templateID))!!
        assertEquals(renamed, loaded.template)
        assertEquals(before.sections, loaded.sections)
        assertEquals(before.exercises, loaded.exercises)
    }

    @Test fun staleMetadataAndContentWritesBothRejectWithoutChanges() = f.test {
        val before = content()
        val stale = Revision(before.template.revision.value - 1u)
        f.error(ApplicationErrorCode.staleRevision, f.templates.save(SaveTemplateCommand(before.template.templateID,
            "虚构旧写入", emptySet(), stale)))
        f.error(ApplicationErrorCode.staleRevision, f.templates.saveContent(SaveTemplateContentCommand(before.template.templateID,
            stale, emptyList(), emptyList())))
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
    }

    @Test fun concurrentTemplateCASAllowsOnlyOneWriter() = f.test {
        val before = content()
        val repositories = List(2) { f.templates }
        val ready = CountDownLatch(2)
        val start = CountDownLatch(1)
        val threads = Executors.newFixedThreadPool(2)
        try {
            val jobs = repositories.mapIndexed { index, repository -> threads.submit(Callable {
                ready.countDown(); check(start.await(10, TimeUnit.SECONDS))
                runBlocking { repository.save(SaveTemplateCommand(before.template.templateID, "虚构并发模板$index", emptySet(), before.template.revision)) }
            }) }
            assertTrue(ready.await(10, TimeUnit.SECONDS)); start.countDown()
            val results = jobs.map { it.get(30, TimeUnit.SECONDS) }
            assertEquals(1, results.count { it is ApplicationResult.Success })
            f.error(ApplicationErrorCode.staleRevision, results.single { it is ApplicationResult.Failure })
            assertEquals(before.template.revision.value + 1u, f.ok(f.templates.find(before.template.templateID))!!.revision.value)
        } finally { threads.shutdownNow() }
    }

    @Test fun metadataWriteFailureDoesNotReturnSuccessAndSameCommandCanRetry() = f.test {
        val before = content()
        val command = SaveTemplateCommand(before.template.templateID, "虚构重试模板", emptySet(), before.template.revision)
        f.failWrites("training_templates", "UPDATE")
        f.error(ApplicationErrorCode.persistenceFailed, f.templateUseCases.retry(command))
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
        f.clearFailure(); f.reopen()
        val saved = f.ok(f.templateUseCases.retry(command))
        f.reopen()
        assertEquals(saved, f.ok(f.templates.find(saved.templateID)))
    }

    @Test fun creationFocusFailureRollsBackTemplateAndRetryCreatesOne() = f.test {
        f.failWrites("template_training_focus", "INSERT")
        val command = SaveTemplateCommand(null, "虚构模板", setOf(BodyPart.entries.first()), null)
        f.error(ApplicationErrorCode.persistenceFailed, f.templates.save(command))
        assertEquals(0L, f.count("training_templates"))
        f.clearFailure()
        f.ok(f.templates.save(command))
        assertEquals(1L, f.count("training_templates"))
    }

    @Test fun contentInsertFailureRollsBackDeletedRowsAndRevisionAndRetryPersists() = f.test {
        val before = content()
        val command = SaveTemplateContentCommand(before.template.templateID, before.template.revision, before.sections,
            before.exercises.map { it.copy(displayNameSnapshot = "虚构改名动作") })
        f.failWrites("template_planned_sets", "INSERT")
        f.error(ApplicationErrorCode.persistenceFailed, f.templateUseCases.retry(command))
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
        f.clearFailure(); f.reopen()
        val saved = f.ok(f.templateUseCases.retry(command))
        f.reopen()
        assertEquals(saved, f.ok(f.templates.loadContent(saved.template.templateID)))
    }

    @Test fun moveSectionKeepsMembersAndPlannedSetsAfterReopen() = f.test {
        val before = content()
        val saved = f.ok(f.templateUseCases.deleteSection(before.template.templateID, before.template.revision,
            before.sections.first().sectionID, SessionSectionDeletionDisposition.MoveExercisesTo(before.sections.last().sectionID)))
        assertEquals(before.exercises.map { it.templateExerciseID }, saved.exercises.map { it.templateExerciseID })
        assertEquals(before.exercises.flatMap { it.plannedSets }, saved.exercises.flatMap { it.plannedSets })
        assertEquals(before.sections.last().sectionID, saved.exercises.first().sectionID)
        assertEquals(before.exercises.last().copy(orderIndex = 2u), saved.exercises.last())
        f.reopen()
        assertEquals(saved, f.ok(f.templates.loadContent(saved.template.templateID)))
    }

    @Test fun moveSectionToUnsectionedKeepsIDsAndValues() = f.test {
        val before = content()
        val saved = f.ok(f.templateUseCases.deleteSection(before.template.templateID, before.template.revision,
            before.sections.first().sectionID, SessionSectionDeletionDisposition.MoveExercisesTo(null)))
        assertNull(saved.exercises.first().sectionID)
        assertEquals(before.exercises.first().templateExerciseID, saved.exercises.first().templateExerciseID)
        assertEquals(before.exercises.first().plannedSets, saved.exercises.first().plannedSets)
    }

    @Test fun deleteSectionRemovesOnlyMembersAndTheirPlannedSets() = f.test {
        val before = content()
        val other = content()
        val saved = f.ok(f.templateUseCases.deleteSection(before.template.templateID, before.template.revision,
            before.sections.first().sectionID, SessionSectionDeletionDisposition.DeleteWithExercises))
        assertEquals(listOf(before.exercises.last().templateExerciseID), saved.exercises.map { it.templateExerciseID })
        assertEquals(before.exercises.last().plannedSets, saved.exercises.single().plannedSets)
        assertEquals(3L, f.count("template_planned_sets"))
        assertEquals(other, f.ok(f.templates.loadContent(other.template.templateID)))
        f.reopen()
        assertEquals(saved, f.ok(f.templates.loadContent(saved.template.templateID)))
    }

    @Test fun cancelledSectionDeletionPerformsZeroWrites() = f.test {
        val before = content()
        f.blockAllWrites(listOf("training_templates", "session_sections", "template_exercises", "template_planned_sets", "template_training_focus"))
        assertEquals(before, f.ok(f.templateUseCases.deleteSection(before.template.templateID, before.template.revision,
            before.sections.first().sectionID, null)))
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
    }

    @Test fun invalidSelfMissingAndForeignSectionTargetsDoNotWrite() = f.test {
        val before = content()
        val other = content()
        for (target in listOf(before.sections.first().sectionID, f.ids.newSectionID(), other.sections.first().sectionID)) {
            f.error(ApplicationErrorCode.invalidState, f.templateUseCases.deleteSection(before.template.templateID, before.template.revision,
                before.sections.first().sectionID, SessionSectionDeletionDisposition.MoveExercisesTo(target)))
        }
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
        assertEquals(other, f.ok(f.templates.loadContent(other.template.templateID)))
    }

    @Test fun sectionDeleteFailureRollsBackAllTablesAndRevision() = f.test {
        val before = content()
        f.failWrites("session_sections", "DELETE")
        f.error(ApplicationErrorCode.persistenceFailed, f.templateUseCases.deleteSection(before.template.templateID, before.template.revision,
            before.sections.first().sectionID, SessionSectionDeletionDisposition.DeleteWithExercises))
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
        f.clearFailure(); f.reopen()
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
    }

    @Test fun applyDeepCopiesNewIDsPendingSetsAndFocusWithoutBidirectionalPollution() = f.test {
        f.student(1)
        val template = content()
        val session = f.start()
        val applied = f.ok(f.templates.applySnapshot(apply(template, session)))
        assertEquals(template.template.trainingFocus, applied.session.trainingFocus)
        assertTrue(applied.sections.map { it.sectionID }.toSet().intersect(template.sections.map { it.sectionID }.toSet()).isEmpty())
        assertEquals(template.exercises.map { it.plannedSets.single().weightValue }, applied.exercises.map { it.sets.single().weightValue })
        assertTrue(applied.exercises.all { it.sets.all { s -> s.state == SetRecordingState.pending && s.completedAtUTC == null } })
        assertEquals(4, (applied.exercises.map { it.sessionExerciseID.value } + applied.exercises.flatMap { it.sets }.map { it.trainingSetID.value }).distinct().size)
        assertEquals(template, f.ok(f.templates.loadContent(template.template.templateID)))
        f.ok(f.templates.saveContent(SaveTemplateContentCommand(template.template.templateID, template.template.revision,
            template.sections, template.exercises.map { it.copy(displayNameSnapshot = "虚构模板新名", plannedSets = emptyList()) })))
        assertEquals(applied, f.ok(f.sessions.loadContent(session.sessionID)))
        val changedTemplate = f.ok(f.templates.loadContent(template.template.templateID))!!
        f.ok(f.sessions.saveContent(SaveSessionContentCommand(session.sessionID, applied.session.revision, applied.sections,
            applied.exercises.map { it.copy(displayNameSnapshot = "虚构训练新名", sets = emptyList()) })))
        assertEquals(changedTemplate, f.ok(f.templates.loadContent(template.template.templateID)))
        f.reopen()
        assertEquals(changedTemplate, f.ok(f.templates.loadContent(template.template.templateID)))
    }

    @Test fun applyChecksBothRevisionsAndRejectsTerminalSessionWithoutChanges() = f.test {
        f.student(1)
        val template = content()
        val session = f.start()
        val command = apply(template, session)
        f.error(ApplicationErrorCode.staleRevision, f.templates.applySnapshot(command.copy(expectedTemplateRevision = Revision(999uL))))
        f.error(ApplicationErrorCode.staleRevision, f.templates.applySnapshot(command.copy(expectedSessionRevision = Revision(999uL))))
        assertTrue(f.ok(f.sessions.loadContent(session.sessionID))!!.exercises.isEmpty())
        val abandoned = f.ok(f.sessions.abandon(AbandonEmptySessionCommand(session.sessionID, session.revision, f.now)))
        f.error(ApplicationErrorCode.invalidState, f.templates.applySnapshot(command.copy(expectedSessionRevision = abandoned.revision)))
        assertEquals(template, f.ok(f.templates.loadContent(template.template.templateID)))
    }

    @Test fun applyFailureRollsBackSessionContentFocusAndRevision() = f.test {
        f.student(1)
        val original = f.sessionContent()
        val template = content()
        f.failWrites("sessions", "UPDATE")
        val command = apply(template, original.session)
        f.error(ApplicationErrorCode.persistenceFailed, f.templates.applySnapshot(command))
        assertEquals(original, f.ok(f.sessions.loadContent(original.session.sessionID)))
        assertEquals(template, f.ok(f.templates.loadContent(template.template.templateID)))
        f.clearFailure(); f.reopen()
        val saved = f.ok(f.templates.applySnapshot(command))
        assertEquals(4, saved.exercises.size)
        f.reopen()
        assertEquals(saved, f.ok(f.sessions.loadContent(original.session.sessionID)))
    }

    @Test fun deleteTemplateIsAtomicAndDoesNotDeleteGeneratedSession() = f.test {
        f.student(1)
        val template = content()
        val applied = f.ok(f.templates.applySnapshot(apply(template, f.start())))
        f.failWrites("training_templates", "DELETE")
        f.error(ApplicationErrorCode.persistenceFailed, f.templates.delete(template.template.templateID))
        assertEquals(template, f.ok(f.templates.loadContent(template.template.templateID)))
        f.clearFailure()
        f.ok(f.templates.delete(template.template.templateID))
        f.reopen()
        assertNull(f.ok(f.templates.find(template.template.templateID)))
        assertEquals(0L, f.count("template_planned_sets"))
        assertEquals(0L, f.count("template_exercises"))
        assertEquals(0L, f.count("template_training_focus"))
        assertEquals(applied, f.ok(f.sessions.loadContent(applied.session.sessionID)))
    }

    @Test fun templateGenerationMismatchRejectsSaveDeleteAndApplication() = f.test {
        f.student(1)
        val template = content()
        val session = f.start()
        val repository = f.templates
        f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value = ? WHERE `key` = 'store_generation'",
            arrayOf(UUID.randomUUID().toString()))
        f.error(ApplicationErrorCode.incompatibleInput, repository.delete(template.template.templateID))
        f.error(ApplicationErrorCode.incompatibleInput, repository.saveContent(SaveTemplateContentCommand(template.template.templateID,
            template.template.revision, emptyList(), emptyList())))
        f.error(ApplicationErrorCode.incompatibleInput, repository.applySnapshot(apply(template, session)))
        assertEquals(template, f.ok(f.templates.loadContent(template.template.templateID)))
        assertTrue(f.ok(f.sessions.loadContent(session.sessionID))!!.exercises.isEmpty())
    }

    @Test fun badOwnershipAndDecimalMappingFailWithoutReplacingRows() = f.test {
        val before = content()
        val other = content()
        f.error(ApplicationErrorCode.invalidState, f.templates.saveContent(SaveTemplateContentCommand(before.template.templateID,
            before.template.revision, other.sections, before.exercises)))
        val huge = before.exercises.map { it.copy(plannedSets = it.plannedSets.map { s -> s.copy(weightValue = BigDecimal("1E+65537")) }) }
        f.error(ApplicationErrorCode.textTooLong, f.templates.saveContent(SaveTemplateContentCommand(before.template.templateID,
            before.template.revision, before.sections, huge)))
        assertEquals(before, f.ok(f.templates.loadContent(before.template.templateID)))
    }
}
