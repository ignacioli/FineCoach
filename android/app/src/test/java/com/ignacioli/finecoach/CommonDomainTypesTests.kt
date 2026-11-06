package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.AppointmentID
import com.ignacioli.finecoach.core.domain.common.CreditLedgerSourceEventKeyFactory
import com.ignacioli.finecoach.core.domain.common.NormalizedName
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class CommonDomainTypesTests {
    @Test fun validatedTextTrimsUnicodeWhitespaceAroundContent() {
        val text = "\u00A0\u2009\n\u3000Coach Note\u0085\u200A\u00A0"
        assertEquals("Coach Note", ValidatedText.required(text).value)
    }

    @Test fun validatedTextNormalizesEquivalentNfcRepresentations() {
        val composed = ValidatedText.required("Caf\u00E9")
        val decomposed = ValidatedText.required("Cafe\u0301")
        assertEquals(composed, decomposed)
        assertEquals("Caf\u00E9", decomposed.value)
    }

    @Test fun validatedTextAccepts65536AndRejects65537SingleByteUtf8() {
        val max = "a".repeat(65_536)
        assertEquals(65_536, ValidatedText.required(max).value.toByteArray(Charsets.UTF_8).size)
        assertThrows(IllegalArgumentException::class.java) { ValidatedText.required(max + "a") }
    }

    @Test fun validatedTextAccepts65536AndRejects65537MixedUtf8Bytes() {
        val max = "你".repeat(21_845) + "a" // 21_845 * 3 + 1 = 65_536 bytes
        val tooLong = "你".repeat(21_845) + "aa" // 65_537 bytes
        assertEquals(65_536, ValidatedText.required(max).value.toByteArray(Charsets.UTF_8).size)
        assertThrows(IllegalArgumentException::class.java) { ValidatedText.required(tooLong) }
    }

    @Test fun validatedTextOptionalReturnsNullForWhitespaceOnly() {
        assertNull(ValidatedText.optional("\u00A0\u3000\n\u0085"))
        assertNull(ValidatedText.optional(null))
    }

    @Test fun validatedTextDoesNotTrimZeroWidthOrBomOrMongolianSeparator() {
        val raw = "\u200Babc\uFEFF\u180E"
        assertEquals(raw, ValidatedText.required(raw).value)
        assertEquals("\u200B", ValidatedText.required("\u200B").value)
        assertEquals("\uFEFF", ValidatedText.required("\uFEFF").value)
        assertEquals("\u180E", ValidatedText.required("\u180E").value)
    }

    @Test fun validatedTextAllowEmptyAndIsEmptyBehaveLikeIos() {
        val emptyAllowed = ValidatedText.parse(" \n\u00A0\u3000", allowEmpty = true)
        assertEquals("", emptyAllowed.value)
        assertEquals(true, emptyAllowed.isEmpty)
        assertThrows(IllegalArgumentException::class.java) {
            ValidatedText.parse(" \n\u00A0\u3000", allowEmpty = false)
        }
    }

    @Test fun validatedTextOptionalThrowsWhenCanonicalTextExceedsUtf8Limit() {
        val tooLong = "你".repeat(21_846) // 21_846 * 3 = 65_538 bytes
        assertThrows(IllegalArgumentException::class.java) { ValidatedText.optional(tooLong) }
    }

    @Test fun normalizedNameUsesValidatedTextCanonicalization() {
        val normalized = NormalizedName.parse("\u3000Cafe\u0301\u00A0")
        assertEquals("Caf\u00E9", normalized.value)
        assertNull(NormalizedName.optional(" \u00A0\n\u3000"))
    }

    @Test fun normalizedNameDoesNotFoldCaseOrFullHalfWidth() {
        assertNotEquals(NormalizedName.parse("Alice"), NormalizedName.parse("alice"))
        assertNotEquals(NormalizedName.parse("A"), NormalizedName.parse("Ａ"))
    }

    @Test fun appointmentIdCanonicalizesUppercaseAndRejectsInvalid() {
        val upper = "01234567-89AB-CDEF-8123-456789ABCDEF"
        val parsed = AppointmentID.parse(upper)
        assertEquals(upper.lowercase(Locale.ROOT), parsed.value)
        assertThrows(IllegalArgumentException::class.java) { AppointmentID.parse("appointment-1") }
    }

    @Test fun uuidParsingRejectsJava8LenientNonCanonicalForms() {
        val invalids = listOf(
            "1-1-1-1-1",
            "0123456789abcdef0123456789abcdef",
            "{01234567-89ab-cdef-8123-456789abcdef}",
            " 01234567-89ab-cdef-8123-456789abcdef",
            "01234567-89ab-cdef-8123-456789abcdef ",
        )
        invalids.forEach { raw ->
            assertThrows(IllegalArgumentException::class.java) { AppointmentID.parse(raw) }
            assertThrows(IllegalArgumentException::class.java) { StudentID.parse(raw) }
        }
    }

    @Test fun appointmentAbsentSourceEventKeyOverloadsMatchAndUppercaseUuidSegment() {
        val raw = "01234567-89ab-cdef-8123-456789abcdef"
        val typed = CreditLedgerSourceEventKeyFactory.appointmentAbsent(AppointmentID.parse(raw))
        val stringly = CreditLedgerSourceEventKeyFactory.appointmentAbsent(raw)
        assertEquals("appointment-absent:01234567-89AB-CDEF-8123-456789ABCDEF", typed.value)
        assertEquals(typed, stringly)
    }
}
