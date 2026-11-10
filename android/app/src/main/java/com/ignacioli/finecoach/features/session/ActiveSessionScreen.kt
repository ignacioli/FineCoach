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
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.features.templates.*
import kotlinx.coroutines.launch
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

@Composable
fun ActiveSessionScreen(state: ActiveSessionUiState, id: SessionID, exercises: ExerciseUiState, templates: TemplateUiState,
    onBack: () -> Unit, onFinish: () -> Unit, recoverySlot: @Composable () -> Unit = {}, restSlot: @Composable () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    var picker by remember { mutableStateOf(false) }
    var review by remember { mutableStateOf(false) }
    var apply by remember { mutableStateOf(false) }
    var sectionForm by remember { mutableStateOf(false) }
    var section by remember { mutableStateOf<SectionRecord?>(null) }
    var sectionOptions by remember { mutableStateOf<SectionRecord?>(null) }
    var exerciseOptions by remember { mutableStateOf<SessionExerciseRecord?>(null) }
    var setOptions by remember { mutableStateOf<TrainingSetRecord?>(null) }
    var editor by remember { mutableStateOf<SessionExerciseRecord?>(null) }
    var editing by remember { mutableStateOf<TrainingSetRecord?>(null) }
    var moving by remember { mutableStateOf<SessionExerciseID?>(null) }
    var confirmSection by remember { mutableStateOf<SectionRecord?>(null) }
    var deleteExercise by remember { mutableStateOf<SessionExerciseRecord?>(null) }
    val content = state.content?.takeIf { it.session.sessionID == id }
    val back = { if (!state.busy) onBack() }
    LaunchedEffect(id) { state.load(id); exercises.search("") }
    val lifecycle = LocalLifecycleOwner.current
    DisposableEffect(lifecycle, id) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) scope.launch { state.checkpoint(interruption = true) }
        }
        lifecycle.lifecycle.addObserver(observer)
        onDispose { lifecycle.lifecycle.removeObserver(observer) }
    }
    fun change(action: (SectionedSession) -> SectionedSession, done: () -> Unit = {}) {
        scope.launch { if (state.mutate(action) is ApplicationResult.Success) done() }
    }
    fun openEditor(row: SessionExerciseRecord, set: TrainingSetRecord? = null) { editing = set; editor = row }
    FcPlatformShell(back) {
        FcPageHeader("训练记录", onBack = back, tag = "active-session")
        SaveStatusView(state)
        recoverySlot()
        Column(Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).testTag("active-session-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("active-session-error")) }
            if (content != null) {
                if (content.session.durationNeedsReview) FcButton("确认训练时长", Modifier.testTag("session-review-duration"), !state.busy) { review = true }
                val axis = (content.sections.map { it.orderIndex to it } + content.exercises.filter { it.sectionID == null }.map { it.orderIndex to it }).sortedBy { it.first }
                @Composable fun exercise(row: SessionExerciseRecord) {
                    FcListRow(row.displayNameSnapshot, Modifier.testTag("session-exercise-${row.sessionExerciseID.value}"),
                        mode = FcRowMode.Action { openEditor(row) })
                    state.previous[row.sessionExerciseID]?.let { FcListRow("上次：${it.toDomain().displaySummary()}", Modifier.testTag("session-previous-${row.sessionExerciseID.value}")) }
                    row.sets.sortedBy { it.orderIndex }.forEachIndexed { index, set ->
                        val deleted = state.deleted
                        if (deleted?.sessionExerciseID == row.sessionExerciseID && deleted.orderIndex.toInt() == index)
                            FcUndoRow("已删除第 ${index + 1} 组", tag = "session-deleted") { scope.launch { state.restoreSet() } }
                        FcSetRow(index + 1, set.toDomain().displaySummary(), set.state == SetRecordingState.completed,
                            set.state == SetRecordingState.pending,
                            { change({ it.copy(session = it.session.confirmingSet(set.trainingSetID, state.clock.now())) }) },
                            { openEditor(row, set) }, Modifier.testTag("session-set-${set.trainingSetID.value}"), !state.busy, "session-set-${set.trainingSetID.value}")
                        FcLinkButton("组操作", Modifier.testTag("session-set-options-${set.trainingSetID.value}"), !state.busy) { setOptions = set }
                    }
                    if (state.deleted?.sessionExerciseID == row.sessionExerciseID && state.deleted!!.orderIndex.toInt() >= row.sets.size)
                        FcUndoRow("已删除一组", tag = "session-deleted") { scope.launch { state.restoreSet() } }
                    FcLinkButton("动作操作", Modifier.testTag("session-exercise-options-${row.sessionExerciseID.value}"), !state.busy) { exerciseOptions = row }
                }
                axis.forEach { (_, item) -> when (item) {
                    is SectionRecord -> {
                        FcGroupEntryRow(item.name, content.exercises.count { it.sectionID == item.sectionID }, Modifier.testTag("session-section-${item.sectionID.value}")) { sectionOptions = item }
                        content.exercises.filter { it.sectionID == item.sectionID }.sortedBy { it.orderIndex }.forEach { exercise(it) }
                    }
                    is SessionExerciseRecord -> exercise(item)
                } }
                FcButton("添加动作", Modifier.testTag("session-add-exercise"), !state.busy) { picker = true }
                FcSecondaryButton("应用模板", Modifier.testTag("session-apply-template"), !state.busy) { apply = true }
                FcSecondaryButton("新建分段", Modifier.testTag("session-add-section"), !state.busy) { section = null; sectionForm = true }
            }
        }
        restSlot()
        RestTimerView(state.rests, id)
        FcButton("结束训练", Modifier.testTag("session-finish"), content != null && !state.busy && state.saveState != FcSaveState.Failed) {
            if (content?.session?.durationNeedsReview == true) review = true else onFinish()
        }
    }
    if (picker) ExercisePicker(exercises, state::addExercise, studentID = content?.session?.studentID) { picker = false }
    if (apply && content != null) ApplyTemplateSheet(templates, content.session, state::accept) { apply = false }
    if (sectionForm) {
        var name by remember(section) { mutableStateOf(section?.name ?: "") }
        FcBottomSheet(if (section == null) "新建分段" else "重命名分段", { if (!state.busy) sectionForm = false }, skipPartiallyExpanded = true) {
            Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).testTag("session-section-form-content")) {
                FcTextField("分段名称", name, { name = it }, Modifier.testTag("session-section-name"))
                state.error?.let { FcListRow(exerciseErrorTitle(it)) }
                FcButton("保存分段", Modifier.testTag("session-section-save"), !state.busy) {
                    change({ original -> section?.let { original.renamingSection(it.sectionID, name, state.clock.now()) }
                        ?: original.addingSection(state.ids.newSectionID(), name, state.clock.now()) }) { sectionForm = false }
                }
                FcSecondaryButton("取消", Modifier.testTag("session-section-cancel"), !state.busy) { sectionForm = false }
            }
        }
    }
    sectionOptions?.let { row ->
        FcBottomSheet("分段操作", { sectionOptions = null }, skipPartiallyExpanded = true) {
            FcActionRow("重命名", Modifier.testTag("session-section-rename"), enabled = !state.busy) { section = row; sectionOptions = null; sectionForm = true }
            listOf(-1 to "上移", 1 to "下移").forEach { (delta, title) -> FcActionRow(title,
                Modifier.testTag(if (delta < 0) "session-section-up" else "session-section-down"), enabled = !state.busy) {
                change({ it.reordering(sessionShiftAxis(content!!, row.sectionID.value, delta), state.clock.now()) }) { sectionOptions = null }
            } }
            FcActionRow("删除分段", Modifier.testTag("session-section-delete"), destructive = true, enabled = !state.busy) {
                sectionOptions = null
                if (content!!.exercises.none { it.sectionID == row.sectionID })
                    change({ it.deletingSection(row.sectionID, SessionSectionDeletionDisposition.DeleteWithExercises, state.clock.now()) })
                else confirmSection = row
            }
            FcSecondaryButton("取消", Modifier.testTag("session-section-options-cancel")) { sectionOptions = null }
        }
    }
    exerciseOptions?.let { row ->
        FcBottomSheet("动作操作", { exerciseOptions = null }, skipPartiallyExpanded = true) {
            FcActionRow("移入分段", Modifier.testTag("session-exercise-move"), enabled = !state.busy) { moving = row.sessionExerciseID; exerciseOptions = null }
            listOf(-1 to "上移", 1 to "下移").forEach { (delta, title) -> FcActionRow(title,
                Modifier.testTag(if (delta < 0) "session-exercise-up" else "session-exercise-down"), enabled = !state.busy) {
                change({ it.reordering(sessionShiftAxis(content!!, row.sessionExerciseID.value, delta), state.clock.now()) }) { exerciseOptions = null }
            } }
            FcActionRow("删除动作", Modifier.testTag("session-exercise-delete"), destructive = true, enabled = !state.busy) {
                exerciseOptions = null
                if (row.sets.any { it.state == SetRecordingState.completed }) deleteExercise = row
                else scope.launch { state.removeExercise(row.sessionExerciseID, false) }
            }
            FcSecondaryButton("取消", Modifier.testTag("session-exercise-options-cancel")) { exerciseOptions = null }
        }
    }
    if (moving != null && content != null) FcBottomSheet("移入分段", { moving = null }, skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 6).verticalScroll(rememberScrollState())) {
            (listOf<SectionRecord?>(null) + content.sections).forEach { target ->
                FcActionRow(target?.name ?: "未分段", Modifier.testTag("session-move-${target?.sectionID?.value ?: "unsectioned"}"), enabled = !state.busy) {
                    change({ it.movingExercise(moving!!, target?.sectionID, state.clock.now()) }) { moving = null }
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("session-move-cancel")) { moving = null }
        }
    }
    confirmSection?.let { row -> FcConfirmationDialog("删除分段“${row.name}”", "分段内的动作将移到“未分段”，动作和训练组会保留。", "删除分段",
        { change({ it.deletingSection(row.sectionID, SessionSectionDeletionDisposition.MoveExercisesTo(null), state.clock.now()) }) { confirmSection = null } },
        { if (!state.busy) confirmSection = null }, tag = "session-delete-section-confirm") }
    deleteExercise?.let { row ->
        FcPlatformShell({ if (!state.busy) deleteExercise = null }) {
            FcPageHeader("删除动作", onBack = { if (!state.busy) deleteExercise = null }, tag = "session-delete-exercise")
            FcListRow("该动作包含已完成组，删除后无法恢复。")
            state.error?.let { FcListRow(exerciseErrorTitle(it)) }
            FcButton("删除动作", Modifier.testTag("session-delete-exercise-confirm"), !state.busy) {
                scope.launch { if (state.removeExercise(row.sessionExerciseID, true) is ApplicationResult.Success) deleteExercise = null }
            }
            FcSecondaryButton("取消", Modifier.testTag("session-delete-exercise-cancel"), !state.busy) { deleteExercise = null }
        }
    }
    setOptions?.let { set -> FcBottomSheet("组操作", { setOptions = null }, skipPartiallyExpanded = true) {
        FcActionRow("编辑", Modifier.testTag("session-set-edit"), enabled = !state.busy) { openEditor(content!!.exercises.first { it.sessionExerciseID == set.sessionExerciseID }, set); setOptions = null }
        FcActionRow("复制", Modifier.testTag("session-set-copy"), enabled = !state.busy) {
            change({ it.copy(session = it.session.copyingSet(set.trainingSetID, state.ids.newTrainingSetID(), state.clock.now())) }) { setOptions = null }
        }
        if (set.state == SetRecordingState.completed) FcActionRow("撤回确认", Modifier.testTag("session-set-unconfirm"), enabled = !state.busy) {
            change({ it.copy(session = it.session.undoingSet(set.trainingSetID, state.clock.now())) }) { setOptions = null }
        }
        FcActionRow("删除组", Modifier.testTag("session-set-delete"), destructive = true, enabled = !state.busy) {
            scope.launch { state.deleteSet(set.toDomain()); if (state.error == null) setOptions = null }
        }
        FcSecondaryButton("取消", Modifier.testTag("session-set-options-cancel")) { setOptions = null }
    } }
    editor?.let { row -> SetEditor(state, row, editing,
        row.sourceID?.let { exercises.preference(it).isUnilateral } == true,
        row.sourceID?.let { exercises.preference(it).isAssisted } == true) { editor = null } }
    if (review) SessionRecoveryReview(state, { review = false }, { review = false })
}

