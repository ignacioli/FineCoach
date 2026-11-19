package com.ignacioli.finecoach.features.session

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

class FinishSessionUiState(val active: ActiveSessionUiState, val useCases: FinishSessionUseCases,
    private val sessions: SessionRepositoryPort) {
    var gate by mutableStateOf<SessionFinishGate?>(null); private set
    var outcome by mutableStateOf<SessionCreditOutcome?>(null); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    var completed by mutableStateOf(false); private set
    var busy by mutableStateOf(false); private set
    var ready by mutableStateOf(false); private set
    var linked by mutableStateOf(false); private set
    var adjustmentTarget: CoursePackageID? = null
    suspend fun prepare() {
        val current = active.content ?: return
when (val found = sessions.linkedAppointmentID(current.session.sessionID)) {
            is ApplicationResult.Failure -> { error = found.error; return }
            is ApplicationResult.Success -> linked = found.value != null
        }
        if (current.session.state == SessionState.completed) { completed = true; settle(); return }
        when (val result = useCases.gate(current.session.sessionID)) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> {
                gate = result.value
                if (gate == SessionFinishGate.canComplete && !current.session.durationNeedsReview) finish(false)
            }
        }
    }
    suspend fun finish(discard: Boolean) {
        val current = active.content ?: return
        if (busy || active.saveState == FcSaveState.Failed) return
        busy = true
        when (val result = useCases.finish(current.session.sessionID, current.session.revision, discard)) {
            is ApplicationResult.Failure -> {
                error = result.error
                // A prior finish step may already be durable. Reload its revision before explicit retry.
                when (val reload = sessions.loadContent(current.session.sessionID)) {
                    is ApplicationResult.Success -> reload.value?.let(active::accept)
                    is ApplicationResult.Failure -> Unit
                }
            }
            is ApplicationResult.Success -> {
                completed = true; active.rests.clear(current.session.sessionID)
                acceptSettlement(result.value.settlement)
            }
        }
        busy = false
    }
    private fun acceptSettlement(result: ApplicationResult<SessionCreditOutcome>) {
        when (result) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> {
                error = null; outcome = result.value
                ready = result.value is SessionCreditOutcome.NoActivePackage || result.value is SessionCreditOutcome.Debited || result.value is SessionCreditOutcome.Skipped
            }
        }
    }
    suspend fun settle() {
        if (busy) return
        val id = active.content?.session?.sessionID ?: return
        busy = true; acceptSettlement(useCases.settlement(id)); busy = false
    }
    suspend fun retryFinish() {
        val id = active.content?.session?.sessionID ?: return
        if (active.useCases.saveStatus(id) is SessionSaveStatus.Failed) {
            when (val retried = active.useCases.retry(id)) {
                is ApplicationResult.Failure -> { error = retried.error; return }
                is ApplicationResult.Success -> when (val loaded = sessions.loadContent(id)) {
                    is ApplicationResult.Failure -> { error = loaded.error; return }
                    is ApplicationResult.Success -> loaded.value?.let(active::accept)
                }
            }
        }
        finish(gate == SessionFinishGate.unresolvedDrafts)
    }
    suspend fun debit() {
        val choice = outcome as? SessionCreditOutcome.AdhocChoiceRequired ?: return
        if (busy) return
        val id = active.content?.session?.sessionID ?: return
        busy = true; acceptSettlement(useCases.debitAdhoc(id, choice.coursePackage.coursePackageID)); busy = false
    }
    suspend fun skip() {
        if (busy) return
        val id = active.content?.session?.sessionID ?: return
        busy = true; acceptSettlement(useCases.skipDebit(id)); busy = false
    }
    suspend fun abandon(onDone: () -> Unit) {
        val current = active.content ?: return
        if (busy) return
        busy = true
        when (val result = useCases.abandonEmpty(current.session.sessionID, current.session.revision, true)) {
            is ApplicationResult.Failure -> error = result.error
            is ApplicationResult.Success -> { error = null; active.rests.clear(current.session.sessionID); onDone() }
        }
        busy = false
    }
}

@Composable
fun FinishSessionScreen(state: FinishSessionUiState, onContinue: () -> Unit, onAbandoned: () -> Unit,
    onSummary: (SessionID) -> Unit, onAdjust: (CoursePackageID) -> Unit) {
    val scope = rememberCoroutineScope()
    LaunchedEffect(state) { state.prepare() }
    LaunchedEffect(state.ready) { if (state.ready) {
        state.adjustmentTarget?.let(onAdjust) ?: state.active.content?.session?.sessionID?.let(onSummary)
    } }
    val current = state.active.content
    val back = { if (!state.busy) { if (state.completed) scope.launch { if (state.linked) state.settle() else state.skip() } else onContinue() }; Unit }
    if (!state.completed && current?.session?.durationNeedsReview == true) {
        DurationReviewScreen(state.active, onContinue) { scope.launch { state.prepare() } }
        return
    }
    FcPlatformShell(back) {
        FcPageHeader(if (state.completed) "训练已完成" else "结束训练", onBack = back, tag = "finish")
        Column(Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).testTag("finish-content")) {
            state.error?.let {
                FcListRow(if (state.completed) (if (state.linked) "训练已完成，扣课未成功，请重试" else "训练已完成，扣课未成功，请重试或不扣课") else "结束失败，请重试", Modifier.testTag("finish-error"))
                FcButton("重试", Modifier.testTag("finish-retry"), !state.busy) {
                    scope.launch { if (state.completed) state.settle() else state.retryFinish() }
                }
            }
            if (!state.completed) when (state.gate) {
                SessionFinishGate.abandonEmpty -> {
                    FcListRow("还没有完成任何组，放弃后不会生成已完成训练或扣课。")
                    FcButton("放弃本次训练", Modifier.testTag("finish-abandon"), !state.busy) { scope.launch { state.abandon(onAbandoned) } }
                }
                SessionFinishGate.unresolvedDrafts -> {
                    FcListRow("仍有未完成的组，请返回继续，或丢弃未完成组并结束。")
                    FcButton("丢弃未完成组并结束", Modifier.testTag("finish-discard"), !state.busy) { scope.launch { state.finish(true) } }
                }
                else -> Unit
            }
            if (!state.completed) FcSecondaryButton("返回继续", Modifier.testTag("finish-return"), !state.busy, onContinue)
            else if (state.error != null || state.outcome is SessionCreditOutcome.PackageUnusable) {
                (state.outcome as? SessionCreditOutcome.PackageUnusable)?.let { notice ->
                    FcListRow(if (notice.reason == SessionCreditUnusableReason.expired) "课包已到期，本次未扣课" else "课包余额不足，本次未扣课")
                    if (!state.linked) FcButton("手工调整", Modifier.testTag("finish-adjust"), !state.busy) {
                        state.adjustmentTarget = notice.coursePackage.coursePackageID
                        scope.launch { state.skip() }
                    }
                }
                if (!state.linked) FcSecondaryButton("不扣课", Modifier.testTag("finish-skip"), !state.busy) { scope.launch { state.skip() } }
            }
        }
    }
    val choice = state.outcome as? SessionCreditOutcome.AdhocChoiceRequired
    if (choice != null && !state.ready && state.error == null) FcConfirmationDialog("本次训练扣课吗？", "当前课包剩余 ${choice.coursePackage.remainingCreditsCache} 课时。", "扣1课时",
        { scope.launch { state.debit() } }, { if (!state.busy) scope.launch { state.skip() } }, cancelTitle = "不扣课", tag = "finish-credit")
}
