package com.ignacioli.finecoach.features.appointments

import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.Snapshot
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.FcBodyParts
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.Locale

class AppointmentListState(val appointments: AppointmentUseCases, private val students: StudentUseCases,
    val clock: AppClock, val zone: ZoneId) {
    var rows by mutableStateOf<List<Appointment>>(emptyList()); private set
    var names by mutableStateOf<Map<StudentID, String>>(emptyMap()); private set
    var loaded by mutableStateOf(false); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    private var generation = 0L
    private var range: Pair<LocalDate, LocalDate>? = null
    fun invalidate() {
        generation++
        range = null
        rows = emptyList(); names = emptyMap(); loaded = false; error = null
    }
    val today get() = clock.today(zone)
    suspend fun load(first: LocalDate = today, last: LocalDate = first) {
        val requestedRange = first to last
        if (range != requestedRange) invalidate() else { generation++; error = null }
        range = requestedRange
        val request = generation
        val result = appointments.inDateRange(first,last)
        if (request != generation) return
        when (result) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> {
                val labels = students.displayNames(result.value.map { it.studentID }.toSet())
                if (request != generation) return
                when (labels) {
                    is ApplicationResult.Failure -> { error = labels.error; return }
                    is ApplicationResult.Success -> {
                        Snapshot.withMutableSnapshot {
                            rows = result.value; names = result.value.associate { it.studentID to labels.value[it.studentID].orEmpty() }
                            loaded = true; error = null
                        }
                    }
                }
            }
        }
    }
    fun title(row: Appointment) = listOfNotNull(names[row.studentID], focus(row).takeIf { it.isNotBlank() }).joinToString(" · ")
    fun focus(row: Appointment) = BodyPart.entries.filter { it in row.trainingFocus }.joinToString("、") { FcBodyParts[it.ordinal] }
    fun status(row: Appointment, overdue: Boolean = false) = when (row.status) {
        AppointmentStatus.scheduled -> if (overdue) "逾期待处理" else "待上课"
        AppointmentStatus.inProgress -> "进行中"
        AppointmentStatus.completed -> "已完成"
        AppointmentStatus.cancelled -> "已取消"
        AppointmentStatus.absent -> "缺席"
    }
}

internal fun LocalDate.chineseDay(): String = format(DateTimeFormatter.ofPattern("M月d日 · EEE", Locale.SIMPLIFIED_CHINESE))
internal fun LocalTime.hourMinute(): String = format(DateTimeFormatter.ofPattern("HH:mm", Locale.ROOT))
