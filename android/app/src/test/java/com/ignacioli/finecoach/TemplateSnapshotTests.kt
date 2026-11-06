package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.core.domain.training.*
import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class TemplateSnapshotTests {
    private val f = TemplateFixtures

    @Test
    fun blankTemplateRequiresOnlyNameAndUsesCommonCanonicalization() {
        val template = f.blank(" \u00a0虚构模板\n")
        assertEquals("虚构模板", template.name.value)
        assertTrue(template.exercises.isEmpty())
        assertTrue(template.sections.isEmpty())
        assertTrue(template.trainingFocus.isEmpty())
        assertEquals(f.now, template.createdAtUTC)
    }

    @Test
    fun invalidNamesMapToDomainErrorForCreateRenameAndExercise() {
        listOf("" to DomainError.emptyText, "\u00a0\n" to DomainError.emptyText,
            "a".repeat(ValidatedText.maximumUTF8Bytes + 1) to DomainError.textTooLong).forEach { (name, expected) ->
            f.error(expected) { f.blank(name) }
            f.error(expected) { f.blank().renamed(name, f.later) }
            f.error(expected) {
                f.blank().addingExercise(f.templateExercise(70), name, RecordMode.reps, nowUTC = f.now)
            }
        }
    }

    @Test
    fun editingFocusPlansOrderAndRemovalPreservesTemplateIdentity() {
        val original = f.template()
        val updated = original.renamed("新模板", f.later).updatingTrainingFocus(setOf(BodyPart.thighs), f.later)
            .replacingPlannedSets(original.exercises.first().templateExerciseID,
                listOf(TemplatePlannedSet(RecordMode.reps, repetitionCount = DecimalValue.parse("15"),
                    unit = MeasurementUnit.repetitions)), f.later)
        assertEquals(original.templateID, updated.templateID)
        assertEquals(original.createdAtUTC, updated.createdAtUTC)
        assertEquals(f.later, updated.updatedAtUTC)
        assertEquals("15", updated.exercises.first().plannedSets.single().repetitionCount?.canonicalString)
        val axis = listOf(SessionSectionAxisItem.Exercise(updated.exercises.last().templateExerciseID.value),
            SessionSectionAxisItem.Section(updated.sections.single().sectionID),
            SessionSectionAxisItem.Exercise(updated.exercises.first().templateExerciseID.value))
        val reordered = updated.reordering(axis, f.later)
        assertEquals(listOf(0u, 2u), reordered.exercises.map { it.orderIndex })
        assertEquals(1u, reordered.sections.single().orderIndex)
        val removed = reordered.removingExercise(reordered.exercises.first().templateExerciseID, f.later)
        assertEquals(1, removed.exercises.size)
        assertEquals(listOf(0u, 1u), (removed.sections.map { it.orderIndex } + removed.exercises.map { it.orderIndex }).sorted())
        assertEquals(2, original.exercises.size)
        assertEquals(setOf(BodyPart.chest), original.trainingFocus)
    }

    @Test
    fun applyingCreatesIndependentNewSectionExerciseAndSetIDsEachTime() {
        val template = f.template()
        val target = f.session()
        val result = f.apply(template, target, 100)
        val again = f.apply(template, target, 200)
        assertEquals(template.exercises.size, result.session.exercises.size - target.session.exercises.size)
        val newExercises = result.session.exercises.drop(target.session.exercises.size)
        assertEquals(2, newExercises.size)
        assertEquals(result.sections.last().sectionID, newExercises.first().sectionID)
        assertNull(newExercises.last().sectionID)
        val sourceIDs = template.exercises.map { it.templateExerciseID.value } + template.sections.map { it.sectionID.value }
        val ids = result.sections.drop(target.sections.size).map { it.sectionID.value } +
            newExercises.flatMap { listOf(it.sessionExerciseID.value) + it.sets.map { set -> set.trainingSetID.value } }
        val otherIDs = again.sections.map { it.sectionID.value } +
            again.session.exercises.drop(1).flatMap { listOf(it.sessionExerciseID.value) + it.sets.map { set -> set.trainingSetID.value } }
        assertEquals(ids.size, ids.toSet().size)
        assertTrue(ids.none { it in sourceIDs || it in otherIDs })
        newExercises.forEach { row ->
            assertEquals(target.session.sessionID, row.sessionID)
            row.sets.forEach { assertEquals(row.sessionExerciseID, it.sessionExerciseID) }
        }
    }

    @Test
    fun appliedPlansArePendingWithFreshTimesAndZeroStatisticsContribution() {
        val result = f.apply(f.template(), SectionedSession(f.emptySession()), 100)
        result.session.exercises.flatMap { it.sets }.forEach {
            assertEquals(SetRecordingState.pending, it.state)
            assertNull(it.completedAtUTC)
            assertEquals(f.later, it.createdAtUTC)
            assertEquals(f.later, it.updatedAtUTC)
            assertFalse(it.contributesToStatistics)
            assertNull(it.ordinaryVolumeContribution())
        }
        assertEquals(0, result.session.completedSetCount)
        assertTrue(result.session.statisticsSets.isEmpty())
        assertEquals(SessionFinishGate.abandonEmpty, result.session.finishGate)
    }

    @Test
    fun applyingRenumbersCombinedAxisAndSetsAndMergesFocusWithoutChangingExistingValues() {
        val target = f.session().copy(session = f.session().session.copy(trainingFocus = setOf(BodyPart.back)))
        val result = f.apply(f.template(), target, 100)
        assertEquals(listOf(0u, 1u, 2u, 3u),
            (result.sections.map { it.orderIndex } + result.session.exercises.map { it.orderIndex }).sorted())
        assertEquals(listOf(0u, 1u), result.session.exercises[1].sets.map { it.orderIndex })
        assertEquals(setOf(BodyPart.back, BodyPart.chest), result.session.trainingFocus)
        assertEquals(target.session.exercises.single().copy(orderIndex = 0u), result.session.exercises.first())
        assertEquals(DecimalValue.parse("0"), result.session.exercises[1].sets.first().weightValue)
    }

    @Test
    fun snapshotCopiesOnlyPlannedValuesAndStructureFromCompletedTraining() {
        val source = f.completed()
        val template = f.snapshot(source)
        assertNotEquals(source.session.sessionID.value, template.templateID.value)
        assertTrue(source.session.trainingFocus.isNotEmpty())
        assertEquals(emptySet<BodyPart>(), template.trainingFocus)
        assertEquals(SectionOwner.Template(template.templateID), template.sections.single().owner)
        assertEquals(template.sections.single().sectionID, template.exercises.first().sectionID)
        assertNotEquals(source.sections.single().sectionID, template.sections.single().sectionID)
        val original = source.session.exercises.first()
        val copied = template.exercises.first()
        assertNotEquals(original.sessionExerciseID.value, copied.templateExerciseID.value)
        assertEquals(original.sourceID, copied.sourceID)
        assertEquals(original.displayNameSnapshot, copied.displayNameSnapshot)
        assertEquals(original.sets.map(TemplatePlannedSet::copyingValuesFrom), copied.plannedSets)
        val forbidden = setOf("studentID", "sessionID", "completedAtUTC", "state", "privateCoachNote",
            "studentFacingSummary", "actionPrivateNote", "coursePackageID", "sourceEventKey", "elapsedSeconds")
        listOf(TrainingTemplate::class.java, TemplateExercise::class.java, TemplatePlannedSet::class.java).forEach { type ->
            assertTrue(type.declaredFields.none { it.name in forbidden })
        }
        assertEquals(SessionState.completed, source.session.state)
        assertEquals(f.now, source.session.exercises.first().sets.first().completedAtUTC)
    }

    @Test
    fun allRecordableValuesSurviveSnapshotAndApplicationWithoutCompletionMetadata() {
        val complete = f.completed()
        val original = complete.session.exercises.first().sets.first()
        val plans = listOf(
            f.plan().copy(side = SetSide.bilateral, leftValue = DecimalValue.parse("1.25"),
                rightValue = DecimalValue.parse("2.5")),
            TemplatePlannedSet(RecordMode.cardio, durationSeconds = DecimalValue.parse("120.25"),
                unit = MeasurementUnit.seconds, distanceValue = DecimalValue.parse("0.75"),
                speedValue = DecimalValue.parse("3.25"), resistanceValue = DecimalValue.parse("4.5")),
            TemplatePlannedSet(RecordMode.duration, durationSeconds = DecimalValue.parse("90"), unit = MeasurementUnit.seconds),
            TemplatePlannedSet(RecordMode.reps, repetitionCount = DecimalValue.parse("12"), unit = MeasurementUnit.repetitions),
        )
        val values = plans.mapIndexed { index, plan ->
            plan.makePendingSet(f.set(60 + index), original.sessionExerciseID, (9 + index).toUInt(), f.now)
                .confirmed(f.now)
        }
        val source = complete.copy(session = complete.session.copy(exercises = listOf(
            complete.session.exercises.first().copy(sets = values))))
        val template = f.snapshot(source)
        val applied = f.apply(template, SectionedSession(f.emptySession(90)), 100)
        assertEquals(plans, applied.session.exercises.single().sets.map(TemplatePlannedSet::copyingValuesFrom))
        assertEquals(listOf(0u, 1u, 2u, 3u), applied.session.exercises.single().sets.map { it.orderIndex })
        assertNull(applied.session.exercises.single().actionPrivateNote)
        assertNull(applied.session.privateCoachNote)
        assertNull(applied.session.studentFacingSummary)
        assertEquals(DecimalValue.parse("0"), applied.session.elapsedSeconds)
    }

    @Test
    fun laterTemplateEditsOrRemovalFromCollectionCannotReachAppliedSnapshot() {
        val plans = mutableListOf(f.plan())
        val focus = mutableSetOf(BodyPart.chest)
        val template = f.blank().updatingTrainingFocus(focus, f.now).addingExercise(
            f.templateExercise(30), "虚构动作", RecordMode.weightReps, plans, nowUTC = f.now)
        val templates = mutableListOf(template)
        val snapshot = f.apply(templates.single(), SectionedSession(f.emptySession()), 100)
        plans.clear()
        focus.clear()
        templates[0] = template.replacingPlannedSets(template.exercises.single().templateExerciseID, emptyList(), f.later)
        templates.clear()
        assertEquals(1, snapshot.session.exercises.single().sets.size)
        assertEquals(setOf(BodyPart.chest), snapshot.session.trainingFocus)
        val editedSession = snapshot.session.editingSet(snapshot.session.exercises.single().sets.single().trainingSetID,
            TrainingSetInput(RecordMode.weightReps, "10", "8", unit = MeasurementUnit.kilograms), f.later)
        assertEquals(DecimalValue.parse("10"), editedSession.exercises.single().sets.single().weightValue)
        assertEquals(DecimalValue.parse("0"), template.exercises.single().plannedSets.single().weightValue)
    }

    @Test
    fun invalidOwnersAxesOrGeneratedIDsAreRejectedWithoutMutatingSource() {
        val template = f.template()
        val target = f.session()
        f.error(DomainError.conflict) {
            template.applying(target, { target.session.exercises.single().sessionExerciseID },
                { f.set(100) }, { f.section(101) }, f.later)
        }
        f.error(DomainError.invalidState) {
            f.apply(template.copy(sections = template.sections.map { it.copy(owner = SectionOwner.Template(f.templateID(90))) }), target, 100)
        }
        f.error(DomainError.invalidState) { template.reordering(emptyList(), f.later) }
        f.error(DomainError.invalidState) { f.apply(template, f.completed(), 100) }
        assertEquals(1, target.session.exercises.size)
        assertEquals(2, template.exercises.size)
    }
}

