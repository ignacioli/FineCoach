package com.ignacioli.finecoach

import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

internal object ScopeBoundaryPolicy {
    // Deliberately scans imports, aliases, calls and resource declarations, not
    // business words in text. Generic DS demonstration text is permitted.
    private val forbidden = mapOf(
        "static-shortcut" to Regex("<\\s*shortcuts?\\b|android\\.app\\.shortcuts", RegexOption.IGNORE_CASE),
        "dynamic-shortcut" to Regex("\\b(?:ShortcutManager(?:Compat)?|ShortcutInfo(?:Compat)?|setDynamicShortcuts|addDynamicShortcuts|pushDynamicShortcut)\\b"),
        "pinned-shortcut" to Regex("\\b(?:requestPinShortcut|createShortcutResultIntent|ACTION_CREATE_SHORTCUT|INSTALL_SHORTCUT)\\b"),
        "assistant" to Regex("actions\\.intent\\.|com\\.google\\.android\\.actions|<\\s*(?:capability|capability-binding|app-actions)\\b|VoiceInteraction(?:Service|Session)|AppActions", RegexOption.IGNORE_CASE),
        "notifications" to Regex("\\b(?:NotificationManager(?:Compat)?|NotificationChannel|NotificationCompat|AlarmManager|POST_NOTIFICATIONS|SCHEDULE_EXACT_ALARM|USE_EXACT_ALARM)\\b"),
        "widgets" to Regex("\\b(?:AppWidgetProvider|AppWidgetManager|GlanceAppWidget|RemoteViews|LiveActivity)\\b|android\\.appwidget"),
        "containers-and-sharing" to Regex("\\b(?:FcbkCodec|FcpaCodec|BackupFileCodec|ArchiveFileCodec|ShareReport|FileProvider|ACTION_SEND|ACTION_SEND_MULTIPLE|ACTION_OPEN_DOCUMENT|ACTION_CREATE_DOCUMENT)\\b", RegexOption.IGNORE_CASE),
        "business-entry" to Regex("\\b(?:Coach|Student|Appointment|Session|Trend|Insight|Backup|Archive|ShareReport)(?:Screen|Route|Activity)\\b"),
    )
    fun validateSource(path: String, source: String) {
        require(!path.substringAfterLast('/').equals("shortcuts.xml", ignoreCase = true)) { "Static shortcuts resource: $path" }
        forbidden.forEach { (kind, pattern) -> require(!pattern.containsMatchIn(source)) { "$kind: $path" } }
        // S0 currently has exactly one product navigation route. Nonliteral route
        // registration also fails, preventing a constant/alias from hiding it.
        val calls = Regex("\\bcomposable\\s*(?:<[^>]+>)?\\s*(?:\\(|\\{)").findAll(source).count()
        val shellRoutes = Regex("\\bcomposable\\s*\\(\\s*\"placeholder\"\\s*\\)").findAll(source).count()
        require(calls == shellRoutes) { "Unapproved product route: $path" }
    }
    fun validateManifest(manifest: Element) {
        fun Element.attr(name: String) = getAttributeNS(MergedPrivacyInputs.ANDROID, name)
        val nodes = manifest.getElementsByTagName("*")
        for (index in 0 until nodes.length) {
            val node = nodes.item(index) as Element
            require(!node.attr("name").contains("shortcuts", ignoreCase = true)) { "Shortcut metadata/entry" }
            require(!Regex("actions\\.intent|com\\.google\\.android\\.actions", RegexOption.IGNORE_CASE)
                .containsMatchIn(node.attr("name"))) { "Assistant metadata/entry" }
            if (node.tagName == "intent-filter") {
                val parent = node.parentNode as Element
                val entries = MergedPrivacyInputs.children(node)
                val pairs = entries.map { it.tagName to it.attr("name") }
                when (parent.attr("name")) {
                    "com.ignacioli.finecoach.MainActivity" -> require(pairs.size == 2 && pairs.toSet() == setOf(
                        "action" to "android.intent.action.MAIN", "category" to "android.intent.category.LAUNCHER"))
                    "androidx.profileinstaller.ProfileInstallReceiver" -> require(pairs.size == 1 &&
                        pairs.single().first == "action" && pairs.single().second in setOf(
                            "androidx.profileinstaller.action.INSTALL_PROFILE", "androidx.profileinstaller.action.SKIP_FILE",
                            "androidx.profileinstaller.action.SAVE_PROFILE", "androidx.profileinstaller.action.BENCHMARK_OPERATION"))
                    else -> require(false) { "Unapproved system intent-filter" }
                }
            }
        }
        CapabilityPolicy.validate(manifest, if (manifest.getElementsByTagName("activity").let { activities ->
            (0 until activities.length).any { (activities.item(it) as Element).attr("name") == "androidx.activity.ComponentActivity" }
        }) "debug" else "release")
    }
}

