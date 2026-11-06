package com.ignacioli.finecoach

import android.os.Bundle
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

class MainActivity : ComponentActivity() {
    internal lateinit var privacyCover: PrivacyCoverPolicy
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        privacyCover = PrivacyCoverPolicy(this)
        privacyCover.onCreate()
        enableEdgeToEdge()
        setContent {
            FineCoachTheme {
                val provider = application as? ShellContentProvider
                if (provider != null) {
                    provider.Content(privacyCover)
                } else {
                    NavHost(
                        navController = rememberNavController(),
                        startDestination = "placeholder",
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        composable("placeholder") { Box(Modifier.fillMaxSize()) }
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

// Only the debug Application supplies sample content; release keeps the empty shell.
internal interface ShellContentProvider {
    @Composable fun Content(privacyCover: PrivacyCoverPolicy)
}
