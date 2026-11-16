package com.ignacioli.finecoach.features.templates

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
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.navigation.S1Routes
import kotlinx.coroutines.launch

@Composable
fun TemplateListScreen(state: TemplateUiState, onNavigate: (String) -> Unit, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var create by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    LaunchedEffect(state) { state.list() }
    FcPlatformShell(onBack) {
        FcPageHeader("训练模板", onBack = onBack, tag = "templates")
        FcScrollBody(Modifier.testTag("template-list-content")) {
            FcListRow("跨学员使用；应用后可单独修改")
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("template-error")) }
            state.templates.forEach { item ->
                FcListRow(item.name, Modifier.testTag("template-open-${item.templateID.value}"),
                    subtitle = templateListMeta(item.trainingFocus, state.exerciseCounts[item.templateID]),
                    mode = FcRowMode.Action { onNavigate(S1Routes.templateDetail(item.templateID)) })
                FcListRowDivider()
            }
        }
        FcPinnedAction {
            FcButton("新建模板", Modifier.testTag("template-new")) { name = ""; create = true }
        }
    }
    if (create) FcBottomSheet("新建模板", { if (!state.busy) create = false }) {
        Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).testTag("template-create-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcTextField("模板名称", name, { name = it }, Modifier.testTag("template-create-name"), enabled = !state.busy)
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("template-create-error")) }
            FcButton("创建", Modifier.testTag("template-create-save"), !state.busy) {
                scope.launch { state.create(name) {
                    create = false; onNavigate(S1Routes.templateDetail(it.templateID))
                } }
            }
            FcSecondaryButton("取消", Modifier.testTag("template-create-cancel"), !state.busy) { create = false }
        }
    }
}

/** T013a supplies a session snapshot; no write happens until an explicit 应用 tap. */
@Composable
fun ApplyTemplateSheet(state: TemplateUiState, target: SessionRecord, onApplied: (SessionContentRecord) -> Unit, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var applying by remember(target.sessionID) { mutableStateOf(false) }
    LaunchedEffect(state, target.sessionID) { state.list() }
    FcBottomSheet("应用模板", { if (!applying) onDismiss() }) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 7).verticalScroll(rememberScrollState())
            .testTag("template-apply-content")) {
            state.templates.forEach { template ->
                FcActionRow("应用 ${template.name}", Modifier.testTag("template-apply-${template.templateID.value}"), enabled = !state.busy) {
                    applying = true
                    scope.launch {
                        try {
                            state.apply(template, target) { onApplied(it); onDismiss() }
                        } finally { applying = false }
                    }
                }
            }
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("template-apply-error")) }
            FcSecondaryButton("取消", Modifier.testTag("template-apply-cancel"), !applying, onDismiss)
        }
    }
}

