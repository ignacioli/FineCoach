package com.ignacioli.finecoach.features.students

import com.ignacioli.finecoach.designsystem.FcText
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.toDomain
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.AppointmentUseCases
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.HistoryQuery
import com.ignacioli.finecoach.core.application.HistoryRepositoryPort
import com.ignacioli.finecoach.core.application.SessionRepositoryPort
import com.ignacioli.finecoach.core.application.StartOrOpenSessionCommand
import com.ignacioli.finecoach.core.application.StudentRecord
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.appointment.Appointment
import com.ignacioli.finecoach.core.domain.appointment.AppointmentStatus
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.StudentLifecycle
import com.ignacioli.finecoach.features.insights.InsightBoardState
import com.ignacioli.finecoach.features.insights.InsightRoutes
import com.ignacioli.finecoach.features.insights.InsightStudentSection
import com.ignacioli.finecoach.features.insights.insightDestination
import com.ignacioli.finecoach.designsystem.FcActionRow
import com.ignacioli.finecoach.designsystem.FcAvatar
import com.ignacioli.finecoach.designsystem.FcButton
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcHeroCard
import com.ignacioli.finecoach.designsystem.FcHintBar
import com.ignacioli.finecoach.designsystem.FcInlineResult
import com.ignacioli.finecoach.designsystem.FcLabelValueRow
import com.ignacioli.finecoach.designsystem.FcLabelValueText
import com.ignacioli.finecoach.designsystem.FcListRowDivider
import com.ignacioli.finecoach.designsystem.FcPageHeader
import com.ignacioli.finecoach.designsystem.FcPlatformShell
import com.ignacioli.finecoach.designsystem.FcResultVariant
import com.ignacioli.finecoach.designsystem.FcSectionLabel
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcTypography
import com.ignacioli.finecoach.navigation.S1Routes
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.launch

data class StudentPackageSummary(
    val balance: Long,
    val totalCredits: Long,
    val endDate: LocalDate?,
)

data class StudentDetailUiState(
    val student: StudentRecord? = null,
    val inProgress: StudentInProgressSummary? = null,
    val sessionKnown: Boolean = false,
    val packageSummary: StudentPackageSummary? = null,
    val packageQueried: Boolean = false,
    val recent: StudentRecentSessionSummary? = null,
    val recentQueried: Boolean = false,
    val nextAppointment: Appointment? = null,
    val nextQueried: Boolean = false,
    val notesExpanded: Boolean = false,
    val errorMessage: String? = null,
    val isLoading: Boolean = false,
    val isRestoring: Boolean = false,
    val isStarting: Boolean = false,
    val hasLoaded: Boolean = false,
) {
    val showsStartTraining: Boolean
        get() {
            val current = student ?: return false
            return current.lifecycle == StudentLifecycle.active && sessionKnown && inProgress == null && !isRestoring
        }

    val showsRestore: Boolean
        get() = student?.lifecycle == StudentLifecycle.archived
}

