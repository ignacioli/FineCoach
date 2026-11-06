package com.ignacioli.finecoach

import java.io.File
import java.util.zip.ZipFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

internal object PrivacySourcePolicy {
    // Scan raw source, including aliases/imports/comments: no suppression markers.
    val forbidden = listOf(
        "java.net", "javax.net", "android.net", "HttpURLConnection", "URLConnection",
        "Socket", "WebView", "okhttp", "retrofit", "io.ktor", "org.apache.http",
        "Cronet", "Volley", "Firebase", "Crashlytics", "Sentry", "Amplitude", "Mixpanel",
        "SQLCipher", "sqlcipher", "FLAG_SECURE", "android.util.Log", "java.util.logging",
        "System.out", "System.err", "printStackTrace", "Timber", "DebugEventLogger",
    )
    private val calls = Regex("\\b(?:Log\\s*\\.|(?:print|println|printf)\\s*\\()")
    fun violations(source: String): List<String> = forbidden.filter { source.contains(it, ignoreCase = true) } +
        if (calls.containsMatchIn(source)) listOf("direct log/print") else emptyList()
    fun validate(source: String) { require(violations(source).isEmpty()) { violations(source).joinToString() } }
}

internal object DependencyPolicy {
    val scopes = setOf("app:debugCompileClasspath", "app:debugRuntimeClasspath", "app:releaseCompileClasspath", "app:releaseRuntimeClasspath",
        "app:debugUnitTestRuntimeClasspath", "app:debugAndroidTestRuntimeClasspath", "app:classpath", "root:classpath",
        "app:kspDebugKotlinProcessorClasspath", "app:kspReleaseKotlinProcessorClasspath", "app:kspDebugUnitTestKotlinProcessorClasspath", "app:kspDebugAndroidTestKotlinProcessorClasspath")
    fun rows(text: String): Set<String> {
        val lines = text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }.toList()
        require(lines.size == lines.toSet().size) { "Duplicate dependency row" }
        require(lines.all { line ->
            val parts = line.split(' ')
            parts.size == 2 && parts[1] in scopes && Regex("[^:\\s]+:[^:\\s]+:[0-9][A-Za-z0-9_.-]*(?:\\+[A-Za-z0-9_.-]+)?").matches(parts[0])
        }) { "Malformed dependency allowlist/report" }
        return lines.toSet()
    }
    fun validate(actual: Set<String>, approved: Set<String>) {
        require(actual.isNotEmpty() && actual == approved) {
            "Dependency drift; unknown=" + (actual - approved).sorted() + "; missing=" + (approved - actual).sorted()
        }
        require(actual.none { Regex("(?i)(firebase|crashlytics|sentry|amplitude|mixpanel|sqlcipher)").containsMatchIn(it) })
    }
}

class PrivacySourceScanTests {
    @Test fun productionSourcesHaveNoForbiddenCapabilitiesOrLogs() {
        val root = File(MergedPrivacyInputs.property("sourceRoot"), "main")
        require(root.isDirectory)
        val sources = root.walkTopDown().filter { it.isFile && it.extension in setOf("kt", "java") }.toList()
        require(sources.isNotEmpty())
        sources.forEach { source ->
            require(PrivacySourcePolicy.violations(source.readText()).isEmpty()) { "Forbidden source: ${source.relativeTo(root)}" }
        }
    }
    @Test fun networkFixturesAreRejected() = rejectFixture("network.txt")
    @Test fun secureWindowFixtureIsRejected() = rejectFixture("secure-window.txt")
    @Test fun loggingFixturesAreRejected() = rejectFixture("logging.txt")
    @Test fun telemetryFixturesAreRejected() = rejectFixture("telemetry.txt")
    private fun rejectFixture(name: String) {
        val lines = requireNotNull(javaClass.getResource("/privacy/$name")).readText().lines().filter { it.isNotBlank() }
        require(lines.isNotEmpty())
        lines.forEach { source -> assertThrows(IllegalArgumentException::class.java) { PrivacySourcePolicy.validate(source) } }
    }
    @Test fun resolvedGraphMatchesEveryApprovedScope() {
        val report = File(MergedPrivacyInputs.property("dependencies")).readText()
        assertEquals(DependencyPolicy.scopes, report.lineSequence().filter { it.startsWith("# scope ") }.map { it.removePrefix("# scope ") }.toSet())
        DependencyPolicy.validate(DependencyPolicy.rows(report), DependencyPolicy.rows(File(MergedPrivacyInputs.property("dependencyAllowlist")).readText()))
    }
    @Test fun rejectsUnparsedConstraintVersionFixture() {
        assertThrows(IllegalArgumentException::class.java) {
            DependencyPolicy.rows("fictional:library:{strictly app:debugAndroidTestRuntimeClasspath")
        }
    }
    @Test fun rejectsUnknownCoordinateFixture() {
        assertThrows(IllegalArgumentException::class.java) {
            DependencyPolicy.validate(setOf("fictional:unapproved:1.0 app:debugRuntimeClasspath"), setOf("fictional:approved:1.0 app:debugRuntimeClasspath"))
        }
    }
    @Test fun rejectsUnknownVersionFixture() {
        assertThrows(IllegalArgumentException::class.java) {
            DependencyPolicy.validate(setOf("fictional:approved:2.0 app:debugRuntimeClasspath"), setOf("fictional:approved:1.0 app:debugRuntimeClasspath"))
        }
    }
    @Test fun releaseContainsNoAppDebugLoggingImplementation() {
        // S0-12 permits exactly one debug-only, fixed-event seed log call.
        val sourceRoot = File(MergedPrivacyInputs.property("sourceRoot"))
        for (variant in listOf("debug", "release")) {
            File(sourceRoot, variant).walkTopDown().filter { it.isFile && it.extension in setOf("kt", "java") }.forEach {
                val source = it.readText()
                val seedEntry = "debug/java/com/ignacioli/finecoach/seed/DebugSeedInstrumentation.kt"
                val call = "android.util.Log.i(\"FineCoachSeed\", result.logLine)"
                if (it.relativeTo(sourceRoot).invariantSeparatorsPath == seedEntry) {
                    require(source.windowed(call.length).count { fragment -> fragment == call } == 1)
                    PrivacySourcePolicy.validate(source.replace(call, ""))
                } else PrivacySourcePolicy.validate(source)
            }
        }
        val apks = File(MergedPrivacyInputs.property("releaseApk")).walkTopDown().filter { it.isFile && it.extension == "apk" }.toList()
        require(apks.size == 1) { "Expected one built release APK" }
        ZipFile(apks.single()).use { apk ->
            val dex = apk.entries().asSequence().filter { Regex("classes[0-9]*\\.dex").matches(it.name) }.toList()
            require(dex.isNotEmpty())
            dex.forEach { entry ->
                val bytes = apk.getInputStream(entry).use { it.readBytes() }
                val strings = String(bytes, Charsets.ISO_8859_1)
                require(!strings.contains("Lcom/ignacioli/finecoach/DebugEventLogger;"))
                require(!strings.contains("FICTIONAL_SENSITIVE_LOG_SENTINEL"))
                require(!strings.contains("Lcom/ignacioli/finecoach/seed/"))
                require(!strings.contains("FineCoachSeed"))
            }
        }
    }
}
