package com.ignacioli.finecoach.features.students

import com.ignacioli.finecoach.designsystem.FcText
import androidx.compose.foundation.Image
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.SessionRepositoryPort
import com.ignacioli.finecoach.core.application.StudentQuery
import com.ignacioli.finecoach.core.application.StudentRecord
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.common.BodyPart
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.StudentLifecycle
import com.ignacioli.finecoach.designsystem.FcTitleIconButton
import com.ignacioli.finecoach.designsystem.FcButton
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcHintBar
import com.ignacioli.finecoach.designsystem.FcGroupEntryRow
import com.ignacioli.finecoach.designsystem.FcInlineResult
import com.ignacioli.finecoach.designsystem.FcListRowDivider
import com.ignacioli.finecoach.designsystem.FcPageHeader
import com.ignacioli.finecoach.designsystem.FcPlatformShell
import com.ignacioli.finecoach.designsystem.FcResultVariant
import com.ignacioli.finecoach.designsystem.FcSearchField
import com.ignacioli.finecoach.designsystem.FcSegmentedSwitch
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcTypography
import com.ignacioli.finecoach.navigation.S1Routes
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.launch

data class StudentListRowInfo(
    val focus: Set<BodyPart> = emptySet(),
    val trailing: String? = null,
)

object StudentListEmptyStatePresentation {
    fun showsEmptyState(hasCompletedInitialLoad: Boolean, studentCount: Int): Boolean =
        hasCompletedInitialLoad && studentCount == 0
}

data class StudentListUiState(
    val showsArchived: Boolean = false,
    val students: List<StudentRecord> = emptyList(),
    val query: String = "",
    val inProgress: List<StudentInProgressSummary> = emptyList(),
    val archivedCount: Int = 0,
    val rowInfo: Map<StudentID, StudentListRowInfo> = emptyMap(),
    val hasCompletedInitialLoad: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val restoringStudentIDs: Set<StudentID> = emptySet(),
) {
    val title: String
        get() = if (showsArchived) "已归档学员" else "学员"

    val showsStudentEmptyState: Boolean
        get() = errorMessage == null && StudentListEmptyStatePresentation.showsEmptyState(
            hasCompletedInitialLoad = hasCompletedInitialLoad,
            studentCount = students.size,
        )

    val isTrulyEmpty: Boolean
        get() = !showsArchived && showsStudentEmptyState && query.isEmpty() && archivedCount == 0
}

