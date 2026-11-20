package com.ignacioli.finecoach.designsystem

import androidx.compose.animation.core.CubicBezierEasing

/** Native mappings of existing motion tokens, design/design-system/README.md §14.2:630–631. */
object FcMotion {
    // motion.duration.emphasis = 1.5 s; Android animation APIs take milliseconds.
    const val durationEmphasisMillis = 1500

    // motion.curve.standard = easeOut, the CSS/SwiftUI cubic curve.
    val curveStandard = CubicBezierEasing(0f, 0f, 0.58f, 1f)
}
