package com.ignacioli.finecoach.features.today

import androidx.compose.foundation.layout.*
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
    var items by mutableStateOf<List<FcHeroEntry>>(emptyList()); private set
    var loading by mutableStateOf(true); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    suspend fun load() {
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
        items = rows; error = null; loading = false
    }
}

@Composable
fun TodayScreen(state: TodayUiState, onNavigate: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    LaunchedEffect(state) { state.load() }
    FcPlatformShell({}) {
        FcPageHeader("今日", tag = "today")
        FcSegmentedSwitch(listOf("今日", "学员"), 0, { if (it == 1) onNavigate(S1Routes.STUDENTS) }, tag = "root")
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("today-content"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            when {
                state.loading -> FcListRow("正在加载", Modifier.testTag("today-loading"))
                state.error != null -> { FcListRow("加载失败，请重试", Modifier.testTag("today-error")); FcButton("重试", Modifier.testTag("today-retry")) { scope.launch { state.load() } } }
                state.items.isEmpty() -> FcListRow("今天还没有进行中的训练", Modifier.testTag("today-empty"))
                state.items.size == 1 -> state.items.single().let { row -> FcHeroCard("进行中", row.title, row.subtitle,
                    Modifier.testTag("hero-${row.id}"), "继续训练", { onNavigate(S1Routes.activeSession(SessionID.parse(row.id))) }) }
                else -> FcMultiHeroCard(state.items, { onNavigate(S1Routes.activeSession(SessionID.parse(it))) }, Modifier.testTag("today-hero"))
            }
            FcSectionLabel("训练资料")
            FcActionRow("动作库", Modifier.testTag("today-exercises")) { onNavigate(S1Routes.EXERCISES) }
            FcActionRow("训练模板", Modifier.testTag("today-templates")) { onNavigate(S1Routes.TEMPLATES) }
        }
    }
}
