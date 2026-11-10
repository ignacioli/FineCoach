package com.ignacioli.finecoach.features.today

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.navigation.S1Routes
import kotlinx.coroutines.launch
import java.time.Duration

class TodayUiState(private val sessions: SessionRepositoryPort, private val students: StudentUseCases, private val clock: AppClock) {
    var todayDate by mutableStateOf(clock.now().atZone(ZoneId.systemDefault()).toLocalDate()); private set
    var hasCompletedInitialLoad by mutableStateOf(false); private set
    var items by mutableStateOf<List<FcHeroEntry>>(emptyList()); private set
    var loading by mutableStateOf(true); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    suspend fun load() {
        todayDate = clock.now().atZone(ZoneId.systemDefault()).toLocalDate()
        loading = true
        val result = sessions.listActiveSessions()
        if (result is ApplicationResult.Failure) { error = result.error; loading = false; return }
        val rows = mutableListOf<FcHeroEntry>()
        for (snapshot in (result as ApplicationResult.Success).value.sortedBy { it.startedAtUTC }) {
            val student = students.find(snapshot.studentID)
            val content = sessions.loadContent(snapshot.sessionID)
            if (student is ApplicationResult.Failure || content is ApplicationResult.Failure) {
                error = (student as? ApplicationResult.Failure)?.error ?: (content as ApplicationResult.Failure).error
                loading = false; return
            }
            val name = (student as ApplicationResult.Success).value?.displayName
            val session = (content as ApplicationResult.Success).value?.session
            if (name == null || session == null || session.state != SessionState.inProgress || session.studentID != snapshot.studentID) {
                error = ApplicationError(ApplicationErrorCode.invalidState); loading = false; return
            }
            val focus = session.trainingFocus.joinToString("、") { FcBodyParts[BodyPart.entries.indexOf(it)] }
            val elapsed = session.elapsedSeconds.toLong() + maxOf(0, Duration.between(session.lastCheckpointUTC, clock.now()).seconds)
            rows += FcHeroEntry(snapshot.sessionID.value, if (focus.isBlank()) name else "$name · $focus", "已训练 ${elapsed / 60} 分钟")
        }
        items = rows; error = null; hasCompletedInitialLoad = true; loading = false
    }
}

@Composable
fun TodayScreen(state: TodayUiState, onNavigate: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    LaunchedEffect(state) { state.load() }
    FcPlatformShell({}) {
        FcPagePrimary("今日", Modifier.fillMaxSize(),
            segments = { FcSegmentedSwitch(listOf("今日", "学员"), 0, { if (it == 1) onNavigate(S1Routes.STUDENTS) }, tag = "root") },
            subtitleModifier = Modifier.testTag("today-date"), subtitle = state.todayDate.format(DateTimeFormatter.ofPattern("M月d日 · EEE", Locale.SIMPLIFIED_CHINESE))) {
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("today-content"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            if (state.error != null) {
                Text("加载今日安排失败，再试一次。", Modifier.testTag("today-error"), style = FcTypography.caption, color = FcColors.statusDestructive)
                FcButton("重试", Modifier.testTag("today-retry")) { scope.launch { state.load() } }
            }
            when {
                !state.hasCompletedInitialLoad -> Spacer(Modifier.fillMaxWidth().testTag("today-loading"))
                state.items.isEmpty() -> FcEmptyState("今天没课，休息一下吧～", "有新课程时会显示在这里",
                    Modifier.fillMaxWidth().padding(vertical = FcSpacing.space4).testTag("today-empty"), ambient = true)
                state.items.size == 1 -> state.items.single().let { row -> FcHeroCard("进行中", row.title, row.subtitle,
                    Modifier.testTag("hero-${row.id}"), "继续训练", { onNavigate(S1Routes.activeSession(SessionID.parse(row.id))) }) }
                else -> FcMultiHeroCard(state.items, { onNavigate(S1Routes.activeSession(SessionID.parse(it))) }, Modifier.testTag("today-hero"))
            }
        }
        }
    }
}
