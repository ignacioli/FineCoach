package com.ignacioli.finecoach.features.students

import com.ignacioli.finecoach.designsystem.FcText
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.ignacioli.finecoach.core.application.ApplicationErrorCode
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.HistoryQuery
import com.ignacioli.finecoach.core.application.HistoryRepositoryPort
import com.ignacioli.finecoach.core.application.SessionRepositoryPort
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.designsystem.FcButton
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcLinkButton
import com.ignacioli.finecoach.designsystem.FcPlatformShell
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcTextField
import com.ignacioli.finecoach.designsystem.FcTypography
import kotlinx.coroutines.launch

sealed interface DeleteStudentFinish {
    data object Cancelled : DeleteStudentFinish
    data object Deleted : DeleteStudentFinish
    data class ContinueTraining(val sessionID: SessionID?) : DeleteStudentFinish
}

data class StudentDeletionImpact(
    val displayName: String,
    val completedSessionCount: Int?,
    val hasInProgressSession: Boolean,
    val inProgressSessionID: SessionID? = null,
)

data class DeleteStudentUiState(
    val impact: StudentDeletionImpact? = null,
    val typedName: String = "",
    val errorMessage: String? = null,
    val didDelete: Boolean = false,
    val isLoading: Boolean = false,
    val isDeleting: Boolean = false,
) {
    val canConfirmDelete: Boolean
        get() {
            val current = impact ?: return false
            if (current.hasInProgressSession || isDeleting || didDelete) return false
            return StudentPresentation.namesMatch(current.displayName, typedName)
        }
}

