package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.core.domain.training.*
import org.junit.Assert.*
import org.junit.Test

class SectionDeletionTests {
    private val f = TemplateFixtures
    private val removed = f.section(11)
    private val target = f.section(14)
    private val member = f.templateExercise(12)
    private val unrelated = f.templateExercise(13)

    private fun template(): TrainingTemplate = f.template().addingSection(target, "辅助训练", f.now)
        .movingExercise(unrelated, target, f.now)

    private fun session(): SectionedSession {
        val result = f.apply(template(), SectionedSession(f.emptySession()), 100)
        // Include completed data: moving must retain completion; deleting must remove it.
        return result.copy(session = result.session.copy(exercises = result.session.exercises.map { row ->
            row.copy(sets = row.sets.map { it.confirmed(f.now) })
        }))
    }

    private fun assertDense(sections: List<SessionSection>, orders: List<UInt>) {
        val axis = sections.map { it.orderIndex } + orders
        assertEquals(axis.indices.map { it.toUInt() }, axis.sorted())
    }

    @Test
    fun templateMoveToSurvivingSectionKeepsEveryExercisePlanAndIdentity() {
        val original = template()
        val result = original.deletingSection(removed,
            SessionSectionDeletionDisposition.MoveExercisesTo(target), f.later)
        assertEquals(listOf(target), result.sections.map { it.sectionID })
        assertEquals(original.exercises.map { it.templateExerciseID }, result.exercises.map { it.templateExerciseID })
        assertEquals(target, result.exercises.first().sectionID)
        assertEquals(original.exercises.first().copy(sectionID = target, orderIndex = result.exercises.first().orderIndex),
            result.exercises.first())
        assertEquals(original.exercises.last().copy(orderIndex = result.exercises.last().orderIndex), result.exercises.last())
        assertDense(result.sections, result.exercises.map { it.orderIndex })
        assertEquals(2, original.sections.size)
    }

    @Test
    fun templateMoveToUnsectionedKeepsPlansAndIdentities() {
        val original = template()
        val result = original.deletingSection(removed, SessionSectionDeletionDisposition.MoveExercisesTo(null), f.later)
        assertNull(result.exercises.first().sectionID)
        assertEquals(original.exercises.first().plannedSets, result.exercises.first().plannedSets)
        assertEquals(member, result.exercises.first().templateExerciseID)
        assertEquals(target, result.exercises.last().sectionID)
        assertDense(result.sections, result.exercises.map { it.orderIndex })
    }

    @Test
    fun templateDeleteWithExercisesRemovesMembersAndPlansOnly() {
        val original = template()
        val result = original.deletingSection(removed, SessionSectionDeletionDisposition.DeleteWithExercises, f.later)
        assertEquals(listOf(target), result.sections.map { it.sectionID })
        assertEquals(listOf(unrelated), result.exercises.map { it.templateExerciseID })
        assertFalse(result.exercises.any { it.templateExerciseID == member })
        assertEquals(original.exercises.last().copy(orderIndex = result.exercises.single().orderIndex), result.exercises.single())
        assertEquals(original.sections.last().copy(orderIndex = result.sections.single().orderIndex), result.sections.single())
        assertDense(result.sections, result.exercises.map { it.orderIndex })
        assertEquals(2, original.exercises.size)
    }

    @Test
    fun sessionMoveToSurvivingSectionPreservesCompletedSetsAndIdentity() {
        val original = session()
        val from = original.sections.first().sectionID
        val to = original.sections.last().sectionID
        val result = original.deletingSection(from, SessionSectionDeletionDisposition.MoveExercisesTo(to), f.later)
        assertEquals(original.session.exercises.map { it.sessionExerciseID }, result.session.exercises.map { it.sessionExerciseID })
        assertEquals(original.session.exercises.first().copy(sectionID = to, orderIndex = result.session.exercises.first().orderIndex),
            result.session.exercises.first())
        assertEquals(original.session.exercises.first().sets, result.session.exercises.first().sets)
        assertTrue(result.session.exercises.first().sets.all { it.completedAtUTC == f.now && it.contributesToStatistics })
        assertEquals(original.session.exercises.last().copy(orderIndex = result.session.exercises.last().orderIndex),
            result.session.exercises.last())
        assertEquals(original.session.studentID, result.session.studentID)
        assertEquals(original.session.sessionID, result.session.sessionID)
        assertDense(result.sections, result.session.exercises.map { it.orderIndex })
    }