class StudentListViewModel(
    val useCases: StudentUseCases,
    val showsArchived: Boolean = false,
    val sessionRepository: SessionRepositoryPort? = null,
    val creditUseCases: CreditUseCases? = null,
    val clock: AppClock = AppClock { Instant.now() },
    val zoneId: ZoneId = ZoneId.systemDefault(),
) {
    var uiState by mutableStateOf(StudentListUiState(showsArchived = showsArchived))
        private set

    private var activeOps by mutableIntStateOf(0)
    val isIdle: Boolean get() = activeOps == 0 && !uiState.isLoading

    suspend fun reload() {
        activeOps += 1
        uiState = uiState.copy(isLoading = true)
        try {
            if (showsArchived) {
                when (val allRes = useCases.list(StudentQuery(includeArchived = true))) {
                    is ApplicationResult.Failure -> {
                        uiState = uiState.copy(
                            isLoading = false,
                            errorMessage = StudentPresentation.errorMessage(allRes.error),
                        )
                    }
                    is ApplicationResult.Success -> {
                        val archived = allRes.value.filter { it.lifecycle == StudentLifecycle.archived }
                        uiState = uiState.copy(
                            students = archived,
                            inProgress = emptyList(),
                            archivedCount = archived.size,
                            hasCompletedInitialLoad = true,
                            isLoading = false,
                            errorMessage = null,
                        )
                    }
                }
            } else {
                val activeQuery = StudentQuery(includeArchived = false, searchText = uiState.query)
                val activeRes = useCases.list(activeQuery)
                if (activeRes is ApplicationResult.Failure) {
                    uiState = uiState.copy(
                        isLoading = false,
                        errorMessage = StudentPresentation.errorMessage(activeRes.error),
                    )
                    return
                }
                val activeStudents = (activeRes as ApplicationResult.Success).value

                val allRes = useCases.list(StudentQuery(includeArchived = true))
                if (allRes is ApplicationResult.Failure) {
                    uiState = uiState.copy(
                        isLoading = false,
                        errorMessage = StudentPresentation.errorMessage(allRes.error),
                    )
                    return
                }
                val allStudents = (allRes as ApplicationResult.Success).value
                val archivedCount = allStudents.count { it.lifecycle == StudentLifecycle.archived }
                val nameByStudentId = allStudents.associate { it.studentID to it.displayName }

                val inProgressList = loadInProgressSummaries(nameByStudentId)
                val infoMap = loadRowInfo(activeStudents)

                uiState = uiState.copy(
                    students = activeStudents,
                    inProgress = inProgressList,
                    archivedCount = archivedCount,
                    rowInfo = infoMap,
                    hasCompletedInitialLoad = true,
                    isLoading = false,
                    errorMessage = null,
                )
            }
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }

    suspend fun updateQuery(newQuery: String) {
        uiState = uiState.copy(query = newQuery)
        reload()
    }

    suspend fun restore(studentID: StudentID): Boolean {
        activeOps += 1
        uiState = uiState.copy(restoringStudentIDs = uiState.restoringStudentIDs + studentID)
        return try {
            when (val res = useCases.restore(studentID)) {
                is ApplicationResult.Failure -> {
                    uiState = uiState.copy(
                        restoringStudentIDs = uiState.restoringStudentIDs - studentID,
                        errorMessage = StudentPresentation.errorMessage(res.error),
                    )
                    false
                }
                is ApplicationResult.Success -> {
                    uiState = uiState.copy(restoringStudentIDs = uiState.restoringStudentIDs - studentID)
                    reload()
                    true
                }
            }
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }

    private suspend fun loadInProgressSummaries(
        nameByStudentId: Map<StudentID, String>,
    ): List<StudentInProgressSummary> {
        val repo = sessionRepository ?: return emptyList()
        val snapshots = when (val res = repo.listActiveSessions()) {
            is ApplicationResult.Failure -> return emptyList()
            is ApplicationResult.Success -> res.value
        }
        return snapshots.mapNotNull { snapshot ->
            val displayName = nameByStudentId[snapshot.studentID]
                ?: (useCases.find(snapshot.studentID) as? ApplicationResult.Success)?.value?.displayName
                ?: return@mapNotNull null
            val sessionRecord = (repo.find(snapshot.sessionID) as? ApplicationResult.Success)?.value
            StudentInProgressSummary(
                sessionID = snapshot.sessionID,
                studentID = snapshot.studentID,
                studentDisplayName = displayName,
                startedAtUTC = snapshot.startedAtUTC,
                trainingFocus = sessionRecord?.trainingFocus.orEmpty(),
            )
        }
    }

    private suspend fun loadRowInfo(students: List<StudentRecord>): Map<StudentID, StudentListRowInfo> {
        val credits = creditUseCases ?: return emptyMap()
        val today = clock.today(zoneId)
        val result = mutableMapOf<StudentID, StudentListRowInfo>()
        for (student in students) {
            val activePkg = (credits.activePackage(student.studentID, today) as? ApplicationResult.Success)?.value
            val trailing = if (activePkg != null) {
                val balance = (credits.balance(student.studentID, activePkg.coursePackageID, today) as? ApplicationResult.Success)?.value
                balance?.let(StudentPresentation::packageRemainingText)
            } else {
                null
            }
            result[student.studentID] = StudentListRowInfo(focus = emptySet(), trailing = trailing)
        }
        return result
    }
}

@Composable
fun StudentListScreen(
    viewModel: StudentListViewModel,
    onRoute: (String) -> Unit,
    onBack: () -> Unit = {},
    showRootSwitch: Boolean = false,
    onOpenArchived: (() -> Unit)? = null,
    autoLoad: Boolean = true,
    insets: WindowInsets = WindowInsets.safeDrawing,
) {
    var showingEmbeddedArchived by remember { mutableStateOf(false) }
    val archivedViewModel = remember(viewModel.useCases, viewModel.clock, viewModel.zoneId) {
        StudentListViewModel(
            useCases = viewModel.useCases,
            showsArchived = true,
            sessionRepository = viewModel.sessionRepository,
            creditUseCases = viewModel.creditUseCases,
            clock = viewModel.clock,
            zoneId = viewModel.zoneId,
        )
    }
    val scope = rememberCoroutineScope()

    LaunchedEffect(viewModel, autoLoad) {
        if (autoLoad && !viewModel.uiState.hasCompletedInitialLoad && viewModel.uiState.errorMessage == null) {
            viewModel.reload()
        }
    }

    if (viewModel.showsArchived) {
        ArchivedStudentListScreen(
            viewModel = viewModel,
            onRoute = onRoute,
            onBack = onBack,
            autoLoad = false,
            insets = insets,
        )
        return
    }

    if (showingEmbeddedArchived) {
        ArchivedStudentListScreen(
            viewModel = archivedViewModel,
            onRoute = onRoute,
            onBack = {
                showingEmbeddedArchived = false
                scope.launch { viewModel.reload() }
            },
            onStudentRestored = {
                scope.launch { viewModel.reload() }
            },
            autoLoad = true,
            insets = insets,
        )
        return
    }

    val state = viewModel.uiState
    val now = viewModel.clock.now()

    FcPlatformShell(
        onBack = onBack,
        insets = insets,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .testTag(StudentTestTags.STUDENT_LIST_ROOT),
        ) {
            com.ignacioli.finecoach.designsystem.FcPagePrimary("学员",
                Modifier.fillMaxWidth().padding(bottom = FcSpacing.space4), // top space.4 is owned by FcPagePrimary (S1-D72)
                segments = if (showRootSwitch) ({
                    FcSegmentedSwitch(listOf("今日", "学员"), 1,
                        { index -> if (index == 0) onRoute(S1Routes.TODAY) }, tag = StudentTestTags.STUDENT_LIST_SEGMENT)
                }) else null,
                actions = {
                    FcTitleIconButton("资料库", painterResource(R.drawable.ic_ms_grid_view),
                        Modifier.testTag("student-list-resource-hub")) { onRoute(S1Routes.RESOURCE_HUB) }
                }) { }

            if (state.isTrulyEmpty) {
                NoStudentsEmptyState(
                    onAddStudent = { onRoute(S1Routes.STUDENT_CREATE) },
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                )
            } else {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(bottom = FcSpacing.space6),
                    verticalArrangement = Arrangement.spacedBy(FcSpacing.space3),
                ) {
                    FcSearchField(
                        title = "搜索学员",
                        value = state.query,
                        onValueChange = { nextQuery ->
                            scope.launch { viewModel.updateQuery(nextQuery) }
                        },
                        modifier = Modifier.testTag(StudentTestTags.STUDENT_LIST_SEARCH),
                    )

                    if (state.inProgress.isNotEmpty() && state.query.isEmpty()) {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(FcSpacing.space2),
                        ) {
                            state.inProgress.forEach { summary ->
                                val barTag = if (state.inProgress.size == 1) {
                                    StudentTestTags.STUDENT_LIST_IN_PROGRESS
                                } else {
                                    StudentTestTags.studentListInProgressRow(summary.studentID)
                                }
                                FcHintBar(
                                    text = StudentPresentation.trainingBarText(summary, now),
                                    actionTitle = "继续训练",
                                    modifier = Modifier.testTag(barTag),
                                    onClick = { onRoute(S1Routes.activeSession(summary.sessionID)) },
                                )
                            }
                        }
                    }

                    state.errorMessage?.let { message ->
                        FcText(
                            text = message,
                            style = FcTypography.caption,
                            color = FcColors.statusDestructive,
                            modifier = Modifier.testTag(StudentTestTags.STUDENT_LIST_ERROR),
                        )
                        // Unlike iOS query/path reloads, this remains the explicit recovery path.
                        FcButton("重试", Modifier.testTag("${StudentTestTags.STUDENT_LIST_ERROR}-retry")) {
                            scope.launch { viewModel.reload() }
                        }
                    }

                    if (state.showsStudentEmptyState) {
                        SearchStudentsEmptyState()
                    } else if (state.students.isNotEmpty()) {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(FcSpacing.space1),
                        ) {
                            state.students.forEach { student ->
                                val info = state.rowInfo[student.studentID] ?: StudentListRowInfo()
                                StudentActiveRow(
                                    displayName = student.displayName,
                                    focusSubtitle = StudentPresentation.focusText(info.focus),
                                    trailingDetail = info.trailing,
                                    modifier = Modifier.testTag(StudentTestTags.studentRow(student.studentID)),
                                    onClick = { onRoute(S1Routes.studentDetail(student.studentID)) },
                                )
                                FcListRowDivider()
                            }
                        }
                    }

                    if (state.query.isEmpty() && state.archivedCount > 0) {
                        FcGroupEntryRow(
                            title = "已归档",
                            count = state.archivedCount,
                            modifier = Modifier.testTag(StudentTestTags.STUDENT_LIST_ARCHIVED),
                            onClick = {
                                if (onOpenArchived != null) {
                                    onOpenArchived()
                                } else {
                                    showingEmbeddedArchived = true
                                }
                            },
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(FcColors.surfacePage)
                        .padding(vertical = FcSpacing.space2),
                ) {
                    FcButton(
                        title = "＋ 新学员",
                        modifier = Modifier.testTag(StudentTestTags.STUDENT_LIST_ADD),
                        onClick = { onRoute(S1Routes.STUDENT_CREATE) },
                    )
                }
            }
        }
    }
}