class StudentDetailViewModel(
    val studentID: StudentID,
    val useCases: StudentUseCases,
    val sessionRepository: SessionRepositoryPort,
    val creditUseCases: CreditUseCases? = null,
    val historyRepository: HistoryRepositoryPort? = null,
    val clock: AppClock = AppClock { Instant.now() },
    val zoneId: ZoneId = ZoneId.systemDefault(),
    private val appointments: AppointmentUseCases? = null,
) {
    var uiState by mutableStateOf(StudentDetailUiState())
        private set

    private var activeOps by mutableIntStateOf(0)
    val isIdle: Boolean get() = activeOps == 0 && !uiState.isLoading && !uiState.isRestoring && !uiState.isStarting

    fun toggleNotes() {
        uiState = uiState.copy(notesExpanded = !uiState.notesExpanded)
    }

    suspend fun reload() {
        activeOps += 1
        uiState = uiState.copy(isLoading = true)
        try {
            when (val studentRes = useCases.find(studentID)) {
                is ApplicationResult.Failure -> {
                    uiState = uiState.copy(
                        isLoading = false,
                        hasLoaded = false,
                        errorMessage = StudentPresentation.errorMessage(studentRes.error),
                    )
                }
                is ApplicationResult.Success -> {
                    val student = studentRes.value
                    if (student == null) {
                        uiState = uiState.copy(
                            isLoading = false,
                            hasLoaded = false,
                            student = null,
                            errorMessage = StudentPresentation.GENERIC_ERROR,
                        )
                        return
                    }
                    val activeRes = sessionRepository.active(studentID)
                    val sessionKnown = activeRes is ApplicationResult.Success
                    val inProgress = (activeRes as? ApplicationResult.Success)?.value?.let { record ->
                        StudentInProgressSummary(
                            sessionID = record.sessionID,
                            studentID = record.studentID,
                            studentDisplayName = student.displayName,
                            startedAtUTC = record.startedAtUTC,
                            trainingFocus = record.trainingFocus,
                        )
                    }
                    val packageRead = readPackage(student.studentID)
                    val recentRead = readRecent()
                    val nextRead = readNext()
                    val error = when {
                        activeRes is ApplicationResult.Failure -> StudentPresentation.errorMessage(activeRes.error)
                        packageRead.failed || recentRead.failed || nextRead.failed -> StudentPresentation.GENERIC_ERROR
                        else -> null
                    }
                    uiState = uiState.copy(
                        student = student,
                        inProgress = inProgress,
                        sessionKnown = sessionKnown,
                        packageSummary = packageRead.summary,
                        packageQueried = packageRead.queried,
                        recent = recentRead.summary,
                        recentQueried = recentRead.queried,
                        nextAppointment = nextRead.appointment,
                        nextQueried = nextRead.queried,
                        isLoading = false,
                        hasLoaded = true,
                        errorMessage = error,
                    )
                }
            }
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }

    suspend fun restore(): Boolean {
        activeOps += 1
        uiState = uiState.copy(isRestoring = true, errorMessage = null)
        return try {
            when (val res = useCases.restore(studentID)) {
                is ApplicationResult.Failure -> {
                    uiState = uiState.copy(
                        isRestoring = false,
                        errorMessage = StudentPresentation.errorMessage(res.error),
                    )
                    false
                }
                is ApplicationResult.Success -> {
                    uiState = uiState.copy(isRestoring = false)
                    reload()
                    true
                }
            }
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }

    suspend fun startOrOpen(): SessionID? {
        val current = uiState.student ?: return null
        if (current.lifecycle != StudentLifecycle.active || uiState.inProgress != null) return null
        activeOps += 1
        uiState = uiState.copy(isStarting = true, errorMessage = null)
        return try {
            when (val res = sessionRepository.startOrOpen(
                StartOrOpenSessionCommand(studentID = studentID, nowUTC = clock.now()),
            )) {
                is ApplicationResult.Failure -> {
                    uiState = uiState.copy(
                        isStarting = false,
                        errorMessage = StudentPresentation.errorMessage(res.error),
                    )
                    null
                }
                is ApplicationResult.Success -> {
                    uiState = uiState.copy(isStarting = false)
                    res.value.sessionID
                }
            }
        } finally {
            activeOps = maxOf(0, activeOps - 1)
        }
    }

    private data class PackageRead(
        val summary: StudentPackageSummary?,
        val queried: Boolean,
        val failed: Boolean,
    )

    private data class RecentRead(
        val summary: StudentRecentSessionSummary?,
        val queried: Boolean,
        val failed: Boolean,
    )

    private data class NextRead(val appointment: Appointment?, val queried: Boolean, val failed: Boolean)

    private suspend fun readPackage(studentID: StudentID): PackageRead {
        val credits = creditUseCases ?: return PackageRead(summary = null, queried = false, failed = false)
        val today = clock.today(zoneId)
        val active = when (val res = credits.activePackage(studentID, today)) {
            is ApplicationResult.Failure -> return PackageRead(summary = null, queried = false, failed = true)
            is ApplicationResult.Success -> res.value
        }
        if (active == null) return PackageRead(summary = null, queried = true, failed = false)
        return when (val balance = credits.balance(studentID, active.coursePackageID, today)) {
            is ApplicationResult.Failure -> PackageRead(summary = null, queried = false, failed = true)
            is ApplicationResult.Success -> PackageRead(
                summary = active.toSummary(balance.value),
                queried = true,
                failed = false,
            )
        }
    }

    private suspend fun readRecent(): RecentRead {
        val history = historyRepository ?: return RecentRead(summary = null, queried = false, failed = false)
        return when (val res = history.list(HistoryQuery(studentID = studentID))) {
            is ApplicationResult.Failure -> RecentRead(summary = null, queried = false, failed = true)
            is ApplicationResult.Success -> {
                val latest = res.value.maxByOrNull { it.completedAtUTC }
                val content = if (latest != null) {
                    when (val loaded = sessionRepository.loadContent(latest.sessionID)) {
                        is ApplicationResult.Failure -> return RecentRead(null, false, true)
                        is ApplicationResult.Success -> loaded.value
                            ?: return RecentRead(null, false, true)
                    }
                } else null
                RecentRead(
                    summary = latest?.let {
                        StudentRecentSessionSummary(
                            sessionID = it.sessionID,
                            completedAtUTC = it.completedAtUTC,
                            trainingFocus = it.trainingFocus,
                            completedSetCount = content?.toDomain()?.session?.statistics?.completedSetCount,
                        )
                    },
                    queried = true,
                    failed = false,
                )
            }
        }
    }

    private suspend fun readNext(): NextRead {
        val booked = appointments ?: return NextRead(null, true, false)
        return when (val res = booked.all()) {
            is ApplicationResult.Failure -> NextRead(null, false, true)
            is ApplicationResult.Success -> {
                val now = clock.now()
                NextRead(res.value.filter {
                    it.studentID == studentID && it.status == AppointmentStatus.scheduled && it.startInstant(zoneId) > now
                }.minByOrNull { it.startInstant(zoneId) }, true, false)
            }
        }
    }
}

private fun CoursePackageRecord.toSummary(balance: Long) = StudentPackageSummary(
    balance = balance,
    totalCredits = totalCredits,
    endDate = endDate,
)

@Composable
fun StudentDetailScreen(
    viewModel: StudentDetailViewModel,
    onRoute: (String) -> Unit,
    onBack: () -> Unit,
    autoLoad: Boolean = true,
    insets: WindowInsets = WindowInsets.safeDrawing,
    insights: InsightBoardState? = null,
    onAppointment: (java.util.UUID) -> Unit = {},
) {
    val scope = rememberCoroutineScope()
    LaunchedEffect(viewModel, autoLoad, insights) {
        if (autoLoad && !viewModel.uiState.hasLoaded && viewModel.uiState.errorMessage == null) {
            viewModel.reload()
        }
        if (insights?.snapshot == null) insights?.load()
    }
    val state = viewModel.uiState
    val student = state.student

    FcPlatformShell(onBack = onBack, insets = insets) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .testTag(StudentTestTags.DETAIL_ROOT),
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = FcSpacing.space6),
                verticalArrangement = Arrangement.spacedBy(FcSpacing.space4),
            ) {
                FcPageHeader(
                    title = student?.displayName.orEmpty(),
                    onBack = onBack,
                    tag = StudentTestTags.DETAIL_HEADER,
                    trailingTitle = if (student != null) "编辑资料" else null,
                    onTrailing = {
                        student?.let { onRoute(S1Routes.studentEdit(it.studentID)) }
                    },
                )
                state.errorMessage?.let { message ->
                    FcInlineResult(
                        variant = FcResultVariant.Failure,
                        title = message,
                        description = "请重试。",
                        icon = painterResource(R.drawable.ic_ms_priority_high),
                        modifier = Modifier.testTag(StudentTestTags.DETAIL_ERROR),
                        onRetry = { scope.launch { viewModel.reload() } },
                        tag = StudentTestTags.DETAIL_ERROR,
                    )
                }
                if (student != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        FcAvatar(name = student.displayName, modifier = Modifier.testTag("conformance:Avatar"))
                        FcText(
                            text = StudentPresentation.goalText(student.trainingGoal),
                            style = FcTypography.callout,
                            color = FcColors.textSecondary,
                        )
                    }
                    if (student.lifecycle == StudentLifecycle.archived) {
                        Column(verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                            FcHintBar(
                                text = "已归档",
                                modifier = Modifier.testTag(StudentTestTags.DETAIL_ARCHIVED_STATUS),
                            )
                            FcText(
                                text = "不能开始新训练。仍可查看下方历史，或恢复为活跃学员。",
                                style = FcTypography.caption,
                                color = FcColors.textSecondary,
                            )
                        }
                    }
                    state.inProgress?.let { summary ->
                        FcHeroCard(
                            badgeText = "进行中",
                            title = StudentPresentation.heroTitle(summary.studentDisplayName, summary.trainingFocus),
                            subtitle = StudentPresentation.heroElapsedSubtitle(summary, viewModel.clock.now()),
                            actionTitle = "继续训练",
                            modifier = Modifier.testTag(StudentTestTags.DETAIL_CONTINUE_TRAINING),
                            onClick = { onRoute(S1Routes.activeSession(summary.sessionID)) },
                        )
                    }
                    if (insights != null) InsightStudentSection(insights, student.studentID) { insight ->
                        insightDestination(insight, viewModel.clock.today(viewModel.zoneId))?.let(onRoute)
                    }
                    OverviewSection(state = state, zoneId = viewModel.zoneId, today = viewModel.clock.today(viewModel.zoneId),
                        onRoute = onRoute, onAppointment = onAppointment)
                    RecordsSection(studentID = student.studentID, onRoute = onRoute)
                    ProfileSection(
                        student = student,
                        notesExpanded = state.notesExpanded,
                        onToggleNotes = viewModel::toggleNotes,
                    )
                }
            }
            if (state.showsRestore) {
                DetailPrimaryButton(
                    title = "恢复学员",
                    tag = StudentTestTags.DETAIL_RESTORE,
                    enabled = !state.isRestoring,
                    onClick = { scope.launch { viewModel.restore() } },
                )
            } else if (state.showsStartTraining) {
                DetailPrimaryButton(
                    title = "开始训练",
                    tag = StudentTestTags.DETAIL_START_TRAINING,
                    enabled = !state.isStarting,
                    onClick = {
                        scope.launch {
                            val sessionID = viewModel.startOrOpen()
                            if (sessionID != null) onRoute(S1Routes.activeSession(sessionID))
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun DetailPrimaryButton(
    title: String,
    tag: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(FcColors.surfacePage)
            .padding(top = FcSpacing.space2, bottom = FcSpacing.space8),
    ) {
        FcButton(
            title = title,
            modifier = Modifier.testTag(tag),
            enabled = enabled,
            onClick = onClick,
        )
    }
}

@Composable
private fun OverviewSection(
    state: StudentDetailUiState,
    zoneId: ZoneId,
    today: LocalDate,
    onRoute: (String) -> Unit,
    onAppointment: (java.util.UUID) -> Unit,
) {
    val student = state.student ?: return
    Column(modifier = Modifier.fillMaxWidth()) {
        FcSectionLabel(
            title = "概览",
            modifier = Modifier.padding(bottom = FcSpacing.space2),
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        StudentOverviewRow(
            kicker = "下一节课",
            modifier = Modifier.testTag("studentDetail.nextClass"),
            onClick = {
                val next = state.nextAppointment
                if (next != null) onAppointment(next.id) else onRoute(InsightRoutes.appointment(today, student.studentID))
            },
        ) {
            if (state.nextQueried) {
                FcText(StudentPresentation.nextClassText(state.nextAppointment), style = FcTypography.body, color = FcColors.textPrimary)
            }
        }
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        StudentOverviewRow(
            kicker = "课包",
            modifier = Modifier.testTag(StudentTestTags.DETAIL_COURSE_PACKAGES),
            onClick = { onRoute(S1Routes.studentPackages(student.studentID)) },
        ) {
            val summary = state.packageSummary
            when {
                summary != null -> {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space1),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        FcText(
                            text = summary.balance.toString(),
                            style = FcTypography.numeralLarge,
                            color = FcColors.textPrimary,
                        )
                        FcText(
                            text = StudentPresentation.packageDetailText(summary.totalCredits, summary.endDate),
                            style = FcTypography.callout,
                            color = FcColors.textSecondary,
                        )
                    }
                }
                state.packageQueried -> {
                    FcText(
                        text = "新建课包后，上完课会按课时扣减",
                        style = FcTypography.body,
                        color = FcColors.textSecondary,
                    )
                }
            }
        }
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        StudentOverviewRow(
            kicker = "最近训练",
            modifier = Modifier.testTag(StudentTestTags.DETAIL_RECENT_TRAINING),
            onClick = {
                val recent = state.recent
                if (state.recentQueried && recent != null) {
                    onRoute(S1Routes.historyDetail(recent.sessionID))
                } else {
                    onRoute(S1Routes.studentHistory(student.studentID))
                }
            },
        ) {
            if (state.recentQueried) {
                FcText(
                    text = StudentPresentation.recentTrainingText(state.recent, zoneId),
                    style = FcTypography.body,
                    color = if (state.recent == null) FcColors.textSecondary else FcColors.textPrimary,
                )
            }
        }
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
    }
}

@Composable
private fun RecordsSection(
    studentID: StudentID,
    onRoute: (String) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        FcSectionLabel(
            title = "记录",
            modifier = Modifier.padding(bottom = FcSpacing.space2),
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        FcActionRow(
            title = "训练历史",
            modifier = Modifier.testTag(StudentTestTags.DETAIL_HISTORY),
            onClick = { onRoute(S1Routes.studentHistory(studentID)) },
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        FcActionRow(
            title = "训练趋势",
            modifier = Modifier.testTag("studentDetail.trends"),
            onClick = { onRoute(S1Routes.studentTrends(studentID)) },
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        FcActionRow(
            title = "身体数据",
            modifier = Modifier.testTag("studentDetail.body"),
            onClick = { onRoute(S1Routes.studentBody(studentID)) },
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
    }
}

@Composable
private fun ProfileSection(
    student: StudentRecord,
    notesExpanded: Boolean,
    onToggleNotes: () -> Unit,
) {
    val hasNotes = !student.injuryNotes.isNullOrEmpty()
    Column(modifier = Modifier.fillMaxWidth()) {
        FcSectionLabel(
            title = "资料",
            modifier = Modifier.padding(bottom = FcSpacing.space2),
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        FcLabelValueText(
            label = "性别",
            value = StudentSexPresentation.title(student.sex),
            modifier = Modifier.testTag(StudentTestTags.DETAIL_PROFILE_SEX),
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        ProfileValue(
            label = "电话",
            value = StudentPresentation.filledOrUnfilled(student.phone),
            modifier = Modifier.testTag(StudentTestTags.DETAIL_PROFILE_PHONE),
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        ProfileValue(
            label = "微信",
            value = StudentPresentation.filledOrUnfilled(student.wechatID),
            modifier = Modifier.testTag(StudentTestTags.DETAIL_PROFILE_WECHAT),
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        ProfileValue(
            label = "教练备注",
            value = StudentPresentation.filledOrUnfilled(student.privateCoachNote),
            modifier = Modifier.testTag(StudentTestTags.DETAIL_PROFILE_PRIVATE_NOTE),
        )
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        FcLabelValueRow(
            label = "注意事项",
            modifier = Modifier.testTag(StudentTestTags.DETAIL_NOTES_FOLD).then(
                if (hasNotes) {
                    Modifier.semantics {
                        stateDescription = if (notesExpanded) "已展开" else "已折叠"
                    }
                } else {
                    Modifier
                },
            ),
            onClick = if (hasNotes) onToggleNotes else null,
        ) {
            val text = when {
                !hasNotes -> "未填写"
                notesExpanded -> student.injuryNotes.orEmpty()
                else -> "已隐藏 · 点击查看"
            }
            FcText(
                text = text,
                modifier = if (hasNotes && notesExpanded) Modifier.testTag(StudentTestTags.DETAIL_NOTES_BODY) else Modifier,
                style = FcTypography.body,
                color = if (!hasNotes || !notesExpanded) FcColors.textSecondary else FcColors.textPrimary,
            )
        }
        if (hasNotes && notesExpanded) {
            FcText(
                text = "此内容不是医疗诊断或医疗建议。仅教练可见，不进入分享报告。",
                modifier = Modifier.padding(bottom = FcSpacing.space3),
                style = FcTypography.caption,
                color = FcColors.textSecondary,
            )
        }
        FcListRowDivider(Modifier.testTag("conformance:Divider"))
        FcText(
            text = "电话与微信由教练手输。不读取系统通讯录，不询问联系人权限。",
            modifier = Modifier.padding(top = FcSpacing.space3),
            style = FcTypography.caption,
            color = FcColors.textSecondary,
        )
    }
}

@Composable
private fun ProfileValue(label: String, value: String, modifier: Modifier = Modifier) {
    FcLabelValueRow(label = label, modifier = modifier.semantics(mergeDescendants = true) { }) {
        FcText(value, style = FcTypography.body,
            color = if (value == "未填写") FcColors.textSecondary else FcColors.textPrimary)
    }
}
