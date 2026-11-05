package com.ignacioli.finecoach.storage.value

import androidx.room.TypeConverter
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID

// Private storage representations, not FCBK/FCPA encoders. No converter is
// registered on the database: the sole entity has two non-null String columns.
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

    private companion object {
        const val MAX_DECIMAL_BYTES = 65_536
        val UUID_PATTERN = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
        val DECIMAL_PATTERN = Regex("-?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)")
    }
}