internal object TemplateFixtures {
    val now: Instant = Instant.ofEpochSecond(1_700_000_000)
    val later: Instant = now.plusSeconds(60)
    fun uuid(n: Int): UUID = UUID(0L, n.toLong())
    fun section(n: Int): SectionID = SectionID.fromUUID(uuid(n))
    fun templateID(n: Int): TemplateID = TemplateID.fromUUID(uuid(n))
    fun templateExercise(n: Int): TemplateExerciseID = TemplateExerciseID.fromUUID(uuid(n))
    fun exercise(n: Int): SessionExerciseID = SessionExerciseID.fromUUID(uuid(n))
    fun set(n: Int): TrainingSetID = TrainingSetID.fromUUID(uuid(n))
    fun emptySession(n: Int = 1): Session = Session.start(SessionID.fromUUID(uuid(n)), StudentID.fromUUID(uuid(2)), nowUTC = now)
    fun blank(name: String = "虚构模板"): TrainingTemplate = TrainingTemplate.blank(templateID(10), name, nowUTC = now)
    fun plan(): TemplatePlannedSet = TemplatePlannedSet(RecordMode.weightReps,
        weightValue = DecimalValue.parse("0"), repetitionCount = DecimalValue.parse("8"), unit = MeasurementUnit.kilograms)
    fun template(): TrainingTemplate = blank().updatingTrainingFocus(setOf(BodyPart.chest), now)
        .addingSection(section(11), "热身", now)
        .addingExercise(templateExercise(12), "虚构推举", RecordMode.weightReps, listOf(plan(), plan()), section(11), nowUTC = now)
        .addingExercise(templateExercise(13), "虚构辅助", RecordMode.reps, listOf(TemplatePlannedSet(RecordMode.reps, repetitionCount = DecimalValue.parse("12"), unit = MeasurementUnit.repetitions)), nowUTC = now)
    fun session(): SectionedSession = SectionedSession(emptySession().addingSessionOnlyExercise(
        exercise(3), "虚构动作", RecordMode.weightReps, now).addingSet(exercise(3), set(4),
        TrainingSetInput(RecordMode.weightReps, "10", "8", unit = MeasurementUnit.kilograms), now)
        .confirmingSet(set(4), now))
    fun completed(): SectionedSession {
        val source = session().addingSection(section(5), "主训练", now).movingExercise(exercise(3), section(5), now)
        return source.copy(session = source.session.finished(now).copy(
            trainingFocus = setOf(BodyPart.chest), privateCoachNote = ValidatedText.required("虚构私密备注"),
            studentFacingSummary = ValidatedText.required("虚构总结"), exercises = source.session.exercises.map {
                it.copy(actionPrivateNote = ValidatedText.required("虚构动作备注"))
            }))
    }
    fun snapshot(from: SectionedSession): TrainingTemplate {
        var next = 50
        return TrainingTemplate.snapshotFromSession(from, templateID(40), "另存模板",
            newExerciseID = { templateExercise(next++) }, newSectionID = { section(next++) }, nowUTC = later)
    }
    fun apply(template: TrainingTemplate, to: SectionedSession, start: Int): SectionedSession {
        var next = start
        return template.applying(to, { exercise(next++) }, { set(next++) }, { section(next++) }, later)
    }
    fun error(expected: DomainError, action: () -> Unit) {
        assertEquals(expected, assertThrows(DomainException::class.java) { action() }.error)
    }
}
