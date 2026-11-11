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
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CreditAdjustmentRecord
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CoursePackageStatus
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.designsystem.FcActionRow
import com.ignacioli.finecoach.designsystem.FcButton
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcConfirmationDialog
import com.ignacioli.finecoach.designsystem.FcInlineResult
import com.ignacioli.finecoach.designsystem.FcListRowDivider
import com.ignacioli.finecoach.designsystem.FcPageHeader
import com.ignacioli.finecoach.designsystem.FcPlatformShell
import com.ignacioli.finecoach.designsystem.FcResultVariant
import com.ignacioli.finecoach.designsystem.FcSectionLabel
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcTypography
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private class CoursePackageListState(
    private val studentID: StudentID,
    private val useCases: CreditUseCases,
    private val students: StudentUseCases?,
) {
    var packages by mutableStateOf<List<CoursePackageRecord>>(emptyList())
    var balances by mutableStateOf<Map<CoursePackageID, Long>>(emptyMap())
    var adjustments by mutableStateOf<List<CreditAdjustmentRecord>>(emptyList())
    var studentName by mutableStateOf<String?>(null)
    var ready by mutableStateOf(false)
    var loadError by mutableStateOf(false)
    var actionError by mutableStateOf<String?>(null)
    var confirmingEnd by mutableStateOf(false)
    var busy by mutableStateOf(false)

    val active: CoursePackageRecord?
        get() = packages.firstOrNull { it.status == CoursePackageStatus.active }

    val historical: List<CoursePackageRecord>
        get() = packages.filter { it.status == CoursePackageStatus.ended }

    fun balanceOf(record: CoursePackageRecord): Long = balances[record.coursePackageID] ?: record.remainingCreditsCache

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
        val loaded = when (listed) {
            is ApplicationResult.Failure -> {
                ready = false
                loadError = true
                return
            }
            is ApplicationResult.Success -> listed.value
        }
        val nextBalances = mutableMapOf<CoursePackageID, Long>()
        for (record in loaded) {
            when (val balance = withContext(Dispatchers.IO) { useCases.balance(studentID, record.coursePackageID) }) {
                is ApplicationResult.Failure -> {
                    ready = false
                    loadError = true
                    return
                }
                is ApplicationResult.Success -> nextBalances[record.coursePackageID] = balance.value
            }
        }
        val activePackage = loaded.firstOrNull { it.status == CoursePackageStatus.active }
        val ledger = if (activePackage == null) {
            emptyList()
        } else {
            when (val result = withContext(Dispatchers.IO) {
                useCases.adjustmentsForPackage(studentID, activePackage.coursePackageID)
            }) {
                is ApplicationResult.Failure -> {
                    ready = false
                    loadError = true
                    return
                }
                is ApplicationResult.Success -> newestFirst(result.value)
            }
        }
        studentName = readStudentName()
        packages = loaded
        balances = nextBalances
        adjustments = ledger
        ready = true
        loadError = false
    }

    suspend fun endActive() {
        val id = active?.coursePackageID ?: return
        when (val result = withContext(Dispatchers.IO) { useCases.endPackage(id) }) {
            is ApplicationResult.Success -> {
                confirmingEnd = false
                actionError = null
                reload()
            }
            is ApplicationResult.Failure -> {
                confirmingEnd = false
                actionError = packageLoadErrorTitle
            }
        }
    }

    private suspend fun readStudentName(): String? {
        val studentLookup = students ?: return null
        return when (val result = withContext(Dispatchers.IO) { studentLookup.find(studentID) }) {
            is ApplicationResult.Success -> result.value?.displayName
            is ApplicationResult.Failure -> null
        }
    }
}

