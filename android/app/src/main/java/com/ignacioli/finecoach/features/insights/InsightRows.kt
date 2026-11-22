package com.ignacioli.finecoach.features.insights

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.insight.Insight
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

private const val NudgeOutMillis = 250
private const val NudgeHoldMillis = 600
private const val NudgeBackMillis = 350

@Composable
fun InsightTodaySection(state: InsightBoardState, onOpen: (Insight) -> Unit, onAll: () -> Unit) {
    val snapshot = state.snapshot ?: return
    val rows = state.visible().take(3)
    if (rows.isEmpty() && !snapshot.failed) return
    Column(Modifier.fillMaxWidth().testTag("today.insights")) {
        if (snapshot.failed) InsightFailure(state)
        if (rows.isNotEmpty()) {
            InsightBlock(state, rows, InsightContext.today, nudge = true, onOpen = onOpen)
            if (state.visible().size > 3) {
                FcGroupEntryRow("全部", state.visible().size, Modifier.testTag("today.insights.all"), onAll)
            }
        }
    }
}

@Composable
fun InsightStudentSection(state: InsightBoardState, studentID: StudentID, onOpen: (Insight) -> Unit) {
    val snapshot = state.snapshot ?: return
    val rows = state.visible(studentID)
    if (rows.isEmpty() && !snapshot.failed) return
    Column(Modifier.fillMaxWidth().testTag("studentDetail.insights")) {
        if (snapshot.failed) InsightFailure(state)
        if (rows.isNotEmpty()) InsightBlock(state, rows, InsightContext.studentDetail, nudge = false, onOpen = onOpen)
    }
}

@Composable
fun InsightsListScreen(state: InsightBoardState, onBack: () -> Unit, onOpen: (Insight) -> Unit) {
    LaunchedEffect(state) { if (state.snapshot == null) state.load() }
    val rows = state.visible()
    FcPageSecondary("需要留意", onBack, tag = "insights-list") {
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(bottom = FcSpacing.space6)
            .testTag("insights-list-content"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            if (state.snapshot?.failed == true) InsightFailure(state)
            if (state.snapshot != null && rows.isEmpty() && pendingCount(state) == 0) {
                FcText("没有需要留意的事", Modifier.testTag("insights.empty"), style = FcTypography.caption, color = FcColors.textSecondary)
            }
            for (group in InsightGroup.entries) {
                val members = rows.filter { it.kind in group.kinds }
                if (members.isNotEmpty()) {
                    Column(Modifier.fillMaxWidth()) {
                        FcSectionLabel(group.title, Modifier.padding(bottom = FcSpacing.space2).testTag("insights.group.${group.tag}"))
                        InsightBlock(state, members, InsightContext.list, nudge = false, onOpen = onOpen, heading = false)
                    }
                }
            }
        }
    }
}

private fun pendingCount(state: InsightBoardState) = state.pending.size

@Composable
private fun InsightFailure(state: InsightBoardState) {
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcText("需要留意暂时算不出来，再试一次。", style = FcTypography.caption, color = FcColors.statusDestructive)
        FcButton("重试", Modifier.testTag("insights-retry")) { scope.launch { state.load() } }
    }
}

private enum class InsightGroup(val title: String, val tag: String, val kinds: Set<Insight.Kind>) {
    Package("课包", "package", setOf(Insight.Kind.packageExhausted, Insight.Kind.packageExpired, Insight.Kind.packageLow)),
    Inactive("很久没来", "inactive", setOf(Insight.Kind.inactive)),
    Stagnant("进步停滞", "stagnant", setOf(Insight.Kind.stagnant)),
}

@Composable
private fun InsightBlock(state: InsightBoardState, rows: List<Insight>, context: InsightContext, nudge: Boolean,
    onOpen: (Insight) -> Unit, heading: Boolean = true) {
    val scope = rememberCoroutineScope()
    val reduceMotion = reduceMotion()
    val first = rows.first().snoozeKey
    LaunchedEffect(first, nudge, reduceMotion, state.snapshot?.nudgePlayed) {
        val played = state.snapshot?.nudgePlayed != false
        if (!nudge || rows.isEmpty() || played) return@LaunchedEffect
        if (reduceMotion) { state.skipNudge(); return@LaunchedEffect }
        state.beginNudge()
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(if (heading) FcSpacing.space2 else FcSpacing.space1)) {
        if (heading) FcSectionLabel("需要留意")
        Column(Modifier.fillMaxWidth()) {
            FcListRowDivider(Modifier.testTag(if (context == InsightContext.studentDetail) "conformance:Divider" else "conformance:DS-LIST-ROW · divider"))
            for (index in rows.indices) {
                val insight = rows[index]
                val pending = state.pending[insight.snoozeKey]
                if (pending != null) {
                    LaunchedEffect(insight.snoozeKey) {
                        kotlinx.coroutines.delay(state.undoRemainingMillis(insight.snoozeKey))
                        state.commit(insight.snoozeKey)
                    }
                    val name = state.snapshot?.studentNames[insight.studentID].orEmpty()
                    FcUndoRow(insightUndoMessage(name, context), Modifier.testTag("insights.undo.${insight.snoozeKey}"),
                        tag = "insights.undo.${insight.snoozeKey}") { scope.launch { state.undo(insight) } }
                } else {
                    InsightSwipeRow(state, insight, context, nudge = nudge && index == 0 && !reduceMotion, onOpen = { onOpen(insight) })
                }
                FcListRowDivider(Modifier.testTag(if (context == InsightContext.studentDetail) "conformance:Divider" else "conformance:DS-LIST-ROW · divider"))
            }
        }
    }
}

