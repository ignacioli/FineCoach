package com.ignacioli.finecoach.features.packages

import com.ignacioli.finecoach.designsystem.FcText
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CreditAdjustmentRecord
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcInlineResult
import com.ignacioli.finecoach.designsystem.FcPageHeader
import com.ignacioli.finecoach.designsystem.FcPlatformShell
import com.ignacioli.finecoach.designsystem.FcResultVariant
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcTypography
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private class CreditAdjustmentTrailState(
    private val studentID: StudentID,
    private val coursePackageID: CoursePackageID,
    private val useCases: CreditUseCases,
) {
    var packageRecord by mutableStateOf<CoursePackageRecord?>(null)
    var balance by mutableStateOf(0L)
    var adjustments by mutableStateOf<List<CreditAdjustmentRecord>>(emptyList())
    var loadError by mutableStateOf(false)
    var busy by mutableStateOf(false)

    fun tryBegin(): Boolean {
        if (busy) return false
        busy = true
        return true
    }

    fun endBusy() {
        busy = false
    }

    suspend fun reload() {
        val listed = withContext(Dispatchers.IO) { useCases.packages(studentID) }
        val packages = when (listed) {
            is ApplicationResult.Failure -> {
                loadError = true
                return
            }
            is ApplicationResult.Success -> listed.value
        }
        val match = packages.firstOrNull { it.coursePackageID == coursePackageID }
        if (match == null) {
            loadError = true
            return
        }
        val balanceResult = withContext(Dispatchers.IO) { useCases.balance(studentID, coursePackageID) }
        val ledger = withContext(Dispatchers.IO) { useCases.adjustmentsForPackage(studentID, coursePackageID) }
        val resolvedBalance = when (balanceResult) {
            is ApplicationResult.Failure -> {
                loadError = true
                return
            }
            is ApplicationResult.Success -> balanceResult.value
        }
        val resolvedLedger = when (ledger) {
            is ApplicationResult.Failure -> {
                loadError = true
                return
            }
            is ApplicationResult.Success -> newestFirst(ledger.value)
        }
        packageRecord = match
        balance = resolvedBalance
        adjustments = resolvedLedger
        loadError = false
    }
}

@Composable
fun CreditAdjustmentTrailScreen(
    studentID: StudentID,
    coursePackageID: CoursePackageID,
    useCases: CreditUseCases,
    zoneID: ZoneId,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val state = remember(studentID, coursePackageID) {
        CreditAdjustmentTrailState(studentID, coursePackageID, useCases)
    }
    val plus = painterResource(R.drawable.ic_ms_add)
    val minus = painterResource(R.drawable.ic_ms_remove)
    val warning = painterResource(R.drawable.ic_ms_warning)
    val scroll = rememberScrollState()
    LaunchedEffect(studentID, coursePackageID) { state.reload() }
    val record = state.packageRecord
    FcPlatformShell(onBack = onBack, modifier = modifier.testTag("package-trail-root")) {
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(scroll)
                .padding(bottom = FcSpacing.space6)
                .testTag("package-trail-form"),
        ) {
            FcPageHeader(
                record?.let { packageDisplayName(it.name, it.startDate) } ?: "课包详情",
                onBack = onBack,
                tag = "package-trail",
            )
            if (state.loadError) {
                FcText(
                    "记录暂不可用，再试一次。",
                    Modifier.padding(vertical = FcSpacing.space2),
                    style = FcTypography.caption,
                    color = FcColors.statusDestructive,
                )
                FcInlineResult(
                    FcResultVariant.Failure,
                    "记录暂不可用，再试一次。",
                    "课时调整没有读取成功。",
                    warning,
                    tag = "package-trail-load",
                    onRetry = {
                        if (!state.tryBegin()) return@FcInlineResult
                        scope.launch {
                            try {
                                state.reload()
                            } finally {
                                state.endBusy()
                            }
                        }
                    },
                )
            }
            if (record != null) {
                PackageDetailBody(
                    studentName = null,
                    packageRecord = record,
                    balance = state.balance,
                    adjustments = state.adjustments,
                    zoneID = zoneID,
                    plus = plus,
                    minus = minus,
                    tagPrefix = "package-trail",
                    modifier = Modifier.padding(top = FcSpacing.space4),
                )
            }
        }
    }
}
