package com.ignacioli.finecoach.features.exercises

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

/** Used by T013a and templates. No template route or template state is required. */
@Composable
fun ExercisePicker(
    state: ExerciseUiState,
    onSelect: suspend (ExerciseSelection) -> ApplicationResult<Unit>,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var mode by remember { mutableStateOf(RecordMode.weightReps) }
    LaunchedEffect(query) { state.search(query) }
    FcBottomSheet("添加动作", onDismiss = { if (!state.busy) onDismiss() }, modifier = Modifier.testTag("exercise-picker")) {
        Column(Modifier.fillMaxWidth().imePadding().heightIn(max = FcComponentMetrics.row * 7)
            .verticalScroll(rememberScrollState()).testTag("exercise-picker-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcSearchField("搜索动作、拼音或名称", query, { query = it }, Modifier.testTag("exercise-search"))
            state.entries.forEach { item ->
                FcListRow(state.selection(item).name, Modifier.testTag("exercise-select-${item.exerciseID.value}"),
                    subtitle = exerciseModeTitle(item.recordMode), mode = if (state.busy) FcRowMode.Unavailable("保存中") else FcRowMode.Action {
                        scope.launch { state.perform({ onSelect(state.selection(item)) }) { onDismiss() } }
                    })
            }
            ExerciseModePicker(mode, { mode = it }, !state.busy, "quick-mode")
            if (state.catalogUnavailable) FcListRow("动作库暂不可用", Modifier.testTag("exercise-catalog-unavailable"))
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("exercise-error")) }
            FcButton("仅本节使用", Modifier.testTag("exercise-session-only"), !state.busy && query.isNotBlank()) {
                scope.launch { state.perform({ onSelect(ExerciseSelection(query.trim(), mode, ExerciseSourceKind.sessionOnly, null)) }) { onDismiss() } }
            }
            FcSecondaryButton("加入动作库", Modifier.testTag("exercise-create-library"), !state.busy && query.isNotBlank()) {
                scope.launch {
                    // Explicit library creation is durable independently of the consuming feature.
                    state.perform({ state.useCases.createCustom(query, mode) }) { }
                    if (state.error == null) state.search(query)
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("exercise-picker-cancel"), !state.busy, onDismiss)
        }
    }
}

@Composable
internal fun ExerciseModePicker(mode: RecordMode, onChange: (RecordMode) -> Unit, enabled: Boolean, tag: String) {
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        RecordMode.entries.forEach { item ->
            FcFilterChip(exerciseModeTitle(item), mode == item, Modifier.testTag("$tag-${item.name}")) { if (enabled) onChange(item) }
        }
    }
}

