package com.ignacioli.finecoach.features.calendar

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.domain.appointment.AppointmentStatus
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.appointments.*
import java.time.LocalDate
import java.time.YearMonth
import java.util.UUID
import kotlinx.coroutines.launch

class CalendarUiState(val list: AppointmentListState, initialDate: LocalDate = list.today) {
    var month by mutableStateOf(YearMonth.from(initialDate)); private set
    var selectedDate by mutableStateOf(initialDate); private set
    val selectedRows get() = list.rows.filter { it.date == selectedDate }.sortedBy { it.startTime }
    suspend fun load() { list.load(month.atDay(1),month.atEndOfMonth()) }
    fun shiftMonth(delta: Long) { month = month.plusMonths(delta); list.invalidate() }
    fun select(day: Int) { if (day in 1..month.lengthOfMonth()) selectedDate = month.atDay(day) }
}

@Composable
fun CalendarScreen(state: CalendarUiState, onBack: () -> Unit, onCreate: (LocalDate) -> Unit, onAppointment: (UUID) -> Unit) {
    val scope = rememberCoroutineScope()
    LaunchedEffect(state, state.month) { state.load() }
    FcPlatformShell(onBack) {
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = FcSpacing.space6)
            .testTag("calendar-content"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                FcPageHeader("课程日历", Modifier.weight(1f), onBack = onBack, tag = "calendar")
                FcText("${state.month.year}年${state.month.monthValue}月", style = FcTypography.headline, color = FcColors.textPrimary)
                FcCalendarMonthButton(true, Modifier.testTag("calendar-previous")) { state.shiftMonth(-1) }
                FcCalendarMonthButton(false, Modifier.testTag("calendar-next")) { state.shiftMonth(1) }
            }
            Row(Modifier.fillMaxWidth()) {
                listOf("日", "一", "二", "三", "四", "五", "六").forEach { day ->
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        FcText(day, style = FcTypography.sectionLabel, color = FcColors.textSecondary)
                    }
                }
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                val leading = state.month.atDay(1).dayOfWeek.value % 7
                val cells = (leading + state.month.lengthOfMonth() + 6) / 7 * 7
                for (week in 0 until cells / 7) Row(Modifier.fillMaxWidth()) {
                    for (column in 0..6) {
                        val day = week * 7 + column - leading + 1
                        Box(Modifier.weight(1f)) {
                            if (day in 1..state.month.lengthOfMonth()) {
                                val date = state.month.atDay(day)
                                FcCalendarDayCell(day, date == state.selectedDate, state.list.rows.any { it.date == date },
                                    Modifier.testTag("calendar-day-$day")) { state.select(day) }
                            } else Spacer(Modifier.fillMaxWidth().height(FcComponentMetrics.touch))
                        }
                    }
                }
            }
            FcListRowDivider(Modifier.testTag("conformance:DS-LIST-ROW · divider"))
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                FcText(state.selectedDate.chineseDay(), style = FcTypography.headline, color = FcColors.textPrimary)
                if (state.list.error != null) {
                    FcText("加载课程安排失败，再试一次。", style = FcTypography.caption, color = FcColors.statusDestructive)
                    FcButton("重试", Modifier.testTag("calendar-retry")) { scope.launch { state.load() } }
                }
                if (state.list.loaded && state.selectedRows.isEmpty()) {
                    Column(Modifier.fillMaxWidth().testTag("calendar-empty"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                        FcAmbientScene(size = FcComponentMetrics.calendarIllustration)
                        FcText("这天没课，歇一歇吧～", style = FcTypography.headline, color = FcColors.actionPrimary)
                    }
                } else Column {
                    state.selectedRows.forEachIndexed { index, row ->
                        FcAppointmentRow(row.startTime.hourMinute(), state.list.title(row), state.list.status(row),
                            Modifier.testTag("calendar-appointment-${row.id}"),
                            onClick = if (row.status == AppointmentStatus.scheduled) ({ onAppointment(row.id) }) else null)
                        if (index < state.selectedRows.lastIndex) FcListRowDivider(Modifier.testTag("conformance:DS-LIST-ROW · divider"))
                    }
                }
            }
        }
        FcPinnedAction { FcButton("＋ 添加课程安排", Modifier.testTag("calendar-add"),
            labelModifier = Modifier.testTag("calendar-add-label")) { onCreate(state.selectedDate) } }
    }
}
