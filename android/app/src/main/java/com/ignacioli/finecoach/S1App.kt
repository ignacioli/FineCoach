package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.semantics.stateDescription
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.compose.*
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.students.*
import com.ignacioli.finecoach.features.packages.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.features.templates.*
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.features.history.*
import com.ignacioli.finecoach.features.today.*
import com.ignacioli.finecoach.features.resources.*
import com.ignacioli.finecoach.navigation.*
import com.ignacioli.finecoach.notifications.*
import kotlinx.coroutines.launch

@Composable
fun S1Root(activity: MainActivity) {
    val context = LocalContext.current
    var graph by remember { mutableStateOf<S1AppGraph?>(null) }
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        when (val result = S1Runtime.open(context)) {
            is ApplicationResult.Failure -> failed = true
            is ApplicationResult.Success -> { graph = result.value; failed = false }
        }
    }
    graph?.let { value ->
        S1App(value, activity.restNotificationSessionID, activity::consumeRestNotificationRoute, activity.notificationPermissionRevision)
    } ?: if (!failed) FcLaunch(Modifier.testTag("s1-loading")) else FcPlatformShell({}, Modifier.testTag("s1-loading")) {
        if (failed) {
            FcText("没有完成，再试一次。", Modifier.testTag("s1-load-error"),
                style = FcTypography.caption, color = FcColors.statusDestructive)
            FcButton("重试", Modifier.testTag("s1-load-retry")) { failed = false; attempt++ }
        }
    }
}

@Composable
private fun OnResume(action: suspend () -> Unit) {
    val lifecycle = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val latest by rememberUpdatedState(action)
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) scope.launch { latest() } }
        lifecycle.lifecycle.addObserver(observer)
        onDispose { lifecycle.lifecycle.removeObserver(observer) }
    }
}

@Composable
private fun AfterStopResume(action: suspend () -> Unit) {
    val lifecycle = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val latest by rememberUpdatedState(action)
    DisposableEffect(lifecycle) {
        var stopped = false
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) stopped = true
            if (event == Lifecycle.Event.ON_RESUME && stopped) {
                stopped = false
                scope.launch { latest() }
            }
        }
        lifecycle.lifecycle.addObserver(observer)
        onDispose { lifecycle.lifecycle.removeObserver(observer) }
    }
}

