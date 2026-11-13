package com.ignacioli.finecoach.features.exercises

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

/** State commands live here to keep this refactor within the screen file's ownership. */
internal suspend fun ExerciseUiState.createLibraryExercise(query: String, mode: RecordMode) {
    perform({ useCases.createCustom(query, mode) }) { }
    if (error == null) search(query)
}

internal suspend fun ExerciseUiState.updateLibraryPreference(command: UpdateExercisePreferenceCommand, onSaved: () -> Unit) {
    perform({ useCases.updatePreference(command) }) { onSaved() }
}

internal suspend fun ExerciseUiState.saveCustomExercise(item: ExerciseRecord?, name: String, mode: RecordMode, onSaved: () -> Unit) {
    perform({ item?.let { useCases.updateCustom(it.exerciseID, name, mode) }
        ?: useCases.createCustom(name, mode) }) { onSaved() }
}

internal suspend fun ExerciseUiState.setCustomExerciseArchived(record: ExerciseRecord, active: Boolean, onSaved: (ExerciseRecord) -> Unit) {
    perform({ if (active) useCases.archiveCustom(record.exerciseID)
        else useCases.restoreCustom(record.exerciseID) }, onSaved)
}

@Composable
fun ExercisePicker(state: ExerciseUiState, onSelect: suspend (ExerciseSelection) -> ApplicationResult<Unit>,
    onDismiss: () -> Unit) = ExercisePicker(state, onSelect, null, onDismiss = onDismiss)

/** Used by T013a and templates. No template route or template state is required. */

