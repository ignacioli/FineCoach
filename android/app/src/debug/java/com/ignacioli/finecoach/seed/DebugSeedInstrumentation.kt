package com.ignacioli.finecoach.seed

import android.app.Activity
import android.app.Instrumentation
import android.app.UiAutomation
import android.os.Bundle
import android.os.Process

// fictional-data: explicit shell instrumentation; never an application startup side effect.
class DebugSeedInstrumentation : Instrumentation() {
    private var scenario = "multi"
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        scenario = arguments?.getString("scenario") ?: "multi"
        start()
    }

    override fun onStart() {
        try {
            // A normal app's startInstrumentation cannot supply a connected shell automation session.
            checkNotNull(getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES))
            val result = loadAndClose()
            val verified = loadAndClose()
            check(result == verified)
            val loggedAt = System.currentTimeMillis()
            android.util.Log.i("FineCoachSeed", result.logLine)
            finish(Activity.RESULT_OK, Bundle().apply {
                putString("seed", result.logLine)
                putInt("seed_pid", Process.myPid())
                putLong("seed_log_time", loggedAt)
            })
        } catch (_: Exception) {
            // No exception message or database content crosses the debug handoff.
            finish(Activity.RESULT_CANCELED, Bundle().apply { putString("seed", "status=failed") })
        }
    }

    private fun loadAndClose(): SeedResult {
        return kotlinx.coroutines.runBlocking { S1DebugSeed.load(targetContext, scenario) }
    }
}
