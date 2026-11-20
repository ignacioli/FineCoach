// fictional-data: S2 shared scenarios use fixed DST dates and synthetic Room records.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.StudentID
import java.io.File
import java.security.MessageDigest
import java.time.*
import java.util.UUID
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class S2VectorRunnerTests {
    @Test fun count() = run("s2-recurrence-count")
    @Test fun endDate() = run("s2-recurrence-end-date")
    @Test fun limit() = run("s2-recurrence-limit")
    @Test fun thisOnly() = run("s2-this-only")
    @Test fun thisAndFuture() = run("s2-this-and-future")
    @Test fun overdue() = run("s2-overdue-persists")
    @Test fun abandon() = run("s1-empty-session-abandon-restores-appointment")
    @Test fun absent() = run("s2-absent-credit-idempotent")
    @Test fun reminders() = run("s2-reminder-tiers")
    @Test fun notification() = run("s2-notification-content")
    @Suppress("UNCHECKED_CAST")
    private fun run(id: String) = s2Run {
        val manifestFile = File(VectorFiles.root, "s2-manifest.json")
        val manifest = VectorJSON(manifestFile.readText()).parse() as Map<String, Any?>
        val entries = manifest["vectors"] as List<Map<String, Any?>>
        check(manifest["count"] == 10L && entries.size == 10 && entries.map { it["id"] }.toSet().size == 10)
        val entry = entries.single { it["id"] == id }
        val file = File(VectorFiles.root, entry["path"] as String)
        check(file.canonicalPath.startsWith(VectorFiles.root.canonicalPath + File.separator))
        check(digest(file) == entry["sha256"])
        val root = VectorJSON(file.readText()).parse() as Map<String, Any?>
        check(root["id"] == id)
        val given = root["given"] as Map<String, Any?>
        val now = Instant.parse((given["clock"] as Map<*, *>)["now"] as String)
        val zone = ZoneId.of(given["timeZone"] as String)
        val state = given["state"] as Map<String, Any?>
        val op = entry["androidAdapter"] as String
        check(entry["iosAdapter"] == op)
        fun date(value: Any?): LocalDate { val d = value as Map<String, Long>; return LocalDate.of(d.getValue("year").toInt(), d.getValue("month").toInt(), d.getValue("day").toInt()) }
        val a = Appointment(UUID(0, 1000), StudentID.fromUUID(UUID(0, 1001)), UUID(0, 1002), LocalDate.parse("2026-03-08"), LocalTime.of(1, 0), createdAtUTC = now, updatedAtUTC = now)
        val actual: Any = when (op) {
            "appointment.recurrence" -> {
                val first = date(state["first"])
                val termination = state["count"]?.let { RecurrenceTermination.RepeatCount((it as Long).toInt()) } ?: RecurrenceTermination.EndDate(date(state["end"]))
                RecurrenceSeries.validateBound(first, termination)
                mapOf("dates" to RecurrenceSeries.materializedDates(RecurrenceInterval.entries.single { it.days == state["interval"] }, first, termination).map { it.toString() })
            }
            "appointment.limit" -> {
                val first = a.date
                val terms = (state["counts"] as List<Long>).map { RecurrenceTermination.RepeatCount(it.toInt()) } +
                    (state["spans"] as List<Long>).map { RecurrenceTermination.EndDate(first.plusDays(it)) }
                mapOf("valid" to terms.map { try { RecurrenceSeries.validateBound(first, it); true } catch (_: IllegalArgumentException) { false } })
            }
            "appointment.detached" -> {
                val updated = a.reschedulingDetached(AppointmentEdit(startTime = LocalTime.of(11, 30), reminderEnabled = false), now)
                mapOf("detached" to updated.isDetachedException, "sameSeries" to (updated.seriesID == a.seriesID), "time" to updated.startTime.toString(), "lead" to updated.reminderLeadMinutes!!.minutes.toLong(), "enabled" to updated.reminderEnabled)
            }
            "appointment.future" -> s2FutureScenario()
            "appointment.overdue" -> mapOf("beforeEnd" to a.isOverdue(now.minusNanos(1), zone), "atEnd" to a.isOverdue(now, zone), "nextDay" to a.isOverdue(now.plusSeconds(86400), zone), "status" to a.status.name)
            "appointment.abandon" -> {
                val row = row(student()); cases.createSingle(row).requireSuccess()
                val session = cases.startTraining(row.id).requireStarted()
                graph.finisher.abandonEmpty(session.sessionID, session.revision, true).requireSuccess()
                val restored = cases.find(row.id).requireSuccess()!!
                mapOf("status" to restored.status.name, "linkedSession" to restored.linkedSessionID)
            }
            "appointment.absent" -> s2AbsentScenario()
            "appointment.reminders" -> mapOf("minutes" to ReminderLeadMinutes.entries.map { it.minutes.toLong() }, "default" to a.reminderLeadMinutes!!.minutes.toLong(), "disabledLead" to a.copy(reminderEnabled = false, reminderLeadMinutes = null).reminderLeadMinutes)
            "appointment.notification" -> mapOf("title" to AppointmentNotificationContentBuilder.title(), "body" to AppointmentNotificationContentBuilder.body(a.startInstant(zone), zone))
            else -> error("Unmapped S2 operation")
        }
        SharedVectorRunner(false, setOf(op)) { dispatched, resolved -> check(dispatched == op && resolved == state); actual }.run(file.readBytes(), file.name)
        VectorFiles.report(file)
        println("S2-MANIFEST sha256=${digest(manifestFile)} count=10")
    }
    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
}
