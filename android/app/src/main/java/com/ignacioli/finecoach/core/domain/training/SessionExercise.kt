package com.ignacioli.finecoach.core.domain.training

import com.ignacioli.finecoach.core.domain.common.ExerciseSourceKind
import com.ignacioli.finecoach.core.domain.common.NormalizedName
import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.SectionID
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.ValidatedText

data class SessionExercise(
    val sessionExerciseID: SessionExerciseID,
    val sessionID: SessionID,
    val orderIndex: UInt,
    val sourceKind: ExerciseSourceKind,
    val sourceID: StableExerciseID?,
    val displayNameSnapshot: NormalizedName,
    val recordModeSnapshot: RecordMode,
    val actionPrivateNote: ValidatedText?,
    val sectionID: SectionID? = null,
    val sets: List<TrainingSet>,
) {

    val hasCompletedSet: Boolean
        get() = sets.any { it.contributesToStatistics }

    fun relocating(orderIndex: UInt): SessionExercise {
        return copy(
            orderIndex = orderIndex,
            sets = sets.mapIndexed { index, trainingSet ->
                trainingSet.relocating(sessionExerciseID = sessionExerciseID, orderIndex = index.toUInt())
            },
        )
    }

    fun relocating(orderIndex: UInt, sectionID: SectionID?): SessionExercise {
        return copy(
            orderIndex = orderIndex,
            sectionID = sectionID,
            sets = sets.mapIndexed { index, trainingSet ->
                trainingSet.relocating(sessionExerciseID = sessionExerciseID, orderIndex = index.toUInt())
            },
        )
    }

    fun replacingActionPrivateNote(note: ValidatedText?): SessionExercise = copy(actionPrivateNote = note)

    fun replacingSets(sets: List<TrainingSet>): SessionExercise {
        return copy(
            sets = sets.mapIndexed { index, trainingSet ->
                trainingSet.relocating(sessionExerciseID = sessionExerciseID, orderIndex = index.toUInt())
            },
        )
    }
}
