package com.ignacioli.finecoach.core.domain.exercise

import com.ignacioli.finecoach.core.domain.common.ExerciseKind
import com.ignacioli.finecoach.core.domain.common.ExerciseLifecycle
import com.ignacioli.finecoach.core.domain.common.NormalizedName
import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.training.parseDomainName

/**
 * Snapshot fields [Session.addingCatalogExercise] reads when a catalog exercise
 * enters the current session (iOS `Session.swift:198-220`).
 *
 * Name claims, preferences, library browse, archive/restore, and provenance
 * belong to T006b (FR-017/018/024). This type keeps only the fields the
 * session needs. [canonicalName] is a [NormalizedName]; [normalizedName] is
 * derived from it. There is no constructor that accepts a separate raw
 * normalized string.
 */
data class ExerciseCatalogItem(
    val exerciseID: StableExerciseID,
    val kind: ExerciseKind,
    val canonicalName: NormalizedName,
    val recordMode: RecordMode,
    val lifecycle: ExerciseLifecycle = ExerciseLifecycle.active,
) {
    val normalizedName: String
        get() = canonicalName.value

    companion object {
        fun make(
            exerciseID: StableExerciseID,
            kind: ExerciseKind,
            canonicalName: String,
            recordMode: RecordMode,
            lifecycle: ExerciseLifecycle = ExerciseLifecycle.active,
        ): ExerciseCatalogItem {
            return ExerciseCatalogItem(
                exerciseID = exerciseID,
                kind = kind,
                canonicalName = parseDomainName(canonicalName, "canonicalName"),
                recordMode = recordMode,
                lifecycle = lifecycle,
            )
        }
    }
}