@Composable
fun CoursePackageListScreen(
    studentID: StudentID,
    useCases: CreditUseCases,
    zoneID: ZoneId,
    onBack: () -> Unit,
    onCreate: () -> Unit,
    onManual: (CoursePackageID) -> Unit,
    onOpenPackage: (CoursePackageID) -> Unit,
    modifier: Modifier = Modifier,
    students: StudentUseCases? = null,
) {
    val scope = rememberCoroutineScope()
    val state = remember(studentID) { CoursePackageListState(studentID, useCases, students) }
    val plus = painterResource(R.drawable.ic_ms_add)
    val minus = painterResource(R.drawable.ic_ms_remove)
    val warning = painterResource(R.drawable.ic_ms_warning)
    val trash = painterResource(R.drawable.ic_ms_delete)
    val scroll = rememberScrollState()
    LaunchedEffect(studentID) { state.reload() }
    FcPlatformShell(onBack = onBack, modifier = modifier.testTag("package-list-root")) {
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(scroll)
                .testTag("package-list-body"),
        ) {
            FcPageHeader("课包详情", onBack = onBack, tag = "package-list")
            if (state.loadError) {
                FcInlineResult(
                    FcResultVariant.Failure,
                    packageLoadErrorTitle,
                    packageLoadErrorDescription,
                    warning,
                    Modifier.padding(top = FcSpacing.space4),
                    tag = "package-list-load",
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
            val active = state.active
            if (state.ready && active != null) {
                PackageDetailBody(
                    studentName = state.studentName,
                    packageRecord = active,
                    balance = state.balanceOf(active),
                    adjustments = state.adjustments,
                    zoneID = zoneID,
                    plus = plus,
                    minus = minus,
                    tagPrefix = "package-list",
                    modifier = Modifier.padding(top = FcSpacing.space4),
                )
            } else if (state.ready) {
                if (!state.studentName.isNullOrEmpty()) {
                    FcText(
                        state.studentName.orEmpty(),
                        Modifier.padding(top = FcSpacing.space4),
                        style = FcTypography.headline,
                        color = FcColors.textSecondary,
                    )
                }
                FcText(
                    noActivePackage,
                    Modifier.padding(top = FcSpacing.space4).testTag("package-list-none"),
                    style = FcTypography.style("callout", 400),
                    color = FcColors.textSecondary,
                )
            }
            if (state.ready) {
                PackageManagement(
                    active = active,
                    historical = state.historical,
                    balanceOf = state::balanceOf,
                    trash = trash,
                    onCreate = onCreate,
                    onEnd = { state.confirmingEnd = true },
                    onOpenPackage = onOpenPackage,
                )
            }
            state.actionError?.let { message ->
                FcText(
                    message,
                    Modifier.padding(vertical = FcSpacing.space2).testTag("package-list-error"),
                    style = FcTypography.caption,
                    color = FcColors.statusDestructive,
                )
            }
        }
        if (state.ready && state.active != null) {
            FcButton(
                "人工调整",
                Modifier.testTag("package-list-manual").padding(bottom = FcSpacing.space4),
            ) {
                state.active?.coursePackageID?.let(onManual)
            }
        } else if (state.ready) {
            FcButton(
                "新建课包",
                Modifier.testTag("package-list-add").padding(bottom = FcSpacing.space4),
            ) {
                onCreate()
            }
        }
    }
    if (state.confirmingEnd) {
        FcConfirmationDialog(
            title = "结束当前课包？",
            message = endPackageMessage,
            confirmTitle = "结束课包",
            onConfirm = {
                if (!state.tryBegin()) return@FcConfirmationDialog
                scope.launch {
                    try {
                        state.endActive()
                    } finally {
                        state.endBusy()
                    }
                }
            },
            onDismiss = { state.confirmingEnd = false },
            cancelTitle = "保留",
            tag = "package-end",
        )
    }
}

@Composable
private fun PackageManagement(
    active: CoursePackageRecord?,
    historical: List<CoursePackageRecord>,
    balanceOf: (CoursePackageRecord) -> Long,
    trash: Painter,
    onCreate: () -> Unit,
    onEnd: () -> Unit,
    onOpenPackage: (CoursePackageID) -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(top = FcSpacing.space4)) {
        FcSectionLabel("课包管理", Modifier.padding(bottom = FcSpacing.space2))
        FcListRowDivider()
        if (active != null) {
            FcActionRow("新建课包", Modifier.testTag("package-list-add"), onClick = onCreate)
            FcListRowDivider()
            FcActionRow(
                "结束当前课包",
                Modifier.testTag("package-list-end"),
                destructive = true,
                trash = trash,
                onClick = onEnd,
            )
            FcListRowDivider()
        }
        historical.forEach { record ->
            FcActionRow(
                packageDisplayName(record.name, record.startDate),
                Modifier.testTag("package-row-${record.coursePackageID.value}"),
                detail = packageBalanceNote(balanceOf(record), record.totalCredits),
                onClick = { onOpenPackage(record.coursePackageID) },
            )
            FcListRowDivider()
        }
    }
}