/** Sections move as blocks; members move only inside their section. */
internal fun sessionShiftAxis(content: SessionContentRecord, key: String, delta: Int): List<SessionSectionAxisItem> {
    val blocks = (content.sections.map { section -> section.orderIndex to
        (listOf<SessionSectionAxisItem>(SessionSectionAxisItem.Section(section.sectionID)) + content.exercises
            .filter { it.sectionID == section.sectionID }.sortedBy { it.orderIndex }.map { SessionSectionAxisItem.Exercise(it.sessionExerciseID.value) }) } +
        content.exercises.filter { it.sectionID == null }.map { it.orderIndex to listOf<SessionSectionAxisItem>(SessionSectionAxisItem.Exercise(it.sessionExerciseID.value)) })
        .sortedBy { it.first }.map { it.second.toMutableList() }.toMutableList()
    val row = content.exercises.firstOrNull { it.sessionExerciseID.value == key }
    if (row?.sectionID != null) {
        val block = blocks.first { it.any { item -> item is SessionSectionAxisItem.Exercise && item.id == key } }
        val index = block.indexOfFirst { it is SessionSectionAxisItem.Exercise && it.id == key }
        if (index + delta in 1 until block.size) java.util.Collections.swap(block, index, index + delta)
    } else {
        val index = blocks.indexOfFirst { block -> when (val item = block.first()) {
            is SessionSectionAxisItem.Section -> item.id.value == key
            is SessionSectionAxisItem.Exercise -> item.id == key
        } }
        if (index >= 0 && index + delta in blocks.indices) java.util.Collections.swap(blocks, index, index + delta)
    }
    return blocks.flatten()
}
