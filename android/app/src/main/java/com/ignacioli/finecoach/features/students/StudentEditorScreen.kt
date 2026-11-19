package com.ignacioli.finecoach.features.students

import com.ignacioli.finecoach.designsystem.FcText
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.KeyboardType
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.HistoryRepositoryPort
import com.ignacioli.finecoach.core.application.SessionRepositoryPort
import com.ignacioli.finecoach.core.application.StudentRecord
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.StudentLifecycle
import com.ignacioli.finecoach.core.domain.common.StudentSex
import com.ignacioli.finecoach.core.domain.common.ValidatedText
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.designsystem.FcActionRow
import com.ignacioli.finecoach.designsystem.FcButton
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcComponentMetrics
import com.ignacioli.finecoach.designsystem.FcFilterChip
import com.ignacioli.finecoach.designsystem.FcLabelValueRow
import com.ignacioli.finecoach.designsystem.FcLinkButton
import com.ignacioli.finecoach.designsystem.FcListRowDivider
import com.ignacioli.finecoach.designsystem.FcPageHeader
import com.ignacioli.finecoach.designsystem.FcPlatformShell
import com.ignacioli.finecoach.designsystem.FcSectionLabel
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcTypography
import com.ignacioli.finecoach.navigation.S1Routes
import kotlinx.coroutines.launch

sealed interface StudentEditorMode {
    data object FirstCreate : StudentEditorMode
    data object Add : StudentEditorMode
    data class Edit(val studentID: StudentID) : StudentEditorMode
}

private enum class StudentManagementOverlay {
    Archive,
    Delete,
}

data class StudentEditorUiState(
    val mode: StudentEditorMode,
    val draft: StudentDraft = StudentDraft(),
    val lifecycle: StudentLifecycle? = null,
    val nameError: String? = null,
    val sexError: String? = null,
    val saveError: String? = null,
    val isSaving: Boolean = false,
    val isLoading: Boolean = false,
    val hasLoaded: Boolean = false,
) {
    val title: String
        get() = when (mode) {
            StudentEditorMode.FirstCreate -> "第一位学员"
            StudentEditorMode.Add -> "添加学员"
            is StudentEditorMode.Edit -> "编辑资料"
        }

    val showsSkip: Boolean
        get() = mode is StudentEditorMode.FirstCreate

    val editingStudentID: StudentID?
        get() = (mode as? StudentEditorMode.Edit)?.studentID
}