    @Test
    fun sessionMoveToUnsectionedRetainsGroupsAndCompletedStatistics() {
        val original = session()
        val result = original.deletingSection(original.sections.first().sectionID,
            SessionSectionDeletionDisposition.MoveExercisesTo(null), f.later)
        assertNull(result.session.exercises.first().sectionID)
        assertEquals(original.session.exercises.first().sets, result.session.exercises.first().sets)
        assertEquals(original.session.completedSetCount, result.session.completedSetCount)
        assertEquals(original.session.exercises.last().sectionID, result.session.exercises.last().sectionID)
        assertDense(result.sections, result.session.exercises.map { it.orderIndex })
    }

    @Test
    fun sessionDeleteWithExercisesDeletesOnlyMemberRowsAndTheirGroups() {
        val original = session()
        val memberRow = original.session.exercises.first()
        val unrelatedRow = original.session.exercises.last()
        val result = original.deletingSection(original.sections.first().sectionID,
            SessionSectionDeletionDisposition.DeleteWithExercises, f.later)
        assertEquals(listOf(original.sections.last().sectionID), result.sections.map { it.sectionID })
        assertEquals(listOf(unrelatedRow.sessionExerciseID), result.session.exercises.map { it.sessionExerciseID })
        assertFalse(result.session.exercises.any { it.sessionExerciseID == memberRow.sessionExerciseID })
        val survivingSetIDs = result.session.exercises.flatMap { it.sets }.map { it.trainingSetID }
        assertTrue(memberRow.sets.none { it.trainingSetID in survivingSetIDs })
        assertEquals(unrelatedRow.copy(orderIndex = result.session.exercises.single().orderIndex), result.session.exercises.single())
        assertEquals(unrelatedRow.sets, result.session.exercises.single().sets)
        assertDense(result.sections, result.session.exercises.map { it.orderIndex })
        assertEquals(2, original.session.exercises.size)
    }

    @Test
    fun unselectedOrCancelledDispositionReturnsOriginalObjectsIncludingRevisionAndTimes() {
        val template = template()
        val session = session()
        // Both a sheet with no selection and one dismissed by cancel send no disposition.
        repeat(2) {
            assertSame(template, template.deletingSection(removed, null, f.later))
            assertSame(session, session.deletingSection(session.sections.first().sectionID, null, f.later))
        }
    }

    @Test
    fun templateRejectsSelfMissingAndForeignTargetsWithNoChange() {
        val original = template()
        val before = original.copy()
        listOf(removed, f.section(99)).forEach { targetID ->
            f.error(DomainError.invalidState) {
                original.deletingSection(removed, SessionSectionDeletionDisposition.MoveExercisesTo(targetID), f.later)
            }
        }
        val foreign = original.copy(sections = original.sections.map {
            if (it.sectionID == target) it.copy(owner = SectionOwner.Template(f.templateID(999))) else it
        })
        f.error(DomainError.invalidState) {
            foreign.deletingSection(removed, SessionSectionDeletionDisposition.MoveExercisesTo(target), f.later)
        }
        assertEquals(before, original)
    }

    @Test
    fun sessionRejectsSelfMissingAndForeignTargetsWithNoChange() {
        val original = session()
        val from = original.sections.first().sectionID
        val before = original.copy()
        listOf(from, f.section(99)).forEach { targetID ->
            f.error(DomainError.invalidState) {
                original.deletingSection(from, SessionSectionDeletionDisposition.MoveExercisesTo(targetID), f.later)
            }
        }
        val foreign = original.copy(sections = original.sections.map {
            if (it == original.sections.last()) it.copy(owner = SectionOwner.Session(f.emptySession(999).sessionID)) else it
        })
        f.error(DomainError.invalidState) {
            foreign.deletingSection(from, SessionSectionDeletionDisposition.MoveExercisesTo(original.sections.last().sectionID), f.later)
        }
        assertEquals(before, original)
    }

