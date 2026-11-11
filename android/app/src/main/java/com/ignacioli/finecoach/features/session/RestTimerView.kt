package com.ignacioli.finecoach.features.session

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.designsystem.*
import java.time.Duration
import kotlinx.coroutines.delay

// README §14: motion.duration.standard, shared by the rest bar and sheets.
internal const val SessionMotionDurationMillis = 250

@Composable
fun RestTimerView(store: RestTimerStore, id: SessionID, clock: AppClock, visible: Boolean = true) {
    val end = store.end(id)
    AnimatedVisibility(end != null && visible, modifier = Modifier.padding(bottom = FcSpacing.space3),
        enter = slideInVertically(tween(SessionMotionDurationMillis)) { it } + fadeIn(tween(SessionMotionDurationMillis)),
        exit = fadeOut(tween(SessionMotionDurationMillis))) {
        if (end != null) {
            var remaining by remember(id, end) { mutableLongStateOf(store.remaining(id)) }
            var overdue by remember(id, end) { mutableLongStateOf(0) }
            LaunchedEffect(id, end) {
                while (true) {
                    remaining = store.remaining(id)
                    overdue = Duration.between(end, clock.now()).seconds.coerceAtLeast(0)
                    delay(1000)
                }
            }
            Row(Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.hub)
                .testTag("rest-content").background(FcColors.surfaceCanvas, RoundedCornerShape(FcShapes.lg)).padding(horizontal = FcSpacing.space4), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
                if (remaining > 0) {
                    Column(Modifier.weight(1f).align(Alignment.Top).padding(top = FcSpacing.space2)) {
                        FcText("组间休息", style = FcTypography.caption, color = FcColors.textSecondary)
                        FcText(restTime(remaining), Modifier.testTag("rest-remaining"), style = FcTypography.numeralLarge, color = FcColors.textPrimary)
                    }
                    FcLinkButton("−15 秒", Modifier.testTag("rest-minus")) { store.adjust(id, -15) }
                    FcLinkButton("+15 秒", Modifier.testTag("rest-plus")) { store.adjust(id, 15) }
                    FcLinkButton("跳过", Modifier.testTag("rest-skip")) { store.clear(id) }
                } else {
                    FcSymbol(FcGlyph.Check)
                    Column(Modifier.weight(1f)) {
                        FcText("休息结束，可以开始下一组", Modifier.testTag("rest-ended"), style = FcTypography.headline, color = FcColors.textPrimary)
                        if (overdue > 0) FcText("已超时 ${restTime(overdue)}", Modifier.testTag("rest-overdue"), style = FcTypography.caption, color = FcColors.textSecondary)
                    }
                    FcLinkButton("关闭", Modifier.testTag("rest-close")) { store.clear(id) }
                }
            }
        }
    }
}

private fun restTime(seconds: Long) = "%d:%02d".format(seconds / 60, seconds % 60)