class StudentEditorViewModel(
    val mode: StudentEditorMode,
    val useCases: StudentUseCases,
    existing: StudentRecord? = null,
) {
    var uiState by mutableStateOf(
        StudentEditorUiState(
            mode = mode,
            draft = existing?.toDraft() ?: StudentDraft(),
            lifecycle = existing?.lifecycle,
            hasLoaded = existing != null || mode !is StudentEditorMode.Edit,
        ),
    )
        private set

    private var activeOps by mutableIntStateOf(0)
    val isIdle: Boolean get() = activeOps == 0 && !uiState.isLoading && !uiState.isSaving

    suspend fun loadIfNeeded() {
        val editMode = mode as? StudentEditorMode.Edit ?: return
        activeOps += 1
        uiState = uiState.copy(isLoading = true)
        try {
            when (val res = useCases.find(editMode.studentID)) {
                is ApplicationResult.Failure -> {
                    uiState = uiState.copy(
                        isLoading = false,
                        saveError = StudentPresentation.errorMessage(res.error),
                    )
                }
                is ApplicationResult.Success -> {
                    val record = res.value
                    if (record == null) {
                        uiState = uiState.copy(
                            isLoading = false,
                            saveError = StudentPresentation.GENERIC_ERROR,
                        )
                    } else {
                        uiState = uiState.copy(
                            draft = record.toDraft(),
                            lifecycle = record.lifecycle,
                            isLoading = false,
                            hasLoaded = true,
                            saveError = null,
                        )
                    }
                }
            }
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }

    fun updateDisplayName(value: String) {
        uiState = uiState.copy(
            draft = uiState.draft.copy(displayName = value),
            nameError = null,
            saveError = null,
        )
    }

    fun updateSex(sex: StudentSex) {
        uiState = uiState.copy(
            draft = uiState.draft.copy(sex = sex),
            sexError = null,
            saveError = null,
        )
    }

    fun updateTrainingGoal(value: String) {
        uiState = uiState.copy(
            draft = uiState.draft.copy(trainingGoal = value),
            saveError = null,
        )
    }

    fun updatePhone(value: String) {
        uiState = uiState.copy(
            draft = uiState.draft.copy(phone = value),
            saveError = null,
        )
    }

    fun updateWechatID(value: String) {
        uiState = uiState.copy(
            draft = uiState.draft.copy(wechatID = value),
            saveError = null,
        )
    }

    fun updatePrivateCoachNote(value: String) {
        uiState = uiState.copy(
            draft = uiState.draft.copy(privateCoachNote = value),
            saveError = null,
        )
    }

    fun updateInjuryNotes(value: String) {
        uiState = uiState.copy(
            draft = uiState.draft.copy(injuryNotes = value),
            saveError = null,
        )
    }

    suspend fun save(): StudentRecord? {
        val currentDraft = uiState.draft
        var nextNameError: String? = null
        var nextSexError: String? = null
        var nextSaveError: String? = null

        try {
            val validatedName = ValidatedText.parse(currentDraft.displayName, allowEmpty = true)
            if (validatedName.isEmpty) {
                nextNameError = StudentPresentation.NAME_REQUIRED_ERROR
            }
        } catch (_: IllegalArgumentException) {
            nextSaveError = StudentPresentation.TEXT_TOO_LONG_ERROR
        }

        if (currentDraft.sex == null) {
            nextSexError = StudentPresentation.SEX_REQUIRED_ERROR
        }

        if (nextNameError != null || nextSexError != null || nextSaveError != null) {
            uiState = uiState.copy(
                nameError = nextNameError,
                sexError = nextSexError,
                saveError = nextSaveError,
            )
            return null
        }

        activeOps += 1
        uiState = uiState.copy(
            nameError = null,
            sexError = null,
            saveError = null,
            isSaving = true,
        )
        return try {
            val result = when (val currentMode = mode) {
                StudentEditorMode.FirstCreate, StudentEditorMode.Add -> useCases.create(currentDraft)
                is StudentEditorMode.Edit -> useCases.update(currentMode.studentID, currentDraft)
            }
            when (result) {
                is ApplicationResult.Failure -> {
                    uiState = uiState.copy(
                        isSaving = false,
                        saveError = StudentPresentation.errorMessage(result.error),
                    )
                    null
                }
                is ApplicationResult.Success -> {
                    uiState = uiState.copy(
                        isSaving = false,
                        lifecycle = result.value.lifecycle,
                        saveError = null,
                    )
                    result.value
                }
            }
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }
}

private fun StudentRecord.toDraft(): StudentDraft = StudentDraft(
    displayName = displayName,
    sex = sex,
    trainingGoal = trainingGoal.orEmpty(),
    injuryNotes = injuryNotes.orEmpty(),
    privateCoachNote = privateCoachNote.orEmpty(),
    phone = phone.orEmpty(),
    wechatID = wechatID.orEmpty(),
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StudentEditorScreen(
    viewModel: StudentEditorViewModel,
    onCancel: () -> Unit,
    onSaved: (StudentRecord?) -> Unit,
    onArchived: () -> Unit = onCancel,
    onDeleted: () -> Unit = {},
    onRoute: (String) -> Unit = {},
    sessionRepository: SessionRepositoryPort? = null,
    historyRepository: HistoryRepositoryPort? = null,
    appointments: com.ignacioli.finecoach.core.application.AppointmentUseCases? = null,
    makeDeleteViewModel: ((StudentID) -> DeleteStudentViewModel)? = null,
    autoLoad: Boolean = true,
    insets: WindowInsets = WindowInsets.safeDrawing,
) {
    var overlay by remember { mutableStateOf<StudentManagementOverlay?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(viewModel, autoLoad) {
        if (autoLoad && !viewModel.uiState.hasLoaded) {
            viewModel.loadIfNeeded()
        }
    }

    val state = viewModel.uiState
    val editingStudentID = state.editingStudentID

    if (editingStudentID != null && overlay != null) {
        when (overlay) {
            StudentManagementOverlay.Archive -> {
                StudentArchiveConfirmationView(
                    studentID = editingStudentID,
                    useCases = viewModel.useCases,
                    onCancel = { overlay = null },
                    onArchived = {
                        overlay = null
                        onArchived()
                    },
                    insets = insets,
                )
            }
            StudentManagementOverlay.Delete -> {
                val deleteViewModel = remember(editingStudentID, viewModel.useCases, sessionRepository, historyRepository, appointments, makeDeleteViewModel) {
                    makeDeleteViewModel?.invoke(editingStudentID) ?: StudentFeatureFactory.deleteViewModel(
                        studentID = editingStudentID,
                        useCases = viewModel.useCases,
                        sessionRepository = sessionRepository,
                        historyRepository = historyRepository,
                        appointments = appointments,
                    )
                }
                DeleteStudentScreen(
                    viewModel = deleteViewModel,
                    onFinish = { finish ->
                        overlay = null
                        when (finish) {
                            DeleteStudentFinish.Cancelled -> Unit
                            DeleteStudentFinish.Deleted -> {
                                onDeleted()
                            }
                            is DeleteStudentFinish.ContinueTraining -> {
                                finish.sessionID?.let { sessionID ->
                                    onRoute(S1Routes.activeSession(sessionID))
                                }
                            }
                        }
                    },
                    insets = insets,
                )
            }
            null -> Unit
        }
        return
    }

    val chipVerticalSpacing = FcSpacing.space2 - (FcComponentMetrics.touch - (FcSpacing.space8 - FcSpacing.space1 / 2))

    FcPlatformShell(
        onBack = onCancel,
        insets = insets,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .testTag(StudentTestTags.EDITOR_ROOT),
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = FcSpacing.space6),
            ) {
                FcPageHeader(
                    title = state.title,
                    modifier = Modifier
                        .padding(bottom = FcSpacing.space4)
                        .testTag(StudentTestTags.EDITOR_HEADER),
                    onBack = onCancel,
                    tag = StudentTestTags.EDITOR_HEADER,
                )
                FcListRowDivider()

                StudentInlineFieldRow(
                    label = "姓名",
                    placeholder = "必填",
                    value = state.draft.displayName,
                    onValueChange = viewModel::updateDisplayName,
                    rowTag = StudentTestTags.EDITOR_ROW_NAME,
                    inputTag = StudentTestTags.EDITOR_NAME,
                    enabled = !state.isSaving,
                )
                EditorErrorText(
                    message = state.nameError,
                    tag = StudentTestTags.EDITOR_NAME_ERROR,
                )
                FcListRowDivider()

                FcLabelValueRow(
                    label = "性别",
                    modifier = Modifier.testTag(StudentTestTags.EDITOR_ROW_SEX),
                ) {
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2),
                        verticalArrangement = Arrangement.spacedBy(chipVerticalSpacing),
                    ) {
                        listOf(
                            StudentSex.male,
                            StudentSex.female,
                            StudentSex.other,
                            StudentSex.undisclosed,
                        ).forEach { sex ->
                            FcFilterChip(
                                title = StudentSexPresentation.title(sex),
                                selected = state.draft.sex == sex,
                                modifier = Modifier.testTag(StudentTestTags.sexIdentifier(sex)),
                                onClick = { viewModel.updateSex(sex) },
                            )
                        }
                    }
                }
                EditorErrorText(
                    message = state.sexError,
                    tag = StudentTestTags.EDITOR_SEX_ERROR,
                )
                FcListRowDivider()

                StudentInlineFieldRow(
                    label = "训练目标",
                    placeholder = "选填",
                    value = state.draft.trainingGoal,
                    onValueChange = viewModel::updateTrainingGoal,
                    rowTag = StudentTestTags.EDITOR_ROW_GOAL,
                    inputTag = StudentTestTags.EDITOR_GOAL,
                    enabled = !state.isSaving,
                )
                FcListRowDivider()

                StudentInlineFieldRow(
                    label = "电话",
                    placeholder = "选填",
                    value = state.draft.phone,
                    onValueChange = viewModel::updatePhone,
                    rowTag = StudentTestTags.EDITOR_ROW_PHONE,
                    inputTag = StudentTestTags.EDITOR_PHONE,
                    enabled = !state.isSaving,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                )
                FcListRowDivider()

                StudentInlineFieldRow(
                    label = "微信",
                    placeholder = "选填",
                    value = state.draft.wechatID,
                    onValueChange = viewModel::updateWechatID,
                    rowTag = StudentTestTags.EDITOR_ROW_WECHAT,
                    inputTag = StudentTestTags.EDITOR_WECHAT,
                    enabled = !state.isSaving,
                )
                FcListRowDivider()

                StudentInlineFieldRow(
                    label = "教练备注",
                    placeholder = "选填",
                    value = state.draft.privateCoachNote,
                    onValueChange = viewModel::updatePrivateCoachNote,
                    rowTag = StudentTestTags.EDITOR_ROW_PRIVATE_NOTE,
                    inputTag = StudentTestTags.EDITOR_PRIVATE_NOTE,
                    enabled = !state.isSaving,
                    singleLine = false,
                )
                FcListRowDivider()

                StudentInlineFieldRow(
                    label = "注意事项",
                    placeholder = "选填",
                    value = state.draft.injuryNotes,
                    onValueChange = viewModel::updateInjuryNotes,
                    rowTag = StudentTestTags.EDITOR_ROW_INJURY_NOTES,
                    inputTag = StudentTestTags.EDITOR_INJURY_NOTES,
                    enabled = !state.isSaving,
                    singleLine = false,
                )
                FcListRowDivider()

                FcText(
                    text = "电话与微信由教练手输。不读取系统通讯录，不询问联系人权限。",
                    modifier = Modifier.padding(top = FcSpacing.space3),
                    style = FcTypography.caption,
                    color = FcColors.textSecondary,
                )

                EditorErrorText(
                    message = state.saveError,
                    tag = StudentTestTags.EDITOR_SAVE_ERROR,
                )

                if (editingStudentID != null) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        FcSectionLabel(
                            title = "管理",
                            modifier = Modifier.padding(top = FcSpacing.space6, bottom = FcSpacing.space2),
                        )
                        FcListRowDivider()
                        if (state.lifecycle == StudentLifecycle.active) {
                            FcActionRow(
                                title = "归档学员",
                                modifier = Modifier.testTag(StudentTestTags.DETAIL_ARCHIVE),
                                detail = "不再出现在列表，可恢复",
                                onClick = { overlay = StudentManagementOverlay.Archive },
                            )
                            FcListRowDivider()
                        }
                        FcActionRow(
                            title = "永久删除",
                            modifier = Modifier.testTag(StudentTestTags.DETAIL_DELETE),
                            detail = "删除学员和训练记录；课包与课时流水仍保留，需二次确认",
                            destructive = true,
                            trash = painterResource(R.drawable.ic_ms_delete),
                            onClick = { overlay = StudentManagementOverlay.Delete },
                        )
                        FcListRowDivider()
                    }
                }

                if (state.showsSkip) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = FcSpacing.space4),
                        contentAlignment = Alignment.Center,
                    ) {
                        FcLinkButton(
                            title = "稍后添加",
                            modifier = Modifier.testTag(StudentTestTags.EDITOR_SKIP),
                            onClick = { onSaved(null) },
                        )
                    }
                }
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(FcColors.surfacePage)
                    .padding(vertical = FcSpacing.space2),
            ) {
                FcButton(
                    title = "保存学员",
                    modifier = Modifier.testTag(StudentTestTags.EDITOR_SAVE),
                    enabled = !state.isSaving,
                    onClick = {
                        scope.launch {
                            val saved = viewModel.save()
                            if (saved != null) {
                                onSaved(saved)
                            }
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun EditorErrorText(
    message: String?,
    tag: String,
) {
    if (message != null) {
        FcText(
            text = message,
            modifier = Modifier
                .padding(bottom = FcSpacing.space2)
                .testTag(tag),
            style = FcTypography.caption,
            color = FcColors.statusDestructive,
        )
    }
}
