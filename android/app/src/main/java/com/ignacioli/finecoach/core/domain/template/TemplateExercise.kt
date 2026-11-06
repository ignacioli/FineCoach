package com.ignacioli.finecoach.core.domain.template

import com.ignacioli.finecoach.core.domain.common.*

/** No per-exercise private note, Student or Session identity can be held here. */
data class TemplateExercise(
    val templateExerciseID: TemplateExerciseID,
    val templateID: TemplateID,
    val sectionID: SectionID?,
    val orderIndex: UInt,
    val sourceKind: ExerciseSourceKind,
    val sourceID: StableExerciseID?,
    val displayNameSnapshot: NormalizedName,
    val recordModeSnapshot: RecordMode,
    val plannedSets: List<TemplatePlannedSet>,
) {
    fun replacingPlannedSets(sets: List<TemplatePlannedSet>): TemplateExercise = copy(plannedSets = sets.toList())
}
