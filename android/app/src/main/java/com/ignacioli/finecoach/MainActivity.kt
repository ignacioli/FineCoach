package com.ignacioli.finecoach

import android.os.Bundle
import android.content.Intent
import android.Manifest
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.navigation.RestNotificationRoute
import com.ignacioli.finecoach.notifications.LocalRestPermissionRequest
import com.ignacioli.finecoach.notifications.LocalRestPermissionRevision
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.designsystem.FcWindowRegistry
import com.ignacioli.finecoach.designsystem.LocalFcWindowRegistry

class MainActivity : ComponentActivity() {
    companion object { const val EXTRA_S0_SHELL = "finecoachS0Shell" }
    private var showS0Shell by mutableStateOf(false)
    var restNotificationSessionID by mutableStateOf<SessionID?>(null)
        private set
    var notificationPermissionRevision by mutableIntStateOf(0)
        private set
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        notificationPermissionRevision++
    }
    fun requestRestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
    fun consumeRestNotificationRoute() { restNotificationSessionID = null }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent)
        applyLaunchIntent(intent)
    }
    private fun applyLaunchIntent(intent: Intent?) {
        showS0Shell = intent?.getBooleanExtra(EXTRA_S0_SHELL, false) == true
        RestNotificationRoute.deliver(intent) { restNotificationSessionID = it; showS0Shell = false }
    }
    internal lateinit var privacyCover: PrivacyCoverPolicy
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLaunchIntent(intent)
        privacyCover = PrivacyCoverPolicy(this)
        privacyCover.onCreate()
        enableEdgeToEdge()
        setContent {
            FineCoachTheme {
              CompositionLocalProvider(LocalRestPermissionRequest provides ::requestRestNotificationPermission, LocalRestPermissionRevision provides notificationPermissionRevision) {
                val provider = application as? ShellContentProvider
                if (provider != null && showS0Shell) {
                    provider.Content(privacyCover)
                } else {
                    val registry = remember(privacyCover) { FcWindowRegistry(privacyCover::registerWindow, privacyCover::unregisterWindow) }
                    CompositionLocalProvider(LocalFcWindowRegistry provides registry) {
                        S1Root(this@MainActivity)
                    }
                }
              }
            }
        }
    }

    override fun onPause() {
        privacyCover.onPause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        privacyCover.onResume()
    }

    override fun onDestroy() {
        privacyCover.onDestroy()
        super.onDestroy()
    }
}

// Only explicit debug harness intents select S0; normal launches open S1 in both variants.
internal interface ShellContentProvider {
    @Composable fun Content(privacyCover: PrivacyCoverPolicy)
}
