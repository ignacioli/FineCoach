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

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ActiveSessionScreen(state: ActiveSessionUiState, id: SessionID, exercises: ExerciseUiState, templates: TemplateUiState,
    onBack: () -> Unit, onFinish: () -> Unit, recoverySlot: @Composable () -> Unit = {}, restSlot: @Composable () -> Unit = {}, students: StudentRepositoryPort? = null) {
    val scope = rememberCoroutineScope()
    var addSheet by remember { mutableStateOf(false) }
    var picker by remember { mutableStateOf(false) }
    var revealed by remember { mutableStateOf<String?>(null) }
    var review by remember { mutableStateOf(false) }
    var apply by remember { mutableStateOf(false) }
    var sectionForm by remember { mutableStateOf(false) }
    var section by remember { mutableStateOf<SectionRecord?>(null) }
    var editor by remember { mutableStateOf<SessionExerciseRecord?>(null) }
    var editing by remember { mutableStateOf<TrainingSetRecord?>(null) }
    var moving by remember { mutableStateOf<SessionExerciseID?>(null) }
    var confirmSection by remember { mutableStateOf<SectionRecord?>(null) }
    var deleteExercise by remember { mutableStateOf<SessionExerciseRecord?>(null) }
    val content = state.content?.takeIf { it.session.sessionID == id }
    var studentName by remember(id) { mutableStateOf("") }
    LaunchedEffect(content?.session?.studentID) {
        content?.session?.studentID?.let { studentID ->
            when (val result = students?.find(studentID)) {
                is ApplicationResult.Success -> studentName = result.value?.displayName.orEmpty()
                is ApplicationResult.Failure -> studentName = "学员信息暂不可用"
                null -> Unit
            }
        }
    }
    val back = { if (!state.busy) onBack() }
    LaunchedEffect(id) { state.load(id); editor = state.content?.exercises?.lastOrNull(); exercises.search("") }
    LaunchedEffect(state.undoableSetID) {
        val recent = state.undoableSetID
        kotlinx.coroutines.delay(4_000) // FCUndoRow.undoWindow, components.md §4.4.
        state.expireRecentUndo(recent)
    }
    val imeVisible = WindowInsets.isImeVisible
    var wasImeVisible by remember { mutableStateOf(false) }
    LaunchedEffect(imeVisible) {
        if (wasImeVisible && !imeVisible && state.rests.end(id) != null && state.rests.remaining(id) == 0L) state.rests.clear(id)
        wasImeVisible = imeVisible
    }
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
    FcPlatformShell(back, Modifier.imePadding()) {

        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("active-session-content"),
            verticalArrangement = Arrangement.spacedBy(if (state.saveState == FcSaveState.Saved) FcSpacing.space3 else FcSpacing.space4)) {
            SessionHeader(studentName, content, state.clock, back)
            if (state.saveState != FcSaveState.Saved) SaveStatusView(state)
            recoverySlot()
            if (state.rests.end(id) != null) com.ignacioli.finecoach.notifications.RestPermissionEntry()
            state.error?.let { FcListRow(exerciseErrorTitle(it), Modifier.testTag("active-session-error")) }
            if (content != null) {
                Column(Modifier.fillMaxWidth().testTag("session-exercises"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
                if (content.exercises.isEmpty()) androidx.compose.material3.Text("先添加动作，再记录组数。", Modifier.testTag("session-empty-hint"),
                    style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
                if (content.session.durationNeedsReview) FcButton("确认训练时长", Modifier.testTag("session-review-duration"), !state.busy) { review = true }
                val axis = (content.sections.map { it.orderIndex to it } + content.exercises.filter { it.sectionID == null }.map { it.orderIndex to it }).sortedBy { it.first }
                @Composable fun exercise(row: SessionExerciseRecord) {
                    Column(Modifier.fillMaxWidth()) {
                    val exerciseTag = "session-exercise-${row.sessionExerciseID.value}"
                    SessionSwipeRow("$exerciseTag-swipe", revealed == exerciseTag, !state.busy, { revealed = if (it) exerciseTag else null },
                        buildList {
                            add(SessionSwipeAction("删除", "session-exercise-delete", destructive = true) {
                                if (row.sets.any { it.state == SetRecordingState.completed }) deleteExercise = row
                                else scope.launch { state.removeExercise(row.sessionExerciseID, false) }
                            })
                            if (content.sections.isNotEmpty()) add(SessionSwipeAction("移入分区", "session-exercise-move") { moving = row.sessionExerciseID })
                        }) {
                        SessionExerciseHeader(row, state.previous[row.sessionExerciseID], state.previousCounts[row.sessionExerciseID] ?: 0, editor?.sessionExerciseID == row.sessionExerciseID, !state.busy) { openEditor(row) }
                    }
                    row.sets.sortedBy { it.orderIndex }.forEachIndexed { index, set ->
                        val deleted = state.deleted
                        if (deleted?.sessionExerciseID == row.sessionExerciseID && deleted.orderIndex.toInt() == index)
                            FcUndoRow("第 ${index + 1} 组已删除", tag = "session-deleted") { scope.launch { state.restoreSet() } }
                        val setTag = "session-set-${set.trainingSetID.value}"
                        val removeSet = {
                            scope.launch { state.deleteSet(set.toDomain()); if (state.error == null && editing?.trainingSetID == set.trainingSetID) { editor = null; editing = null } }
                            Unit
                        }
                        SessionSwipeRow("$setTag-swipe", revealed == setTag, !state.busy, { revealed = if (it) setTag else null },
                            listOf(SessionSwipeAction("删除", "session-set-delete", destructive = true, run = removeSet)),
                            onFullSwipe = if (set.state != SetRecordingState.completed) removeSet else null) {
                        FcSetRow(index + 1, set.toDomain().displaySummary(), set.state == SetRecordingState.completed,
                            set.state == SetRecordingState.pending,
                            { change({ it.copy(session = it.session.confirmingSet(set.trainingSetID, state.clock.now())) }) },
                            { openEditor(row, set) }, Modifier.testTag("session-set-${set.trainingSetID.value}"), !state.busy, "session-set-${set.trainingSetID.value}",
                            onUndo = if (state.undoableSetID == set.trainingSetID) ({ scope.launch { state.undoRecentSet(); if (state.error == null) { editor = row; editing = null } }; Unit }) else null)
                        }
                        if (editor?.sessionExerciseID == row.sessionExerciseID && editing?.trainingSetID == set.trainingSetID) {
                            Spacer(Modifier.height(FcSpacing.space3))
                            key(set.trainingSetID) { SetEditor(state, row, set,
                                row.sourceID?.let { exercises.preference(it).isUnilateral } == true,
                                row.sourceID?.let { exercises.preference(it).isAssisted } == true) { editing = null } }
                        }
                    }
                    if (state.deleted?.sessionExerciseID == row.sessionExerciseID && state.deleted!!.orderIndex.toInt() >= row.sets.size)
                        FcUndoRow("第 ${state.deleted!!.orderIndex.toInt() + 1} 组已删除", tag = "session-deleted") { scope.launch { state.restoreSet() } }
                    if (editor?.sessionExerciseID == row.sessionExerciseID && editing == null) {
                        Spacer(Modifier.height(FcSpacing.space3))
                        key(row.sessionExerciseID, "new") { SetEditor(state, row, null,
                            row.sourceID?.let { exercises.preference(it).isUnilateral } == true,
                            row.sourceID?.let { exercises.preference(it).isAssisted } == true) { editor = null } }
                    }
                    Spacer(Modifier.height(if (editor?.sessionExerciseID == row.sessionExerciseID) FcSpacing.space1 else FcSpacing.space4))
                    FcListRowDivider(Modifier.testTag("session-divider-${row.sessionExerciseID.value}"))
                    }
                }
                axis.forEach { (_, item) -> when (item) {
                    is SectionRecord -> {
                        val sectionTag = "session-section-${item.sectionID.value}"
                        SessionSwipeRow("$sectionTag-swipe", revealed == sectionTag, !state.busy, { revealed = if (it) sectionTag else null },
                            listOf(SessionSwipeAction("删除分区", "session-section-delete", destructive = true) {
                                if (content.exercises.none { it.sectionID == item.sectionID })
                                    change({ it.deletingSection(item.sectionID, SessionSectionDeletionDisposition.DeleteWithExercises, state.clock.now()) })
                                else confirmSection = item
                            })) {
                            androidx.compose.material3.Text(item.name, Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.touch).testTag(sectionTag),
                                style = FcTypography.sectionLabel, color = FcColors.textSecondary)
                        }
                        content.exercises.filter { it.sectionID == item.sectionID }.sortedBy { it.orderIndex }.forEach { exercise(it) }
                    }
                    is SessionExerciseRecord -> exercise(item)
                } }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space6 + FcSpacing.space1)) {
                    FcLinkButton("＋ 添加动作", Modifier.testTag("session-add-exercise"), !state.busy) { addSheet = true }
                    FcLinkButton("＋ 新建分区", Modifier.testTag("session-add-section"), !state.busy) { section = null; sectionForm = true }
                }
                }
            }
        }
        restSlot()
        RestTimerView(state.rests, id, state.clock, !WindowInsets.isImeVisible)
        Box(Modifier.fillMaxWidth().padding(bottom = FcSpacing.space8)) {
        FcButton("结束训练", Modifier.testTag("session-finish"), content != null && !state.busy && state.saveState != FcSaveState.Failed,
            labelModifier = Modifier.offset(x = -FcSpacing.space1 / 2)) {
            if (content?.session?.durationNeedsReview == true) review = true else onFinish()
        }
        }
    }
    if (addSheet) FcBottomSheet("添加动作", { addSheet = false }, skipPartiallyExpanded = true) {
        Row(Modifier.fillMaxWidth().testTag("session-add-tabs"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcFilterChip("动作库", true, Modifier.testTag("session-add-library")) { addSheet = false; picker = true }
            FcFilterChip("从模板", false, Modifier.testTag("session-apply-template")) { addSheet = false; apply = true }
        }
        FcLinkButton("取消", Modifier.testTag("session-add-cancel")) { addSheet = false }
    }
    if (picker) ExercisePicker(exercises, { selection ->
        val result = state.addExercise(selection)
        if (result is ApplicationResult.Success) { editor = state.content?.exercises?.lastOrNull(); editing = null }
        result
    }, studentID = content?.session?.studentID) { picker = false }
    if (apply && content != null) ApplyTemplateSheet(templates, content.session, state::accept) { apply = false }
    if (sectionForm) {
        var name by remember(section) { mutableStateOf(section?.name ?: "") }
        FcBottomSheet(if (section == null) "新建分区" else "重命名分区", { if (!state.busy) sectionForm = false }, skipPartiallyExpanded = true) {
            Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).testTag("session-section-form-content")) {
                FcTextField("分区名称", name, { name = it }, Modifier.testTag("session-section-name"))
                state.error?.let { FcListRow(exerciseErrorTitle(it)) }
                FcButton("新建分区", Modifier.testTag("session-section-save"), !state.busy) {
                    change({ original -> section?.let { original.renamingSection(it.sectionID, name, state.clock.now()) }
                        ?: original.addingSection(state.ids.newSectionID(), name, state.clock.now()) }) { sectionForm = false }
                }
                FcSecondaryButton("取消", Modifier.testTag("session-section-cancel"), !state.busy) { sectionForm = false }
            }
        }
    }
    if (moving != null && content != null) FcBottomSheet("移入分区", { moving = null }, skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 6).verticalScroll(rememberScrollState())) {
            (listOf<SectionRecord?>(null) + content.sections).forEach { target ->
                FcActionRow(target?.name ?: "未分区", Modifier.testTag("session-move-${target?.sectionID?.value ?: "unsectioned"}"), enabled = !state.busy) {
                    change({ it.movingExercise(moving!!, target?.sectionID, state.clock.now()) }) { moving = null }
                }
            }
            FcSecondaryButton("取消", Modifier.testTag("session-move-cancel")) { moving = null }
        }
    }
    confirmSection?.let { row -> FcConfirmationDialog("删除分区「${row.name}」？", "分区里的 ${content?.exercises?.count { it.sectionID == row.sectionID } ?: 0} 个动作会移到「无分区」", "删除分区",
        { change({ it.deletingSection(row.sectionID, SessionSectionDeletionDisposition.MoveExercisesTo(null), state.clock.now()) }) { confirmSection = null } },
        { if (!state.busy) confirmSection = null }, tag = "session-delete-section-confirm") }
    deleteExercise?.let { row ->
        FcPlatformShell({ if (!state.busy) deleteExercise = null }) {
            androidx.compose.material3.Text("删除动作", Modifier.fillMaxWidth().testTag("session-delete-exercise-title"),
                style = FcTypography.titleLarge, color = FcColors.textPrimary)
            FcListRow("该动作包含已完成组，删除后无法恢复。")
            state.error?.let { FcListRow(exerciseErrorTitle(it)) }
            FcButton("删除动作", Modifier.testTag("session-delete-exercise-confirm"), !state.busy) {
                scope.launch { if (state.removeExercise(row.sessionExerciseID, true) is ApplicationResult.Success) deleteExercise = null }
            }
            FcSecondaryButton("取消", Modifier.testTag("session-delete-exercise-cancel"), !state.busy) { deleteExercise = null }
        }
    }
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
