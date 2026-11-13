package com.ignacioli.finecoach.features.session

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.designsystem.*

internal data class SessionSwipeAction(val title: String, val tag: String, val destructive: Boolean = false, val run: () -> Unit)

/** Only unfinished sets permit a full swipe to execute deletion. */
@Composable
internal fun SessionSwipeRow(tag: String, open: Boolean, enabled: Boolean, reveal: (Boolean) -> Unit,
    actions: List<SessionSwipeAction>, onFullSwipe: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val threshold = with(density) { FcComponentMetrics.touch.toPx() }
    val orderedActions = actions.sortedBy { it.destructive }
    fun actionWidth(action: SessionSwipeAction) = when (action.tag) {
        "session-section-delete" -> FcComponentMetrics.label + FcSpacing.space4
        "session-exercise-move" -> FcComponentMetrics.hub + FcSpacing.space4 + FcSpacing.space1
        else -> FcComponentMetrics.hub + FcSpacing.space3
    }
    var actionStripWidth by remember { mutableIntStateOf(0) }
    var width by remember { mutableIntStateOf(0) }
    val fullSwipe by rememberUpdatedState(onFullSwipe)
    val revealWidth by animateFloatAsState(if (open) actionStripWidth.toFloat() else 0f, tween(SessionMotionDurationMillis), label = "session-swipe")
    BoxWithConstraints(Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.touch).testTag(tag).onSizeChanged { width = it.width }.pointerInput(enabled, open) {
        if (enabled) {
            var drag = 0f
            detectHorizontalDragGestures(onDragStart = { drag = 0f }, onDragEnd = {
                if (fullSwipe != null && width > 0 && drag <= -width * 0.8f) { reveal(false); fullSwipe?.invoke() }
                else if (drag < -threshold) reveal(true) else if (drag > threshold) reveal(false)
            }, onHorizontalDrag = { change, amount -> change.consume(); drag += amount })
        }
    }) {
        if (open) Box(Modifier.matchParentSize(), contentAlignment = Alignment.CenterEnd) {
            Row(Modifier.width(IntrinsicSize.Max).fillMaxHeight().onSizeChanged { actionStripWidth = it.width },
                verticalAlignment = Alignment.CenterVertically) {
                orderedActions.forEach { action ->
                    val section = action.tag == "session-section-delete"
                    Box(Modifier.widthIn(min = actionWidth(action)).width(IntrinsicSize.Max)
                        .fillMaxHeight().heightIn(min = FcComponentMetrics.touch)
                        .testTag(action.tag).clickable(enabled = enabled, role = Role.Button) { reveal(false); action.run() },
                        contentAlignment = Alignment.Center) {
                        Row(Modifier.fillMaxWidth().testTag("${action.tag}-visual")
                            .then(if (section) Modifier.height(FcSpacing.space8 + FcSpacing.space1).clip(CircleShape) else Modifier.fillMaxHeight())
                            .background(if (action.destructive) FcColors.statusDestructive else FcColors.surfaceSelected)
                            .padding(horizontal = FcSpacing.space2), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2, Alignment.CenterHorizontally),
                            verticalAlignment = Alignment.CenterVertically) {
                            if (section) FcSymbol(painterResource(R.drawable.ic_ms_delete), Modifier.size(FcSpacing.space4), tint = FcColors.actionOn)
                            FcText(action.title, style = FcTypography.style("callout", 600),
                                color = if (action.destructive) FcColors.actionOn else FcColors.textPrimary, maxLines = 1, softWrap = false)
                        }
                    }
                }
            }
        }
        // Reveal only the trailing area; keep the leading title/ordinal at its original x.
        // Measure the content at the closed width so its trailing controls are clipped, not reflowed.
        Column(Modifier.fillMaxWidth().padding(end = with(density) { revealWidth.toDp() })
            .heightIn(min = FcComponentMetrics.touch).clipToBounds()
            .wrapContentWidth(Alignment.Start, unbounded = true).width(maxWidth)
            .background(FcColors.surfacePage), verticalArrangement = Arrangement.Center) { content() }
    }
}
