package com.ignacioli.finecoach

import com.ignacioli.finecoach.storage.value.StorageValueConverters
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeParseException
import java.util.Locale
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class StorageValueTests {
    private val converter = StorageValueConverters()

    @Test fun uuidRoundTripWritesLowercaseCanonical() {
        val text = "01234567-89ab-cdef-0123-456789abcdef"
        val uuid = UUID.fromString(text)
        assertEquals(text, converter.uuidToString(uuid))
        assertEquals(uuid, converter.stringToUuid(text.uppercase(Locale.ROOT)))
        assertEquals(uuid, converter.stringToUuid(converter.uuidToString(uuid)))
    }

    @Test fun malformedUuidRejectsShortGroupsAndWhitespace() {
        listOf("1-1-1-1-1", "0123456789abcdef0123456789abcdef", "not-a-uuid", " 01234567-89ab-cdef-0123-456789abcdef").forEach {
            assertThrows(IllegalArgumentException::class.java) { converter.stringToUuid(it) }
        }
    }

    @Test fun decimalRoundTripPreservesNumericPrecisionAndCanonicalizesScale() {
        val samples = mapOf(
            "123.45000" to "123.45", "-123.4500" to "-123.45", "-0.000" to "0",
            "123456789012345678901234567890.12345678" to "123456789012345678901234567890.12345678",
            "0.00000000000000000000000000000000000001" to "0.00000000000000000000000000000000000001",
        )
        samples.forEach { (input, expected) ->
            val value = BigDecimal(input)
            assertEquals(expected, converter.decimalToString(value))
            assertEquals(0, value.compareTo(converter.stringToDecimal(converter.decimalToString(value))))
        }
    }

    @Test fun decimalAcceptsContractLexicalFormsAndLimits() {
        mapOf(" 01.00\n" to "1", ".5" to "0.5", "1." to "1", "-.5" to "-0.5").forEach { (input, expected) ->
            assertEquals(expected, converter.decimalToString(converter.stringToDecimal(input)))
        }
        val boundary = "1".repeat(65_536)
        assertEquals(boundary, converter.decimalToString(converter.stringToDecimal(boundary)))
        assertThrows(IllegalArgumentException::class.java) { converter.stringToDecimal(boundary + "1") }
        assertThrows(IllegalArgumentException::class.java) { converter.decimalToString(BigDecimal("1E+65536")) }
    }

    @Test fun decimalRejectsFloatingSyntaxAndInvalidInputs() {
        listOf("", "-", ".", "-.", "+1", "1e2", "1E2", "1,2", "1 2", "NaN", "Infinity", "１", "1.2.3").forEach {
            assertThrows(IllegalArgumentException::class.java) { converter.stringToDecimal(it) }
        }
    }

    @Test fun instantRoundTripRetainsWholeMillisecondsAndNanoseconds() {
        listOf("2026-11-04T12:34:56Z", "2026-11-04T12:34:56.123Z", "2026-11-04T12:34:56.123456789Z",
            "1969-12-31T23:59:59.999999999Z").forEach {
            val instant = Instant.parse(it)
            assertEquals(it, converter.instantToString(instant))
            assertEquals(instant, converter.stringToInstant(converter.instantToString(instant)))
        }
    }

    @Test fun instantRejectsInvalidAndNonCanonicalStorageStrings() {
        listOf("2026-11-04T12:34:56+00:00", "2026-11-04T12:34:56.000Z").forEach {
            assertThrows(IllegalArgumentException::class.java) { converter.stringToInstant(it) }
        }
        listOf("not-an-instant", "2026-11-04", "2026-11-04T12:34:56").forEach {
            assertThrows(DateTimeParseException::class.java) { converter.stringToInstant(it) }
        }
    }

    @Test fun calendarDateAndMinuteTimeRoundTripWithoutTimezone() {
        listOf("0001-01-01", "2024-02-29", "9999-12-31").forEach {
            val date = LocalDate.parse(it)
            assertEquals(it, converter.localDateToString(date))
            assertEquals(date, converter.stringToLocalDate(converter.localDateToString(date)))
        }
        listOf("00:00", "09:05", "23:59").forEach {
            val time = LocalTime.parse(it)
            assertEquals(it, converter.localTimeToString(time))
            assertEquals(time, converter.stringToLocalTime(converter.localTimeToString(time)))
        }
    }

    @Test fun calendarDateRejectsInvalidAndNonCanonicalValues() {
        listOf("2026-02-29", "2026-13-01", "2026-1-01", "2026-01-01Z").forEach {
            assertThrows(DateTimeParseException::class.java) { converter.stringToLocalDate(it) }
        }
        assertThrows(IllegalArgumentException::class.java) { converter.stringToLocalDate("0000-01-01") }
        assertThrows(IllegalArgumentException::class.java) { converter.localDateToString(LocalDate.of(10000, 1, 1)) }
    }

    @Test fun calendarTimeRejectsInvalidSecondsAndFractions() {
        listOf("24:00", "12:60", "9:05", "09:05Z").forEach {
            assertThrows(DateTimeParseException::class.java) { converter.stringToLocalTime(it) }
        }
        listOf("09:05:00", "09:05:01", "09:05:00.001").forEach {
            assertThrows(IllegalArgumentException::class.java) { converter.stringToLocalTime(it) }
        }
        assertThrows(IllegalArgumentException::class.java) { converter.localTimeToString(LocalTime.of(9, 5, 1)) }
    }
}