@Composable
fun ExerciseLibraryScreen(state: ExerciseUiState, onBack: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var hidden by remember { mutableStateOf(false) }
    var edit by remember { mutableStateOf<ExerciseRecord?>(null) }
    var creating by remember { mutableStateOf(false) }
    var options by remember { mutableStateOf<ExerciseRecord?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(query, hidden, refresh) { state.search(query, hidden) }
    if (creating || edit != null) {
        CustomExerciseEditor(state, edit, { creating = false; edit = null; refresh++ })
        return
    }
    FcPlatformShell(onBack) {
        FcPageHeader("动作库", onBack = onBack, tag = "exercise-library", trailingTitle = "新建", onTrailing = { creating = true })
        Column(Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).testTag("exercise-library-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcSearchField("搜索动作或拼音", query, { query = it }, Modifier.testTag("exercise-library-search"))
            FcFilterChip("显示已隐藏动作", hidden, Modifier.testTag("exercise-show-hidden")) { hidden = !hidden }
            if (state.catalogUnavailable) FcListRow("动作库暂不可用", Modifier.testTag("exercise-catalog-unavailable"))
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("exercise-error")) }
            state.entries.forEach { item ->
                val p = state.preference(item.exerciseID)
                FcListRow(p.alias ?: item.canonicalName, Modifier.testTag("exercise-options-${item.exerciseID.value}"),
                    subtitle = if (p.isHidden || item.lifecycle == ExerciseLifecycle.archived) "已隐藏" else exerciseModeTitle(item.recordMode),
                    mode = FcRowMode.Action { options = item })
                FcListRowDivider()
            }
        }
    }
    options?.let { item ->
        val p = state.preference(item.exerciseID)
        var alias by remember(item.exerciseID) { mutableStateOf(p.alias ?: "") }
        fun update(command: UpdateExercisePreferenceCommand) {
            scope.launch { state.perform({ state.useCases.updatePreference(command) }) { options = null; refresh++ } }
        }
        fun command(aliasValue: String? = p.alias, favorite: Boolean = p.isFavorite, isHidden: Boolean = p.isHidden,
            assisted: Boolean = p.isAssisted, unilateral: Boolean? = p.isUnilateral) =
            UpdateExercisePreferenceCommand(item.exerciseID, aliasValue, favorite, isHidden, assisted, unilateral)
        FcBottomSheet("动作选项", { if (!state.busy) options = null }, skipPartiallyExpanded = true) {
            Column(Modifier.fillMaxWidth().imePadding().heightIn(max = FcComponentMetrics.row * 7)
                .verticalScroll(rememberScrollState()).testTag("exercise-options-content")) {
                FcTextField("显示名", alias, { alias = it }, Modifier.testTag("exercise-alias"))
                FcButton("保存显示名", Modifier.testTag("exercise-alias-save"), !state.busy) { update(command(aliasValue = alias)) }
                FcActionRow(if (p.isFavorite) "取消收藏" else "收藏", Modifier.testTag("exercise-favorite"), enabled = !state.busy) { update(command(favorite = !p.isFavorite)) }
                FcActionRow(if (p.isHidden) "恢复显示" else "隐藏动作", Modifier.testTag("exercise-hide"), enabled = !state.busy) { update(command(isHidden = !p.isHidden)) }
                FcActionRow(if (p.isAssisted) "取消辅助记录" else "辅助记录", Modifier.testTag("exercise-assisted"), enabled = !state.busy) { update(command(assisted = !p.isAssisted)) }
                FcActionRow(if (p.isUnilateral == true) "双侧记录" else "单侧记录", Modifier.testTag("exercise-unilateral"), enabled = !state.busy) { update(command(unilateral = p.isUnilateral != true)) }
                if (item.kind == ExerciseKind.custom) FcActionRow("编辑自定义动作", Modifier.testTag("exercise-edit"), enabled = !state.busy) { options = null; edit = item }
                state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("exercise-options-error")) }
                FcSecondaryButton("取消", Modifier.testTag("exercise-options-cancel"), !state.busy) { options = null }
            }
        }
    }
}

@Composable
fun CustomExerciseEditor(state: ExerciseUiState, existing: ExerciseRecord?, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var item by remember(existing) { mutableStateOf(existing) }
    var name by remember(existing) { mutableStateOf(existing?.canonicalName ?: "") }
    var mode by remember(existing) { mutableStateOf(existing?.recordMode ?: RecordMode.weightReps) }
    val active = item?.lifecycle != ExerciseLifecycle.archived
    val back = { if (!state.busy) onBack() }
    BackHandler(onBack = back)
    FcPlatformShell(back) {
        FcPageHeader(if (existing == null) "新建动作" else "编辑动作", onBack = back, tag = "exercise-editor")
        Column(Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).testTag("exercise-editor-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            FcTextField("动作名称", name, { name = it }, Modifier.testTag("exercise-name"), enabled = active && !state.busy)
            ExerciseModePicker(mode, { mode = it }, active && !state.busy, "exercise-mode")
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("exercise-error")) }
            FcButton("保存", Modifier.testTag("exercise-save"), active && !state.busy) {
                scope.launch { state.perform({ item?.let { state.useCases.updateCustom(it.exerciseID, name, mode) }
                    ?: state.useCases.createCustom(name, mode) }) { onBack() } }
            }
            item?.let { record ->
                FcSecondaryButton(if (active) "隐藏自定义动作" else "恢复自定义动作", Modifier.testTag("exercise-archive"), !state.busy) {
                    scope.launch { state.perform({ if (active) state.useCases.archiveCustom(record.exerciseID)
                        else state.useCases.restoreCustom(record.exerciseID) }) { item = it } }
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("exercise-editor-cancel"), !state.busy, back)
        }
    }
}
