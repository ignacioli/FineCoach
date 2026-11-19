package com.ignacioli.finecoach.features.appointments

import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import java.time.*
import java.time.temporal.ChronoUnit
import java.util.UUID

/** UI draft only; success is published only after the atomic application operation succeeds. */
class AppointmentEditorState(private val appointments: AppointmentUseCases, private val studentUseCases: StudentUseCases,
    private val clock: AppClock, val zone: ZoneId, initialDate: LocalDate, val appointmentID: UUID? = null) {
    enum class Scope { single, future }
    var students by mutableStateOf<List<StudentRecord>>(emptyList()); private set
    var studentID by mutableStateOf<StudentID?>(null)
    var date by mutableStateOf(initialDate)
    var time by mutableStateOf(LocalTime.of(9, 0))
    var duration by mutableStateOf(60)
    var focus by mutableStateOf<Set<BodyPart>>(emptySet())
    var interval by mutableStateOf<RecurrenceInterval?>(null)
    var endByCount by mutableStateOf(false)
    var endDate by mutableStateOf(initialDate.plusDays(28))
    var count by mutableStateOf(8)
    var reminderEnabled by mutableStateOf(true)
    var lead by mutableStateOf(ReminderLeadMinutes.sixty)
    var loaded by mutableStateOf(false); private set
    var busy by mutableStateOf(false); private set
    var saved by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var original by mutableStateOf<Appointment?>(null); private set
    var series by mutableStateOf<RecurrenceSeries?>(null); private set
    var affectedCount by mutableStateOf(0); private set
    var scopeRequested by mutableStateOf(false); private set
    var conflict by mutableStateOf<String?>(null); private set
    private var pendingScope: Scope? = null
    val editing get() = appointmentID != null
    val termination get() = if (endByCount) RecurrenceTermination.RepeatCount(count) else RecurrenceTermination.EndDate(endDate)
    val boundError: String? get() = when {
        endByCount && count < 2 -> "不是有效数字。"
        !endByCount && endDate < date -> "当前状态不允许此操作。"
        endByCount && count > RecurrenceSeries.MAXIMUM_INSTANCES -> "周期安排超过可物化上限（最多 366 次）。"
        !endByCount && ChronoUnit.DAYS.between(date,endDate) > RecurrenceSeries.MAXIMUM_INSTANCES -> "周期安排超过可物化上限（最多 366 次）。"
        else -> null
    }
    val validBound get() = boundError == null
    val preview: String? get() {
        val repeat = interval ?: return null
        boundError?.let { return it }
        val dates = RecurrenceSeries.materializedDates(repeat, date, termination)
        if (dates.isEmpty()) return null
        fun LocalDate.shortDay() = "${monthValue}月${dayOfMonth}日"
        return "将创建 ${dates.size} 节课（${dates.first().shortDay()} – ${dates.last().shortDay()}，每 ${repeat.days} 天一次）"
    }
    suspend fun load() {
        when (val result = studentUseCases.list()) {
            is ApplicationResult.Failure -> { error = "加载学员失败，再试一次。"; return }
            is ApplicationResult.Success -> students = result.value.filter { it.lifecycle == StudentLifecycle.active }
        }
        if (!editing) { if (studentID == null) studentID = students.firstOrNull()?.studentID }
        else {
            when (val result = appointments.find(checkNotNull(appointmentID))) {
                is ApplicationResult.Failure -> { error = "加载课程安排失败，再试一次。"; return }
                is ApplicationResult.Success -> {
                    val row = result.value ?: run { error = "课程安排不存在。"; return }
                    if (row.status != AppointmentStatus.scheduled) { error = "该课程安排不能编辑。"; return }
                    original = row; studentID = row.studentID; date = row.date; time = row.startTime
                    duration = row.durationMinutes; focus = row.trainingFocus; reminderEnabled = row.reminderEnabled
                    lead = row.reminderLeadMinutes ?: ReminderLeadMinutes.sixty
                    if (row.seriesID != null && !row.isDetachedException) when (val found = appointments.series(row.seriesID)) {
                        is ApplicationResult.Failure -> { error = "加载周期规则失败，再试一次。"; return }
                        is ApplicationResult.Success -> series = found.value?.takeIf { it.status == RecurrenceSeriesStatus.active }
                    }
                }
            }
        }
        original?.let { row -> if (series != null) {
            when (val found = appointments.all()) {
                is ApplicationResult.Failure -> { error = "读取受影响课程失败，再试一次。"; return }
                is ApplicationResult.Success -> affectedCount = found.value.count {
                    it.seriesID == row.seriesID && it.date >= row.date && it.status == AppointmentStatus.scheduled && !it.isDetachedException
                }
            }
        } }
        loaded = true; error = null

    }
    fun dismissScope() { scopeRequested = false }
    fun dismissConflict() { conflict = null; pendingScope = null }
    suspend fun overrideConflict() { if (conflict == null) return; conflict = null; save(pendingScope, override = true) }
    suspend fun save(scope: Scope? = null, override: Boolean = false) {
        if (busy || !loaded || saved) return
        error = null
        val id = studentID ?: run { error = "选择一位学员。"; return }
        if (duration <= 0) { error = "预计时长必须大于 0。"; return }
        if (!editing && interval != null && !validBound) { error = boundError; return }
        val old = original
        val scheduleChanged = old != null && (old.date != date || old.startTime != time || old.durationMinutes != duration ||
            old.reminderEnabled != reminderEnabled || (reminderEnabled && old.reminderLeadMinutes != lead))
        if (old != null && !scheduleChanged && old.trainingFocus == focus) { saved = true; return }
        if (scheduleChanged && series != null && scope == null) { scopeRequested = true; return }
        if (scope == Scope.future && old?.date != date) { error = "日期已改变，只能修改仅本次。"; return }
        scopeRequested = false; pendingScope = scope
        busy = true
        try {
            val now = clock.now()
            val candidate = Appointment(old?.id ?: UUID.randomUUID(), id, date = date, startTime = time,
                durationMinutes = duration, reminderEnabled = reminderEnabled, reminderLeadMinutes = if (reminderEnabled) lead else null,
                trainingFocus = focus, createdAtUTC = old?.createdAtUTC ?: now, updatedAtUTC = now)
            val result: ApplicationResult<*> = when {
                old != null && !scheduleChanged -> appointments.updateTrainingFocus(old.id, focus)
                old != null && scope == Scope.future -> appointments.editFuture(checkNotNull(old.seriesID), old.date,
                    FutureAppointmentEdit(time, duration, reminderEnabled, lead, if (focus != old.trainingFocus) focus else null), override)
                old != null -> appointments.editSingle(old.id, AppointmentEdit(date, time, duration, reminderEnabled, lead,
                    if (focus != old.trainingFocus) focus else null), override)
                interval == null -> appointments.createSingle(candidate, override)
                else -> appointments.createRecurring(RecurrenceSeries(UUID.randomUUID(), id, checkNotNull(interval), termination,
                    time, duration, reminderEnabled, if (reminderEnabled) lead else null, createdAtUTC = now, updatedAtUTC = now), date, focus, override)
            }
            when (result) {
                is ApplicationResult.Success -> saved = true
                is ApplicationResult.Failure -> {
                    if (result.error.code == ApplicationErrorCode.conflict && !override) {
                        when {
                            old != null && scope == Scope.future -> conflict = ""
                            old == null && interval != null -> {
                                var conflictingCount = 0
                                for (day in RecurrenceSeries.materializedDates(checkNotNull(interval), date, termination)) {
                                    when (val checked = appointments.conflicts(candidate.copy(date = day))) {
                                        is ApplicationResult.Failure -> { error = "读取冲突失败，再试一次。"; return }
                                        is ApplicationResult.Success -> if (checked.value.isNotEmpty()) conflictingCount++
                                    }
                                }
                                conflict = "有 $conflictingCount 节课存在时间冲突。"
                            }
                            else -> when (val checked = appointments.conflicts(candidate, old?.id)) {
                                is ApplicationResult.Failure -> error = "读取冲突失败，再试一次。"
                                is ApplicationResult.Success -> conflict = checked.value.joinToString("\n") {
                                    "${it.displayName} ${it.start.atZone(zone).toLocalTime().hourMinute()}"
                                }
                            }
                        }
                    } else error = "没有保存课程安排，再试一次。"
                }
            }
        } finally { busy = false }
    }
}
