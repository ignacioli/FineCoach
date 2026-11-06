package com.ignacioli.finecoach.core.domain.template

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import java.time.Instant

/** Content aggregate. Deleting its persisted rows is the TemplateRepository's responsibility. */
data class TrainingTemplate(
    val templateID: TemplateID,
    val name: NormalizedName,
    val trainingFocus: Set<BodyPart>,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
    val sections: List<SessionSection> = emptyList(),
    val exercises: List<TemplateExercise> = emptyList(),
) {
    private fun layout(): SectionLayout<TemplateExercise> {
        if (exercises.any { it.templateID != templateID }) fail(DomainError.invalidState)
        return SectionLayout(
            SectionOwner.Template(templateID), sections, exercises,
            { it.templateExerciseID.value }, { it.orderIndex }, { it.sectionID },
            { row, index, target -> row.copy(orderIndex = index, sectionID = target) },
        )
    }

    fun renamed(name: String, nowUTC: Instant): TrainingTemplate =
        copy(name = parseDomainName(name, "templateName"), updatedAtUTC = nowUTC)

    fun updatingTrainingFocus(value: Set<BodyPart>, nowUTC: Instant): TrainingTemplate =
        copy(trainingFocus = value.toSet(), updatedAtUTC = nowUTC)

    fun addingExercise(
        id: TemplateExerciseID,
        displayName: String,
        recordMode: RecordMode,
        plannedSets: List<TemplatePlannedSet> = emptyList(),
        sectionID: SectionID? = null,
        sourceKind: ExerciseSourceKind = ExerciseSourceKind.sessionOnly,
        sourceID: StableExerciseID? = null,
        nowUTC: Instant,
    ): TrainingTemplate {
        val (headers, rows) = layout().normalized()
        if (rows.any { it.templateExerciseID == id }) fail(DomainError.conflict)
        if (sectionID != null && headers.none { it.sectionID == sectionID }) fail(DomainError.invalidState)
        val row = TemplateExercise(
            id, templateID, sectionID, (headers.size + rows.size).toUInt(), sourceKind, sourceID,
            parseDomainName(displayName, "displayName"), recordMode, plannedSets.toList(),
        )
        return copy(sections = headers, exercises = rows + row, updatedAtUTC = nowUTC)
    }

    fun replacingPlannedSets(id: TemplateExerciseID, sets: List<TemplatePlannedSet>, nowUTC: Instant): TrainingTemplate {
        if (exercises.none { it.templateExerciseID == id }) fail(DomainError.notFound)
        return copy(
            exercises = exercises.map { if (it.templateExerciseID == id) it.replacingPlannedSets(sets) else it },
            updatedAtUTC = nowUTC,
        )
    }

    fun removingExercise(id: TemplateExerciseID, nowUTC: Instant): TrainingTemplate {
        if (exercises.none { it.templateExerciseID == id }) fail(DomainError.notFound)
        val remaining = copy(exercises = exercises.filterNot { it.templateExerciseID == id })
        return changed(remaining.layout().normalized(), nowUTC)
    }

    fun addingSection(id: SectionID, name: String, nowUTC: Instant): TrainingTemplate =
        changed(layout().addingSection(id, name), nowUTC)

    fun renamingSection(id: SectionID, name: String, nowUTC: Instant): TrainingTemplate =
        changed(layout().renamingSection(id, name), nowUTC)

    fun movingExercise(id: TemplateExerciseID, target: SectionID?, nowUTC: Instant): TrainingTemplate =
        changed(layout().movingExercise(id.value, target), nowUTC)

    fun reordering(axis: List<SessionSectionAxisItem>, nowUTC: Instant): TrainingTemplate =
        changed(layout().reordered(axis), nowUTC)

    fun deletingSection(
        id: SectionID,
        disposition: SessionSectionDeletionDisposition?,
        nowUTC: Instant,
    ): TrainingTemplate {
        if (disposition == null) return this
        return changed(layout().deletingSection(id, disposition), nowUTC)
    }

    private fun changed(content: Pair<List<SessionSection>, List<TemplateExercise>>, nowUTC: Instant): TrainingTemplate =
        copy(sections = content.first, exercises = content.second, updatedAtUTC = nowUTC)

    /** Explicit generators must supply fresh IDs; collisions are rejected, never silently overwritten. */
    fun applying(
        to: SectionedSession,
        newExerciseID: () -> SessionExerciseID,
        newSetID: () -> TrainingSetID,
        newSectionID: () -> SectionID,
        nowUTC: Instant,
    ): SectionedSession {
        if (to.session.state != SessionState.inProgress) fail(DomainError.invalidState)
        val (existingSections, existingExercises) = to.layout().normalized()
        val (templateSections, templateExercises) = layout().normalized()
        val used = mutableSetOf<String>()
        used.addAll(existingSections.map { it.sectionID.value })
        used.addAll(existingExercises.flatMap { row -> listOf(row.sessionExerciseID.value) + row.sets.map { it.trainingSetID.value } })
        used.add(to.session.sessionID.value)
        used.add(templateID.value)
        used.addAll(templateSections.map { it.sectionID.value })
        used.addAll(templateExercises.map { it.templateExerciseID.value })
        fun fresh(value: String) { if (!used.add(value)) fail(DomainError.conflict) }
        val mapping = templateSections.associate { header ->
            header.sectionID to newSectionID().also { fresh(it.value) }
        }
        val offset = existingSections.size + existingExercises.size
        val newSections = templateSections.map {
            it.copy(sectionID = mapping.getValue(it.sectionID), owner = SectionOwner.Session(to.session.sessionID),
                orderIndex = it.orderIndex + offset.toUInt())
        }
        val newExercises = templateExercises.map { row ->
            val id = newExerciseID().also { fresh(it.value) }
            SessionExercise(
                sessionExerciseID = id, sessionID = to.session.sessionID,
                orderIndex = row.orderIndex + offset.toUInt(), sourceKind = row.sourceKind, sourceID = row.sourceID,
                displayNameSnapshot = row.displayNameSnapshot, recordModeSnapshot = row.recordModeSnapshot,
                actionPrivateNote = null, sectionID = row.sectionID?.let { mapping.getValue(it) },
                sets = row.plannedSets.mapIndexed { index, planned ->
                    planned.copy().makePendingSet(newSetID().also { fresh(it.value) }, id, index.toUInt(), nowUTC)
                },
            )
        }
        val updated = to.session.copy(exercises = existingExercises)
            .appendingTemplateExercises(newExercises, nowUTC)
            .mergingTrainingFocus(trainingFocus.toSet(), nowUTC)
        return SectionedSession(updated, existingSections + newSections)
    }

    companion object {
        fun blank(id: TemplateID, name: String, trainingFocus: Set<BodyPart> = emptySet(), nowUTC: Instant): TrainingTemplate =
            TrainingTemplate(id, parseDomainName(name, "templateName"), trainingFocus.toSet(), nowUTC, nowUTC)

        /** Like iOS's Domain helper, accepts any state; S1's UI entry remains completed-only (T012). */
        fun snapshotFromSession(
            from: SectionedSession,
            id: TemplateID,
            name: String,
            // iOS TemplateUseCases.saveAsTemplate defaults to [] and no caller passes the source focus.
            trainingFocus: Set<BodyPart> = emptySet(),
            newExerciseID: () -> TemplateExerciseID,
            newSectionID: () -> SectionID,
            nowUTC: Instant,
        ): TrainingTemplate {
            val (headers, rows) = from.layout().normalized()
            val used = (headers.map { it.sectionID.value } + rows.flatMap { row ->
                listOf(row.sessionExerciseID.value) + row.sets.map { it.trainingSetID.value }
            } + from.session.sessionID.value).toMutableSet()
            fun fresh(value: String) { if (!used.add(value)) fail(DomainError.conflict) }
            fresh(id.value)
            val mapping = headers.associate { it.sectionID to newSectionID().also { next -> fresh(next.value) } }
            return blank(id, name, trainingFocus, nowUTC).copy(
                sections = headers.map {
                    it.copy(sectionID = mapping.getValue(it.sectionID), owner = SectionOwner.Template(id))
                },
                exercises = rows.map { row ->
                    TemplateExercise(
                        newExerciseID().also { fresh(it.value) }, id, row.sectionID?.let { mapping.getValue(it) },
                        row.orderIndex, row.sourceKind, row.sourceID, row.displayNameSnapshot, row.recordModeSnapshot,
                        row.sets.sortedBy { it.orderIndex }.map(TemplatePlannedSet::copyingValuesFrom),
                    )
                },
            )
        }
    }
}
