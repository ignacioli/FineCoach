import com.google.devtools.ksp.gradle.KspAATask
import org.gradle.api.artifacts.component.ModuleComponentIdentifier
import org.gradle.api.artifacts.result.UnresolvedDependencyResult
import com.android.build.gradle.tasks.MergeResources
import com.android.build.api.artifact.SingleArtifact
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element
import org.gradle.process.CommandLineArgumentProvider
import org.gradle.process.ExecOperations
import javax.inject.Inject
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.ksp)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.roborazzi)
}

android {
    namespace = "com.ignacioli.finecoach"
    compileSdk {
        version = release(37) { minorApiLevel = 0 }
    }
    buildToolsVersion = "36.0.0"

    defaultConfig {
        applicationId = "com.ignacioli.finecoach"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true }
    testOptions { unitTests.isIncludeAndroidResources = true }
    sourceSets {
        getByName("androidTest") {
            assets.srcDir("../../shared/test-vectors")
            assets.srcDir("schemas-synthetic")
            assets.srcDir("schemas")
        }
        getByName("test") {
            resources.srcDir("../../shared/test-vectors")
        }
    }
}

kotlin { jvmToolchain(21) }

// The schema is both compiler input (history) and generated output. Keep the
// directory present on a fresh checkout; JSON contents come only from Room.
class RoomSchemaArgProvider(
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    val schemaDir: File,
) : CommandLineArgumentProvider {
    override fun asArguments(): Iterable<String> = listOf("room.schemaLocation=${schemaDir.path}")
}

ksp {
    arg("room.incremental", "true")
    arg("room.generateKotlin", "true")
}

// KSP 2.3.13 exposes task-local argument providers. Never inherit the app
// schema location in the instrumentation compilation.
tasks.withType<KspAATask>().configureEach {
    val schemaDirectory = layout.projectDirectory.dir(
        if (name.endsWith("AndroidTestKotlin")) "schemas-synthetic" else "schemas",
    )
    commandLineArgumentProviders.add(RoomSchemaArgProvider(schemaDirectory.asFile))
}

// AGP assets.srcDir does not retain builtBy dependencies (S0-04 T008).
// Order every debug androidTest consumer, including asset merge and lint model
// tasks, after the main KSP export; keep task lookup lazy and configuration-only.
tasks.matching { it.name.contains("DebugAndroidTest") }.configureEach {
    dependsOn(tasks.named<KspAATask>("kspDebugKotlin"))
}

tasks.withType<Test>().configureEach {
    inputs.dir(layout.projectDirectory.dir("schemas"))
    systemProperty("finecoach.roomSchemaDirectory", layout.projectDirectory.dir("schemas").asFile.absolutePath)
    systemProperty("finecoach.storageProjectDirectory", layout.projectDirectory.asFile.absolutePath)
}

dependencies {
    implementation(libs.room.runtime)
    ksp(libs.room.compiler)
    androidTestImplementation(libs.room.testing)
    add("kspAndroidTest", libs.room.compiler)
    implementation(libs.kotlin.stdlib)
    implementation(platform(libs.kotlinx.serialization.bom))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.runtime)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.text)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.activity.compose)
    implementation(libs.navigation.compose)

    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.test.junit)
    testImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.junit)
}

// Keep plugin cache/restore operations inside build/. Captures use an explicit
// baseline File, so plugin restore tasks can never recreate a missing baseline.
roborazzi {
    outputDir.set(layout.buildDirectory.dir("outputs/roborazzi/environment"))
}

val environmentBaseline = rootProject.layout.projectDirectory.file(
    "screenshot-baselines/environment/fixed-geometry.png",
)
val environmentClasses = listOf(
    "com.ignacioli.finecoach.EnvironmentSmokeTests",
    "com.ignacioli.finecoach.PlatformCryptoAvailabilityTests",
    "com.ignacioli.finecoach.PlatformCryptoParityTests",
    "com.ignacioli.finecoach.EnvironmentScreenshotSpikeTests",
)
val recordRequested = providers.gradleProperty("roborazzi.test.record")
    .orElse(providers.systemProperty("roborazzi.test.record")).orElse("false")

tasks.withType<Test>().configureEach {
    // Verify is the default. Only the owner's explicit record invocation writes.
    systemProperty("roborazzi.test.record", recordRequested.get())
    systemProperty("roborazzi.test.verify", providers.gradleProperty("roborazzi.test.verify")
        .orElse(recordRequested.map { (!it.equals("true", ignoreCase = true)).toString() }).get())
    systemProperty("finecoach.environmentBaseline", environmentBaseline.asFile.absolutePath)
}

val environmentSmoke = tasks.register<Test>("s0EnvironmentSmoke") {
    group = "verification"
    description = "API36/Compose/host crypto/environment screenshot verify; never record"
    check(!recordRequested.get().equals("true", ignoreCase = true) &&
        !System.getProperty("roborazzi.test.record", "false").equals("true", ignoreCase = true)) {
        "s0EnvironmentSmoke forbids roborazzi.test.record=true"
    }
    // Reuse AGP's resource-aware runtime, not its execution, filters, actions or
    // Roborazzi cache/restore finalizers. FileCollections retain build dependencies.
    val debugTest = tasks.named<Test>("testDebugUnitTest").get()
    testClassesDirs = debugTest.testClassesDirs
    classpath = debugTest.classpath
    javaLauncher.set(debugTest.javaLauncher)
    setJvmArgs(debugTest.jvmArgs)
    jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
    systemProperties(debugTest.systemProperties)
    workingDir = debugTest.workingDir
    filter {
        setIncludePatterns(*environmentClasses.toTypedArray())
        isFailOnNoMatchingTests = true
    }
    failOnNoDiscoveredTests.set(true)
    reports.junitXml.required.set(true)
    reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/s0EnvironmentSmoke"))
    reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/s0EnvironmentSmoke"))
    binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/s0EnvironmentSmoke/binary"))
    inputs.files(environmentBaseline.asFile).withPropertyName("environmentBaseline")
    outputs.dir(layout.buildDirectory.dir("reports/s0/environment"))
    // Every gate invocation must execute, rather than accept old XML/cache results.
    outputs.upToDateWhen { false }
    outputs.doNotCacheIf("Environment evidence must execute on this host") { true }
    doFirst {
        check(!recordRequested.get().equals("true", ignoreCase = true) &&
            !System.getProperty("roborazzi.test.record", "false").equals("true", ignoreCase = true) &&
            !systemProperties["roborazzi.test.record"].toString().equals("true", ignoreCase = true)) {
            "s0EnvironmentSmoke forbids roborazzi.test.record=true"
        }
        check(environmentBaseline.asFile.isFile) {
            "Missing owner-approved environment baseline: ${environmentBaseline.asFile}; never auto-record"
        }
        systemProperty("roborazzi.test.record", "false")
        systemProperty("roborazzi.test.compare", "false")
        systemProperty("roborazzi.test.verify", "true")
        systemProperty("roborazzi.compare.output.dir",
            layout.buildDirectory.dir("reports/s0/environment/images").get().asFile.absolutePath)
        systemProperty("roborazzi.result.dir",
            layout.buildDirectory.dir("reports/s0/environment/results").get().asFile.absolutePath)
        systemProperty("roborazzi.project.path", projectDir.absolutePath)
    }
}

