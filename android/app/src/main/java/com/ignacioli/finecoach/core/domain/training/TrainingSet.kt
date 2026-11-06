package com.ignacioli.finecoach.core.domain.training

import com.ignacioli.finecoach.core.domain.common.MeasurementUnit
import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SetRecordingState
import com.ignacioli.finecoach.core.domain.common.SetSide
import com.ignacioli.finecoach.core.domain.common.TrainingSetID
import java.time.Instant

data class TrainingSetInput(
    val recordMode: RecordMode,
    val weightValue: String? = null,
    val repetitionCount: String? = null,
    val durationSeconds: String? = null,
    val unit: MeasurementUnit,
    val side: SetSide = SetSide.none,
    val leftValue: String? = null,
    val rightValue: String? = null,
    val distanceValue: String? = null,
    val speedValue: String? = null,
    val resistanceValue: String? = null,
)

data class TrainingSet(
    val trainingSetID: TrainingSetID,
    val sessionExerciseID: SessionExerciseID,
    val orderIndex: UInt,
    val state: SetRecordingState,
    val recordMode: RecordMode,
    val weightValue: DecimalValue?,
    val repetitionCount: DecimalValue?,
    val durationSeconds: DecimalValue?,
    val unit: MeasurementUnit,
    val side: SetSide,
    val leftValue: DecimalValue?,
    val rightValue: DecimalValue?,
    val distanceValue: DecimalValue?,
    val speedValue: DecimalValue?,
    val resistanceValue: DecimalValue?,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
    val completedAtUTC: Instant?,
) {
    val contributesToStatistics: Boolean
        get() = state == SetRecordingState.completed

    val displaySummary: String
        get() = when (recordMode) {
            RecordMode.weightReps -> {
                val reps = repetitionCount?.canonicalString ?: "-"
                val unitText = when (unit) {
                    MeasurementUnit.kilograms -> "kg"
                    MeasurementUnit.pounds -> "lb"
                    else -> ""
                }
                val load = when (side) {
                    SetSide.none -> weightValue?.canonicalString
                    SetSide.left -> leftValue?.canonicalString ?: weightValue?.canonicalString
                    SetSide.right -> rightValue?.canonicalString ?: weightValue?.canonicalString
                    SetSide.bilateral -> if (leftValue != null && rightValue != null) {
                        "${leftValue.canonicalString}/${rightValue.canonicalString}"
                    } else {
                        weightValue?.canonicalString
                    }
                } ?: "-"
                "$load $unitText × $reps"
            }

            RecordMode.reps -> "${repetitionCount?.canonicalString ?: "-"} 次"
            RecordMode.duration -> "${durationSeconds?.canonicalString ?: "-"} 秒"
            RecordMode.cardio -> {
                val duration = durationSeconds?.canonicalString ?: "-"
                val distance = distanceValue?.canonicalString ?: "-"
                "$duration 秒 / $distance"
            }
        }

    fun ordinaryVolumeContribution(): DecimalValue? {
        if (state != SetRecordingState.completed || recordMode != RecordMode.weightReps || repetitionCount == null) {
            return null
        }
        val load = when (side) {
            SetSide.none -> weightValue ?: return null
            SetSide.bilateral -> {
                if (leftValue != null && rightValue != null) {
                    leftValue.adding(rightValue)
                } else if (weightValue != null && leftValue == null && rightValue == null) {
                    weightValue.multipliedBy(DecimalValue.parse("2"))
                } else {
                    return null
                }
            }

            SetSide.left -> leftValue ?: weightValue ?: return null
            SetSide.right -> rightValue ?: weightValue ?: return null
        }
        return load.multipliedBy(repetitionCount)
    }

    fun updating(input: TrainingSetInput, nowUTC: Instant): TrainingSet {
        val parsed = ParsedFields.fromInput(input)
        val nextState = when (state) {
            SetRecordingState.completed -> if (parsed.canComplete()) SetRecordingState.pending else SetRecordingState.draft
            SetRecordingState.pending,
            SetRecordingState.draft,
            -> SetRecordingState.draft
        }
        return copy(
            state = nextState,
            recordMode = parsed.recordMode,
            weightValue = parsed.weightValue,
            repetitionCount = parsed.repetitionCount,
            durationSeconds = parsed.durationSeconds,
            unit = parsed.unit,
            side = parsed.side,
            leftValue = parsed.leftValue,
            rightValue = parsed.rightValue,
            distanceValue = parsed.distanceValue,
            speedValue = parsed.speedValue,
            resistanceValue = parsed.resistanceValue,
            updatedAtUTC = nowUTC,
            completedAtUTC = null,
        )
    }

    fun confirmed(nowUTC: Instant): TrainingSet = confirmed(nowUTC = nowUTC, completedAtUTC = nowUTC)

    fun confirmed(nowUTC: Instant, completedAtUTC: Instant): TrainingSet {
        ParsedFields.fromSet(this).validateForCompletion()
        return copy(state = SetRecordingState.completed, updatedAtUTC = nowUTC, completedAtUTC = completedAtUTC)
    }

    fun copiedAsPending(id: TrainingSetID, orderIndex: UInt, nowUTC: Instant): TrainingSet {
        ParsedFields.fromSet(this).validateForCompletion()
        return copy(
            trainingSetID = id,
            orderIndex = orderIndex,
            state = SetRecordingState.pending,
            createdAtUTC = nowUTC,
            updatedAtUTC = nowUTC,
            completedAtUTC = null,
        )
    }

    fun copiedAsPendingSnapshot(
        id: TrainingSetID,
        sessionExerciseID: SessionExerciseID,
        orderIndex: UInt,
        nowUTC: Instant,
    ): TrainingSet {
        return copy(
            trainingSetID = id,
            sessionExerciseID = sessionExerciseID,
            orderIndex = orderIndex,
            state = SetRecordingState.pending,
            createdAtUTC = nowUTC,
            updatedAtUTC = nowUTC,
            completedAtUTC = null,
        )
    }

    fun undone(nowUTC: Instant): TrainingSet {
        if (state != SetRecordingState.completed) {
            fail(DomainError.invalidState)
        }
        return copy(state = SetRecordingState.pending, updatedAtUTC = nowUTC, completedAtUTC = null)
    }

    fun relocating(sessionExerciseID: SessionExerciseID, orderIndex: UInt): TrainingSet {
        return copy(sessionExerciseID = sessionExerciseID, orderIndex = orderIndex)
    }

    companion object {
        fun makeDraft(
            id: TrainingSetID,
            sessionExerciseID: SessionExerciseID,
            orderIndex: UInt,
            input: TrainingSetInput,
            nowUTC: Instant,
        ): TrainingSet {
            val parsed = ParsedFields.fromInput(input)
            return TrainingSet(
                trainingSetID = id,
                sessionExerciseID = sessionExerciseID,
                orderIndex = orderIndex,
                state = SetRecordingState.draft,
                recordMode = parsed.recordMode,
                weightValue = parsed.weightValue,
                repetitionCount = parsed.repetitionCount,
                durationSeconds = parsed.durationSeconds,
                unit = parsed.unit,
                side = parsed.side,
                leftValue = parsed.leftValue,
                rightValue = parsed.rightValue,
                distanceValue = parsed.distanceValue,
                speedValue = parsed.speedValue,
                resistanceValue = parsed.resistanceValue,
                createdAtUTC = nowUTC,
                updatedAtUTC = nowUTC,
                completedAtUTC = null,
            )
        }
    }
}

