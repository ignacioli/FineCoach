package com.ignacioli.finecoach.core.domain.common

import java.text.Normalizer
import java.util.Locale
import java.util.UUID

private const val MAX_UTF8_BYTES = 64 * 1024
private val CANONICAL_UUID_REGEX = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

private fun canonicalUUID(raw: String): String {
    require(CANONICAL_UUID_REGEX.matches(raw)) { "UUID must be canonical 8-4-4-4-12 format" }
    return UUID.fromString(raw).toString()
}

private fun isUnicodeWhitespace(codePoint: Int): Boolean = when (codePoint) {
    0x0009, // TAB
    0x000A, // LF
    0x000B, // VT
    0x000C, // FF
    0x000D, // CR
    0x0020, // SPACE
    0x0085, // NEL
    0x00A0, // NBSP
    0x1680, // OGHAM SPACE MARK
    0x2028, // LINE SEPARATOR
    0x2029, // PARAGRAPH SEPARATOR
    0x202F, // NARROW NBSP
    0x205F, // MEDIUM MATHEMATICAL SPACE
    0x3000, // IDEOGRAPHIC SPACE
    -> true
    in 0x2000..0x200A -> true // EN QUAD .. HAIR SPACE
    else -> false
}

private fun trimUnicodeWhitespace(raw: String): String {
    var start = 0
    var end = raw.length

    while (start < end) {
        val codePoint = raw.codePointAt(start)
        if (!isUnicodeWhitespace(codePoint)) break
        start += Character.charCount(codePoint)
    }
    while (start < end) {
        val codePoint = raw.codePointBefore(end)
        if (!isUnicodeWhitespace(codePoint)) break
        end -= Character.charCount(codePoint)
    }
    return raw.substring(start, end)
}

private fun utf8ByteCount(value: String): Int = value.toByteArray(Charsets.UTF_8).size

private fun canonicalText(raw: String): String {
    return Normalizer.normalize(trimUnicodeWhitespace(raw), Normalizer.Form.NFC)
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
value class AppointmentID private constructor(val value: String) {
    companion object {
        fun parse(raw: String): AppointmentID = AppointmentID(canonicalUUID(raw))
        fun fromUUID(value: UUID): AppointmentID = AppointmentID(value.toString())
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
            require(utf8ByteCount(canonical) <= MAX_UTF8_BYTES) {
                "StableExerciseID exceeds max UTF-8 length"
            }
            return StableExerciseID(canonical)
        }
    }
}

@JvmInline
value class ValidatedText private constructor(val value: String) {
    companion object {
        const val maximumUTF8Bytes: Int = MAX_UTF8_BYTES

        fun parse(raw: String, allowEmpty: Boolean = false): ValidatedText {
            val canonical = canonicalText(raw)
            require(allowEmpty || canonical.isNotEmpty()) { "ValidatedText must not be empty" }
            require(utf8ByteCount(canonical) <= maximumUTF8Bytes) {
                "ValidatedText exceeds max UTF-8 length"
            }
            return ValidatedText(canonical)
        }

        fun required(raw: String): ValidatedText = parse(raw = raw, allowEmpty = false)

        fun optional(raw: String?): ValidatedText? {
            if (raw == null) return null
            val canonical = canonicalText(raw)
            if (canonical.isEmpty()) return null
            require(utf8ByteCount(canonical) <= maximumUTF8Bytes) {
                "ValidatedText exceeds max UTF-8 length"
            }
            return ValidatedText(canonical)
        }
    }

    val isEmpty: Boolean get() = value.isEmpty()
}

@JvmInline
value class NormalizedName private constructor(val value: String) {
    companion object {
        fun parse(raw: String): NormalizedName = NormalizedName(ValidatedText.required(raw).value)
        fun optional(raw: String?): NormalizedName? = ValidatedText.optional(raw)?.let { NormalizedName(it.value) }
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

    fun appointmentAbsent(appointmentID: AppointmentID): SourceEventKey =
        SourceEventKey.parse("appointment-absent:${keyUUID(appointmentID.value)}")

    fun appointmentAbsent(appointmentID: String): SourceEventKey =
        SourceEventKey.parse("appointment-absent:${keyUUID(canonicalUUID(appointmentID))}")

    fun adhocSession(sessionID: SessionID): SourceEventKey =
        SourceEventKey.parse("adhoc-session:${keyUUID(sessionID.value)}")

    fun manualCorrection(adjustmentID: CreditAdjustmentID): SourceEventKey =
        SourceEventKey.parse("manual-correction:${keyUUID(adjustmentID.value)}")
}
