package com.ignacioli.finecoach.features.packages

import com.ignacioli.finecoach.designsystem.FcText
import com.ignacioli.finecoach.designsystem.FcScrollBody
import com.ignacioli.finecoach.designsystem.FcPinnedAction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.designsystem.FcButton
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcLabelValueRow
import com.ignacioli.finecoach.designsystem.FcListRowDivider
import com.ignacioli.finecoach.designsystem.FcPageHeader
import com.ignacioli.finecoach.designsystem.FcPlatformShell
import com.ignacioli.finecoach.designsystem.FcSegmentedSwitch
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcStepper
import com.ignacioli.finecoach.designsystem.FcTextField
import com.ignacioli.finecoach.designsystem.FcTypography
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private class ManualCreditAdjustmentState(
    private val coursePackageID: CoursePackageID,
    private val useCases: CreditUseCases,
) {
    var direction by mutableStateOf(CreditDirection.debit)
    var amount by mutableStateOf(1)
    var reason by mutableStateOf("")
    var busy by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    var saved by mutableStateOf(false)

    fun tryBegin(): Boolean {
        if (busy) return false
        busy = true
        return true
    }

    fun endBusy() {
        busy = false
    }

    suspend fun save() {
        val result = withContext(Dispatchers.IO) {
            useCases.recordManualCorrection(
                coursePackageID = coursePackageID,
                direction = direction,
                amount = amount.toLong(),
                reasonText = reason.trim(),
            )
        }
        when (result) {
            is ApplicationResult.Success -> {
                error = null
                saved = true
            }
            is ApplicationResult.Failure -> error = manualSaveMessage(result.error)
        }
    }
}

@Composable
fun ManualCreditAdjustmentScreen(
    coursePackageID: CoursePackageID,
    useCases: CreditUseCases,
    onBack: () -> Unit,
    onSaved: () -> Unit,
    modifier: Modifier = Modifier,
    windowInsets: WindowInsets = WindowInsets.safeDrawing,
) {
    val scope = rememberCoroutineScope()
    val state = remember(coursePackageID) { ManualCreditAdjustmentState(coursePackageID, useCases) }
    val minus = painterResource(R.drawable.ic_ms_remove)
    val plus = painterResource(R.drawable.ic_ms_add)
    val scroll = rememberScrollState()
    val reasonReady = state.reason.trim().isNotEmpty()
    LaunchedEffect(state.saved) {
        if (state.saved) onSaved()
    }
    Box(modifier.fillMaxSize().testTag("package-manual-root")) {
        FcPlatformShell(onBack = onBack, insets = windowInsets) {
            FcScrollBody(Modifier.testTag("package-manual-form"), scroll) {
                FcPageHeader("人工调整课时", onBack = onBack, tag = "package-manual")
                FcListRowDivider()
                FcLabelValueRow("调整方向", trailingControl = true) {
                    FcSegmentedSwitch(
                        listOf("扣减", "返还"),
                        if (state.direction == CreditDirection.debit) 0 else 1,
                        { index ->
                            state.direction = if (index == 0) CreditDirection.debit else CreditDirection.credit
                        },
                        tag = "manual-adjustment-direction",
                    )
                }
                FcListRowDivider()
                FcLabelValueRow("课时数", trailingControl = true) {
                    FcStepper(
                        "课时数",
                        state.amount,
                        1..999,
                        { state.amount = it },
                        minus,
                        plus,
                        tag = "manual-adjustment-amount",
                    )
                }
                FcListRowDivider()
                FcText(
                    "调整原因（必填）",
                    Modifier.padding(top = FcSpacing.space4),
                    style = FcTypography.style("callout", 400),
                    color = FcColors.textSecondary,
                )
                Box(Modifier.fillMaxWidth().padding(top = FcSpacing.space2).testTag("package-manual-reason-slot")) {
                    FcTextField(
                        "说明本次调整的原因",
                        state.reason,
                        { state.reason = it },
                        Modifier.testTag("package-manual-reason"),
                        visualModifier = Modifier.heightIn(min = FcSpacing.space8 * 2 + FcSpacing.space6),
                        singleLine = false,
                    )
                }
                state.error?.let { message ->
                    FcText(
                        message,
                        Modifier.padding(vertical = FcSpacing.space2).testTag("package-manual-error"),
                        style = FcTypography.style("callout", 400),
                        color = FcColors.statusDestructive,
                    )
                }
            }
            FcPinnedAction {
                FcButton(
                    "保存调整",
                    Modifier.testTag("package-manual-save"),
                    enabled = reasonReady && !state.busy,
                ) {
                    if (!reasonReady || !state.tryBegin()) return@FcButton
                    scope.launch {
                        try {
                            state.save()
                        } finally {
                            state.endBusy()
                        }
                    }
                }
            }
        }
    }
}
