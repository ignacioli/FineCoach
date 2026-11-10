package com.ignacioli.finecoach.features.today

import android.animation.ValueAnimator
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.withInfiniteAnimationFrameNanos
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.designsystem.FcColors
import kotlin.random.Random

internal fun ambientMotionRunning(active: Boolean, lowPower: Boolean, reducedMotion: Boolean): Boolean =
    active && !lowPower && !reducedMotion

internal data class AmbientSteam(val opacity: Float, val x: Float, val y: Float)
internal data class AmbientFrame(val steam: List<AmbientSteam>, val breathScale: Float, val closedEyes: Boolean)

// FCMotion.ambientEase uses UnitCurve.easeInOut: the symmetric CSS cubic curve.
private val ambientEase = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)
private fun ease(progress: Double): Float = ambientEase.transform(progress.toFloat().coerceIn(0f, 1f))

/** Pure counterpart of FCAmbientEmptyScene.frame(at:blinkSchedule:reducedMotion:). */
internal fun ambientFrame(elapsedSeconds: Double, blinkSchedule: List<Double>, reducedMotion: Boolean = false, paused: Boolean = false): AmbientFrame {
    if (reducedMotion) return AmbientFrame(List(2) { AmbientSteam(0.45f, 0f, 0f) }, 1f, false)
    val steam = List(3) { index ->
        val local = elapsedSeconds - index * 1.2
        if (local < 0) AmbientSteam(0f, 0f, 0f) else {
            val progress = (local % 3.6) / 3.6
            val opacity = when {
                progress <= 0.25 -> 0.6f * ease(progress / 0.25)
                progress <= 0.7 -> 0.6f + (0.35f - 0.6f) * ease((progress - 0.25) / 0.45)
                else -> 0.35f * (1f - ease((progress - 0.7) / 0.3))
            }
            AmbientSteam(opacity, 1.5f * ease(progress), -20f * ease(progress))
        }
    }
    val progress = (elapsedSeconds % 4.2) / 4.2
    val breath = ease(if (progress <= 0.5) progress * 2 else (1 - progress) * 2)
    return AmbientFrame(steam, 1f + 0.008f * breath,
        !paused && blinkSchedule.any { elapsedSeconds >= it && elapsedSeconds < it + 0.14 })
}

/** Original 220pt coordinates from FCAmbientEmptyScene.steamPath / FCMotion. */
internal fun ambientSteamPath(index: Int): Path {
    require(index in 0..2)
    val origin = listOf(Offset(125f, 104f), Offset(131f, 103f), Offset(137f, 104f))[index]
    val finalHeight = listOf(13f, 14f, 13f)[index]
    return Path().apply {
        moveTo(origin.x, origin.y)
        cubicTo(origin.x - 3f, origin.y - 5f, origin.x + 3f, origin.y - 9f, origin.x, origin.y - 14f)
        cubicTo(origin.x - 3f, origin.y - 19f, origin.x + 3f, origin.y - 23f, origin.x, origin.y - 14f - finalHeight)
    }
}

/** Original C30 layers and native steam; metrics mirror FCMotion / README §14.2. */
@Composable
internal fun TodayAmbientScene() {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val power = remember(context) { context.getSystemService(PowerManager::class.java) }
    var active by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    var lowPower by remember { mutableStateOf(power.isPowerSaveMode) }
    var systemReducedMotion by remember { mutableStateOf(!ValueAnimator.areAnimatorsEnabled()) }
    DisposableEffect(context, lifecycle) {
        val observer = LifecycleEventObserver { _, _ ->
            active = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            systemReducedMotion = !ValueAnimator.areAnimatorsEnabled()
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) { lowPower = power.isPowerSaveMode }
        }
        lifecycle.addObserver(observer)
        ContextCompat.registerReceiver(context, receiver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED), ContextCompat.RECEIVER_NOT_EXPORTED)
        onDispose { lifecycle.removeObserver(observer); context.unregisterReceiver(receiver) }
    }
    val reducedMotion = systemReducedMotion
    val running = ambientMotionRunning(active, lowPower, reducedMotion)
    var elapsedSeconds by remember { mutableDoubleStateOf(0.0) }
    var blinkSchedule by remember { mutableStateOf(emptyList<Double>()) }
    LaunchedEffect(running) {
        if (!running) return@LaunchedEffect
        var lastFrame: Long? = null
        while (true) {
            withInfiniteAnimationFrameNanos { timestamp ->
                lastFrame?.let { elapsedSeconds += (timestamp - it).coerceAtLeast(0) / 1_000_000_000.0 }
                lastFrame = timestamp
                if (elapsedSeconds >= (blinkSchedule.lastOrNull() ?: 0.0) - 7.0) {
                    val next = (blinkSchedule.lastOrNull() ?: elapsedSeconds) + Random.nextDouble(4.0, 7.0)
                    blinkSchedule = blinkSchedule.filter { it + 0.14 >= elapsedSeconds } +
                        if (Random.nextDouble() < 0.2) listOf(next, next + 0.32) else listOf(next)
                }
            }
        }
    }
    val frame = ambientFrame(elapsedSeconds, blinkSchedule, reducedMotion, paused = !running)
    Box(Modifier.size(220.dp).testTag("today-empty-scene")) {
        Box(Modifier.matchParentSize().graphicsLayer {
            scaleX = frame.breathScale; scaleY = frame.breathScale; transformOrigin = TransformOrigin(0.44f, 0.78f)
        }) {
            Image(painterResource(R.drawable.mascot_cafe_rabbit), contentDescription = null, modifier = Modifier.matchParentSize())
            // Cancellation/pause immediately opens the eyes; resume never waits closed for the next blink.
            if (frame.closedEyes) Image(painterResource(R.drawable.mascot_cafe_blink), contentDescription = null, modifier = Modifier.matchParentSize())
        }
        Image(painterResource(R.drawable.mascot_cafe_table), contentDescription = null, modifier = Modifier.matchParentSize())
        Canvas(Modifier.matchParentSize()) {
            val ratio = size.width / 220f
            frame.steam.forEachIndexed { index, steam ->
                withTransform({
                    scale(ratio, ratio, pivot = Offset.Zero)
                    translate(steam.x, steam.y)
                }) {
                    drawPath(ambientSteamPath(index), FcColors.textDisabled.copy(alpha = steam.opacity),
                        style = Stroke(width = 2.2f, cap = StrokeCap.Round))
                }
            }
        }
    }
}