@Composable
fun S1App(graph: S1AppGraph, notificationSession: SessionID? = null, consumeNotification: () -> Unit = {}, permissionRevision: Int = 0) {
    val nav = rememberNavController()
    val navigator = remember(nav) { S1Navigator(nav) }
    var recovered by remember(graph) { mutableStateOf(false) }
    var recoveryError by remember { mutableStateOf(false) }
    var recoveryAttempt by remember { mutableIntStateOf(0) }
    var notificationMissing by remember { mutableStateOf(false) }
    var adjustmentRequested by remember { mutableStateOf<CoursePackageID?>(null) }
    val adapter = remember(graph) { RestNotifications(graph.context) }
    LaunchedEffect(graph, recoveryAttempt) {
        graph.prepareExerciseCatalog()
        graph.rests.notifications = adapter
        when (graph.recovery.reconcileOnLaunch()) {
            is ApplicationResult.Failure -> recoveryError = true
            is ApplicationResult.Success -> { recovered = true; recoveryError = false }
        }
    }
    LaunchedEffect(permissionRevision) { graph.rests.rescheduleAll() }
    LaunchedEffect(recovered, notificationSession) {
        if (recovered && notificationSession != null) {
            when (val result = graph.sessions.find(notificationSession)) {
                is ApplicationResult.Failure -> notificationMissing = true
                is ApplicationResult.Success -> if (result.value?.state == SessionState.inProgress) navigator.open(S1Routes.activeSession(notificationSession)) else notificationMissing = true
            }
            consumeNotification()
        }
    }
    if (!recovered) {
        FcPlatformShell({}, Modifier.testTag("s1-recovery-state")) {
            if (recoveryError) {
                FcText("恢复失败", Modifier.testTag("s1-recovery-error"),
                    style = FcTypography.caption, color = FcColors.statusDestructive)
                FcButton("重试", Modifier.testTag("s1-recovery-retry")) { recoveryError = false; recoveryAttempt++ }
            }
        }; return
    }
    val back = { navigator.back() }
    NavHost(nav, startDestination = S1Routes.TODAY, modifier = Modifier.fillMaxSize().testTag("s1-navigation").semantics { testTagsAsResourceId = true }) {
        composable(S1Routes.TODAY) {
            val today = remember { TodayUiState(graph.sessions, graph.students, graph.clock) }
            OnResume { today.load() }
            TodayScreen(today, navigator::open)
        }
        composable(S1Routes.STUDENTS) {
            val state = remember { StudentListViewModel(graph.students, sessionRepository = graph.sessions, creditUseCases = graph.credits, clock = graph.clock, zoneId = graph.zone) }
            OnResume { state.reload() }
            StudentListScreen(state, navigator::open, { navigator.open(S1Routes.TODAY) }, showRootSwitch = true, autoLoad = false)
        }
        composable(S1Routes.STUDENT_CREATE) {
            val state = remember { StudentEditorViewModel(StudentEditorMode.Add, graph.students) }
            StudentEditorScreen(state, back, { record -> if (record != null) { navigator.back(); navigator.open(S1Routes.studentDetail(record.studentID)) } }, sessionRepository = graph.sessions, historyRepository = graph.historyRepository)
        }
        composable(S1Routes.STUDENT_DETAIL) { entry ->
            val id = StudentID.parse(requireNotNull(entry.arguments?.getString(S1Routes.ARG_STUDENT_ID)))
            val state = remember(id) { StudentDetailViewModel(id, graph.students, graph.sessions, graph.credits, graph.historyRepository, graph.clock, graph.zone) }
            OnResume { state.reload() }
            StudentDetailScreen(state, navigator::open, back, autoLoad = false)
        }
        composable(S1Routes.STUDENT_EDIT) { entry ->
            val id = StudentID.parse(requireNotNull(entry.arguments?.getString(S1Routes.ARG_STUDENT_ID)))
            val state = remember(id) { StudentEditorViewModel(StudentEditorMode.Edit(id), graph.students) }
            StudentEditorScreen(state, back, { back() }, onArchived = back, onDeleted = { navigator.open(S1Routes.STUDENTS) },
                onRoute = navigator::open, sessionRepository = graph.sessions, historyRepository = graph.historyRepository)
        }
        composable(S1Routes.STUDENT_PACKAGES) { entry ->
            val id = StudentID.parse(requireNotNull(entry.arguments?.getString(S1Routes.ARG_STUDENT_ID)))
            var create by remember { mutableStateOf(false) }
            var manual by remember { mutableStateOf<CoursePackageID?>(null) }
            when {
                create -> CoursePackageEditorScreen(id, graph.credits, graph.clock, graph.zone, { create = false }, { create = false })
                manual != null -> ManualCreditAdjustmentScreen(manual!!, graph.credits, { manual = null }, { manual = null })
                else -> CoursePackageListScreen(id, graph.credits, graph.zone, back, { create = true }, { manual = it }, { navigator.open(S1Routes.packageDetail(it)) }, students = graph.students)
            }
        }
        composable(S1Routes.PACKAGE_DETAIL) { entry ->
            val id = CoursePackageID.parse(requireNotNull(entry.arguments?.getString(S1Routes.ARG_PACKAGE_ID)))
            if (adjustmentRequested == id) {
                val done = { adjustmentRequested = null; back() }
                ManualCreditAdjustmentScreen(id, graph.credits, done, done)
            } else S1PackageTrail(graph, id, back)
        }
        composable(S1Routes.STUDENT_HISTORY) { entry ->
            val id = StudentID.parse(requireNotNull(entry.arguments?.getString(S1Routes.ARG_STUDENT_ID)))
            val state = remember(id) { HistoryUiState(graph.history, id, graph.students) }
            OnResume { state.list() }
            HistoryListScreen(state, graph.zone, navigator::open, back)
        }
        composable(S1Routes.HISTORY_DETAIL) { entry ->
            val id = SessionID.parse(requireNotNull(entry.arguments?.getString(S1Routes.ARG_SESSION_ID)))
            val state = remember(id) { HistoryUiState(graph.history, null, graph.students) }
            val templates = remember(id) { HistoryTemplateState(graph.templates, graph.clock, graph.ids) }
            HistoryDetailScreen(state, id, graph.zone, back, templates)
        }
        composable(S1Routes.RESOURCE_HUB) {
            ResourceHubScreen(graph.exerciseRepository, graph.templates, navigator::open, back)
        }
        composable(S1Routes.EXERCISES) {
            val state = remember { ExerciseUiState(graph.exercises, graph.exerciseRepository, graph.historyRepository, graph.sessions) }
            ExerciseLibraryScreen(state, back)
        }
        composable(S1Routes.TEMPLATES) {
            val state = remember { TemplateUiState(graph.templates, graph.clock, graph.ids) }
            TemplateListScreen(state, navigator::open, back)
        }
        composable(S1Routes.TEMPLATE_DETAIL) { entry ->
            val id = TemplateID.parse(requireNotNull(entry.arguments?.getString(S1Routes.ARG_TEMPLATE_ID)))
            val state = remember(id) { TemplateUiState(graph.templates, graph.clock, graph.ids) }
            val exercises = remember { ExerciseUiState(graph.exercises, graph.exerciseRepository, graph.historyRepository, graph.sessions) }
            TemplateEditorScreen(state, id, exercises, back)
        }
        composable(S1Routes.SESSION_ACTIVE) { entry ->
            val id = SessionID.parse(requireNotNull(entry.arguments?.getString(S1Routes.ARG_SESSION_ID)))
            S1ActiveDestination(graph, id, back, { navigator.open(S1Routes.TODAY) }, { adjustmentRequested = it; navigator.open(S1Routes.packageDetail(it)) })
        }
    }
    if (notificationMissing) FcConfirmationDialog("训练无法打开", "该训练已结束或不存在。", "知道了", { notificationMissing = false }, { notificationMissing = false }, tag = "notification-unavailable")
}

