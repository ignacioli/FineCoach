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
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.SaveCoursePackageResult
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.designsystem.FcButton
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcDatePickerDialog
import com.ignacioli.finecoach.designsystem.FcConfirmationDialog
import com.ignacioli.finecoach.designsystem.FcInlineResult
import com.ignacioli.finecoach.designsystem.FcLabelValueRow
import com.ignacioli.finecoach.designsystem.FcListRowDivider
import com.ignacioli.finecoach.designsystem.FcPageHeader
import com.ignacioli.finecoach.designsystem.FcPlatformShell
import com.ignacioli.finecoach.designsystem.FcResultVariant
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcStepper
import com.ignacioli.finecoach.designsystem.FcTextField
import com.ignacioli.finecoach.designsystem.FcToggle
import com.ignacioli.finecoach.designsystem.FcTypography
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal enum class PickingDate { Start, End }

internal data class EditorContext(
    val asOf: LocalDate,
    val existing: CoursePackageRecord?,
    val balance: Long,
    val requiresConfirmation: Boolean,
)

internal data class PackageConfirmation(
    val packageId: CoursePackageID?,
    val message: String,
)

internal class CoursePackageEditorState(
    private val studentID: StudentID,
    private val useCases: CreditUseCases,
    private val clock: AppClock,
    private val zoneID: ZoneId,
) {
    var name by mutableStateOf("")
    var totalCredits by mutableStateOf(10)
    var hasStartDate by mutableStateOf(false)
    var hasEndDate by mutableStateOf(false)
    var startDate by mutableStateOf(clock.today(zoneID))
    var endDate by mutableStateOf(clock.today(zoneID))
    var loading by mutableStateOf(true)
    var ready by mutableStateOf(false)
    var loadError by mutableStateOf(false)
    var busy by mutableStateOf(false)
    var saveError by mutableStateOf<String?>(null)
    var context by mutableStateOf<EditorContext?>(null)
    var confirmation by mutableStateOf<PackageConfirmation?>(null)
    var picking by mutableStateOf<PickingDate?>(null)

    fun tryBegin(): Boolean {
        if (busy) return false
        busy = true
        return true
    }

    fun endBusy() {
        busy = false
    }

    suspend fun reload() {
        val result = withContext(Dispatchers.IO) { useCases.loadCreationContext(studentID) }
        when (result) {
            is ApplicationResult.Success -> {
                val value = result.value
                context = EditorContext(
                    asOf = value.asOf,
                    existing = value.existingActivePackage,
                    balance = value.existingActivePackageBalance,
                    requiresConfirmation = value.requiresConfirmation,
                )
                ready = true
                loadError = false
            }
            is ApplicationResult.Failure -> {
                ready = false
                loadError = true
            }
        }
        loading = false
    }

    suspend fun saveWithoutConfirmation() {
        val loaded = withContext(Dispatchers.IO) { useCases.loadCreationContext(studentID) }
        when (loaded) {
            is ApplicationResult.Failure -> {
                ready = false
                loadError = true
                saveError = null
            }
            is ApplicationResult.Success -> {
                val value = loaded.value
                context = EditorContext(
                    asOf = value.asOf,
                    existing = value.existingActivePackage,
                    balance = value.existingActivePackageBalance,
                    requiresConfirmation = value.requiresConfirmation,
                )
                ready = true
                loadError = false
                if (value.requiresConfirmation) {
                    val existing = value.existingActivePackage
                    if (existing != null) {
                        confirmation = confirmationFor(existing, value.existingActivePackageBalance)
                    }
                } else {
                    apply(
                        withContext(Dispatchers.IO) {
                            useCases.createActivePackage(
                                studentID = studentID,
                                name = trimmedName(),
                                totalCredits = totalCredits.toLong(),
                                startDate = if (hasStartDate) startDate else null,
                                endDate = if (hasEndDate) endDate else null,
                                observedActivePackageID = value.observedActivePackageID,
                                confirmReplaceActivePackage = false,
                            )
                        },
                    )
                }
            }
        }
    }

    suspend fun confirmShownPackage(shownId: CoursePackageID) {
        apply(
            withContext(Dispatchers.IO) {
                useCases.createActivePackage(
                    studentID = studentID,
                    name = trimmedName(),
                    totalCredits = totalCredits.toLong(),
                    startDate = if (hasStartDate) startDate else null,
                    endDate = if (hasEndDate) endDate else null,
                    observedActivePackageID = shownId,
                    confirmReplaceActivePackage = true,
                )
            },
        )
    }

    suspend fun reloadConfirmation() {
        reload()
        val current = context
        val existingPackage = current?.existing
        confirmation = if (current != null && current.requiresConfirmation && existingPackage != null) {
            confirmationFor(existingPackage, current.balance)
        } else {
            null
        }
    }

    fun cancelConfirmation() {
        confirmation = null
        useCases.cancelPackageReplacement()
    }

    private suspend fun apply(result: ApplicationResult<SaveCoursePackageResult>) {
        when (result) {
            is ApplicationResult.Failure -> {
                saveError = editorSaveMessage(result.error)
            }
            is ApplicationResult.Success -> when (val value = result.value) {
                is SaveCoursePackageResult.Saved -> {
                    confirmation = null
                    saveError = null
                    saved = true
                }
                is SaveCoursePackageResult.RequiresReconfirmation -> {
                    val current = value.currentActivePackage
                    if (current == null) {
                        context = context?.copy(existing = null, balance = 0L, requiresConfirmation = false)
                        confirmation = PackageConfirmation(packageId = null, message = replacementChangedMessage)
                    } else {
                        val balance = displayedBalance(current)
                        context = EditorContext(
                            asOf = context?.asOf ?: clock.today(zoneID),
                            existing = current,
                            balance = balance,
                            requiresConfirmation = true,
                        )
                        confirmation = confirmationFor(current, balance)
                    }
                    saveError = null
                }
            }
        }
    }

    private suspend fun displayedBalance(record: CoursePackageRecord): Long =
        when (val result = withContext(Dispatchers.IO) { useCases.balance(studentID, record.coursePackageID) }) {
            is ApplicationResult.Success -> result.value
            is ApplicationResult.Failure -> record.remainingCreditsCache
        }

    private fun confirmationFor(record: CoursePackageRecord, balance: Long): PackageConfirmation =
        PackageConfirmation(
            packageId = record.coursePackageID,
            message = replacementConfirmMessage(packageDisplayName(record.name, record.startDate), balance),
        )

    private fun trimmedName(): String? = name.trim().ifEmpty { null }

    var saved by mutableStateOf(false)
}

