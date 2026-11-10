// fictional-data: source and APK boundaries only; no user records.
package com.ignacioli.finecoach

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class S1SeedIsolationTests {
    private val app = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))
    @Test fun seedCodeAndInstrumentationAreDebugOnly() {
        val main = File(app,"src/main").walkTopDown().filter { it.isFile && it.extension in setOf("kt","xml") }.toList()
        assertTrue(main.isNotEmpty())
        main.forEach { file ->
            val source=file.readText()
            assertFalse(source.contains("S1DebugSeed")); assertFalse(source.contains("DebugSeedInstrumentation"))
            assertFalse(source.contains("s1_debug_seed.")); assertFalse(source.contains("fictional-s1-coach-core-v1")); assertFalse(source.contains("fictional-s1-coach-core-v2")); assertFalse(source.contains("S1SeedFixture"))
        }
        assertTrue(File(app,"src/debug/java/com/ignacioli/finecoach/seed/S1DebugSeed.kt").isFile)
        assertTrue(File(app,"src/debug/assets/seed/s1-seed.json").isFile)
        assertFalse(File(app,"src/main/assets/seed/s1-seed.json").exists())
        assertTrue(File(app,"src/debug/AndroidManifest.xml").readText().contains("seed.DebugSeedInstrumentation"))
        assertFalse(File(app,"src/main/AndroidManifest.xml").readText().contains("<instrumentation"))
    }
    @Test fun ordinaryDebugLaunchUsesS1AndDoesNotSeedAutomatically() {
        val activity=File(app,"src/main/java/com/ignacioli/finecoach/MainActivity.kt").readText()
        assertTrue(activity.contains("getBooleanExtra(EXTRA_S0_SHELL, false)"))
        assertTrue(activity.contains("S1Root(this@MainActivity)"))
        val application=File(app,"src/debug/java/com/ignacioli/finecoach/S0DebugApplication.kt").readText()
        assertFalse(application.contains("S1DebugSeed")); assertFalse(application.contains("DebugSeedLoader"))
    }
    @Test fun installerHasExplicitSerialAndDoesNotResetOrClear() {
        val build=File(app,"build.gradle.kts").readText()
        val installer=build.substringAfter("val installSeededDebug =").substringBefore("// T013:")
        assertTrue(build.contains("Exactly one connected, authorized device matching the explicit serial"))
        assertTrue(installer.contains("requireSingleDevice()")); assertTrue(installer.contains("\"-s\", serial"))
        assertFalse(installer.contains("\"clear\"")); assertFalse(installer.contains("\"uninstall\""))
        assertTrue(installer.contains("INSTRUMENTATION_CODE: -1"))
        assertTrue(installer.contains("JsonSlurper")); assertTrue(installer.contains("seed/s1-seed.json")); assertTrue(installer.contains("Status: ok")); assertTrue(installer.contains("S1DebugSeed"))
    }
    @Test fun releaseGateScansBinaryEntriesAndRunsTheExactIsolationSuite() {
        val build=File(app,"build.gradle.kts").readText()
        val gate=build.substringAfter("val seedIsolation =").substringBefore("// No shell command strings")
        assertTrue(gate.contains("assembleRelease")); assertTrue(gate.contains("S1DebugSeed"))
        assertTrue(gate.contains("UTF_16LE")); assertTrue(gate.contains("classes[0-9]"))
        assertTrue(build.contains("com.ignacioli.finecoach.S1SeedIsolationTests"))
        assertTrue(build.contains("S1 seed checks must run nonzero tests without failures or skips"))
    }
}
