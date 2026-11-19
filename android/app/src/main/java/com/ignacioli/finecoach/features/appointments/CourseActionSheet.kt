package com.ignacioli.finecoach.features.appointments

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.util.UUID

class CourseActionState(val id: UUID, private val appointments: AppointmentUseCases,
    private val credits: CreditUseCases, private val students: StudentUseCases,
    private val clock: AppClock, private val zone: ZoneId) {
    var row by mutableStateOf<Appointment?>(null); private set
    var name by mutableStateOf(""); private set
    var deletable by mutableStateOf(false); private set
    var busy by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var previous by mutableStateOf<SessionID?>(null); private set
    var opened by mutableStateOf<SessionID?>(null); private set
    var changed by mutableStateOf(false); private set
    suspend fun load() {
        error = null; deletable = false
        when (val found = appointments.find(id)) {
            is ApplicationResult.Failure -> { error = "读取课程失败，请重试。"; return }
            is ApplicationResult.Success -> row = found.value
        }
        val current = row ?: run { error = "课程安排不存在。"; return }
        when (val found = students.displayNames(setOf(current.studentID))) {
            is ApplicationResult.Failure -> { error = "读取课程失败，请重试。"; return }
            is ApplicationResult.Success -> name = found.value[current.studentID].orEmpty()
        }
        when (val ledger = credits.ledger(current.studentID)) {
            is ApplicationResult.Failure -> error = "读取课时流水失败，请重试。"
            is ApplicationResult.Success -> deletable = current.canPermanentlyDelete(clock.now(), zone) &&
                ledger.value.none { it.linkedAppointmentID == id.toString() }
        }
    }
    suspend fun start() {
        if (busy) return
        busy = true; error = null
        when (val result = appointments.startTraining(id)) {
            is ApplicationResult.Failure -> error = "开始训练失败，请重试。"
            is ApplicationResult.Success -> when (val value = result.value) {
                is AppointmentTrainingStartResult.Started -> opened = value.session.sessionID
                is AppointmentTrainingStartResult.PreviousTrainingNeedsHandling -> previous = value.sessionID
            }
        }
        busy = false
    }
    suspend fun cancel() = mutate { appointments.cancel(id) }
    suspend fun delete() { if (deletable) mutate { appointments.deleteFuture(id, true) } }
    suspend fun absent(choice: AbsentCreditChoice) {
        if (busy) return
        busy = true; error = null
        when (val result = appointments.markAbsent(id, choice, true)) {
            is ApplicationResult.Failure -> error = "标记缺席失败，请重试。"
            is ApplicationResult.Success -> {
                row = result.value.appointment
                if (result.value.settlement is ApplicationResult.Failure) error = "已标记缺席，扣课未成功，请重试。"
                else changed = true
            }
        }
        busy = false
    }
    private suspend fun mutate(action: suspend () -> ApplicationResult<*>) {
        if (busy) return
        busy = true; error = null
        when (action()) {
            is ApplicationResult.Failure -> error = "操作未完成，请重试。"
            is ApplicationResult.Success -> changed = true
        }
        busy = false
    }
}

