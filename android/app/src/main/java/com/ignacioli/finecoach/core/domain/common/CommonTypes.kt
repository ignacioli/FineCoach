package com.ignacioli.finecoach.core.domain.common

import java.text.Normalizer
import java.util.Locale
import java.util.UUID

private const val MAX_UTF8_BYTES = 64 * 1024

private fun canonicalUUID(raw: String): String = UUID.fromString(raw).toString()

private fun canonicalText(raw: String): String {
    return Normalizer.normalize(raw.trim(), Normalizer.Form.NFC)
}

@JvmInline
value class StudentID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): StudentID = StudentID(canonicalUUID(raw))
        fun fromUUID(value: UUID): StudentID = StudentID(value.toString())
    }
}

@JvmInline
value class CoursePackageID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): CoursePackageID = CoursePackageID(canonicalUUID(raw))
        fun fromUUID(value: UUID): CoursePackageID = CoursePackageID(value.toString())
    }
}

@JvmInline
value class CreditAdjustmentID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): CreditAdjustmentID = CreditAdjustmentID(canonicalUUID(raw))
        fun fromUUID(value: UUID): CreditAdjustmentID = CreditAdjustmentID(value.toString())
    }
}

@JvmInline
value class SessionID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): SessionID = SessionID(canonicalUUID(raw))
        fun fromUUID(value: UUID): SessionID = SessionID(value.toString())
    }
}

@JvmInline
value class TemplateID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): TemplateID = TemplateID(canonicalUUID(raw))
        fun fromUUID(value: UUID): TemplateID = TemplateID(value.toString())
    }
}

@JvmInline
value class SectionID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): SectionID = SectionID(canonicalUUID(raw))
        fun fromUUID(value: UUID): SectionID = SectionID(value.toString())
    }
}

@JvmInline
value class SessionExerciseID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): SessionExerciseID = SessionExerciseID(canonicalUUID(raw))
        fun fromUUID(value: UUID): SessionExerciseID = SessionExerciseID(value.toString())
    }
}

@JvmInline
value class TemplateExerciseID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): TemplateExerciseID = TemplateExerciseID(canonicalUUID(raw))
        fun fromUUID(value: UUID): TemplateExerciseID = TemplateExerciseID(value.toString())
    }
}

@JvmInline
value class TrainingSetID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): TrainingSetID = TrainingSetID(canonicalUUID(raw))
        fun fromUUID(value: UUID): TrainingSetID = TrainingSetID(value.toString())
    }
}

@JvmInline
value class StableExerciseID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): StableExerciseID {
            val canonical = canonicalText(raw)
            require(canonical.isNotBlank()) { "StableExerciseID must be non-blank" }
            require(canonical.toByteArray(Charsets.UTF_8).size <= MAX_UTF8_BYTES) {
                "StableExerciseID exceeds max UTF-8 length"
            }
            return StableExerciseID(canonical)
        }
    }
}

@JvmInline
value class Revision(val value: ULong) {
    init { require(value > 0uL) { "Revision must be positive" } }

    companion object {
        fun parse(raw: String): Revision = Revision(raw.toULong())
    }
}

@JvmInline
value class SourceEventKey private constructor(val value: String) {
    companion object {
        fun parse(raw: String): SourceEventKey {
            val canonical = raw.trim()
            require(canonical.isNotBlank()) { "SourceEventKey must be non-blank" }
            return SourceEventKey(canonical)
        }
    }
}

enum class StudentSex(val wireValue: String) {
    male("male"),
    female("female"),
    other("other"),
    undisclosed("undisclosed");

    companion object {
        fun parse(raw: String): StudentSex =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown StudentSex: $raw")
    }
}

enum class StudentLifecycle(val wireValue: String) {
    active("active"),
    archived("archived");

    companion object {
        fun parse(raw: String): StudentLifecycle =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown StudentLifecycle: $raw")
    }
}

enum class CoursePackageStatus(val wireValue: String) {
    active("active"),
    ended("ended");

    companion object {
        fun parse(raw: String): CoursePackageStatus =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown CoursePackageStatus: $raw")
    }
}

enum class CreditDirection(val wireValue: String) {
    debit("debit"),
    credit("credit");

    companion object {
        fun parse(raw: String): CreditDirection =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown CreditDirection: $raw")
    }
}