@Composable
fun CoursePackageEditorScreen(
    studentID: StudentID,
    useCases: CreditUseCases,
    clock: AppClock,
    zoneID: ZoneId,
    onBack: () -> Unit,
    onSaved: () -> Unit,
    modifier: Modifier = Modifier,
    windowInsets: WindowInsets = WindowInsets.safeDrawing,
) {
    val scope = rememberCoroutineScope()
    val state = remember(studentID) { CoursePackageEditorState(studentID, useCases, clock, zoneID) }
    val minus = painterResource(R.drawable.ic_ms_remove)
    val plus = painterResource(R.drawable.ic_ms_add)
    val warning = painterResource(R.drawable.ic_ms_warning)
    val scroll = rememberScrollState()
    LaunchedEffect(studentID) { state.reload() }
    LaunchedEffect(state.saved) {
        if (state.saved) onSaved()
    }
    Box(modifier.fillMaxSize().testTag("package-editor-root")) {
        FcPlatformShell(onBack = onBack, insets = windowInsets) {
            FcScrollBody(Modifier.testTag("package-editor-form"), scroll) {
                FcPageHeader("新建课包", Modifier.padding(bottom = FcSpacing.space4), onBack = onBack, tag = "package-editor")
                FcListRowDivider()
                FcLabelValueRow("课包名称") {
                    Box(Modifier.weight(1f).testTag("package-editor-name-slot")) {
                        FcTextField(
                            "课包名称",
                            state.name,
                            { state.name = it },
                            Modifier.testTag("package-editor-name"),
                        )
                    }
                }
                FcListRowDivider()
                FcLabelValueRow("总课时数", trailingControl = true) {
                    FcStepper(
                        "总课时数",
                        state.totalCredits,
                        1..999,
                        { state.totalCredits = it },
                        minus,
                        plus,
                        tag = "package-editor-credits",
                    )
                }
                FcListRowDivider()
                FcLabelValueRow("设置开始日期", trailingControl = true) {
                    FcToggle(
                        "设置开始日期",
                        state.hasStartDate,
                        { state.hasStartDate = it },
                        Modifier.testTag("package-editor-has-start"),
                    )
                }
                if (state.hasStartDate) {
                    FcListRowDivider()
                    FcLabelValueRow(
                        "开始日期",
                        Modifier.testTag("package-editor-start"),
                        onClick = { state.picking = PickingDate.Start },
                    ) {
                        FcText(packageDateText(state.startDate), style = FcTypography.body, color = FcColors.textPrimary)
                    }
                }
                FcListRowDivider()
                FcLabelValueRow("设置结束日期", trailingControl = true) {
                    FcToggle(
                        "设置结束日期",
                        state.hasEndDate,
                        { state.hasEndDate = it },
                        Modifier.testTag("package-editor-has-end"),
                    )
                }
                if (state.hasEndDate) {
                    FcListRowDivider()
                    FcLabelValueRow(
                        "结束日期",
                        Modifier.testTag("package-editor-end"),
                        onClick = { state.picking = PickingDate.End },
                    ) {
                        FcText(packageDateText(state.endDate), style = FcTypography.body, color = FcColors.textPrimary)
                    }
                }
                FcListRowDivider()
                val existing = state.context?.existing
                if (state.ready && existing != null) {
                    FcText(
                        replacementWarning(
                            packageDisplayName(existing.name, existing.startDate),
                            state.context?.balance ?: existing.remainingCreditsCache,
                        ),
                        Modifier.padding(vertical = FcSpacing.space2).testTag("package-editor-warning"),
                        style = FcTypography.style("callout", 400),
                        color = FcColors.statusWarning,
                    )
                }
                if (state.loadError) {
                    FcInlineResult(
                        FcResultVariant.Failure,
                        packageLoadErrorTitle,
                        packageLoadErrorDescription,
                        warning,
                        tag = "package-editor-load",
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
                state.saveError?.let { message ->
                    FcText(
                        message,
                        Modifier.padding(vertical = FcSpacing.space2).testTag("package-editor-error"),
                        style = FcTypography.style("callout", 400),
                        color = FcColors.statusDestructive,
                    )
                }
            }
            FcPinnedAction {
                FcButton(
                    "保存",
                    Modifier.testTag("package-editor-save"),
                    enabled = state.ready && !state.busy && state.confirmation == null,
                ) {
                    if (!state.ready || state.confirmation != null || !state.tryBegin()) return@FcButton
                    scope.launch {
                        try {
                            state.saveWithoutConfirmation()
                        } finally {
                            state.endBusy()
                        }
                    }
                }
            }
        }
        val pending = state.confirmation
        if (pending != null) {
            FcConfirmationDialog(
                title = "结束当前课包？",
                message = pending.message,
                confirmTitle = if (pending.packageId == null) "重新查看" else "确认结束并新建",
                onConfirm = {
                    val shownId = pending.packageId
                    if (shownId == null) {
                        if (!state.tryBegin()) return@FcConfirmationDialog
                        scope.launch {
                            try {
                                state.reloadConfirmation()
                            } finally {
                                state.endBusy()
                            }
                        }
                    } else {
                        if (!state.tryBegin()) return@FcConfirmationDialog
                        scope.launch {
                            try {
                                state.confirmShownPackage(shownId)
                            } finally {
                                state.endBusy()
                            }
                        }
                    }
                },
                onDismiss = { state.cancelConfirmation() },
                cancelTitle = "取消",
                tag = "package-replace",
            )
        }
        when (state.picking) {
            PickingDate.Start -> FcDatePickerDialog(
                initialMillis = localDateToUtcMillis(state.startDate),
                onSelect = { millis ->
                    if (millis != null) state.startDate = utcMillisToLocalDate(millis)
                    state.picking = null
                },
                onDismiss = { state.picking = null },
            )
            PickingDate.End -> FcDatePickerDialog(
                initialMillis = localDateToUtcMillis(state.endDate),
                onSelect = { millis ->
                    if (millis != null) state.endDate = utcMillisToLocalDate(millis)
                    state.picking = null
                },
                onDismiss = { state.picking = null },
            )
            null -> Unit
        }
    }
}
