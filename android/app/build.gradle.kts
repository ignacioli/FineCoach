import com.android.build.api.artifact.SingleArtifact

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
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
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.test.junit)
    testImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.junit)
}

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
    "s0EnvironmentSmoke" to "T032/T003: crypto parity and environment screenshot smoke",
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