class DeleteStudentViewModel(
    val studentID: StudentID,
    val useCases: StudentUseCases,
    val sessionRepository: SessionRepositoryPort? = null,
    val historyRepository: HistoryRepositoryPort? = null,
) {
    var uiState by mutableStateOf(DeleteStudentUiState())
        private set

    private var activeOps by mutableIntStateOf(0)
    val isIdle: Boolean get() = activeOps == 0 && !uiState.isLoading && !uiState.isDeleting

    suspend fun load() {
        activeOps += 1
        uiState = uiState.copy(isLoading = true)
        try {
            val studentRes = useCases.find(studentID)
            if (studentRes is ApplicationResult.Failure) {
                uiState = uiState.copy(
                    isLoading = false,
                    errorMessage = StudentPresentation.errorMessage(studentRes.error),
                )
                return
            }
            val student = (studentRes as ApplicationResult.Success).value
            if (student == null) {
                uiState = uiState.copy(
                    isLoading = false,
                    errorMessage = StudentPresentation.GENERIC_ERROR,
                )
                return
            }

            val activeSession = (sessionRepository?.active(studentID) as? ApplicationResult.Success)?.value
            val completedCount = historyRepository?.let { history ->
                (history.list(HistoryQuery(studentID = studentID)) as? ApplicationResult.Success)?.value?.size
            }

            uiState = uiState.copy(
                impact = StudentDeletionImpact(
                    displayName = student.displayName,
                    completedSessionCount = completedCount,
                    hasInProgressSession = activeSession != null,
                    inProgressSessionID = activeSession?.sessionID,
                ),
                isLoading = false,
                errorMessage = null,
            )
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }

    fun updateTypedName(value: String) {
        uiState = uiState.copy(
            typedName = value,
            errorMessage = null,
        )
    }

    suspend fun confirmDelete(): Boolean {
        activeOps += 1
        uiState = uiState.copy(isDeleting = true, errorMessage = null)
        return try {
            val currentImpact = uiState.impact
            when (val res = useCases.delete(studentID, uiState.typedName)) {
                is ApplicationResult.Success -> {
                    uiState = uiState.copy(
                        didDelete = true,
                        isDeleting = false,
                        errorMessage = null,
                    )
                    true
                }
                is ApplicationResult.Failure -> {
                    if (res.error.code == ApplicationErrorCode.invalidState) {
                        val freshStudent = (useCases.find(studentID) as? ApplicationResult.Success)?.value
                        val expectedName = freshStudent?.displayName ?: currentImpact?.displayName.orEmpty()
                        if (expectedName.isNotEmpty() && StudentPresentation.namesMatch(expectedName, uiState.typedName)) {
                            val activeSession = (sessionRepository?.active(studentID) as? ApplicationResult.Success)?.value
                            val updatedImpact = (currentImpact ?: StudentDeletionImpact(expectedName, null, true)).copy(
                                displayName = expectedName,
                                hasInProgressSession = true,
                                inProgressSessionID = activeSession?.sessionID,
                            )
                            uiState = uiState.copy(
                                impact = updatedImpact,
                                isDeleting = false,
                                errorMessage = null,
                            )
                        } else {
                            uiState = uiState.copy(
                                isDeleting = false,
                                errorMessage = StudentPresentation.DELETE_NAME_MISMATCH_ERROR,
                            )
                        }
                    } else {
                        uiState = uiState.copy(
                            isDeleting = false,
                            errorMessage = StudentPresentation.errorMessage(res.error),
                        )
                    }
                    false
                }
            }
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }
}

@Composable
fun StudentArchiveConfirmationView(
    studentID: StudentID,
    useCases: StudentUseCases,
    onCancel: () -> Unit,
    onArchived: () -> Unit,
    insets: WindowInsets = WindowInsets.safeDrawing,
) {
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isArchiving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    FcPlatformShell(
        onBack = onCancel,
        insets = insets,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(vertical = FcSpacing.space4)
                .testTag(StudentTestTags.ARCHIVE_ROOT),
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(FcSpacing.space4),
            ) {
                FcText(
                    text = "归档学员",
                    modifier = Modifier.semantics { heading() },
                    style = FcTypography.title,
                    color = FcColors.textPrimary,
                )
                FcText(
                    text = "归档之后：",
                    style = FcTypography.body,
                    color = FcColors.textPrimary,
                )
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(FcSpacing.space2),
                ) {
                    FcText(
                        text = "• 从活跃学员列表中隐藏",
                        style = FcTypography.body,
                        color = FcColors.textPrimary,
                    )
                    FcText(
                        text = "• 不能开始新训练",
                        style = FcTypography.body,
                        color = FcColors.textPrimary,
                    )
                    FcText(
                        text = "• 仍可查看训练历史",
                        style = FcTypography.body,
                        color = FcColors.textPrimary,
                    )
                    FcText(
                        text = "• 之后可以恢复为活跃",
                        style = FcTypography.body,
                        color = FcColors.textPrimary,
                    )
                }
                FcText(
                    text = "归档不是删除。永久删除在编辑页的「永久删除」。",
                    style = FcTypography.body,
                    color = FcColors.textSecondary,
                )
                errorMessage?.let { message ->
                    FcText(
                        text = message,
                        modifier = Modifier.testTag(StudentTestTags.ARCHIVE_ERROR),
                        style = FcTypography.caption,
                        color = FcColors.statusDestructive,
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(FcColors.surfacePage)
                    .padding(top = FcSpacing.space2),
                verticalArrangement = Arrangement.spacedBy(FcSpacing.space2),
            ) {
                FcButton(
                    title = "归档学员",
                    modifier = Modifier.testTag(StudentTestTags.ARCHIVE_CONFIRM),
                    enabled = !isArchiving,
                    onClick = {
                        scope.launch {
                            isArchiving = true
                            errorMessage = null
                            when (val res = useCases.archive(studentID)) {
                                is ApplicationResult.Success -> {
                                    isArchiving = false
                                    onArchived()
                                }
                                is ApplicationResult.Failure -> {
                                    isArchiving = false
                                    errorMessage = StudentPresentation.errorMessage(res.error)
                                }
                            }
                        }
                    },
                )
                FcLinkButton(
                    title = "取消",
                    modifier = Modifier.testTag(StudentTestTags.ARCHIVE_CANCEL),
                    enabled = !isArchiving,
                    onClick = onCancel,
                )
            }
        }
    }
}

@Composable
fun DeleteStudentScreen(
    viewModel: DeleteStudentViewModel,
    onFinish: (DeleteStudentFinish) -> Unit,
    autoLoad: Boolean = true,
    insets: WindowInsets = WindowInsets.safeDrawing,
) {
    val scope = rememberCoroutineScope()

    LaunchedEffect(viewModel, autoLoad) {
        if (autoLoad && viewModel.uiState.impact == null && viewModel.uiState.errorMessage == null) {
            viewModel.load()
        }
    }

    val state = viewModel.uiState
    val impact = state.impact

    FcPlatformShell(
        onBack = {
            if (state.didDelete) {
                onFinish(DeleteStudentFinish.Deleted)
            } else {
                onFinish(DeleteStudentFinish.Cancelled)
            }
        },
        insets = insets,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(vertical = FcSpacing.space4)
                .testTag(StudentTestTags.DELETE_ROOT),
        ) {
            when {
                state.didDelete -> {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(FcSpacing.space4),
                    ) {
                        FcText(
                            text = "学员已永久删除",
                            modifier = Modifier
                                .testTag(StudentTestTags.DELETE_DONE)
                                .semantics { heading() },
                            style = FcTypography.title,
                            color = FcColors.textPrimary,
                        )
                        FcButton(
                            title = "返回学员列表",
                            modifier = Modifier.testTag(StudentTestTags.DELETE_BACK_TO_LIST),
                            onClick = { onFinish(DeleteStudentFinish.Deleted) },
                        )
                    }
                }

                impact != null && impact.hasInProgressSession -> {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(FcSpacing.space4),
                    ) {
                        FcText(
                            text = "${impact.displayName} 有进行中的训练，不能永久删除。",
                            modifier = Modifier
                                .testTag(StudentTestTags.DELETE_BLOCKED)
                                .semantics { heading() },
                            style = FcTypography.title,
                            color = FcColors.textPrimary,
                        )
                        FcText(
                            text = "状态不只靠颜色：当前为「训练中」，须先结束或继续完成该训练。",
                            style = FcTypography.body,
                            color = FcColors.textSecondary,
                        )
                    }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(FcColors.surfacePage)
                            .padding(top = FcSpacing.space2),
                        verticalArrangement = Arrangement.spacedBy(FcSpacing.space2),
                    ) {
                        FcButton(
                            title = "继续训练",
                            modifier = Modifier.testTag(StudentTestTags.DELETE_CONTINUE_TRAINING),
                            onClick = { onFinish(DeleteStudentFinish.ContinueTraining(impact.inProgressSessionID)) },
                        )
                        FcLinkButton(
                            title = "回到详情",
                            modifier = Modifier.testTag(StudentTestTags.DELETE_BACK_TO_DETAIL),
                            onClick = { onFinish(DeleteStudentFinish.Cancelled) },
                        )
                        FcLinkButton(
                            title = "取消",
                            modifier = Modifier.testTag(StudentTestTags.DELETE_CANCEL),
                            onClick = { onFinish(DeleteStudentFinish.Cancelled) },
                        )
                    }
                }

                impact != null -> {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(FcSpacing.space3),
                    ) {
                        FcText(
                            text = "永久删除",
                            modifier = Modifier.semantics { heading() },
                            style = FcTypography.title,
                            color = FcColors.textPrimary,
                        )
                        FcText(
                            text = "将永久删除「${impact.displayName}」及其在本机的关联数据。",
                            style = FcTypography.body,
                            color = FcColors.textPrimary,
                        )
                        FcText(
                            text = "将一并删除",
                            style = FcTypography.headline,
                            color = FcColors.textPrimary,
                        )
                        FcText(
                            text = "• 显示名称、性别、训练目标",
                            style = FcTypography.body,
                            color = FcColors.textPrimary,
                        )
                        FcText(
                            text = "• 伤病 / 注意事项、教练备注、电话与微信",
                            style = FcTypography.body,
                            color = FcColors.textPrimary,
                        )
                        impact.completedSessionCount?.let { count ->
                            FcText(
                                text = "• $count 条已完成训练记录",
                                style = FcTypography.body,
                                color = FcColors.textPrimary,
                            )
                        }
                        FcText(
                            text = "输入显示名称以确认",
                            style = FcTypography.body,
                            color = FcColors.textPrimary,
                        )
                        FcTextField(
                            title = "显示名称",
                            value = state.typedName,
                            onValueChange = viewModel::updateTypedName,
                            modifier = Modifier.testTag(StudentTestTags.DELETE_NAME),
                            enabled = !state.isDeleting,
                        )
                        state.errorMessage?.let { message ->
                            FcText(
                                text = message,
                                modifier = Modifier.testTag(StudentTestTags.DELETE_ERROR),
                                style = FcTypography.caption,
                                color = FcColors.statusDestructive,
                            )
                        }
                        FcText(
                            text = "删除后无法从本页恢复。已分享的旧图片和自行保存的备份不会被远程改写或删除。",
                            style = FcTypography.caption,
                            color = FcColors.textSecondary,
                        )
                    }

                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(FcColors.surfacePage)
                            .padding(top = FcSpacing.space2),
                        verticalArrangement = Arrangement.spacedBy(FcSpacing.space2),
                    ) {
                        FcButton(
                            title = "永久删除",
                            modifier = Modifier.testTag(StudentTestTags.DELETE_CONFIRM),
                            enabled = state.canConfirmDelete,
                            onClick = {
                                scope.launch { viewModel.confirmDelete() }
                            },
                        )
                        FcLinkButton(
                            title = "取消",
                            modifier = Modifier.testTag(StudentTestTags.DELETE_CANCEL),
                            enabled = !state.isDeleting,
                            onClick = { onFinish(DeleteStudentFinish.Cancelled) },
                        )
                    }
                }

                else -> {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(FcSpacing.space4),
                    ) {
                        state.errorMessage?.let { message ->
                            FcText(
                                text = message,
                                modifier = Modifier.testTag(StudentTestTags.DELETE_ERROR),
                                style = FcTypography.caption,
                                color = FcColors.statusDestructive,
                            )
                        }
                    }
                    FcLinkButton(
                        title = "取消",
                        modifier = Modifier.testTag(StudentTestTags.DELETE_CANCEL),
                        onClick = { onFinish(DeleteStudentFinish.Cancelled) },
                    )
                }
            }
        }
    }
}