@Composable
fun ExercisePicker(
    state: ExerciseUiState,
    onSelect: suspend (ExerciseSelection) -> ApplicationResult<Unit>,
    studentID: StudentID?,
    isTemplateContext: Boolean = false,
    onTemplate: (() -> Unit)? = null,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var mode by remember { mutableStateOf(RecordMode.weightReps) }
    var muscle by remember { mutableStateOf<String?>(null) }
    var equipment by remember { mutableStateOf<String?>(null) }
    var filters by remember { mutableStateOf(false) }
    LaunchedEffect(query, studentID, isTemplateContext) {
        state.reload(query, studentID = studentID, recentEnabled = !isTemplateContext)
    }

    FcBottomSheet("添加动作", onDismiss = { if (!state.busy) onDismiss() }, modifier = Modifier.testTag(if (onTemplate != null) "conformance:Sheet" else "exercise-picker"), skipPartiallyExpanded = true, panelFlow = onTemplate != null) {
Column(Modifier.fillMaxWidth().weight(1f, fill = false).then(if (onTemplate != null) Modifier.testTag("exercise-picker") else Modifier), verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
if (onTemplate != null) Row(Modifier.fillMaxWidth().padding(horizontal = FcSpacing.space4).testTag("session-add-tabs"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
    FcFilterChip("动作库", true, Modifier.testTag("session-add-library"), visualModifier = Modifier.testTag("conformance:Tab · 动作库")) {}
    FcFilterChip("从模板", false, Modifier.testTag("session-apply-template"), visualModifier = Modifier.testTag("conformance:Tab · 从模板"), onClick = onTemplate)
}
Column(Modifier.fillMaxWidth().imePadding().then(if (onTemplate != null) Modifier.weight(1f, fill = false) else Modifier.heightIn(max = FcComponentMetrics.row * 7))
            .verticalScroll(rememberScrollState()).testTag("exercise-picker-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            Box(Modifier.then(if (onTemplate != null) Modifier.padding(horizontal = FcSpacing.space4) else Modifier)) { ExerciseSearchRow(query, { query = it }, equipment != null, "exercise-search", "exercise-picker", showFilters = !isTemplateContext) { filters = true } }
            if (!isTemplateContext) ExerciseMuscleChips(muscle, { muscle = it }, "exercise-picker")
            Column(Modifier.then(if (onTemplate != null) Modifier.padding(horizontal = FcSpacing.space4) else Modifier)) {
            ExerciseBrowseRows(state, query, muscle, equipment, studentID, "exercise-picker",
                { "exercise-select-${it.exerciseID.value}" }, !state.busy, showRecent = !isTemplateContext) { item ->
                scope.launch { state.perform({ onSelect(state.selection(item)) }) { onDismiss() } }
            }
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
                    state.createLibraryExercise(query, mode)
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("exercise-picker-cancel"), !state.busy, onDismiss)
        }
    }
    }
    if (filters && !isTemplateContext) ExerciseFilterSheet(equipment, { equipment = it }, null, {}, "exercise-picker", { filters = false })
}

/** Feature composition of existing DS components; both surfaces share the same browse anatomy. */
@Composable
private fun ExerciseSearchRow(query: String, onQuery: (String) -> Unit, active: Boolean,
    searchTag: String, prefix: String, showFilters: Boolean = true, onFilters: () -> Unit) {
    Row(Modifier.fillMaxWidth().testTag("$prefix-search-row"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcSearchField("搜索动作", query, onQuery, Modifier.weight(1f).testTag(searchTag),
            visualModifier = if (prefix == "exercise-library" || prefix == "exercise-picker") Modifier.testTag("conformance:Search") else Modifier)
        if (showFilters) FcTitleIconButton("筛选", painterResource(if (active) R.drawable.ic_ms_filter_alt_filled else R.drawable.ic_ms_filter_alt),
            Modifier.testTag("$prefix-filter").semantics { stateDescription = if (active) "已筛选" else "" },
            visualModifier = if (prefix == "exercise-library" || prefix == "exercise-picker") Modifier.testTag("conformance:icon / filter") else Modifier, onClick = onFilters)
    }
}

@Composable
private fun ExerciseMuscleChips(muscle: String?, onMuscle: (String?) -> Unit, prefix: String) {
    Row(Modifier.fillMaxWidth().testTag("$prefix-muscles").horizontalScroll(rememberScrollState())
        .then(if (prefix == "exercise-library" || prefix == "exercise-picker") Modifier.padding(horizontal = FcSpacing.space4) else Modifier),
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcFilterChip("全部", muscle == null, Modifier.testTag("$prefix-muscle-all"),
            visualModifier = if (prefix == "exercise-library" || prefix == "exercise-picker") Modifier.testTag("conformance:Chip") else Modifier) { onMuscle(null) }
        ExerciseBrowse.muscles.forEach { value ->
            FcFilterChip(value, muscle == value, Modifier.testTag("$prefix-muscle-$value"),
                visualModifier = if (prefix == "exercise-library" || prefix == "exercise-picker") Modifier.testTag("conformance:Chip") else Modifier) { onMuscle(value) }
        }
    }
}

@Composable
private fun ExerciseFilterSheet(equipment: String?, onEquipment: (String?) -> Unit, hidden: Boolean?,
    onHidden: (Boolean) -> Unit, prefix: String, onDismiss: () -> Unit) {
    FcBottomSheet("筛选", onDismiss, Modifier.testTag("$prefix-filter-sheet"), skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 7)
            .verticalScroll(rememberScrollState()).testTag("$prefix-filter-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcSectionLabel("器械")
            FlowRow(Modifier.fillMaxWidth().testTag("$prefix-equipment"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                FcFilterChip("全部", equipment == null, Modifier.testTag("$prefix-equipment-all")) { onEquipment(null) }
                ExerciseBrowse.equipment.forEach { value ->
                    FcFilterChip(value, equipment == value, Modifier.testTag("$prefix-equipment-$value")) { onEquipment(value) }
                }
            }
            if (hidden != null) {
                FcListRowDivider()
                FcLabelValueRow("显示已隐藏", trailingControl = true) {
                    FcToggle("显示已隐藏", hidden, onHidden, Modifier.testTag("exercise-show-hidden"))
                }

            }
            FcLinkButton("完成", Modifier.fillMaxWidth().testTag("$prefix-filter-done"), onClick = onDismiss)
        }
    }
}

@Composable
private fun ExerciseBrowseRows(state: ExerciseUiState, query: String, muscle: String?, equipment: String?,
    studentID: StudentID?, prefix: String, rowTag: (ExerciseRecord) -> String, enabled: Boolean = true, showRecent: Boolean = true,
    onClick: (ExerciseRecord) -> Unit) {
    val recent = state.recentEntries
    val library = prefix == "exercise-library" || (prefix == "exercise-picker" && showRecent)
    val divider = if (library) Modifier.testTag("conformance:Divider") else Modifier
    @Composable fun row(item: ExerciseRecord, tag: String) {
        val icon = state.metadata[item.exerciseID].takeIf { item.kind == ExerciseKind.builtIn }?.let {
            FcEquipmentIcon.icon(it.equipmentClass, it.primaryMuscleGroup)
        }
        FcListRow(state.selection(item).name, Modifier.testTag(tag), subtitle = state.subtitle(item),
            leading = state.metadata[item.exerciseID].takeIf { item.kind == ExerciseKind.builtIn }?.let { facet ->
                FcEquipmentIcon.icon(facet.equipmentClass, facet.primaryMuscleGroup)?.let { painterResource(it.drawable) }
            }, reservesLeading = true, favorite = state.preference(item.exerciseID).isFavorite,
            exerciseLibrary = library,
            leadingModifier = if (library && icon != null) Modifier.testTag("conformance:icon / ${icon.name.replace('_', '-')}") else Modifier,
            disclosureVisualTag = if (library) "conformance:›" else null,
            mode = if (enabled) FcRowMode.Action { onClick(item) } else FcRowMode.Unavailable("保存中"))
        FcListRowDivider(divider)
    }
    state.historyError?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("$prefix-history-error")) }
    if (showRecent && ExerciseBrowse.showsRecent(query, muscle, equipment, recent)) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcSectionLabel("最近练过", Modifier.testTag("$prefix-recent"))
            Column(Modifier.fillMaxWidth()) {
                FcListRowDivider(divider)
                recent.forEach { row(it, "$prefix-recent-${it.exerciseID.value}") }
            }
        }
        Spacer(Modifier.height(FcSpacing.space4))
    }
    state.sections(muscle, equipment).forEach { section ->
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcSectionLabel("${section.title} · ${section.entries.size}", Modifier.testTag("$prefix-section-${section.id}"))
            Column(Modifier.fillMaxWidth()) {
                FcListRowDivider(divider)
                section.entries.forEach { row(it, rowTag(it)) }
            }
        }
        Spacer(Modifier.height(FcSpacing.space4))
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
    var muscle by remember { mutableStateOf<String?>(null) }
    var equipment by remember { mutableStateOf<String?>(null) }
    var filters by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    LaunchedEffect(query, hidden, refresh) { state.reload(query, hidden) }
    if (creating || edit != null) {
        CustomExerciseEditor(state, edit, { creating = false; edit = null; refresh++ })
        return
    }
    FcPlatformShell(onBack) {
        FcPageHeader("动作库", onBack = onBack, tag = "exercise-library", backVisualTag = "conformance:Back", trailingTitle = "＋ 自定义", onTrailing = { creating = true })
        Spacer(Modifier.height(FcSpacing.space4))
        BoxWithConstraints(Modifier.fillMaxWidth().weight(1f)) {
            Column(Modifier.requiredWidth(maxWidth + FcSpacing.space8).imePadding().verticalScroll(rememberScrollState()).testTag("exercise-library-content"),
                verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
                Box(Modifier.padding(horizontal = FcSpacing.space4)) {
                    ExerciseSearchRow(query, { query = it }, equipment != null || hidden, "exercise-library-search", "exercise-library") { filters = true }
                }
                ExerciseMuscleChips(muscle, { muscle = it }, "exercise-library")
                Column(Modifier.padding(horizontal = FcSpacing.space4)) {
                    if (state.catalogUnavailable) FcListRow("动作库暂不可用", Modifier.testTag("exercise-catalog-unavailable"))
                    state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("exercise-error")) }
                    ExerciseBrowseRows(state, query, muscle, equipment, null, "exercise-library",
                        { "exercise-options-${it.exerciseID.value}" }) { options = it }
                }
            }
        }
    }
    if (filters) ExerciseFilterSheet(equipment, { equipment = it }, hidden, { hidden = it }, "exercise-library", { filters = false })
    options?.let { item ->

        val p = state.preference(item.exerciseID)
        var alias by remember(item.exerciseID) { mutableStateOf(p.alias ?: "") }
        fun update(command: UpdateExercisePreferenceCommand) {
            scope.launch { state.updateLibraryPreference(command) { options = null; refresh++ } }
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
                scope.launch { state.saveCustomExercise(item, name, mode) { onBack() } }
            }
            item?.let { record ->
                FcSecondaryButton(if (active) "隐藏自定义动作" else "恢复自定义动作", Modifier.testTag("exercise-archive"), !state.busy) {
                    scope.launch { state.setCustomExerciseArchived(record, active) { item = it } }
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("exercise-editor-cancel"), !state.busy, back)
        }
    }
}