    @Test
    fun missingSectionDeletionRejectsBothDispositionsForBothOwners() {
        val originalTemplate = template()
        val originalSession = session()
        listOf(SessionSectionDeletionDisposition.MoveExercisesTo(null),
            SessionSectionDeletionDisposition.DeleteWithExercises).forEach { disposition ->
            f.error(DomainError.notFound) { originalTemplate.deletingSection(f.section(999), disposition, f.later) }
            f.error(DomainError.notFound) { originalSession.deletingSection(f.section(999), disposition, f.later) }
        }
    }

    @Test
    fun sectionCreateRenameMoveInAndOutAndReorderWorkForBothOwners() {
        val template = f.blank().addingSection(removed, "主训练", f.now)
            .addingExercise(member, "虚构动作", RecordMode.reps, nowUTC = f.now)
            .renamingSection(removed, " 重命名 ", f.later)
        assertEquals("重命名", template.sections.single().name.value)
        val movedTemplate = template.movingExercise(member, removed, f.later)
        assertEquals(removed, movedTemplate.exercises.single().sectionID)
        assertNull(movedTemplate.movingExercise(member, null, f.later).exercises.single().sectionID)
        val session = f.session().addingSection(removed, "主训练", f.now).renamingSection(removed, "重命名", f.later)
        val movedSession = session.movingExercise(session.session.exercises.single().sessionExerciseID, removed, f.later)
        assertEquals(removed, movedSession.session.exercises.single().sectionID)
        assertNull(movedSession.movingExercise(session.session.exercises.single().sessionExerciseID, null, f.later)
            .session.exercises.single().sectionID)
        val reordered = movedSession.reordering(listOf(SessionSectionAxisItem.Section(removed),
            SessionSectionAxisItem.Exercise(movedSession.session.exercises.single().sessionExerciseID.value)), f.later)
        assertEquals(0u, reordered.sections.single().orderIndex)
        assertEquals(1u, reordered.session.exercises.single().orderIndex)
        f.error(DomainError.invalidState) { movedSession.reordering(emptyList(), f.later) }
        f.error(DomainError.invalidState) { template.movingExercise(member, f.section(999), f.later) }
        f.error(DomainError.invalidState) { session.movingExercise(f.exercise(3), f.section(999), f.later) }
        f.error(DomainError.emptyText) { template.renamingSection(removed, " ", f.later) }
        f.error(DomainError.textTooLong) { session.renamingSection(removed, "a".repeat(ValidatedText.maximumUTF8Bytes + 1), f.later) }
    }

    @Test
    fun emptySectionDeletionRequiresExplicitChoiceAndDuplicateAxisEntriesAreRejected() {
        val template = f.blank().addingSection(removed, "空分段", f.now)
        assertSame(template, template.deletingSection(removed, null, f.later))
        val deleted = template.deletingSection(removed, SessionSectionDeletionDisposition.DeleteWithExercises, f.later)
        assertTrue(deleted.sections.isEmpty())
        assertTrue(deleted.exercises.isEmpty())
        val session = SectionedSession(f.emptySession()).addingSection(removed, "空分段", f.now)
        assertTrue(session.deletingSection(removed, SessionSectionDeletionDisposition.MoveExercisesTo(null), f.later).sections.isEmpty())
        val full = template()
        val duplicate = listOf(SessionSectionAxisItem.Section(removed), SessionSectionAxisItem.Section(removed))
        f.error(DomainError.invalidState) { full.reordering(duplicate, f.later) }
        f.error(DomainError.conflict) { full.addingSection(removed, "重复", f.later) }
    }
}