@Composable
fun CourseActionSheet(state: CourseActionState, onDismiss: () -> Unit, onChanged: () -> Unit,
    onEdit: (UUID) -> Unit, onSession: (SessionID) -> Unit) {
    val scope = rememberCoroutineScope()
    var confirmation by remember { mutableStateOf<String?>(null) }
    var choosingAbsent by remember { mutableStateOf(false) }
    LaunchedEffect(state) { state.load() }
    LaunchedEffect(state.changed) { if (state.changed) onChanged() }
    LaunchedEffect(state.opened) { state.opened?.let(onSession) }
    val row = state.row
    if (confirmation == null) FcBottomSheet(row?.let { "${it.startTime.hourMinute()} · ${it.durationMinutes} 分钟" } ?: "课程安排", onDismiss,
        Modifier.testTag("course-sheet"), titleStyle = FcTypography.title, accessory = {
            row?.let { FcText(when(it.status) { AppointmentStatus.scheduled -> "待上课"; AppointmentStatus.inProgress -> "进行中"; AppointmentStatus.completed -> "已完成"; AppointmentStatus.cancelled -> "已取消"; AppointmentStatus.absent -> "缺席" }, style=FcTypography.caption,color=FcColors.textSecondary) }
        }, subtitle = row?.let {
            val focus = BodyPart.entries.filter { part -> part in it.trainingFocus }.joinToString("、") { part -> FcBodyParts[part.ordinal] }
            listOf(state.name, focus).filter(String::isNotBlank).joinToString(" · ")
        }) {
        Column(Modifier.fillMaxWidth().testTag("course-actions")) {
            state.error?.let { FcText(it, Modifier.testTag("course-error"), style = FcTypography.caption, color = FcColors.statusDestructive) }
            state.previous?.let { previous ->
                FcText("请先处理该学员的上次训练，结束或放弃空训练后再开始本次安排。", style = FcTypography.caption, color = FcColors.textSecondary)
                FcButton("进入上次训练", Modifier.testTag("course-previous"), !state.busy) { onSession(previous) }
            }
            if (row == null) FcButton("重试", Modifier.testTag("course-retry")) { scope.launch { state.load() } }
            else if (row.status == AppointmentStatus.scheduled || (row.status == AppointmentStatus.absent && state.error != null)) {
                if (choosingAbsent || row.status == AppointmentStatus.absent) {
                    FcSectionLabel("标记缺席")
                    if (row.absentCreditChoice != AbsentCreditChoice.charged) FcActionRow("不扣课", Modifier.testTag("course-absent-free"), enabled = !state.busy) { scope.launch { state.absent(AbsentCreditChoice.notCharged) } }
                    FcListRowDivider()
                    if (row.absentCreditChoice != AbsentCreditChoice.notCharged) FcActionRow("扣1课时", Modifier.testTag("course-absent-debit"), enabled = !state.busy) { scope.launch { state.absent(AbsentCreditChoice.charged) } }
                    FcLinkButton("返回", Modifier.fillMaxWidth().testTag("course-absent-back")) { choosingAbsent = false }
                } else {
                    FcButton("开始训练", Modifier.padding(vertical = FcSpacing.space2).testTag("course-start"), !state.busy) { scope.launch { state.start() } }
                    FcActionRow("标记缺席", Modifier.testTag("course-absent"), detail = "扣课 / 不扣课", enabled = !state.busy) { choosingAbsent = true }
                    FcListRowDivider()
                    FcActionRow("编辑安排", Modifier.testTag("course-edit"), enabled = !state.busy) { onEdit(state.id) }
                    FcListRowDivider()
                    FcActionRow("取消本次", Modifier.testTag("course-cancel"), detail = "需二次确认", destructive = true, enabled = !state.busy) { confirmation = "cancel" }
                    if (state.deletable) {
                        FcListRowDivider()
                        FcActionRow("删除误建", Modifier.testTag("course-delete"), detail = "需二次确认", destructive = true, enabled = !state.busy) { confirmation = "delete" }
                    }
                }
            } else if (row.status == AppointmentStatus.inProgress && row.linkedSessionID != null) {
                FcButton("继续训练", Modifier.testTag("course-continue")) { onSession(SessionID.fromUUID(row.linkedSessionID)) }
            }
            FcLinkButton("取消", Modifier.fillMaxWidth().testTag("course-dismiss"), enabled = !state.busy, onClick = onDismiss)
        }
    }
    confirmation?.let { action -> FcConfirmationDialog(if (action == "delete") "删除误建安排？" else "取消本次课程？",
        if (action == "delete") "永久删除此安排，无法撤销。" else "保留课程记录，本次不扣课。",
        if (action == "delete") "删除误建" else "取消本次",
        { confirmation = null; scope.launch { if (action == "delete") state.delete() else state.cancel() } },
        { confirmation = null }, tag = "course-confirm") }
}
