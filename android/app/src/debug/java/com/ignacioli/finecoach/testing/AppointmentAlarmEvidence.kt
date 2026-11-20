// fictional-data: debug test support parses alarm scheduling metadata, never notification or student content.
package com.ignacioli.finecoach.testing

/** dumpsys does not expose the Intent identifier: bind the action to the requested RTC trigger. */
internal object AppointmentAlarmEvidence {
    fun packageRecords(dump: String, packageName: String): List<String> {
        val lines = dump.lines()
        val header = Regex("^\\s*(?:RTC_WAKEUP|RTC|ELAPSED_WAKEUP|ELAPSED) #\\d+: Alarm\\{")
        return lines.indices.filter { header.containsMatchIn(lines[it]) }.mapNotNull { index ->
            if (!Regex("\\s${Regex.escape(packageName)}(?:\\s|\\})").containsMatchIn(lines[index])) return@mapNotNull null
            val indent = lines[index].takeWhile(Char::isWhitespace).length
            val body = lines.drop(index + 1).takeWhile { line ->
                line.isNotBlank() && line.takeWhile(Char::isWhitespace).length > indent && !header.containsMatchIn(line)
            }
            (listOf(lines[index]) + body).joinToString("\n")
        }
    }
    fun matching(records: List<String>, action: String, fireMillis: Long): List<String> = records.filter { record ->
        Regex("\\borigWhen $fireMillis(?:\\s|\\})").containsMatchIn(record.lineSequence().first()) &&
            Regex("(?m)^\\s*tag=\\*walarm\\*:${Regex.escape(action)}\\s*$").containsMatchIn(record)
    }
    fun isWindowFallback(record: String): Boolean {
        val reason = Regex("\\bexactAllowReason=(\\S+)").find(record)?.groupValues?.get(1)
        val window = Regex("\\bwindow=(\\S+)").find(record)?.groupValues?.get(1)
        // dumpsys uses TimeUtils durations, such as +10m0s0ms; literal 0 denotes an exact alarm.
        val positiveWindow = window == null ||
            (Regex("\\+(?:[0-9]+d)?(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?(?:[0-9]+ms)?").matches(window) &&
                window.any { it in '1'..'9' })
        return reason?.startsWith("permission", ignoreCase = true) != true && positiveWindow
    }
}