@Composable
fun ArchivedStudentListScreen(
    viewModel: StudentListViewModel,
    onRoute: (String) -> Unit,
    onBack: () -> Unit,
    onStudentRestored: (() -> Unit)? = null,
    autoLoad: Boolean = true,
    insets: WindowInsets = WindowInsets.safeDrawing,
) {
    val scope = rememberCoroutineScope()

    LaunchedEffect(viewModel, autoLoad) {
        if (autoLoad) {
            viewModel.reload()
        }
    }

    val state = viewModel.uiState

    FcPlatformShell(
        onBack = onBack,
        insets = insets,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = FcSpacing.space6)
                .testTag(StudentTestTags.ARCHIVED_LIST_ROOT),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space4),
        ) {
            FcPageHeader(
                title = "已归档学员",
                modifier = Modifier.testTag(StudentTestTags.ARCHIVED_HEADER),
                onBack = onBack,
                tag = StudentTestTags.ARCHIVED_HEADER,
            )

            FcText(
                text = "归档学员不出现在学员列表与今日，历史记录全部保留。",
                style = FcTypography.style("callout", 400),
                color = FcColors.textSecondary,
            )

            state.errorMessage?.let { message ->
                FcText(
                    text = message,
                    style = FcTypography.caption,
                    color = FcColors.statusDestructive,
                    modifier = Modifier.testTag(StudentTestTags.ARCHIVED_ERROR),
                )
                FcButton("重试", Modifier.testTag("${StudentTestTags.ARCHIVED_ERROR}-retry")) {
                    scope.launch { viewModel.reload() }
                }
            }

            if (state.showsStudentEmptyState) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = FcSpacing.space6)
                        .testTag(StudentTestTags.STUDENT_LIST_EMPTY),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(FcSpacing.space2),
                ) {
                    FcText(
                        text = "没有已归档学员",
                        style = FcTypography.headline,
                        color = FcColors.textPrimary,
                    )
                    FcText(
                        text = "归档后的学员会出现在这里，历史仍保留并可恢复。",
                        style = FcTypography.caption,
                        color = FcColors.textSecondary,
                        textAlign = TextAlign.Center,
                    )
                }
            } else if (state.students.isNotEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(FcSpacing.space1),
                ) {
                    FcListRowDivider()
                    state.students.forEach { student ->
                        StudentArchivedRow(
                            displayName = student.displayName,
                            archivedOnSubtitle = StudentPresentation.archivedOnText(
                                updatedAtUTC = student.updatedAtUTC,
                                zoneId = viewModel.zoneId,
                            ),
                            rowTag = StudentTestTags.studentRow(student.studentID),
                            restoreTag = StudentTestTags.studentListRestore(student.studentID),
                            restoreEnabled = student.studentID !in state.restoringStudentIDs,
                            onOpenDetail = { onRoute(S1Routes.studentDetail(student.studentID)) },
                            onRestore = {
                                scope.launch {
                                    if (viewModel.restore(student.studentID)) {
                                        onStudentRestored?.invoke()
                                    }
                                }
                            },
                        )
                        FcListRowDivider()
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchStudentsEmptyState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = FcSpacing.space6)
            .testTag(StudentTestTags.STUDENT_LIST_EMPTY),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(FcSpacing.space2),
    ) {
        FcText(
            text = "没有找到匹配的学员",
            style = FcTypography.headline,
            color = FcColors.textPrimary,
        )
        FcText(
            text = "试试显示名称中的其他字，或清空搜索。",
            style = FcTypography.caption,
            color = FcColors.textSecondary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun NoStudentsEmptyState(
    onAddStudent: () -> Unit,
    modifier: Modifier = Modifier,
) {
    com.ignacioli.finecoach.designsystem.FcEmptyState(
        title = "还没有学员", description = "开始记录第一堂课",
        modifier = modifier.fillMaxSize().padding(top = FcSpacing.space6).testTag(StudentTestTags.STUDENT_LIST_EMPTY),
        illustrationTag = "student-list-empty-mascot", actionTitle = "＋ 新建学员",
        actionTag = StudentTestTags.STUDENT_LIST_EMPTY_ADD, onAction = onAddStudent,
    )
}
