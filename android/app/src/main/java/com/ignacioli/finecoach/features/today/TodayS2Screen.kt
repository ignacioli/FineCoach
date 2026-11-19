package com.ignacioli.finecoach.features.today

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.appointments.*
import com.ignacioli.finecoach.navigation.S1Routes
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.UUID

@Composable
fun TodayS2Screen(training: TodayUiState, state: AppointmentListState, onNavigate: (String) -> Unit,
    onCalendar: () -> Unit, onCreate: (LocalDate) -> Unit, onAppointment: (UUID) -> Unit, onSettings: () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    var expanded by remember { mutableStateOf(false) }
    LaunchedEffect(state, training) { training.load(); state.load() }
    val ordered = TodayOrderingPolicy.order(state.rows, state.today, state.clock.now(), state.zone)
    FcPlatformShell({}) {
        FcPagePrimary("今日", Modifier.fillMaxSize(),
            subtitle = state.today.chineseDay(), subtitleModifier = Modifier.testTag("today-date"),
            actions = {
                FcTitleAddButton("新建课程安排", painterResource(R.drawable.ic_ms_add), Modifier.testTag("today-add"), Modifier.testTag("conformance:icon / plus")) { onCreate(state.today) }
                FcTitleIconButton("课程日历", painterResource(R.drawable.ic_ms_calendar_month), Modifier.testTag("today-calendar"),
                    Modifier.testTag("conformance:icon / calendar"), onClick = onCalendar)
                FcTitleIconButton("设置", painterResource(R.drawable.ic_ms_settings), Modifier.testTag("today-settings"),
                    Modifier.testTag("conformance:icon / gearshape"), onClick = onSettings)
            }, segments = { FcSegmentedSwitch(listOf("今日", "学员"), 0, { if (it == 1) onNavigate(S1Routes.STUDENTS) }, tag = "root") }) {
            Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(bottom = FcSpacing.space6)
                .testTag("today-content"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
                if (state.error != null || training.error != null) {
                    FcText("加载今日安排失败，再试一次。", style = FcTypography.caption, color = FcColors.statusDestructive)
                    FcButton("重试", Modifier.testTag("today-retry")) { scope.launch { training.load(); state.load() } }
                }
                when (training.items.size) {
                    0 -> Unit
                    1 -> training.items.single().let { row -> FcHeroCard("进行中", row.title, row.subtitle, Modifier.testTag("hero-${row.id}"),
                        "继续训练", { onNavigate(S1Routes.activeSession(SessionID.parse(row.id))) }) }
                    else -> FcMultiHeroCard(training.items, { onNavigate(S1Routes.activeSession(SessionID.parse(it))) })
                }
                if (state.loaded && training.hasCompletedInitialLoad && training.items.isEmpty() && ordered.isEmpty()) {
                    FcEmptyState("今天没课，休息一下吧～", "有新课程时会显示在这里", Modifier.testTag("today-empty"), ambient = true)
                }
                val overdue = ordered.filter { it.section == TodayOrderingSection.overdue }
                if (overdue.isNotEmpty()) Column {
                    FcListRowDivider()
                    overdue.forEach { item ->
                        FcAppointmentRow(item.appointment.startTime.hourMinute(), state.title(item.appointment), state.status(item.appointment, true),
                            Modifier.testTag("today-appointment-${item.appointment.id}"), showsDisclosure = false, overdue = true, onClick = { onAppointment(item.appointment.id) })
                        FcListRowDivider()
                    }
                }
                ordered.firstOrNull { it.section == TodayOrderingSection.nextUp }?.appointment?.let { row ->
                    Column(verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                        FcSectionLabel("下一节课")
                        Column { FcListRowDivider(Modifier.testTag("conformance:DS-LIST-ROW · divider"))
                            FcAppointmentRow(row.startTime.hourMinute(), state.names[row.studentID].orEmpty(), state.status(row),
                                Modifier.testTag("today-appointment-${row.id}"), prominent = true,
                                subtitle = listOf("${row.durationMinutes} 分钟", state.focus(row)).filter { it.isNotBlank() }.joinToString(" · "), onClick = { onAppointment(row.id) }) }
                    }
                }
                val remaining = ordered.filter { it.section == TodayOrderingSection.remainingToday }
                if (remaining.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    FcSectionLabel("其余今日课程")
                    Column { FcListRowDivider(Modifier.testTag("conformance:DS-LIST-ROW · divider"))
                        remaining.forEach { item ->
                            FcAppointmentRow(item.appointment.startTime.hourMinute(), state.title(item.appointment), state.status(item.appointment),
                                Modifier.testTag("today-appointment-${item.appointment.id}"), showsDisclosure = false, onClick = { onAppointment(item.appointment.id) })
                            FcListRowDivider(Modifier.testTag("conformance:DS-LIST-ROW · divider"))
                        }
                    }
                }
                val resolved = ordered.filter { it.section == TodayOrderingSection.resolved }
                if (resolved.isNotEmpty()) Column {
                    FcGroupEntryRow("已处理", resolved.size, Modifier.testTag("today-resolved")) { expanded = !expanded }
                    if (expanded) resolved.forEach { item -> FcAppointmentRow(item.appointment.startTime.hourMinute(), state.title(item.appointment),
                        state.status(item.appointment), Modifier.testTag("today-resolved-${item.appointment.id}")) }
                }
            }
        }
    }
}