class ScopeBoundaryTests {
    @Test fun allProductionSourcesAndMergedResourcesStayInsideS0() {
        val src = File(MergedPrivacyInputs.property("sourceRoot"))
        val roots = src.listFiles().orEmpty().filter { it.isDirectory && it.name !in setOf("test", "androidTest") } +
            MergedPrivacyInputs.variants.map { File(MergedPrivacyInputs.property("resources.$it")) }
        val files = roots.flatMap { root ->
            require(root.isDirectory)
            root.walkTopDown().filter { it.isFile && it.extension in setOf("kt", "java", "xml") }.toList()
        }
        assertTrue(files.isNotEmpty())
        files.forEach { ScopeBoundaryPolicy.validateSource(it.invariantSeparatorsPath, it.readText()) }
    }
    @Test fun bothMergedManifestsHaveOnlyShellAndApprovedLibraryEntries() {
        MergedPrivacyInputs.variants.forEach { ScopeBoundaryPolicy.validateManifest(MergedPrivacyInputs.manifest(it)) }
    }
    @Test fun rejectsStaticShortcutResource() = reject("<shortcuts><shortcut /></shortcuts>")
    @Test fun rejectsShortcutFileEvenWhenEmpty() {
        assertThrows(IllegalArgumentException::class.java) { ScopeBoundaryPolicy.validateSource("res/xml/shortcuts.xml", "<resources />") }
    }
    @Test fun rejectsDynamicShortcutRegistrationIncludingCompatAndAliases() {
        listOf("ShortcutManager", "ShortcutInfo.Builder", "ShortcutManagerCompat.pushDynamicShortcut()",
            "setDynamicShortcuts(items)", "addDynamicShortcuts(items)", "import android.content.pm.ShortcutManager as FictionalManager")
            .forEach(::reject)
    }
    @Test fun rejectsPinnedShortcutRegistration() {
        listOf("requestPinShortcut(item, callback)", "createShortcutResultIntent(item)", "ACTION_CREATE_SHORTCUT", "INSTALL_SHORTCUT").forEach(::reject)
    }
    @Test fun rejectsShortcutMetadataInMergedManifest() = mutateManifest("<meta-data android:name=\"android.app.shortcuts\" android:resource=\"@xml/fictional\" />")
    @Test fun rejectsDedicatedIntentFilter() = mutateManifest("<intent-filter><action android:name=\"fictional.START_SESSION\" /></intent-filter>", activity = true)
    @Test fun rejectsAssistantAndAppActionsSourceAndMetadata() {
        listOf("<capability android:name=\"actions.intent.START_EXERCISE\" />", "<capability-binding />", "<app-actions />",
            "VoiceInteractionService", "AppActions", "com.google.android.actions").forEach(::reject)
        mutateManifest("<meta-data android:name=\"com.google.android.actions\" android:resource=\"@xml/fictional\" />")
    }
    @Test fun rejectsS1ToS5RoutesIncludingIndirectRegistration() {
        listOf("student", "appointment", "trend", "backup", "widget").forEach { reject("composable(\"$it\") {}") }
        reject("composable(route = fictionalRoute) {}")
        reject("composable<FictionalRoute> {}")
    }
    @Test fun rejectsDeferredCapabilitiesAndContainerCodecs() {
        listOf("NotificationManager", "AlarmManager", "POST_NOTIFICATIONS", "AppWidgetProvider", "RemoteViews",
            "BackupFileCodec", "ArchiveFileCodec", "ShareReport", "ACTION_SEND", "StudentScreen", "TrendRoute").forEach(::reject)
    }
    @Test fun genericComponentDemonstrationDoesNotBecomeABusinessEntry() {
        ScopeBoundaryPolicy.validateSource("FictionalCatalog.kt", "BasicText(\"预约 / 备份 / 学员\")")
        ScopeBoundaryPolicy.validateSource("MainActivity.kt", "composable(\"placeholder\") {}")
    }
    private fun reject(source: String) {
        assertThrows(IllegalArgumentException::class.java) { ScopeBoundaryPolicy.validateSource("fictional.kt", source) }
    }
    private fun mutateManifest(xml: String, activity: Boolean = false) {
        val manifest = MergedPrivacyInputs.manifest("debug")
        val parent = manifest.getElementsByTagName(if (activity) "activity" else "application").item(0)
        val fragment = MergedPrivacyInputs.parse("<root xmlns:android=\"${MergedPrivacyInputs.ANDROID}\">$xml</root>")
        parent.appendChild(manifest.ownerDocument.importNode(fragment.firstChild, true))
        assertThrows(IllegalArgumentException::class.java) { ScopeBoundaryPolicy.validateManifest(manifest) }
    }
}
