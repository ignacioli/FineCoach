package com.ignacioli.finecoach

import android.app.Activity
import android.content.Context
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.FrameLayout

/** Covers registered app windows synchronously, without waiting for recomposition. */
internal class PrivacyCoverPolicy(private val activity: Activity) {
    private val windows = linkedMapOf<Window, View?>()
    private var paused = false

    fun onCreate() {
        if (Build.VERSION.SDK_INT >= 33) activity.setRecentsScreenshotEnabled(false)
        registerWindow(activity.window)
    }

    // Every independent app Dialog/BottomSheet window must register before display
    // and unregister on disposal. A cover in the activity cannot cover its windows.
    fun registerWindow(window: Window) {
        if (windows.containsKey(window)) return
        windows[window] = null
        if (paused && Build.VERSION.SDK_INT < 33) cover(window)
    }

    fun unregisterWindow(window: Window) {
        windows.remove(window)?.let { (it.parent as? ViewGroup)?.removeView(it) }
    }

    fun onPause() {
        paused = true
        if (Build.VERSION.SDK_INT < 33) windows.keys.toList().forEach(::cover)
    }

    fun onResume() {
        paused = false
        windows.keys.toList().forEach { window ->
            windows[window]?.let { (it.parent as? ViewGroup)?.removeView(it) }
            windows[window] = null
        }
    }

    fun onDestroy() {
        windows.keys.toList().forEach(::unregisterWindow)
    }

    private fun cover(window: Window) {
        if (windows[window] != null) return
        val decor = window.decorView as ViewGroup
        val cover = FrameLayout(window.context).apply {
            tag = COVER_TAG
            setBackgroundColor(backgroundColor(context))
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        windows[window] = cover
        decor.addView(cover, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        cover.bringToFront()
        // Size the opaque surface now; the system may snapshot before next layout.
        cover.measure(View.MeasureSpec.makeMeasureSpec(decor.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(decor.height, View.MeasureSpec.EXACTLY))
        cover.layout(0, 0, decor.width, decor.height)
        decor.invalidate()
    }

    companion object {
        const val COVER_TAG = "s0-privacy-cover"

        fun backgroundColor(context: Context): Int = context.obtainStyledAttributes(
            intArrayOf(android.R.attr.colorBackground),
        ).let { attributes ->
            try { attributes.getColor(0, context.getColor(android.R.color.background_light)) }
            finally { attributes.recycle() }
        }
    }
}
