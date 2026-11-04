import com.android.build.api.artifact.SingleArtifact
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

plugins {
    alias(libs.plugins.android.application)
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
        }
        getByName("test") {
            resources.srcDir("../../shared/test-vectors")
            assets.srcDir("src/test/assets")
        }
    }
}

kotlin { jvmToolchain(21) }

dependencies {
    implementation(libs.kotlin.stdlib)
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
    "s0Room" to "T007/T008: Room skeleton and migration harness",
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