@Composable
private fun reduceMotion(): Boolean {
    val resolver = LocalContext.current.contentResolver
    val scale = Settings.Global.getString(resolver, Settings.Global.ANIMATOR_DURATION_SCALE)
    return scale == "0" || scale == "0.0"
}

@Composable
private fun InsightSwipeRow(state: InsightBoardState, insight: Insight, context: InsightContext, nudge: Boolean, onOpen: () -> Unit) {
    val scope = rememberCoroutineScope()
    val copy = insightCopy(insight, state.snapshot?.studentNames[insight.studentID].orEmpty(),
        insight.exerciseID?.let { state.snapshot?.exerciseNames[it] }.orEmpty(), context)
    val density = LocalDensity.current
    val hint = with(density) { (FcComponentMetrics.hub + FcSpacing.space2).toPx() }
    val shift = remember { Animatable(0f) }
    var open by remember { mutableStateOf(false) }
    var width by remember { mutableIntStateOf(0) }
    LaunchedEffect(nudge, state.nudgePhase) {
        if (nudge && state.nudgePhase == "playing" && state.snapshot?.nudgePlayed == false) {
            shift.animateTo(hint, tween(NudgeOutMillis, easing = FcMotion.curveStandard))
            kotlinx.coroutines.delay(NudgeHoldMillis.toLong())
            shift.animateTo(0f, tween(NudgeBackMillis, easing = FcMotion.curveStandard))
            state.markNudgePlayed()
        }
    }
    val reveal = if (open) hint else shift.value
    Box(Modifier.fillMaxWidth().onSizeChanged { width = it.width }.pointerInput(open) {
        var drag = 0f
        detectHorizontalDragGestures(onDragStart = { drag = 0f }, onDragEnd = {
            if (width > 0 && drag <= -width * 0.8f) { open = false; scope.launch { state.snooze(insight) } }
            else if (drag < -with(density) { FcComponentMetrics.touch.toPx() }) open = true
            else if (drag > with(density) { FcComponentMetrics.touch.toPx() }) open = false
        }, onHorizontalDrag = { change, amount -> change.consume(); drag += amount })
    }) {
        if (reveal > 0f) {
            Box(Modifier.matchParentSize(), contentAlignment = Alignment.CenterEnd) {
                Row(Modifier.clip(CircleShape).background(FcColors.textSecondary)
                    .padding(horizontal = FcSpacing.space2, vertical = FcSpacing.space2)
                    .then(if (open) Modifier.testTag("insights.snooze.${insight.snoozeKey}").clickable(role = Role.Button) {
                        open = false; scope.launch { state.snooze(insight) }
                    } else Modifier.semantics { hideFromAccessibility() }.testTag("insights.nudge.${insight.snoozeKey}")),
                    horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2), verticalAlignment = Alignment.CenterVertically) {
                    FcSymbol(painterResource(R.drawable.ic_ms_notifications), Modifier.size(FcSpacing.space4), tint = FcColors.actionOn)
                    FcText("暂不提醒", style = FcTypography.caption, color = FcColors.actionOn, maxLines = 1, softWrap = false)
                }
            }
        }
        Column(Modifier.fillMaxWidth().padding(end = with(density) { reveal.toDp() }).clipToBounds()
            .background(FcColors.surfacePage)) {
            Column(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onOpen).semantics {
                contentDescription = copy.accessibilityLabel
                customActions = listOf(CustomAccessibilityAction("暂不提醒") { scope.launch { state.snooze(insight) }; true })
            }.padding(vertical = FcSpacing.space3)
                .testTag("insights.row.${insight.snoozeKey}"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
                FcText(copy.title, style = FcTypography.body, color = FcColors.textPrimary)
                copy.subtitle?.let { FcText(it, style = FcTypography.caption, color = FcColors.textSecondary) }
            }
        }
    }
}