private data class ParsedFields(
    val recordMode: RecordMode,
    val weightValue: DecimalValue?,
    val repetitionCount: DecimalValue?,
    val durationSeconds: DecimalValue?,
    val unit: MeasurementUnit,
    val side: SetSide,
    val leftValue: DecimalValue?,
    val rightValue: DecimalValue?,
    val distanceValue: DecimalValue?,
    val speedValue: DecimalValue?,
    val resistanceValue: DecimalValue?,
) {
    fun canComplete(): Boolean = runCatching { validateForCompletion() }.isSuccess

    fun validateForCompletion() {
        when (recordMode) {
            RecordMode.weightReps -> {
                if (weightValue == null) {
                    fail(DomainError.invalidNumber, "weightValue")
                }
                requirePositiveInteger(repetitionCount, "repetitionCount")
                if (durationSeconds != null) {
                    fail(DomainError.invalidMode, "durationSeconds")
                }
                if (unit != MeasurementUnit.kilograms && unit != MeasurementUnit.pounds) {
                    fail(DomainError.invalidUnit, "unit")
                }
                requireNoCardioFields(distanceValue, speedValue, resistanceValue)
            }

            RecordMode.reps -> {
                if (weightValue != null || durationSeconds != null) {
                    fail(DomainError.invalidMode)
                }
                requirePositiveInteger(repetitionCount, "repetitionCount")
                if (unit != MeasurementUnit.repetitions) {
                    fail(DomainError.invalidUnit, "unit")
                }
                requireNoCardioFields(distanceValue, speedValue, resistanceValue)
            }

            RecordMode.duration -> {
                if (weightValue != null || repetitionCount != null) {
                    fail(DomainError.invalidMode)
                }
                if (durationSeconds == null || !durationSeconds.isPositive) {
                    fail(DomainError.invalidNumber, "durationSeconds")
                }
                if (unit != MeasurementUnit.seconds) {
                    fail(DomainError.invalidUnit, "unit")
                }
                requireNoCardioFields(distanceValue, speedValue, resistanceValue)
            }

            RecordMode.cardio -> {
                if (weightValue != null || repetitionCount != null) {
                    fail(DomainError.invalidMode)
                }
                if (durationSeconds == null || !durationSeconds.isPositive) {
                    fail(DomainError.invalidNumber, "durationSeconds")
                }
                if (distanceValue == null || !distanceValue.isPositive) {
                    fail(DomainError.invalidNumber, "distanceValue")
                }
                if (unit != MeasurementUnit.seconds) {
                    fail(DomainError.invalidUnit, "unit")
                }
            }
        }
        validateSide()
    }

    private fun validateSide() {
        when (side) {
            SetSide.none -> {
                if (leftValue != null || rightValue != null) {
                    fail(DomainError.invalidState, "side")
                }
            }

            SetSide.left -> {
                if (leftValue == null || rightValue != null) {
                    fail(DomainError.invalidNumber, "side")
                }
            }

            SetSide.right -> {
                if (rightValue == null || leftValue != null) {
                    fail(DomainError.invalidNumber, "side")
                }
            }

            SetSide.bilateral -> {
                if (leftValue == null || rightValue == null) {
                    fail(DomainError.invalidNumber, "side")
                }
            }
        }
    }

    companion object {
        fun fromInput(input: TrainingSetInput): ParsedFields {
            return ParsedFields(
                recordMode = input.recordMode,
                weightValue = parseDecimal(input.weightValue),
                repetitionCount = parseDecimal(input.repetitionCount),
                durationSeconds = parseDecimal(input.durationSeconds),
                unit = input.unit,
                side = input.side,
                leftValue = parseDecimal(input.leftValue),
                rightValue = parseDecimal(input.rightValue),
                distanceValue = parseDecimal(input.distanceValue),
                speedValue = parseDecimal(input.speedValue),
                resistanceValue = parseDecimal(input.resistanceValue),
            )
        }

        fun fromSet(set: TrainingSet): ParsedFields {
            return ParsedFields(
                recordMode = set.recordMode,
                weightValue = set.weightValue,
                repetitionCount = set.repetitionCount,
                durationSeconds = set.durationSeconds,
                unit = set.unit,
                side = set.side,
                leftValue = set.leftValue,
                rightValue = set.rightValue,
                distanceValue = set.distanceValue,
                speedValue = set.speedValue,
                resistanceValue = set.resistanceValue,
            )
        }

        private fun parseDecimal(raw: String?): DecimalValue? {
            val canonical = optionalText(raw) ?: return null
            return DecimalValue.parse(canonical)
        }

        private fun requirePositiveInteger(value: DecimalValue?, field: String) {
            if (value == null || !value.isPositive || !value.isInteger) {
                fail(DomainError.invalidNumber, field)
            }
        }

        private fun requireNoCardioFields(
            distanceValue: DecimalValue?,
            speedValue: DecimalValue?,
            resistanceValue: DecimalValue?,
        ) {
            if (distanceValue != null || speedValue != null || resistanceValue != null) {
                fail(DomainError.invalidMode)
            }
        }
    }
}
