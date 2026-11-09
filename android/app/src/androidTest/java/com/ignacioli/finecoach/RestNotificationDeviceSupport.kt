// fictional-data: generic system-state waits; callers supply only dedicated test-install IDs.
package com.ignacioli.finecoach

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.notification.StatusBarNotification
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import androidx.test.platform.app.InstrumentationRegistry
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.navigation.RestNotificationRoute
import com.ignacioli.finecoach.notifications.RestNotifications
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.junit.Assert.assertTrue

internal object RestNotificationDeviceSupport {
    /** Poll only the observation. The business action is executed once by the caller, never here. */
    fun <T : Any> awaitSystemState(description: String, onTimeout: () -> Unit = {}, observe: () -> T?): T {
        val result = CompletableFuture<T>()
        val executor = Executors.newSingleThreadScheduledExecutor()
        val polling = executor.scheduleAtFixedRate({
            try { observe()?.let { result.complete(it) } }
            catch (failure: Throwable) { result.completeExceptionally(failure) }
        }, 0, 50, TimeUnit.MILLISECONDS)
        try {
            return result.get(15, TimeUnit.SECONDS)
        } catch (timeout: TimeoutException) {
            polling.cancel(false)
            executor.shutdownNow()
            val failure = AssertionError("System state timeout: $description", timeout)
            try { onTimeout() } catch (diagnosticFailure: Throwable) { failure.addSuppressed(diagnosticFailure) }
            throw failure
        } catch (failure: ExecutionException) {
            throw failure.cause ?: failure
        } finally {
            polling.cancel(false)
            executor.shutdownNow()
        }
    }

    fun awaitPosted(manager: NotificationManager, id: SessionID): StatusBarNotification =
        awaitSystemState("exactly one notification for the requested test session") {
            val matches = manager.activeNotifications.filter { it.tag == id.value && it.id == 0 }
            check(matches.size <= 1) { "Duplicate notification identity" }
            matches.singleOrNull()
        }

    fun awaitRemoved(manager: NotificationManager, id: SessionID) {
        awaitSystemState("requested test notification removed") {
            true.takeIf { manager.activeNotifications.none { it.tag == id.value && it.id == 0 } }
        }
    }

    /** Prepare one already-due system-adapter request; this does not test inexact-alarm timing. */
    fun deliverDue(context: Context, adapter: RestNotifications, id: SessionID) {
        val deadline = System.currentTimeMillis() - 1
        assertTrue(context.getSharedPreferences("rest-notification-deadlines", Context.MODE_PRIVATE)
            .edit().putLong(id.value, deadline).commit())
        adapter.receive(Intent().setAction(RestNotificationRoute.ACTION)
            .putExtra(RestNotificationRoute.SESSION, id.value).putExtra("restDeadline", deadline))
    }

    fun <T> withReportedViewIds(action: () -> T): T {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val info = checkNotNull(automation.serviceInfo) { "UiAutomation accessibility service unavailable" }
        val originalFlags = info.flags
        val requiredFlags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
            AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        info.flags = originalFlags or requiredFlags
        automation.serviceInfo = info
        try {
            check(checkNotNull(automation.serviceInfo).flags and requiredFlags == requiredFlags)
            return action()
        } finally {
            automation.serviceInfo = checkNotNull(automation.serviceInfo).apply { flags = originalFlags }
        }
    }

    fun awaitDestination(context: Context, id: SessionID, phase: String) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val resourceId = "active-destination-${id.value}"
        awaitSystemState("requested Session destination in the app accessibility tree ($phase)",
            onTimeout = { reportWindows(resourceId, phase) }) {
            val windows = automation.windows
            try {
                true.takeIf {
                    windows.any { window ->
                        if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) false else {
                            val root = window.root
                            if (root == null) false else try {
                                root.packageName?.toString() == context.packageName && hasID(root, resourceId)
                            } finally { root.recycle() }
                        }
                    }
                }
            } finally { windows.forEach { it.recycle() } }
        }
    }

    /** Metadata only: never emit text, contentDescription, stateDescription or database contents. */
    private fun reportWindows(expectedResourceId: String, phase: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val automation = instrumentation.uiAutomation
        fun emit(value: String) {
            instrumentation.sendStatus(2, Bundle().apply { putString("stream", "\nREST_DESTINATION_TIMEOUT $value\n") })
        }
        fun safe(value: CharSequence?): String = value?.toString()?.replace('\n', ' ')?.replace('\r', ' ') ?: "<null>"
        emit("phase=$phase api=${Build.VERSION.SDK_INT} flags=${automation.serviceInfo?.flags} expectedResourceId=$expectedResourceId")
        val activeRoot = automation.rootInActiveWindow
        if (activeRoot == null) emit("activeRoot=<null>") else try {
            emit("activeRoot windowId=${activeRoot.windowId} package=${safe(activeRoot.packageName)}")
        } finally { activeRoot.recycle() }
        val windows = automation.windows
        try {
            emit("interactiveWindowCount=${windows.size}")
            for (window in windows) {
                emit("window id=${window.id} type=${window.type} title=${safe(window.title)} layer=${window.layer} active=${window.isActive} focused=${window.isFocused}")
                val root = window.root
                if (root == null) emit("window id=${window.id} root=<null>") else try {
                    val ids = linkedSetOf<String>()
                    collectVisibleIDs(root, ids)
                    emit("window id=${window.id} package=${safe(root.packageName)} visibleResourceIds=${ids.joinToString()}")
                } finally { root.recycle() }
            }
        } finally { windows.forEach { it.recycle() } }
    }

    private fun collectVisibleIDs(node: AccessibilityNodeInfo, ids: MutableSet<String>) {
        if (node.isVisibleToUser) node.viewIdResourceName?.let { ids.add(it) }
        for (index in 0 until node.childCount) {
            val child = node.getChild(index) ?: continue
            try { collectVisibleIDs(child, ids) } finally { child.recycle() }
        }
    }

    private fun hasID(node: AccessibilityNodeInfo, id: String): Boolean {
        if (node.isVisibleToUser && node.viewIdResourceName == id) return true
        for (index in 0 until node.childCount) {
            val child = node.getChild(index) ?: continue
            try { if (hasID(child, id)) return true } finally { child.recycle() }
        }
        return false
    }
}