@Composable
fun TemplateEditorScreen(state: TemplateUiState, id: TemplateID, exercises: ExerciseUiState, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var picker by remember { mutableStateOf(false) }
    var metadata by remember { mutableStateOf(false) }
    var sectionForm by remember { mutableStateOf(false) }
    var renameSection by remember { mutableStateOf<SectionRecord?>(null) }
    var sectionOptions by remember { mutableStateOf<SectionRecord?>(null) }
    var exerciseOptions by remember { mutableStateOf<TemplateExerciseRecord?>(null) }
    var moving by remember { mutableStateOf<TemplateExerciseID?>(null) }
    var confirmSection by remember { mutableStateOf<SectionRecord?>(null) }
    var deleteTemplate by remember { mutableStateOf(false) }
    var removeExercise by remember { mutableStateOf<TemplateExerciseID?>(null) }
    var planned by remember { mutableStateOf<TemplateExerciseRecord?>(null) }
    val back = { if (!state.busy) onBack() }
    LaunchedEffect(id) { state.load(id) }
    val content = state.content?.takeIf { it.template.templateID == id }
    fun change(action: suspend () -> ApplicationResult<Unit>, done: () -> Unit = {}) {
        scope.launch { if (action() is ApplicationResult.Success) done() }
    }
    FcPlatformShell(back) {
        FcPageHeader(content?.template?.name ?: "训练模板", onBack = back, tag = "template-editor",
            trailingTitle = "编辑", trailingEnabled = content != null && !state.busy, onTrailing = { metadata = true })
        Column(Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).testTag("template-editor-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("template-error")) }
            if (content != null) {
                // Shared order axis: section headers contain their members; unsectioned rows retain their position.
                val axis = (content.sections.map { it.orderIndex to it } +
                    content.exercises.filter { it.sectionID == null }.map { it.orderIndex to it }).sortedBy { it.first }
                axis.forEach { (_, value) ->
                    if (value is SectionRecord) {
                        FcGroupEntryRow(value.name, content.exercises.count { it.sectionID == value.sectionID },
                            Modifier.testTag("template-section-${value.sectionID.value}")) { sectionOptions = value }
                        content.exercises.filter { it.sectionID == value.sectionID }.sortedBy { it.orderIndex }.forEach { row ->
                            FcListRow(row.displayNameSnapshot, Modifier.testTag("template-exercise-${row.templateExerciseID.value}"),
                                subtitle = "${row.plannedSets.size} 个计划组", indented = true, mode = FcRowMode.Action { exerciseOptions = row })
                        }
                    } else if (value is TemplateExerciseRecord) FcListRow(value.displayNameSnapshot,
                        Modifier.testTag("template-exercise-${value.templateExerciseID.value}"), subtitle = "${value.plannedSets.size} 个计划组",
                        mode = FcRowMode.Action { exerciseOptions = value })
                }
                FcButton("添加动作", Modifier.testTag("template-add-exercise"), !state.busy) { picker = true }
                FcSecondaryButton("新建分段", Modifier.testTag("template-add-section"), !state.busy) { renameSection = null; sectionForm = true }
                FcActionRow("删除模板", Modifier.testTag("template-delete"), destructive = true, enabled = !state.busy) { deleteTemplate = true }
            }
        }
    }
    if (picker) ExercisePicker(exercises, state::addExercise, studentID = null, isTemplateContext = true) { picker = false }
    if (metadata && content != null) {
        var name by remember { mutableStateOf(content.template.name) }
        var focus by remember { mutableStateOf(content.template.trainingFocus) }
        FcBottomSheet("编辑模板", { if (!state.busy) metadata = false }) {
            Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).testTag("template-metadata-content")) {
                FcTextField("模板名称", name, { name = it }, Modifier.testTag("template-name"), enabled = !state.busy)
                FcBodyPartPicker(focus.map { BodyPart.entries.indexOf(it) }.toSet(), { index ->
                    if (!state.busy) { val part = BodyPart.entries[index]; focus = if (part in focus) focus - part else focus + part }
                }, tag = "template-focus")
                state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("template-metadata-error")) }
                FcButton("保存", Modifier.testTag("template-save"), !state.busy) { scope.launch { state.saveMetadata(name, focus) { metadata = false } } }
                FcSecondaryButton("取消", Modifier.testTag("template-metadata-cancel"), !state.busy) { metadata = false }
            }
        }
    }
    if (sectionForm) {
        var name by remember(renameSection) { mutableStateOf(renameSection?.name ?: "") }
        FcBottomSheet(if (renameSection == null) "新建分段" else "重命名分段", { if (!state.busy) sectionForm = false }) {
            Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).testTag("template-section-form-content")) {
                FcTextField("分段名称", name, { name = it }, Modifier.testTag("template-section-name"), enabled = !state.busy)
                state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("template-section-error")) }
                FcButton("保存分段", Modifier.testTag("template-section-save"), !state.busy) {
                    change({ state.saveSection(renameSection?.sectionID, name) }) { sectionForm = false }
                }
                FcSecondaryButton("取消", Modifier.testTag("template-section-cancel"), !state.busy) { sectionForm = false }
            }
        }
    }
    sectionOptions?.let { section ->
        FcBottomSheet("分段操作", { sectionOptions = null }) {
            FcActionRow("重命名", Modifier.testTag("template-section-rename"), enabled = !state.busy) { renameSection = section; sectionOptions = null; sectionForm = true }
            FcActionRow("上移", Modifier.testTag("template-section-up"), enabled = !state.busy) {
                change({ state.reorder(content!!, section.sectionID.value, -1) }) { sectionOptions = null }
            }
            FcActionRow("下移", Modifier.testTag("template-section-down"), enabled = !state.busy) {
                change({ state.reorder(content!!, section.sectionID.value, 1) }) { sectionOptions = null }
            }
            FcActionRow("删除分段", Modifier.testTag("template-section-delete"), destructive = true, enabled = !state.busy) {
                sectionOptions = null
                if (content!!.exercises.none { it.sectionID == section.sectionID }) {
                    change({ state.deleteSection(section.sectionID, SessionSectionDeletionDisposition.DeleteWithExercises) })
                } else confirmSection = section
            }
            FcSecondaryButton("取消", Modifier.testTag("template-section-options-cancel")) { sectionOptions = null }
        }
    }
    exerciseOptions?.let { row ->
        FcBottomSheet("动作操作", { exerciseOptions = null }, skipPartiallyExpanded = true) {
            FcActionRow("计划组", Modifier.testTag("template-planned-sets"), enabled = !state.busy) { planned = row; exerciseOptions = null }
            FcActionRow("移入分段", Modifier.testTag("template-exercise-move"), enabled = !state.busy) { moving = row.templateExerciseID; exerciseOptions = null }
            FcActionRow("上移", Modifier.testTag("template-exercise-up"), enabled = !state.busy) {
                change({ state.reorder(content!!, row.templateExerciseID.value, -1) }) { exerciseOptions = null }
            }
            FcActionRow("下移", Modifier.testTag("template-exercise-down"), enabled = !state.busy) {
                change({ state.reorder(content!!, row.templateExerciseID.value, 1) }) { exerciseOptions = null }
            }
            FcActionRow("移除动作", Modifier.testTag("template-exercise-remove"), destructive = true, enabled = !state.busy) { removeExercise = row.templateExerciseID; exerciseOptions = null }
            FcSecondaryButton("取消", Modifier.testTag("template-exercise-options-cancel")) { exerciseOptions = null }
        }
    }
    if (moving != null && content != null) SectionTargetSheet(content.sections, state.busy, "template-move", { moving = null }) { target ->
        change({ state.moveExercise(moving!!, target) }) { moving = null }
    }
    confirmSection?.let { section ->
        FcConfirmationDialog("删除分段“${section.name}”", "分段内的动作将移到“未分段”，动作和计划组会保留。", "删除分段",
            { change({ state.deleteSection(section.sectionID, SessionSectionDeletionDisposition.MoveExercisesTo(null)) }) { confirmSection = null } },
            { if (!state.busy) confirmSection = null }, tag = "template-delete-section-confirm")
    }
    removeExercise?.let { exercise -> FcConfirmationDialog("移除动作", "删除该动作的计划组。", "移除",
        { change({ state.removeExercise(exercise) }) { removeExercise = null } }, { if (!state.busy) removeExercise = null }, tag = "template-remove-confirm") }
    if (deleteTemplate) FcConfirmationDialog("删除模板", "已应用到训练的独立记录不受影响。", "删除", {
        scope.launch { state.delete(id) { deleteTemplate = false; onBack() } }
    }, { if (!state.busy) deleteTemplate = false }, tag = "template-delete-confirm")
    planned?.let { row -> PlannedSetsSheet(state, row) { planned = null } }
}

@Composable
private fun SectionTargetSheet(sections: List<SectionRecord>, busy: Boolean, tag: String, onDismiss: () -> Unit, onSelect: (SectionID?) -> Unit) {
    FcBottomSheet("移入分段", { if (!busy) onDismiss() }) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 6).verticalScroll(rememberScrollState()).testTag("$tag-content")) {
            FcActionRow("未分段", Modifier.testTag("$tag-unsectioned"), enabled = !busy) { onSelect(null) }
            sections.forEach { target -> FcActionRow(target.name, Modifier.testTag("$tag-${target.sectionID.value}"), enabled = !busy) { onSelect(target.sectionID) } }
            FcSecondaryButton("取消", Modifier.testTag("$tag-cancel"), !busy, onDismiss)
        }
    }
}
