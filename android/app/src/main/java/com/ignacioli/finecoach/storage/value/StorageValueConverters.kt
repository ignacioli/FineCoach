package com.ignacioli.finecoach.storage.value

import androidx.room.TypeConverter
import com.ignacioli.finecoach.core.domain.common.*
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID

// Private storage representations, not FCBK/FCPA encoders.
class StorageValueConverters {
    @TypeConverter
    fun uuidToString(value: UUID): String = value.toString()

    @TypeConverter
    fun stringToUuid(value: String): UUID {
        require(UUID_PATTERN.matches(value)) { "Invalid UUID" }
        return UUID.fromString(value)
    }

    @TypeConverter
    fun decimalToString(value: BigDecimal): String {
        // Prevent huge exponent expansion before allocating the plain string.
        val normalized = value.stripTrailingZeros()
        val length = if (normalized.signum() == 0) 1L else {
            val precision = normalized.precision().toLong()
            val scale = normalized.scale().toLong()
            (if (scale <= 0) precision - scale else maxOf(precision + 1, scale + 2)) +
                if (normalized.signum() < 0) 1 else 0
        }
        require(length <= MAX_DECIMAL_BYTES) { "Decimal exceeds storage limit" }
        return if (normalized.signum() == 0) "0" else normalized.toPlainString()
    }

    @TypeConverter
    fun stringToDecimal(value: String): BigDecimal {
        val trimmed = value.trim()
        require(DECIMAL_PATTERN.matches(trimmed)) { "Invalid decimal" }
        return BigDecimal(decimalToString(BigDecimal(trimmed)))
    }

    // Preserve all nanoseconds privately; future codecs apply their own format
    // rules. In particular, FCBK's whole-second writer must not truncate storage.
    @TypeConverter
    fun instantToString(value: Instant): String = value.toString()

    @TypeConverter
    fun stringToInstant(value: String): Instant {
        val parsed = Instant.parse(value)
        require(value == parsed.toString()) { "Non-canonical UTC instant" }
        return parsed
    }

    @TypeConverter
    fun localDateToString(value: LocalDate): String {
        require(value.year in 1..9999) { "Calendar year outside canonical range" }
        return value.toString()
    }

    @TypeConverter
    fun stringToLocalDate(value: String): LocalDate {
        val parsed = LocalDate.parse(value)
        require(value == localDateToString(parsed)) { "Non-canonical calendar date" }
        return parsed
    }

    @TypeConverter
    fun localTimeToString(value: LocalTime): String {
        require(value.second == 0 && value.nano == 0) { "Calendar time has minute precision" }
        return value.toString()
    }

    @TypeConverter
    fun stringToLocalTime(value: String): LocalTime {
        val parsed = LocalTime.parse(value)
        require(value == localTimeToString(parsed)) { "Non-canonical calendar time" }
        return parsed
    }

    @TypeConverter
    fun studentSexToString(value: StudentSex): String = value.wireValue

    @TypeConverter
    fun stringToStudentSex(value: String): StudentSex = StudentSex.parse(value)

    @TypeConverter
    fun studentLifecycleToString(value: StudentLifecycle): String = value.wireValue

    @TypeConverter
    fun stringToStudentLifecycle(value: String): StudentLifecycle = StudentLifecycle.parse(value)

    @TypeConverter
    fun coursePackageStatusToString(value: CoursePackageStatus): String = value.wireValue

    @TypeConverter
    fun stringToCoursePackageStatus(value: String): CoursePackageStatus = CoursePackageStatus.parse(value)

    @TypeConverter
    fun creditDirectionToString(value: CreditDirection): String = value.wireValue

    @TypeConverter
    fun stringToCreditDirection(value: String): CreditDirection = CreditDirection.parse(value)

    @TypeConverter
    fun creditReasonKindToString(value: CreditReasonKind): String = value.wireValue

    @TypeConverter
    fun stringToCreditReasonKind(value: String): CreditReasonKind = CreditReasonKind.parse(value)

    @TypeConverter
    fun sessionStateToString(value: SessionState): String = value.wireValue

    @TypeConverter
    fun stringToSessionState(value: String): SessionState = SessionState.parse(value)

    @TypeConverter
    fun exerciseKindToString(value: ExerciseKind): String = value.wireValue

    @TypeConverter
    fun stringToExerciseKind(value: String): ExerciseKind = ExerciseKind.parse(value)

    @TypeConverter
    fun exerciseLifecycleToString(value: ExerciseLifecycle): String = value.wireValue

    @TypeConverter
    fun stringToExerciseLifecycle(value: String): ExerciseLifecycle = ExerciseLifecycle.parse(value)

    @TypeConverter
    fun exerciseSourceKindToString(value: ExerciseSourceKind): String = value.wireValue

    @TypeConverter
    fun stringToExerciseSourceKind(value: String): ExerciseSourceKind = ExerciseSourceKind.parse(value)

    @TypeConverter
    fun exerciseClaimScopeToString(value: ExerciseClaimScope): String = value.wireValue

    @TypeConverter
    fun stringToExerciseClaimScope(value: String): ExerciseClaimScope = ExerciseClaimScope.parse(value)

    @TypeConverter
    fun recordModeToString(value: RecordMode): String = value.wireValue

    @TypeConverter
    fun stringToRecordMode(value: String): RecordMode = RecordMode.parse(value)

    @TypeConverter
    fun measurementUnitToString(value: MeasurementUnit): String = value.wireValue

    @TypeConverter
    fun stringToMeasurementUnit(value: String): MeasurementUnit = MeasurementUnit.parse(value)

    @TypeConverter
    fun setSideToString(value: SetSide): String = value.wireValue

    @TypeConverter
    fun stringToSetSide(value: String): SetSide = SetSide.parse(value)

    @TypeConverter
    fun setRecordingStateToString(value: SetRecordingState): String = value.wireValue

    @TypeConverter
    fun stringToSetRecordingState(value: String): SetRecordingState = SetRecordingState.parse(value)

    @TypeConverter
    fun sessionSectionOwnerKindToString(value: SessionSectionOwnerKind): String = value.wireValue

    @TypeConverter
    fun stringToSessionSectionOwnerKind(value: String): SessionSectionOwnerKind = SessionSectionOwnerKind.parse(value)

    @TypeConverter
    fun bodyPartToString(value: BodyPart): String = value.wireValue

    @TypeConverter
    fun stringToBodyPart(value: String): BodyPart = BodyPart.parse(value)

    @TypeConverter
    fun booleanToInt(value: Boolean): Int = if (value) 1 else 0

    @TypeConverter
    fun intToBoolean(value: Int): Boolean {
        require(value == 0 || value == 1) { "Invalid stored Boolean" }
        return value == 1
    }

    private companion object {
        const val MAX_DECIMAL_BYTES = 65_536
        val UUID_PATTERN = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
        val DECIMAL_PATTERN = Regex("-?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)")
    }
}
