package com.ignacioli.finecoach.features.session

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.IntOffset
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.designsystem.*
import kotlin.math.roundToInt

internal data class SessionSwipeAction(val title: String, val tag: String, val destructive: Boolean = false, val run: () -> Unit)

/** Only unfinished sets permit a full swipe to execute deletion. */
@Composable
internal fun SessionSwipeRow(tag: String, open: Boolean, enabled: Boolean, reveal: (Boolean) -> Unit,
    actions: List<SessionSwipeAction>, onFullSwipe: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val threshold = with(density) { FcComponentMetrics.touch.toPx() }
    val actionWidth = FcComponentMetrics.hub
    val distance = with(density) { (actionWidth * actions.size).toPx() }
    var width by remember { mutableIntStateOf(0) }
    val fullSwipe by rememberUpdatedState(onFullSwipe)
    val offset by animateFloatAsState(if (open) -distance else 0f, tween(SessionMotionDurationMillis), label = "session-swipe")
    Box(Modifier.fillMaxWidth().clipToBounds().testTag(tag).onSizeChanged { width = it.width }.pointerInput(enabled, open) {
        if (enabled) {
            var drag = 0f
            detectHorizontalDragGestures(onDragStart = { drag = 0f }, onDragEnd = {
                if (fullSwipe != null && width > 0 && drag <= -width * 0.8f) { reveal(false); fullSwipe?.invoke() }
                else if (drag < -threshold) reveal(true) else if (drag > threshold) reveal(false)
            }, onHorizontalDrag = { change, amount -> change.consume(); drag += amount })
        }
    }) {
        if (open) Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
            actions.forEach { action ->
                Column(Modifier.width(actionWidth).fillMaxHeight()
                    .background(if (action.destructive) FcColors.statusDestructive else FcColors.textSecondary)
                    .testTag(action.tag).clickable(enabled = enabled, role = Role.Button) { reveal(false); action.run() }
                    .padding(horizontal = FcSpacing.space1), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center) {
                    if (action.destructive) FcSymbol(painterResource(R.drawable.ic_ms_delete), tint = FcColors.actionOn)
                    Text(action.title, style = FcTypography.caption, color = FcColors.actionOn, maxLines = 1)
                }
            }
        }
        Column(Modifier.fillMaxWidth().offset { IntOffset(offset.roundToInt(), 0) }.background(FcColors.surfacePage)) { content() }
    }
}