// A finalizer also rejects NO-SOURCE/onlyIf skips, for which Test.doLast never runs.
val validateEnvironmentSmoke = tasks.register("validateS0EnvironmentSmokeResults") {
    doLast {
        val smoke = environmentSmoke.get()
        check(!smoke.state.skipped && smoke.state.failure == null) {
            "s0EnvironmentSmoke did not successfully execute: ${smoke.state.skipMessage ?: smoke.state.failure}"
        }
        val xmlFiles = smoke.reports.junitXml.outputLocation.get().asFile
            .listFiles { file -> file.name.startsWith("TEST-") && file.extension == "xml" }
            .orEmpty()
        check(xmlFiles.isNotEmpty()) { "s0EnvironmentSmoke has no JUnit XML" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
            setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val counts = mutableMapOf<String, Int>()
        for (xml in xmlFiles) {
            val suite = factory.newDocumentBuilder().parse(xml).documentElement
            val name = suite.getAttribute("name")
            check(name in environmentClasses) { "Unexpected environment suite: $name" }
            val cases = suite.getElementsByTagName("testcase")
            val count = suite.getAttribute("tests").toInt()
            check(count > 0 && count == cases.length) { "Empty/inconsistent suite: $name" }
            for (attribute in listOf("failures", "errors", "skipped")) {
                check(suite.getAttribute(attribute).toInt() == 0) { "$name has $attribute" }
            }
            for (index in 0 until cases.length) {
                val case = cases.item(index) as Element
                check(listOf("skipped", "failure", "error").all {
                    case.getElementsByTagName(it).length == 0
                }) { "Unsuccessful testcase: $name.${case.getAttribute("name")}" }
            }
            check(counts.put(name, count) == null) { "Duplicate suite: $name" }
        }
        check(counts.keys == environmentClasses.toSet()) { "Missing environment suites: ${environmentClasses - counts.keys}" }
        logger.lifecycle("s0EnvironmentSmoke: ${counts.values.sum()} tests, 0 failures/errors/skips; $counts")
    }
}
environmentSmoke.configure { finalizedBy(validateEnvironmentSmoke) }

val roomClasses = listOf(
    "com.ignacioli.finecoach.RoomSkeletonTests",
    "com.ignacioli.finecoach.StorageValueTests",
    "com.ignacioli.finecoach.StoragePrivacyTests",
)
val roomGate = tasks.register<Test>("s0Room") {
    group = "verification"
    description = "Room skeleton and storage values/privacy (JVM only)"
    val debugTest = tasks.named<Test>("testDebugUnitTest").get()
    testClassesDirs = debugTest.testClassesDirs
    classpath = debugTest.classpath
    javaLauncher.set(debugTest.javaLauncher)
    setJvmArgs(debugTest.jvmArgs)
    jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
    systemProperties(debugTest.systemProperties)
    workingDir = debugTest.workingDir
    filter {
        setIncludePatterns(*roomClasses.toTypedArray())
        isFailOnNoMatchingTests = true
    }
    failOnNoDiscoveredTests.set(true)
    reports.junitXml.required.set(true)
    reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/s0Room"))
    reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/s0Room"))
    binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/s0Room/binary"))
    outputs.upToDateWhen { false }
    outputs.doNotCacheIf("Room evidence must execute on this host") { true }
}

val validateRoomGate = tasks.register("validateS0RoomResults") {
    doLast {
        val gate = roomGate.get()
        check(!gate.state.skipped && gate.state.failure == null) {
            "s0Room did not successfully execute: ${gate.state.skipMessage ?: gate.state.failure}"
        }
        val xmlFiles = gate.reports.junitXml.outputLocation.get().asFile
            .listFiles { file -> file.name.startsWith("TEST-") && file.extension == "xml" }
            .orEmpty()
        check(xmlFiles.isNotEmpty()) { "s0Room has no JUnit XML" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
            setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val counts = mutableMapOf<String, Int>()
        for (xml in xmlFiles) {
            val suite = factory.newDocumentBuilder().parse(xml).documentElement
            val name = suite.getAttribute("name")
            check(name in roomClasses) { "Unexpected Room suite: $name" }
            val cases = suite.getElementsByTagName("testcase")
            val count = suite.getAttribute("tests").toInt()
            check(count > 0 && count == cases.length) { "Empty/inconsistent suite: $name" }
            for (attribute in listOf("failures", "errors", "skipped")) {
                check(suite.getAttribute(attribute).toInt() == 0) { "$name has $attribute" }
            }
            for (index in 0 until cases.length) {
                val case = cases.item(index) as Element
                check(listOf("skipped", "failure", "error").all {
                    case.getElementsByTagName(it).length == 0
                }) { "Unsuccessful testcase: $name.${case.getAttribute("name")}" }
            }
            check(counts.put(name, count) == null) { "Duplicate suite: $name" }
        }
        check(counts.keys == roomClasses.toSet()) { "Missing Room suites: ${roomClasses - counts.keys}" }
        logger.lifecycle("s0Room: ${counts.values.sum()} tests, 0 failures/errors/skips; $counts")
    }
}
roomGate.configure { finalizedBy(validateRoomGate) }

androidComponents {
    onVariants(selector().withBuildType("debug")) { variant ->
        val mergedManifest = variant.artifacts.get(SingleArtifact.MERGED_MANIFEST)
        tasks.withType<Test>().configureEach {
            // Robolectric 4.17 reads FileDescriptor internals on JDK 21.
            jvmArgs("--add-exports=java.base/jdk.internal.access=ALL-UNNAMED")
            inputs.file(mergedManifest)
            systemProperty("finecoach.mergedManifest", mergedManifest.get().asFile.absolutePath)
            systemProperty("finecoach.compileSdk", android.compileSdk.toString())
        }
    }
}

// T004: retain provider dependencies for both manifests and merged XML outputs.
androidComponents {
    onVariants { variant ->
        val name = variant.name
        if (name == "debug" || name == "release") {
            val manifest = variant.artifacts.get(SingleArtifact.MERGED_MANIFEST)
            val mergeTaskName = "merge" + name.replaceFirstChar { it.uppercaseChar() } + "Resources"
            val resources = layout.buildDirectory.dir("privacyMergedResources/" + name)
            tasks.withType<MergeResources>().configureEach {
                if (this.name == mergeTaskName) mergedNotCompiledResourcesOutputDirectory.set(resources)
            }
            tasks.withType<Test>().matching { it.name == "testDebugUnitTest" || it.name == "testReleaseUnitTest" }.configureEach {
                inputs.file(manifest)
                inputs.dir(resources)
                dependsOn(mergeTaskName)
                systemProperty("finecoach.manifest." + name, manifest.get().asFile.absolutePath)
                systemProperty("finecoach.resources." + name, resources.get().asFile.absolutePath)
            }
        }
    }
}

// T005: resolve the same complete configurations as the host inventory.
val privacyDependencyReport = layout.buildDirectory.file("reports/s0/privacy/resolved.txt")
val privacyDependencyGraph = tasks.register("writePrivacyDependencyGraph") {
    val allowlist = rootProject.layout.projectDirectory.file("dependency-allowlist/resolved.txt")
    inputs.file(allowlist)
    outputs.file(privacyDependencyReport)
    outputs.upToDateWhen { false }
    doLast {
        val graphs = listOf(
            "app:debugCompileClasspath" to configurations.getByName("debugCompileClasspath"),
            "app:debugRuntimeClasspath" to configurations.getByName("debugRuntimeClasspath"),
            "app:releaseCompileClasspath" to configurations.getByName("releaseCompileClasspath"),
            "app:releaseRuntimeClasspath" to configurations.getByName("releaseRuntimeClasspath"),
            "app:debugUnitTestRuntimeClasspath" to configurations.getByName("debugUnitTestRuntimeClasspath"),
            "app:debugAndroidTestRuntimeClasspath" to configurations.getByName("debugAndroidTestRuntimeClasspath"),
            "app:kspDebugKotlinProcessorClasspath" to configurations.getByName("kspDebugKotlinProcessorClasspath"),
            "app:kspReleaseKotlinProcessorClasspath" to configurations.getByName("kspReleaseKotlinProcessorClasspath"),
            "app:kspDebugUnitTestKotlinProcessorClasspath" to configurations.getByName("kspDebugUnitTestKotlinProcessorClasspath"),
            "app:kspDebugAndroidTestKotlinProcessorClasspath" to configurations.getByName("kspDebugAndroidTestKotlinProcessorClasspath"),
            "app:classpath" to buildscript.configurations.getByName("classpath"),
            "root:classpath" to rootProject.buildscript.configurations.getByName("classpath"),
        )
        val rows = mutableListOf<String>()
        graphs.forEach { (scope, configuration) ->
            val result = configuration.incoming.resolutionResult
            check(result.allDependencies.none { it is UnresolvedDependencyResult }) { "Unresolved dependencies: " + scope }
            rows += "# scope " + scope
            result.allComponents.mapNotNull { it.id as? ModuleComponentIdentifier }
                .map { it.group + ":" + it.module + ":" + it.version + " " + scope }
                .distinct().sorted().forEach { rows += it }
        }
        privacyDependencyReport.get().asFile.apply { parentFile.mkdirs(); writeText(rows.joinToString("\n") + "\n") }
    }
}
androidComponents {
    onVariants(selector().withBuildType("debug")) { variant ->
        val apk = variant.artifacts.get(SingleArtifact.APK)
        tasks.withType<Test>().matching { it.name == "testDebugUnitTest" }.configureEach {
            inputs.dir(apk)
            systemProperty("finecoach.debugApk", apk.get().asFile.absolutePath)
        }
    }
    onVariants(selector().withBuildType("release")) { variant ->
        val apk = variant.artifacts.get(SingleArtifact.APK)
        tasks.withType<Test>().matching { it.name == "testDebugUnitTest" || it.name == "testReleaseUnitTest" }.configureEach {
            inputs.dir(apk)
            systemProperty("finecoach.releaseApk", apk.get().asFile.absolutePath)
        }
    }
}
tasks.withType<Test>().matching { it.name == "testDebugUnitTest" || it.name == "testReleaseUnitTest" }.configureEach {
    dependsOn(privacyDependencyGraph)
    // T019/S0-14 visual suites run only in s0G5 / s0Conformance, never in the unit gate.
    // The owner's explicit record run (README T019) is the only path that keeps ComponentScreenshotTests.
    filter {
        if (!recordRequested.get().equals("true", ignoreCase = true)) excludeTestsMatching("com.ignacioli.finecoach.ComponentScreenshotTests")
        excludeTestsMatching("com.ignacioli.finecoach.TrainingConformanceTests")
        excludeTestsMatching("com.ignacioli.finecoach.ExerciseConformanceTests")
        excludeTestsMatching("com.ignacioli.finecoach.AddExerciseConformanceTests")
        excludeTestsMatching("com.ignacioli.finecoach.TodayConformanceTests")
        excludeTestsMatching("com.ignacioli.finecoach.SessionDetailConformanceTests")
        excludeTestsMatching("com.ignacioli.finecoach.StudentListConformanceTests")
        excludeTestsMatching("com.ignacioli.finecoach.StudentDetailConformanceTests")
        excludeTestsMatching("com.ignacioli.finecoach.P7SideBySideTests")
    }
    inputs.file(privacyDependencyReport)
    inputs.file(rootProject.layout.projectDirectory.file("dependency-allowlist/resolved.txt"))
    inputs.dir(layout.projectDirectory.dir("src/main"))
    inputs.dir(rootProject.layout.projectDirectory.dir("../shared"))
    inputs.dir(layout.projectDirectory.dir("schemas-synthetic"))
    inputs.files(fileTree("src") { include("**/resources/**", "**/assets/**", "**/seeds/**", "**/fixtures/**") })
    inputs.files(fileTree("src") { include("debug/**/*.kt", "debug/**/*.java", "release/**/*.kt", "release/**/*.java") })
    systemProperty("finecoach.sourceRoot", layout.projectDirectory.dir("src").asFile.absolutePath)
    systemProperty("finecoach.dependencies", privacyDependencyReport.get().asFile.absolutePath)
    systemProperty("finecoach.dependencyAllowlist", rootProject.layout.projectDirectory.file("dependency-allowlist/resolved.txt").asFile.absolutePath)
}

// Reserve the approved interfaces. Each is replaced by its owning task only
// when the full, non-empty test/report contract is implemented (plan section 4).
val pendingGates = mapOf(
    "s0G8" to "T004-T010: complete privacy and scope checks",
)
pendingGates.forEach { (gate, owner) ->
    tasks.register(gate) {
        group = "verification"
        description = "未实现 — $owner"
        doLast { throw GradleException("$gate 未实现：$owner；不能报告 PASS。") }
    }
}

// T019: the exact S1 suites run independently of the broad JVM gate.
val s1SeedChecks = tasks.register<Test>("s1SeedChecks") {
    group = "verification"
    val debugTest = tasks.named<Test>("testDebugUnitTest").get()
    testClassesDirs = debugTest.testClassesDirs
    classpath = debugTest.classpath
    javaLauncher.set(debugTest.javaLauncher)
    setJvmArgs(debugTest.jvmArgs)
    jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
    systemProperties(debugTest.systemProperties)
    workingDir = debugTest.workingDir
    filter {
        setIncludePatterns("com.ignacioli.finecoach.S1DebugSeedTests", "com.ignacioli.finecoach.S1SeedIsolationTests")
        isFailOnNoMatchingTests = true
    }
    failOnNoDiscoveredTests.set(true)
    reports.junitXml.required.set(true)
    reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/s1SeedChecks"))
    reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/s1SeedChecks"))
    binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/s1SeedChecks/binary"))
    outputs.upToDateWhen { false }
    outputs.doNotCacheIf("Seed checks must execute") { true }
    doLast {
        val expected = mapOf("com.ignacioli.finecoach.S1DebugSeedTests" to 12, "com.ignacioli.finecoach.S1SeedIsolationTests" to 4)
        val files = reports.junitXml.outputLocation.get().asFile.listFiles { file -> file.name.startsWith("TEST-") && file.extension == "xml" }.orEmpty()
        check(files.size == expected.size) { "S1 seed checks must run nonzero tests without failures or skips" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
            setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val actual = files.associate { file ->
            val suite = factory.newDocumentBuilder().parse(file).documentElement
            check(suite.getAttribute("failures") == "0" && suite.getAttribute("errors") == "0" && suite.getAttribute("skipped") == "0") {
                "S1 seed checks must run nonzero tests without failures or skips"
            }
            suite.getAttribute("name") to suite.getAttribute("tests").toInt()
        }
        check(actual == expected) { "S1 seed checks must run nonzero tests without failures or skips" }
        actual.forEach { (suite, count) -> logger.lifecycle("S1-SEED-CHECK suite=$suite tests=$count failures=0 errors=0 skips=0") }
    }
}

// S0-12: inspect the actual APK entries, including binary XML/string pools.
val seedIsolation = tasks.register("s0SeedIsolation") {
    group = "verification"
    description = "Reject debug seed/catalog code, resources and entries in the assembled Release APK"
    dependsOn("assembleRelease", s1SeedChecks)
}
androidComponents.onVariants(androidComponents.selector().withBuildType("release")) { variant ->
    val apkDirectory = variant.artifacts.get(SingleArtifact.APK)
    seedIsolation.configure {
        inputs.dir(apkDirectory)
        doLast {
            val apks = apkDirectory.get().asFile.walkTopDown().filter { it.isFile && it.extension == "apk" }.toList()
            check(apks.size == 1) { "s0SeedIsolation: expected exactly one Release APK" }
            val forbidden = listOf(
                "com/ignacioli/finecoach/seed/", "com.ignacioli.finecoach.seed.",
                "S1DebugSeed", "S1SeedIDs", "s1_debug_seed.", "s1-debug-seed.lock", "fictional-s1-coach-core-v1", "fictional-s1-coach-core-v2", "fictional-s1-coach-core-v3", "S1SeedFixture", "seed/s1-seed.json",
                "DebugSeed", "SeedContributor", "SeedResult", "MetadataSeedContributor",
                "S0ComponentCatalog", "S0Catalog", "S0DebugApplication", "FineCoachSeed", "finecoach-debug-seed.db",
                "debug_seed.", "debug_seed_", "s0_catalog", "s0_seed", "SEED version=",
            )
            val encoded = forbidden.flatMap { name ->
                listOf(Charsets.UTF_8, Charsets.UTF_16LE, Charsets.UTF_16BE).map {
                    String(name.toByteArray(it), Charsets.ISO_8859_1)
                }
            }
            var dexCount = 0
            var resourceCount = 0
            var manifestCount = 0
            ZipFile(apks.single()).use { zip ->
                for (entry in zip.entries().asSequence().filter { !it.isDirectory }) {
                    check(forbidden.none { entry.name.contains(it, ignoreCase = true) } &&
                        !Regex("(?i)(^|[/_.-])(seed|catalog)([/_.-]|$)").containsMatchIn(entry.name)) {
                        "s0SeedIsolation: debug APK entry ${entry.name}"
                    }
                    if (Regex("classes[0-9]*\\.dex").matches(entry.name)) dexCount++
                    if (entry.name == "AndroidManifest.xml") manifestCount++
                    if (entry.name == "resources.arsc") resourceCount++
                    val content = zip.getInputStream(entry).use { String(it.readBytes(), Charsets.ISO_8859_1) }
                    check(encoded.none { content.contains(it) }) { "s0SeedIsolation: debug content in ${entry.name}" }
                }
            }
            check(dexCount > 0 && manifestCount == 1 && resourceCount == 1) {
                "s0SeedIsolation: missing dex, manifest or resource table"
            }
            val digest = MessageDigest.getInstance("SHA-256").digest(apks.single().readBytes())
                .joinToString("") { "%02x".format(it) }
            logger.lifecycle("s0SeedIsolation: status=ok apk=${apks.single().name} sha256=$digest dex=$dexCount manifest=1 resources=1")
        }
    }
}

// No shell command strings: serial and arguments remain distinct process arguments.
abstract class SeedDeviceTask : DefaultTask() {
    @get:InputFile abstract val adbFile: RegularFileProperty
    @get:Input abstract val deviceSerial: Property<String>
    @get:Input abstract val environmentSerial: Property<String>

    fun adb(vararg arguments: String): String {
        val output = temporaryDir.resolve("adb-output.txt")
        val process = ProcessBuilder(listOf(adbFile.get().asFile.absolutePath) + arguments)
            .redirectErrorStream(true).redirectOutput(output).start()
        try {
            check(process.waitFor(60, TimeUnit.SECONDS)) { "S0 seed adb command timed out" }
            check(process.exitValue() == 0) { "S0 seed adb command failed (exit=${process.exitValue()})" }
            return output.readText()
        } finally {
            if (process.isAlive) process.destroyForcibly()
            output.delete()
        }
    }

    fun requireSingleDevice(): String {
        val serial = deviceSerial.get()
        check(Regex("[A-Za-z0-9][A-Za-z0-9._:-]*").matches(serial)) {
            "Specify -Pandroid.device=<serial> or ANDROID_SERIAL; no automatic selection"
        }
        check(environmentSerial.get().isBlank() || environmentSerial.get() == serial) { "Conflicting ANDROID_SERIAL and android.device" }
        val inventory = adb("devices", "-l")
        check(inventory.contains("List of devices attached")) { "Missing adb inventory" }
        val devices = inventory.substringAfter("List of devices attached").lineSequence()
            .filter { it.isNotBlank() }.map { it.trim().split(Regex("\\s+")) }.toList()
        check(devices.size == 1 && devices.single().take(2) == listOf(serial, "device")) {
            "Exactly one connected, authorized device matching the explicit serial is required"
        }
        return serial
    }
}

val seedDeviceSerial = providers.gradleProperty("android.device").orElse(providers.environmentVariable("ANDROID_SERIAL")).orElse("")
val validateSeedDevice = tasks.register<SeedDeviceTask>("validateS0SeedDevice") {
    group = "verification"
    adbFile.set(androidComponents.sdkComponents.adb)
    deviceSerial.set(seedDeviceSerial)
    environmentSerial.set(providers.environmentVariable("ANDROID_SERIAL").orElse(""))
    doLast { requireSingleDevice() }
}
// Ordering is added without changing the behavior of a direct installDebug invocation.
tasks.matching { it.name == "installDebug" }.configureEach { mustRunAfter(validateSeedDevice) }
val requestedSeedScenario = providers.gradleProperty("s1.seedScenario").orElse("multi")
val installSeededDebug = tasks.register<SeedDeviceTask>("s0InstallSeededDebug") {
    group = "verification"
    description = "Build/install S1DebugSeed on one explicit device, verify durable seed, launch default S1"
    dependsOn(validateSeedDevice, "assembleDebug")
    inputs.property("seedScenario", requestedSeedScenario)
    inputs.file(layout.projectDirectory.file("src/debug/assets/seed/s1-seed.json"))
    adbFile.set(androidComponents.sdkComponents.adb)
    deviceSerial.set(seedDeviceSerial)
    environmentSerial.set(providers.environmentVariable("ANDROID_SERIAL").orElse(""))
}
androidComponents.onVariants(androidComponents.selector().withBuildType("debug")) { variant ->
    val apkDirectory = variant.artifacts.get(SingleArtifact.APK)
    installSeededDebug.configure {
        inputs.dir(apkDirectory)
        doLast {
            val serial = requireSingleDevice()
            val scenario = requestedSeedScenario.get()
            check(scenario in setOf("empty", "single", "multi")) { "Unknown S1 seed scenario" }
            val apks = apkDirectory.get().asFile.walkTopDown().filter { it.isFile && it.extension == "apk" }.toList()
            check(apks.size == 1) { "Expected exactly one Debug APK" }
            val installed = adb("-s", serial, "install", "-r", "-t", apks.single().absolutePath)
            check(installed.lineSequence().any { it.trim() == "Success" }) { "Debug APK installation failed" }
            adb("-s", serial, "shell", "am", "force-stop", "com.ignacioli.finecoach")
            val api = adb("-s", serial, "shell", "getprop", "ro.build.version.sdk").trim().toInt()
            check(api >= 31) { "S0 requires API 31+" }
            val build = adb("-s", serial, "shell", "getprop", "ro.build.id").trim()
            val result = adb("-s", serial, "shell", "am", "instrument", "-w", "-r",
                "-e", "scenario", scenario, "com.ignacioli.finecoach/.seed.DebugSeedInstrumentation")
            val lines = result.lineSequence().map { it.trim() }.toList()
            check(lines.count { it == "INSTRUMENTATION_CODE: -1" } == 1 &&
                lines.none { it.startsWith("INSTRUMENTATION_FAILED") || it.startsWith("INSTRUMENTATION_ABORTED") }) {
                "Seed instrumentation did not finish successfully"
            }
            fun resultValue(key: String): String = lines.single { it.startsWith("INSTRUMENTATION_RESULT: $key=") }.substringAfter('=')
            val expected = resultValue("seed")
            val fixture = groovy.json.JsonSlurper().parse(file("src/debug/assets/seed/s1-seed.json")) as Map<*, *>
            val expectedRows = requireNotNull((fixture["expectedRows"] as Map<*, *>)[scenario])
            val expectedVersion = requireNotNull(fixture["seedVersion"])
            check(expected == "SEED version=$expectedVersion rows=$expectedRows status=ok") { "Missing successful S1 seed result" }
            val pid = resultValue("seed_pid").toInt().also { check(it > 0) }
            val loggedAt = resultValue("seed_log_time").toLong().also { check(it > 0) }
            val logs = adb("-s", serial, "logcat", "-d", "-v", "epoch", "--pid=$pid", "-s", "FineCoachSeed:I", "*:S")
            val logPattern = Regex("^\\s*([0-9]+\\.[0-9]+)\\s+[0-9]+\\s+[0-9]+\\s+I\\s+FineCoachSeed\\s*:\\s*(SEED .*)$")
            val fresh = logs.lineSequence().mapNotNull { logPattern.matchEntire(it) }.filter {
                it.groupValues[1].toBigDecimal().multiply(1000.toBigDecimal()).toLong() >= loggedAt
            }.map { it.groupValues[2] }.toList()
            check(fresh == listOf(expected)) { "Missing, duplicate or stale SEED logcat event" }
            val launch = adb("-s", serial, "shell", "am", "start", "-W", "-n", "com.ignacioli.finecoach/.MainActivity")
            check(launch.lineSequence().any { it.trim() == "Status: ok" } && !launch.contains("Error:")) { "Debug shell launch failed" }
            val digest = MessageDigest.getInstance("SHA-256").digest(apks.single().readBytes())
                .joinToString("") { "%02x".format(it) }
            logger.lifecycle(expected)
            logger.lifecycle("s0InstallSeededDebug: status=ok serial=$serial api=$api build=$build apkSha256=$digest")
        }
    }
}

// T013: README is the only generation input; build outputs are never committed.
abstract class GenerateDesignTokensTask : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val generatorScript: RegularFileProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sourceReadme: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @get:Inject
    abstract val execOperations: ExecOperations

    @TaskAction
    fun generate() {
        execOperations.exec {
            commandLine("node", generatorScript.get().asFile.absolutePath,
                "--input", sourceReadme.get().asFile.absolutePath,
                "--output", outputDir.get().asFile.absolutePath)
        }.assertNormalExitValue()
    }
}

val designTokenScript = rootProject.layout.projectDirectory.file("../scripts/android/generate-tokens.mjs")
val designTokenReadme = rootProject.layout.projectDirectory.file("../design/design-system/README.md")
val designTokenOutput = layout.buildDirectory.dir("generated/designtokens")
val generateDesignTokens = tasks.register<GenerateDesignTokensTask>("generateDesignTokens") {
    group = "build"
    description = "Generate the four approved design token Kotlin files"
    generatorScript.set(designTokenScript)
    sourceReadme.set(designTokenReadme)
    outputDir.set(designTokenOutput)
}
val checkDesignTokens = tasks.register<Exec>("checkDesignTokens") {
    group = "verification"
    description = "Regenerate in a temporary directory and reject missing/extra/edited output"
    inputs.file(designTokenScript)
    inputs.file(designTokenReadme)
    // Inspect the existing output at execution time, without a producer input
    // dependency that could regenerate (and hide) an edit before verification.
    // This Exec has no outputs/cache entry and therefore always executes.
    // Bootstrap only an absent output directory. Existing output must be checked
    // before compile's generator can replace it, including on an incremental build.
    doFirst {
        if (!designTokenOutput.get().asFile.exists()) {
            providers.exec {
                commandLine("node", designTokenScript.asFile.absolutePath,
                    "--input", designTokenReadme.asFile.absolutePath,
                    "--output", designTokenOutput.get().asFile.absolutePath)
            }.result.get().assertNormalExitValue()
        }
    }
    commandLine("node", designTokenScript.asFile.absolutePath,
        "--input", designTokenReadme.asFile.absolutePath,
        "--output", designTokenOutput.get().asFile.absolutePath, "--check")
}
generateDesignTokens.configure { mustRunAfter(checkDesignTokens) }
androidComponents {
    onVariants { variant ->
        requireNotNull(variant.sources.kotlin) { "Missing Kotlin sources for ${variant.name}" }
            .addGeneratedSourceDirectory(generateDesignTokens, GenerateDesignTokensTask::outputDir)
    }
}

val designTokenClasses = listOf(
    "com.ignacioli.finecoach.TokenParityTests",
    "com.ignacioli.finecoach.TypographyTests",
    "com.ignacioli.finecoach.ContrastTests",
    "com.ignacioli.finecoach.TokenGeneratorTests",
)
val designTokenGate = tasks.register<Test>("s0G1") {
    group = "verification"
    description = "Token generation/parity, typography, contrast and generator negative tests"
    dependsOn(checkDesignTokens)
    val debugTest = tasks.named<Test>("testDebugUnitTest").get()
    testClassesDirs = debugTest.testClassesDirs
    classpath = debugTest.classpath
    javaLauncher.set(debugTest.javaLauncher)
    setJvmArgs(debugTest.jvmArgs)
    jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
    systemProperties(debugTest.systemProperties)
    workingDir = debugTest.workingDir
    filter {
        setIncludePatterns(*designTokenClasses.toTypedArray())
        isFailOnNoMatchingTests = true
    }
    failOnNoDiscoveredTests.set(true)
    reports.junitXml.required.set(true)
    reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/s0G1"))
    reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/s0G1"))
    binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/s0G1/binary"))
    inputs.file(designTokenScript)
    inputs.file(designTokenReadme)
    outputs.upToDateWhen { false }
    outputs.doNotCacheIf("G1 evidence must execute on this host") { true }
}
val validateDesignTokenGate = tasks.register("validateS0G1Results") {
    doLast {
        val gate = designTokenGate.get()
        check(!gate.state.skipped && gate.state.failure == null) {
            "s0G1 did not successfully execute: ${gate.state.skipMessage ?: gate.state.failure}"
        }
        val xmlFiles = gate.reports.junitXml.outputLocation.get().asFile
            .listFiles { file -> file.name.startsWith("TEST-") && file.extension == "xml" }.orEmpty()
        check(xmlFiles.isNotEmpty()) { "s0G1 has no JUnit XML" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
            setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val counts = mutableMapOf<String, Int>()
        for (xml in xmlFiles) {
            val suite = factory.newDocumentBuilder().parse(xml).documentElement
            val name = suite.getAttribute("name")
            check(name in designTokenClasses) { "Unexpected G1 suite: $name" }
            val cases = suite.getElementsByTagName("testcase")
            val count = suite.getAttribute("tests").toInt()
            check(count > 0 && count == cases.length) { "Empty/inconsistent G1 suite: $name" }
            for (attribute in listOf("failures", "errors", "skipped")) {
                check(suite.getAttribute(attribute).toInt() == 0) { "$name has $attribute" }
            }
            for (index in 0 until cases.length) {
                val case = cases.item(index) as Element
                check(listOf("skipped", "failure", "error").all {
                    case.getElementsByTagName(it).length == 0
                }) { "Unsuccessful G1 testcase: $name.${case.getAttribute("name")}" }
            }
            check(counts.put(name, count) == null) { "Duplicate G1 suite: $name" }
        }
        check(counts.keys == designTokenClasses.toSet()) { "Missing G1 suites: ${designTokenClasses - counts.keys}" }
        val expectedCounts = mapOf(
            "com.ignacioli.finecoach.TokenParityTests" to 6,
            "com.ignacioli.finecoach.TypographyTests" to 7,
            "com.ignacioli.finecoach.ContrastTests" to 17,
            "com.ignacioli.finecoach.TokenGeneratorTests" to 9,
        )
        check(counts == expectedCounts) { "Unexpected G1 testcase counts: $counts; expected $expectedCounts" }
        logger.lifecycle("s0G1: ${counts.values.sum()} tests, 0 failures/errors/skips; $counts")
    }
}
designTokenGate.configure { finalizedBy(validateDesignTokenGate) }


// T016: non-empty, verify-only G2; no screenshot recording or G3/G4 prerequisites.
val componentClasses = listOf(
    "com.ignacioli.finecoach.ComponentCatalogTests",
    "com.ignacioli.finecoach.ComponentCatalogStateTests",
    "com.ignacioli.finecoach.ComponentContractTests",
    "com.ignacioli.finecoach.PlatformShellTests",
)
val componentGate = tasks.register<Test>("s0G2") {
    group = "verification"
    description = "Approved component roster, representative states, contracts and platform shell"
    dependsOn(checkDesignTokens)
    val debugTest = tasks.named<Test>("testDebugUnitTest").get()
    testClassesDirs = debugTest.testClassesDirs
    classpath = debugTest.classpath
    javaLauncher.set(debugTest.javaLauncher)
    setJvmArgs(debugTest.jvmArgs)
    jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
    systemProperties(debugTest.systemProperties)
    workingDir = debugTest.workingDir
    filter {
        setIncludePatterns(*componentClasses.toTypedArray())
        isFailOnNoMatchingTests = true
    }
    failOnNoDiscoveredTests.set(true)
    reports.junitXml.required.set(true)
    reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/s0G2"))
    reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/s0G2"))
    binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/s0G2/binary"))
    inputs.file(rootProject.layout.projectDirectory.file("../design/design-system/components.md"))
    inputs.dir(layout.projectDirectory.dir("src/main/java/com/ignacioli/finecoach/designsystem"))
    inputs.dir(layout.projectDirectory.dir("src/debug"))
    outputs.upToDateWhen { false }
    outputs.doNotCacheIf("G2 evidence must execute on this host") { true }
}
val validateComponentGate = tasks.register("validateS0G2Results") {
    doLast {
        val gate = componentGate.get()
        check(!gate.state.skipped && gate.state.failure == null) {
            "s0G2 did not successfully execute: ${gate.state.skipMessage ?: gate.state.failure}"
        }
        val xmlFiles = gate.reports.junitXml.outputLocation.get().asFile
            .listFiles { file -> file.name.startsWith("TEST-") && file.extension == "xml" }.orEmpty()
        check(xmlFiles.isNotEmpty()) { "s0G2 has no JUnit XML" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
            setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val counts = mutableMapOf<String, Int>()
        for (xml in xmlFiles) {
            val suite = factory.newDocumentBuilder().parse(xml).documentElement
            val name = suite.getAttribute("name")
            check(name in componentClasses) { "Unexpected G2 suite: $name" }
            val cases = suite.getElementsByTagName("testcase")
            val count = suite.getAttribute("tests").toInt()
            check(count > 0 && count == cases.length) { "Empty/inconsistent G2 suite: $name" }
            for (attribute in listOf("failures", "errors", "skipped")) {
                check(suite.getAttribute(attribute).toInt() == 0) { "$name has $attribute" }
            }
            for (index in 0 until cases.length) {
                val case = cases.item(index) as Element
                check(listOf("skipped", "failure", "error").all {
                    case.getElementsByTagName(it).length == 0
                }) { "Unsuccessful G2 testcase: $name.${case.getAttribute("name")}" }
            }
            check(counts.put(name, count) == null) { "Duplicate G2 suite: $name" }
        }
        check(counts.keys == componentClasses.toSet()) { "Missing G2 suites: ${componentClasses - counts.keys}" }
        val expectedCounts = mapOf(
            "com.ignacioli.finecoach.ComponentCatalogTests" to 6,
            "com.ignacioli.finecoach.ComponentCatalogStateTests" to 66,
            "com.ignacioli.finecoach.ComponentContractTests" to 36,
            "com.ignacioli.finecoach.PlatformShellTests" to 5,
        )
        check(counts == expectedCounts) { "Unexpected G2 testcase counts: $counts; expected $expectedCounts" }
        logger.lifecycle("s0G2: ${counts.values.sum()} tests, 0 failures/errors/skips; $counts")
    }
}
componentGate.configure { finalizedBy(validateComponentGate) }

// S0-06: read source fixtures directly; never copy them into an app bundle.
val sharedVectorRoot = rootProject.layout.projectDirectory.dir("../shared/test-vectors")
// Standard testDebugUnitTest must also be able to discover these source files.
tasks.withType<Test>().configureEach {
    inputs.dir(sharedVectorRoot)
    systemProperty("finecoach.sharedVectorRoot", sharedVectorRoot.asFile.absolutePath)
}
val sharedVectorClasses = listOf(
    "com.ignacioli.finecoach.VectorFormatTests",
    "com.ignacioli.finecoach.SharedVectorTests",
)
val sharedVectorGate = tasks.register<Test>("s0G6") {
    group = "verification"
    description = "Shared vector conformance and real Domain samples; separate locked counts"
    val debugTest = tasks.named<Test>("testDebugUnitTest").get()
    testClassesDirs = debugTest.testClassesDirs
    classpath = debugTest.classpath
    javaLauncher.set(debugTest.javaLauncher)
    setJvmArgs(debugTest.jvmArgs)
    jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
    systemProperties(debugTest.systemProperties)
    workingDir = debugTest.workingDir
    filter {
        setIncludePatterns(*sharedVectorClasses.toTypedArray())
        isFailOnNoMatchingTests = true
    }
    failOnNoDiscoveredTests.set(true)
    reports.junitXml.required.set(true)
    reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/s0G6"))
    reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/s0G6"))
    binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/s0G6/binary"))
    outputs.upToDateWhen { false }
    outputs.doNotCacheIf("G6 evidence must execute on this host") { true }
}
val validateSharedVectorGate = tasks.register("validateS0G6Results") {
    doLast {
        val gate = sharedVectorGate.get()
        check(!gate.state.skipped && gate.state.failure == null) {
            "s0G6 did not successfully execute: ${gate.state.skipMessage ?: gate.state.failure}"
        }
        val xmlFiles = gate.reports.junitXml.outputLocation.get().asFile
            .listFiles { file -> file.name.startsWith("TEST-") && file.extension == "xml" }.orEmpty()
        check(xmlFiles.isNotEmpty()) { "s0G6 has no JUnit XML" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
            setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val counts = mutableMapOf<String, Int>()
        for (xml in xmlFiles) {
            val suite = factory.newDocumentBuilder().parse(xml).documentElement
            val name = suite.getAttribute("name")
            check(name in sharedVectorClasses) { "Unexpected G6 suite: $name" }
            val cases = suite.getElementsByTagName("testcase")
            val count = suite.getAttribute("tests").toInt()
            check(count > 0 && count == cases.length) { "Empty/inconsistent G6 suite: $name" }
            for (attribute in listOf("failures", "errors", "skipped")) {
                check(suite.getAttribute(attribute).toInt() == 0) { "$name has $attribute" }
            }
            for (index in 0 until cases.length) {
                val case = cases.item(index) as Element
                check(listOf("skipped", "failure", "error").all {
                    case.getElementsByTagName(it).length == 0
                }) { "Unsuccessful G6 testcase: $name.${case.getAttribute("name")}" }
            }
            check(counts.put(name, count) == null) { "Duplicate G6 suite: $name" }
        }
        check(counts.keys == sharedVectorClasses.toSet()) { "Missing G6 suites: ${sharedVectorClasses - counts.keys}" }
        val expectedCounts = mapOf(
            "com.ignacioli.finecoach.VectorFormatTests" to 72,
            "com.ignacioli.finecoach.SharedVectorTests" to 5,
        )
        check(counts == expectedCounts) { "Unexpected G6 testcase counts: $counts; expected $expectedCounts" }
        logger.lifecycle("s0G6: ${counts.values.sum()} tests, 0 failures/errors/skips; $counts")
    }
}
sharedVectorGate.configure { finalizedBy(validateSharedVectorGate) }

// T019/S0-14: isolated tasks reuse T003's resource-aware JVM without plugin
// restore/finalizers. No gate ever accepts a record request.
fun registerVisualGate(taskName: String, suite: String, expectedTests: Int): TaskProvider<Test> {
    val gate = tasks.register<Test>(taskName) {
        group = "verification"
        val debugTest = tasks.named<Test>("testDebugUnitTest").get()
        testClassesDirs = debugTest.testClassesDirs
        classpath = debugTest.classpath
        javaLauncher.set(debugTest.javaLauncher)
        setJvmArgs(debugTest.jvmArgs)
        jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
        systemProperties(debugTest.systemProperties)
        workingDir = debugTest.workingDir
        filter { setIncludePatterns("com.ignacioli.finecoach.$suite"); isFailOnNoMatchingTests = true }
        failOnNoDiscoveredTests.set(true)
        reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/$taskName"))
        reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/$taskName"))
        binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/$taskName/binary"))
        outputs.upToDateWhen { false }
        outputs.doNotCacheIf("Visual gate must execute") { true }
        inputs.dir(rootProject.layout.projectDirectory.dir("design-assets"))
        doFirst {
            check(!recordRequested.get().equals("true", true) && !System.getProperty("roborazzi.test.record", "false").equals("true", true)) {
                "$taskName forbids roborazzi.test.record=true"
            }
            systemProperty("roborazzi.test.record", "false")
            systemProperty("roborazzi.test.compare", "false")
            systemProperty("roborazzi.test.verify", "true")
            systemProperty("roborazzi.compare.output.dir", layout.buildDirectory.dir("reports/s0/components/images").get().asFile.absolutePath)
            systemProperty("roborazzi.result.dir", layout.buildDirectory.dir("reports/s0/components/results").get().asFile.absolutePath)
        }
    }
    val validation = tasks.register("validate${taskName.replaceFirstChar(Char::uppercase)}Results") {
        doLast {
            val test = gate.get()
            check(!test.state.skipped && test.state.failure == null) { "$taskName failed or skipped: ${test.state.failure ?: test.state.skipMessage}" }
            val xml = test.reports.junitXml.outputLocation.get().asFile.listFiles { f -> f.name.startsWith("TEST-") && f.extension == "xml" }.orEmpty()
            check(xml.size == 1) { "$taskName requires exactly one suite" }
            val factory = DocumentBuilderFactory.newInstance().apply {
                setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
                setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
                setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
                setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
            }
            val suiteXml = factory.newDocumentBuilder().parse(xml.single()).documentElement
            check(suiteXml.getAttribute("name") == "com.ignacioli.finecoach.$suite")
            check(suiteXml.getAttribute("tests").toInt() == expectedTests && suiteXml.getElementsByTagName("testcase").length == expectedTests)
            for (attr in listOf("failures", "errors", "skipped")) check(suiteXml.getAttribute(attr).toInt() == 0)
            check(listOf("failure", "error", "skipped").all { suiteXml.getElementsByTagName(it).length == 0 })
            logger.lifecycle("$taskName: $expectedTests tests, 0 failures/errors/skips")
        }
    }
    gate.configure { finalizedBy(validation) }
    return gate
}
val screenshotGate = registerVisualGate("s0G5", "ComponentScreenshotTests", 1)
// P7 is capture-only: captureToImage writes sheets without invoking a comparator.
registerVisualGate("p7SideBySide", "P7SideBySideTests", 15).configure {
    outputs.dir(layout.buildDirectory.dir("outputs/p7"))
}
val visualBaselineBefore = mutableMapOf<String, String>()
fun visualBaselineManifest(): Map<String, String> = rootProject.fileTree("screenshot-baselines").files.associate {
    it.relativeTo(rootProject.projectDir).path to MessageDigest.getInstance("SHA-256").digest(it.readBytes()).joinToString("") { byte -> "%02x".format(byte) }
}
val baselineUnchanged = tasks.register("verifyS0G5BaselineUnchanged") {
    doLast { check(visualBaselineBefore == visualBaselineManifest()) { "BASELINE_CHANGED during s0G5" } }
}
screenshotGate.configure {
    inputs.files(rootProject.fileTree("screenshot-baselines/components"))
    doFirst { visualBaselineBefore.putAll(visualBaselineManifest()) }
    finalizedBy(baselineUnchanged)
}
registerVisualGate("s0Conformance", "TrainingConformanceTests", 1)
// Diagnostic reports only: page deviations do not join the training conformance gate.
registerVisualGate("p1ExerciseConformance", "ExerciseConformanceTests", 2)
registerVisualGate("p4ExerciseLibraryConformance", "ExerciseConformanceTests", 1).configure {
    filter { setIncludePatterns("com.ignacioli.finecoach.ExerciseConformanceTests.exerciseLibraryConformance") }
}

registerVisualGate("p4AddExerciseConformance", "AddExerciseConformanceTests", 1)
registerVisualGate("p4TodayConformance", "TodayConformanceTests", 1)
registerVisualGate("p4SessionDetailConformance", "SessionDetailConformanceTests", 1)

val entryLayoutClasses = listOf("com.ignacioli.finecoach.EntryLayoutHarnessTests")
val entryLayoutGate = tasks.register<Test>("s0G4") {
    group = "verification"
    description = "Reusable entry and layout assertion fixtures"
    val debugTest = tasks.named<Test>("testDebugUnitTest").get()
    testClassesDirs = debugTest.testClassesDirs
    classpath = debugTest.classpath
    javaLauncher.set(debugTest.javaLauncher)
    setJvmArgs(debugTest.jvmArgs)
    jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
    systemProperties(debugTest.systemProperties)
    workingDir = debugTest.workingDir
    filter {
        setIncludePatterns(*entryLayoutClasses.toTypedArray())
        isFailOnNoMatchingTests = true
    }
    failOnNoDiscoveredTests.set(true)
    reports.junitXml.required.set(true)
    reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/s0G4"))
    reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/s0G4"))
    binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/s0G4/binary"))
    outputs.upToDateWhen { false }
    outputs.doNotCacheIf("G4 evidence must execute on this host") { true }
}
val validateEntryLayoutGate = tasks.register("validateS0G4Results") {
    doLast {
        val gate = entryLayoutGate.get()
        check(!gate.state.skipped && gate.state.failure == null) {
            "s0G4 did not successfully execute: ${gate.state.skipMessage ?: gate.state.failure}"
        }
        val xmlFiles = gate.reports.junitXml.outputLocation.get().asFile
            .listFiles { file -> file.name.startsWith("TEST-") && file.extension == "xml" }.orEmpty()
        check(xmlFiles.isNotEmpty()) { "s0G4 has no JUnit XML" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
            setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val counts = mutableMapOf<String, Int>()
        for (xml in xmlFiles) {
            val suite = factory.newDocumentBuilder().parse(xml).documentElement
            val name = suite.getAttribute("name")
            check(name in entryLayoutClasses) { "Unexpected G4 suite: $name" }
            val cases = suite.getElementsByTagName("testcase")
            val count = suite.getAttribute("tests").toInt()
            check(count > 0 && count == cases.length) { "Empty/inconsistent G4 suite: $name" }
            for (attribute in listOf("failures", "errors", "skipped")) {
                check(suite.getAttribute(attribute).toInt() == 0) { "$name has $attribute" }
            }
            for (index in 0 until cases.length) {
                val case = cases.item(index) as Element
                check(listOf("skipped", "failure", "error").all {
                    case.getElementsByTagName(it).length == 0
                }) { "Unsuccessful G4 testcase: $name.${case.getAttribute("name")}" }
            }
            check(counts.put(name, count) == null) { "Duplicate G4 suite: $name" }
        }
        check(counts.keys == entryLayoutClasses.toSet()) { "Missing G4 suites: ${entryLayoutClasses - counts.keys}" }
        logger.lifecycle("s0G4: ${counts.values.sum()} tests, 0 failures/errors/skips; $counts")
    }
}
entryLayoutGate.configure { finalizedBy(validateEntryLayoutGate) }

val designScanClasses = listOf("com.ignacioli.finecoach.DesignValueScanTests")
val designScanGate = tasks.register<Test>("s0G3") {
    group = "verification"
    description = "Design value source scan and positive/negative fixtures"
    val debugTest = tasks.named<Test>("testDebugUnitTest").get()
    testClassesDirs = debugTest.testClassesDirs
    classpath = debugTest.classpath
    javaLauncher.set(debugTest.javaLauncher)
    setJvmArgs(debugTest.jvmArgs)
    jvmArgumentProviders.addAll(debugTest.jvmArgumentProviders)
    systemProperties(debugTest.systemProperties)
    workingDir = debugTest.workingDir
    inputs.dir(layout.projectDirectory.dir("src/main"))
    inputs.dir(layout.projectDirectory.dir("src/debug"))
    systemProperty("finecoach.sourceRoot", layout.projectDirectory.dir("src").asFile.absolutePath)
    filter {
        setIncludePatterns(*designScanClasses.toTypedArray())
        isFailOnNoMatchingTests = true
    }
    failOnNoDiscoveredTests.set(true)
    reports.junitXml.required.set(true)
    reports.junitXml.outputLocation.set(layout.buildDirectory.dir("test-results/s0G3"))
    reports.html.outputLocation.set(layout.buildDirectory.dir("reports/tests/s0G3"))
    binaryResultsDirectory.set(layout.buildDirectory.dir("test-results/s0G3/binary"))
    outputs.upToDateWhen { false }
    outputs.doNotCacheIf("G3 evidence must execute on this host") { true }
}
val validateDesignScanGate = tasks.register("validateS0G3Results") {
    doLast {
        val gate = designScanGate.get()
        check(!gate.state.skipped && gate.state.failure == null) {
            "s0G3 did not successfully execute: ${gate.state.skipMessage ?: gate.state.failure}"
        }
        val xmlFiles = gate.reports.junitXml.outputLocation.get().asFile
            .listFiles { file -> file.name.startsWith("TEST-") && file.extension == "xml" }.orEmpty()
        check(xmlFiles.isNotEmpty()) { "s0G3 has no JUnit XML" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
            setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val counts = mutableMapOf<String, Int>()
        for (xml in xmlFiles) {
            val suite = factory.newDocumentBuilder().parse(xml).documentElement
            val name = suite.getAttribute("name")
            check(name in designScanClasses) { "Unexpected G3 suite: $name" }
            val cases = suite.getElementsByTagName("testcase")
            val count = suite.getAttribute("tests").toInt()
            check(count > 0 && count == cases.length) { "Empty/inconsistent G3 suite: $name" }
            for (attribute in listOf("failures", "errors", "skipped")) {
                check(suite.getAttribute(attribute).toInt() == 0) { "$name has $attribute" }
            }
            for (index in 0 until cases.length) {
                val case = cases.item(index) as Element
                check(listOf("skipped", "failure", "error").all {
                    case.getElementsByTagName(it).length == 0
                }) { "Unsuccessful G3 testcase: $name.${case.getAttribute("name")}" }
            }
            check(counts.put(name, count) == null) { "Duplicate G3 suite: $name" }
        }
        check(counts.keys == designScanClasses.toSet()) { "Missing G3 suites: ${designScanClasses - counts.keys}" }
        logger.lifecycle("s0G3: ${counts.values.sum()} tests, 0 failures/errors/skips; $counts")
    }
}
designScanGate.configure { finalizedBy(validateDesignScanGate) }

registerVisualGate("p4StudentListConformance", "StudentListConformanceTests", 1)

registerVisualGate("p4StudentDetailConformance", "StudentDetailConformanceTests", 1)
