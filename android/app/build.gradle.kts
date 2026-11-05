import com.google.devtools.ksp.gradle.KspAATask
import org.gradle.api.artifacts.component.ModuleComponentIdentifier
import org.gradle.api.artifacts.result.UnresolvedDependencyResult
import com.android.build.gradle.tasks.MergeResources
import com.android.build.api.artifact.SingleArtifact
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element
import org.gradle.process.CommandLineArgumentProvider

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
    inputs.file(privacyDependencyReport)
    inputs.file(rootProject.layout.projectDirectory.file("dependency-allowlist/resolved.txt"))
    inputs.dir(layout.projectDirectory.dir("src/main"))
    inputs.files(fileTree("src") { include("debug/**/*.kt", "debug/**/*.java", "release/**/*.kt", "release/**/*.java") })
    systemProperty("finecoach.sourceRoot", layout.projectDirectory.dir("src").asFile.absolutePath)
    systemProperty("finecoach.dependencies", privacyDependencyReport.get().asFile.absolutePath)
    systemProperty("finecoach.dependencyAllowlist", rootProject.layout.projectDirectory.file("dependency-allowlist/resolved.txt").asFile.absolutePath)
}

// Reserve the approved interfaces. Each is replaced by its owning task only
// when the full, non-empty test/report contract is implemented (plan section 4).
val pendingGates = mapOf(
    "s0G1" to "T013: token generation and validation",
    "s0G2" to "T016: approved component contracts",
    "s0G3" to "T018: design value scan",
    "s0G4" to "T017: entry and layout harness",
    "s0G5" to "T019/T020: screenshot verify and owner-approved baselines",
    "s0G6" to "T022-T024: shared vectors",
    "s0G8" to "T004-T010: complete privacy and scope checks",
    "s0SeedIsolation" to "T025: release seed isolation",
    "s0InstallSeededDebug" to "T026: explicit device install and seed verification",
    "generateDesignTokens" to "T013: design token generator",
    "checkDesignTokens" to "T013: independent design token comparison",
)
pendingGates.forEach { (gate, owner) ->
    tasks.register(gate) {
        group = "verification"
        description = "未实现 — $owner"
        doLast { throw GradleException("$gate 未实现：$owner；不能报告 PASS。") }
    }
}
