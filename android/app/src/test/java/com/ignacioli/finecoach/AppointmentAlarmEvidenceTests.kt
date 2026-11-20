// fictional-data: verbatim host dumpsys records from fictional test installs; negative variants are invented.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.testing.AppointmentAlarmEvidence
import java.io.File
import org.junit.Assert.*
import org.junit.Test

class AppointmentAlarmEvidenceTests {
    private val pkg = "com.ignacioli.finecoach"
    private val action = "$pkg.APPOINTMENT_REMINDER"
    private val fire = 1795188742000L
    @Test fun touchedDevicePatternsRequireEscapedLiteralBracesForIcu() {
        // These patterns use no brace quantifiers. ICU rejects bare brace literals that JDK accepts.
        fun hasBareBrace(pattern: String): Boolean {
            var escaped = false
            for (char in pattern) {
                if (escaped) escaped = false
                else if (char == '\\') escaped = true
                else if (char == '{' || char == '}') return true
            }
            return false
        }
        assertTrue(hasBareBrace("\\s\\Qcom.ignacioli.finecoach\\E(?:\\s|})"))
        assertTrue(hasBareBrace("\\borigWhen $fire(?:\\s|})"))
        assertFalse(hasBareBrace("\\borigWhen $fire(?:\\s|\\})"))
        val root = File(MergedPrivacyInputs.property("sourceRoot"))
        val files = mapOf(
            "debug/java/com/ignacioli/finecoach/testing/AppointmentAlarmEvidence.kt" to 7,
            "debug/java/com/ignacioli/finecoach/seed/S1DebugSeed.kt" to 2,
            "androidTest/java/com/ignacioli/finecoach/AppointmentReminderDeviceTests.kt" to 0,
        )
        val literals = Regex("""Regex\("((?:\\.|[^"\\])*)"\)""")
        for ((path, count) in files) {
            val patterns = literals.findAll(File(root, path).readText()).map { match ->
                match.groupValues[1].replace("\\\\", "\\")
                    .replace("\${Regex.escape(packageName)}", Regex.escape(pkg))
                    .replace("\${Regex.escape(action)}", Regex.escape(action))
                    .replace("\$fireMillis", fire.toString())
            }.toList()
            assertEquals("Guard must inspect every touched pattern: $path", count, patterns.size)
            for (pattern in patterns) {
                assertFalse("Unescaped brace in device regex: $path", hasBareBrace(pattern))
                Regex(pattern)
            }
        }
    }
    private val exactRecord = """
        RTC_WAKEUP #45: Alarm{dbb6662 type 0 origWhen 1795188742000 whenElapsed 86467596 com.ignacioli.finecoach}
          tag=*walarm*:com.ignacioli.finecoach.APPOINTMENT_REMINDER
          type=RTC_WAKEUP origWhen=2026-11-20 23:32:22.000 window=0 exactAllowReason=permission repeatInterval=0 count=0 flags=0x5
          operation=PendingIntent{3c8a3f3: PendingIntentRecord{f5408b0 com.ignacioli.finecoach broadcastIntent}}
    """.trimIndent()
    private val windowRecord = """
        RTC_WAKEUP #8: Alarm{c06cf41 type 0 origWhen 1795104739000 whenElapsed 102599 com.ignacioli.finecoach}
          tag=*walarm*:com.ignacioli.finecoach.APPOINTMENT_REMINDER
          type=RTC_WAKEUP origWhen=2026-11-20 00:12:19.000 window=+10m0s0ms repeatInterval=0 count=0 flags=0x0
    """.trimIndent()
    private fun record(epoch: Long = fire, owner: String = pkg, tag: String = action) = exactRecord
        .replace("origWhen $fire ", "origWhen $epoch ")
        .replace(" $pkg}", " $owner}")
        .replace("tag=*walarm*:$action", "tag=*walarm*:$tag")
    @Test fun exactHostRecordMatchesRequestedEpochWithoutIdentifierOrToken() {
        val rows = AppointmentAlarmEvidence.packageRecords(exactRecord, pkg)
        assertEquals(1, AppointmentAlarmEvidence.matching(rows, action, fire).size)
        assertFalse(AppointmentAlarmEvidence.isWindowFallback(rows.single()))
    }
    @Test fun windowHostRecordMatchesAndProvesFallback() {
        val rows = AppointmentAlarmEvidence.packageRecords(windowRecord, pkg)
        assertEquals(1, AppointmentAlarmEvidence.matching(rows, action, 1795104739000L).size)
        assertTrue(AppointmentAlarmEvidence.isWindowFallback(rows.single()))
        assertFalse(AppointmentAlarmEvidence.isWindowFallback(windowRecord + " exactAllowReason=permission"))
        assertFalse(AppointmentAlarmEvidence.isWindowFallback(windowRecord.replace("window=+10m0s0ms", "window=0")))
    }
    @Test fun durationWindowsRequireValidUnitsAndStrictlyPositiveValue() {
        for (duration in listOf("+1ms", "+1s0ms", "+1h0m0s0ms", "+1d0h0m0s0ms")) {
            assertTrue(AppointmentAlarmEvidence.isWindowFallback(windowRecord.replace("+10m0s0ms", duration)))
        }
        for (duration in listOf("0", "+0ms", "+0m0s0ms", "-10m0s0ms", "+", "+10mgarbage", "+1s1m")) {
            assertFalse(AppointmentAlarmEvidence.isWindowFallback(windowRecord.replace("+10m0s0ms", duration)))
        }
    }
    @Test fun otherEpochActionAndPackageNeverStandInForRequestedAppointment() {
        val dump = listOf(record(fire + 1), record(tag = "fictional.OTHER"), record(owner = "fictional.other")).joinToString("\n")
        val rows = AppointmentAlarmEvidence.packageRecords(dump, pkg)
        assertEquals(2, rows.size)
        assertTrue(AppointmentAlarmEvidence.matching(rows, action, fire).isEmpty())
    }
    @Test fun adjacentRecordsKeepTriggerAndActionInSameRecord() {
        val rows = AppointmentAlarmEvidence.packageRecords(record(tag = "fictional.OTHER") + "\n" + record(fire + 1), pkg)
        assertEquals(2, rows.size)
        assertTrue(AppointmentAlarmEvidence.matching(rows, action, fire).isEmpty())
        assertEquals(1, AppointmentAlarmEvidence.matching(rows, action, fire + 1).size)
    }
}