@Composable
private fun S1ActiveDestination(graph: S1AppGraph, id: SessionID, onBack: () -> Unit, onToday: () -> Unit, onAdjust: (CoursePackageID) -> Unit) {
    val active = remember(id) { ActiveSessionUiState(graph.active, graph.clock, graph.ids, graph.sessions, graph.historyRepository, graph.exercises, graph.rests) }
    val exercises = remember { ExerciseUiState(graph.exercises, graph.exerciseRepository, graph.historyRepository, graph.sessions) }
    val templates = remember { TemplateUiState(graph.templates, graph.clock, graph.ids) }
    val summary = remember(id) { SessionSummaryUiState(graph.history, graph.clock) }
    val summaryTemplates = remember(id) { HistoryTemplateState(graph.templates, graph.clock, graph.ids) }
    var finishing by remember { mutableStateOf(false) }
    var summarizing by remember { mutableStateOf(false) }
    LaunchedEffect(id) {
        val existing = graph.sessions.find(id)
        if (existing is ApplicationResult.Success && existing.value?.state == SessionState.completed) summarizing = true
    }
    AfterStopResume {
        active.resume(id)
        if (active.error == null && active.content?.session?.state == SessionState.completed) summarizing = true
    }
    Box(Modifier.fillMaxSize().testTag("active-destination-${id.value}").semantics { stateDescription = if (active.busy) "正在加载" else "已加载" }) {
    when {
        summarizing -> SessionSummaryScreen(summary, id, onToday, onToday) { summary.detail?.let { HistoryTemplateEntry(summaryTemplates, it.content) } }
        finishing -> {
            val state = remember(id) { FinishSessionUiState(active, graph.finisher, graph.sessions) }
            FinishSessionScreen(state, { finishing = false }, onToday, { summarizing = true }, onAdjust)
        }
        else -> ActiveSessionScreen(active, id, exercises, templates, onBack, { finishing = true }, students = graph.studentRepository)
    }
    }
}

@Composable
private fun S1PackageTrail(graph: S1AppGraph, id: CoursePackageID, onBack: () -> Unit) {
    var owner by remember(id) { mutableStateOf<StudentID?>(null) }
    var failed by remember(id) { mutableStateOf(false) }
    LaunchedEffect(id) {
        when (val result = graph.packageOwner(id)) {
            is ApplicationResult.Failure -> failed = true
            is ApplicationResult.Success -> { owner = result.value; failed = result.value == null }
        }
    }
    owner?.let { CreditAdjustmentTrailScreen(it, id, graph.credits, graph.zone, onBack) } ?: FcPlatformShell(onBack) {
        FcPageHeader("课时流水", onBack = onBack, tag = "package-trail-loading")
        FcListRow(if (failed) "课包无法打开，请返回重试" else "正在加载")
    }
}