enum class CreditReasonKind(val wireValue: String) {
    sessionComplete("sessionComplete"),
    appointmentAbsent("appointmentAbsent"),
    adhocSession("adhocSession"),
    manualCorrection("manualCorrection"),
    sessionReopen("sessionReopen");

    companion object {
        fun parse(raw: String): CreditReasonKind =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown CreditReasonKind: $raw")
    }
}

enum class SessionState(val wireValue: String) {
    inProgress("inProgress"),
    completed("completed"),
    abandonedEmpty("abandonedEmpty");

    companion object {
        fun parse(raw: String): SessionState =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown SessionState: $raw")
    }
}

enum class ExerciseKind(val wireValue: String) {
    builtIn("builtIn"),
    custom("custom");

    companion object {
        fun parse(raw: String): ExerciseKind =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown ExerciseKind: $raw")
    }
}

enum class ExerciseLifecycle(val wireValue: String) {
    active("active"),
    archived("archived");

    companion object {
        fun parse(raw: String): ExerciseLifecycle =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown ExerciseLifecycle: $raw")
    }
}

enum class ExerciseSourceKind(val wireValue: String) {
    builtIn("builtIn"),
    custom("custom"),
    sessionOnly("sessionOnly");

    companion object {
        fun parse(raw: String): ExerciseSourceKind =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown ExerciseSourceKind: $raw")
    }
}

enum class ExerciseClaimScope(val wireValue: String) {
    activeCatalog("activeCatalog"),
    currentSession("currentSession");

    companion object {
        fun parse(raw: String): ExerciseClaimScope =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown ExerciseClaimScope: $raw")
    }
}

enum class RecordMode(val wireValue: String) {
    weightReps("weightReps"),
    reps("reps"),
    duration("duration"),
    cardio("cardio");

    companion object {
        fun parse(raw: String): RecordMode =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown RecordMode: $raw")
    }
}

enum class MeasurementUnit(val wireValue: String) {
    kilograms("kilograms"),
    pounds("pounds"),
    repetitions("repetitions"),
    seconds("seconds"),
    none("none");

    companion object {
        fun parse(raw: String): MeasurementUnit =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown MeasurementUnit: $raw")
    }
}

enum class SetSide(val wireValue: String) {
    none("none"),
    left("left"),
    right("right"),
    bilateral("bilateral");

    companion object {
        fun parse(raw: String): SetSide =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown SetSide: $raw")
    }
}

enum class SetRecordingState(val wireValue: String) {
    draft("draft"),
    pending("pending"),
    completed("completed");

    companion object {
        fun parse(raw: String): SetRecordingState =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown SetRecordingState: $raw")
    }
}

enum class SessionSectionOwnerKind(val wireValue: String) {
    session("session"),
    template("template");

    companion object {
        fun parse(raw: String): SessionSectionOwnerKind =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown SessionSectionOwnerKind: $raw")
    }
}

enum class BodyPart(val wireValue: String) {
    chest("chest"),
    shoulders("shoulders"),
    back("back"),
    thighs("thighs"),
    calves("calves"),
    arms("arms"),
    glutes("glutes"),
    core("core");

    companion object {
        fun parse(raw: String): BodyPart =
            entries.firstOrNull { it.wireValue == raw } ?: throw IllegalArgumentException("Unknown BodyPart: $raw")
    }
}

object CreditLedgerSourceEventKeyFactory {
    private fun keyUUID(raw: String): String = raw.uppercase(Locale.ROOT)

    fun sessionComplete(sessionID: SessionID): SourceEventKey =
        SourceEventKey.parse("session-complete:${keyUUID(sessionID.value)}")

    fun sessionReopen(sessionID: SessionID): SourceEventKey =
        SourceEventKey.parse("session-reopen:${keyUUID(sessionID.value)}")

    fun appointmentAbsent(appointmentID: String): SourceEventKey =
        SourceEventKey.parse("appointment-absent:${keyUUID(canonicalUUID(appointmentID))}")

    fun adhocSession(sessionID: SessionID): SourceEventKey =
        SourceEventKey.parse("adhoc-session:${keyUUID(sessionID.value)}")

    fun manualCorrection(adjustmentID: CreditAdjustmentID): SourceEventKey =
        SourceEventKey.parse("manual-correction:${keyUUID(adjustmentID.value)}")
}
