package com.ignacioli.finecoach.core.domain.template

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.core.domain.training.TrainingSet
import java.time.Instant

/** Planned values only: no identity, completion state, statistics or timestamps. */
data class TemplatePlannedSet(
    val recordMode: RecordMode,
    val weightValue: DecimalValue? = null,
    val repetitionCount: DecimalValue? = null,
    val durationSeconds: DecimalValue? = null,
    val unit: MeasurementUnit,
    val side: SetSide = SetSide.none,
    val leftValue: DecimalValue? = null,
    val rightValue: DecimalValue? = null,
    val distanceValue: DecimalValue? = null,
    val speedValue: DecimalValue? = null,
    val resistanceValue: DecimalValue? = null,
) {
    fun makePendingSet(id: TrainingSetID, exerciseID: SessionExerciseID, orderIndex: UInt, nowUTC: Instant): TrainingSet =
        TrainingSet(
            id, exerciseID, orderIndex, SetRecordingState.pending, recordMode,
            weightValue, repetitionCount, durationSeconds, unit, side, leftValue, rightValue,
            distanceValue, speedValue, resistanceValue, nowUTC, nowUTC, null,
        )

    companion object {
        fun copyingValuesFrom(set: TrainingSet): TemplatePlannedSet = TemplatePlannedSet(
            set.recordMode, set.weightValue, set.repetitionCount, set.durationSeconds, set.unit, set.side,
            set.leftValue, set.rightValue, set.distanceValue, set.speedValue, set.resistanceValue,
        )
    }
}
