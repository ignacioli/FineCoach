package com.ignacioli.finecoach

import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

internal object FictionalDataPolicy {
    const val DECLARATION = "fictional-data"
    val sentinels = setOf("S0SENTINEL-recents", "S0SENTINEL-recents-dialog")
    // These pre-existing policy fixtures contain API fragments only, not people.
    // Pin their provenance to content; a changed/new fixture needs a declaration.
    private val policyFixtures = mapOf(
        "privacy/logging.txt" to "3aafbb371773444cfa76e34ad44ccf5f47ee22d1f43f1de205091d8cedde6dc2",
        "privacy/network.txt" to "872ac7ee5d9bd96e4d281103dd0c10d81767684943d729f2ceb33272fdd43e2d",
        "privacy/secure-window.txt" to "82c881c8cd58ed484758a103f748e7ea8b9632bf87801d5725969cb1d044fad0",
        "privacy/telemetry.txt" to "b43241d8739de122821e45caff9cf77e344c31a0e8baad933a3d39e42b2cb96e",
        "privacy/valid-extraction.xml" to "f418293f594ab02038d77a2999b87eccdc9625e9dc4c7026dd4ff1535490810a",
    )
    private val email = Regex("[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\\.[A-Za-z]{2,})")
    fun validateName(path: String) {
        require(!Regex("(?i)(S0SENTINEL|FICTIONAL_SENSITIVE|@|(?:^|[/_-])(?:student|coach|patient)[_-]?[0-9]{6,}|1[3-9][0-9]{9})")
            .containsMatchIn(path)) { "Sensitive/sentinel filename: $path" }
    }
    fun validateContent(text: String) {
        email.findAll(text).forEach { require(it.groupValues[1] in setOf("example.com", "example.org", "example.net", "example.invalid")) }
        require(!Regex("(?<![0-9a-fA-F])1[3-9][0-9]{9}(?![0-9a-fA-F])").containsMatchIn(text)) { "Unapproved phone-like data" }
    }
    fun validateFixture(path: String, bytes: ByteArray, declaration: String? = null) {
        validateName(path)
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        // A third-party license is not fictional data. Exempt only the exact
        // source/APK paths, and require byte provenance from the iOS original.
        if (path in setOf("main/assets/fonts/OFL.txt", "assets/fonts/OFL.txt")) {
            val app = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))
            val original = File(app, "../../ios/FineCoachApp/Resources/Fonts/OFL.txt").canonicalFile
            require(original.isFile) { "Missing original font license: $original" }
            val originalHash = MessageDigest.getInstance("SHA-256").digest(original.readBytes())
                .joinToString("") { "%02x".format(it) }
            require(hash == originalHash) { "Font license differs from iOS original: $path" }
            return
        }
        if (policyFixtures[path] == hash) return
        val text = bytes.toString(Charsets.UTF_8)
        require(text.contains(DECLARATION) || declaration?.contains(DECLARATION) == true) { "Fixture lacks fictional declaration: $path" }
        validateContent(text)
    }
    fun validateVector(path: String, text: String) {
        validateName(path)
        val vector = JSONObject(text)
        val tags = vector.getJSONObject("meta").getJSONArray("tags")
        require((0 until tags.length()).any { tags.getString(it) == DECLARATION }) { "Missing vector fictional-data tag: $path" }
        validateContent(vector.toString())
    }
    fun validateSample(text: String) {
        require(text.contains(DECLARATION))
        val found = Regex("S0SENTINEL[-A-Za-z0-9_]*").findAll(text).map { it.value }.toSet()
        require(found == sentinels) { "Sample sentinel drift" }
        validateContent(text)
    }
    fun fixtureFiles(root: File): List<File> = root.walkTopDown().filter { file ->
        file.isFile && file.name != "fictional-data.txt" && (
            Regex("(?i)(seed|fixture|sample)").containsMatchIn(file.name) ||
                file.relativeTo(root).invariantSeparatorsPath.split('/').any {
                    it.lowercase() in setOf("assets", "resources", "fixtures", "fixture", "seeds", "seed", "samples")
                })
    }.toList()
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class FictionalDataPolicyTests {
    private val app get() = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))

    @Test fun currentAndFutureFixturesAndSeedsAreDiscoveredAndDeclared() {
        val src = File(app, "src")
        val fixtures = FictionalDataPolicy.fixtureFiles(src)
        assertTrue(fixtures.isNotEmpty())
        fixtures.forEach { file ->
            val path = file.relativeTo(src).invariantSeparatorsPath
            val policyPath = path.substringAfter("/resources/", path)
            val sidecar = File(file.parentFile, "fictional-data.txt").takeIf { it.isFile }?.readText()
            FictionalDataPolicy.validateFixture(policyPath, file.readBytes(), sidecar)
        }
        // A future inline seed implementation must declare its fictional source,
        // even when no separate seed directory/assets exist yet.
        src.walkTopDown().filter { it.isFile && it.extension in setOf("kt", "java") }.forEach { file ->
            val source = file.readText()
            if (Regex("(?i)(seed|fixture|sample)").containsMatchIn(file.name) ||
                Regex("\\b(?:class|object|fun)\\s+\\w*[Ss]eed\\w*").containsMatchIn(source)) {
                require(source.contains(FictionalDataPolicy.DECLARATION)) { "Undeclared inline data source: ${file.name}" }
            }
            FictionalDataPolicy.validateName(file.relativeTo(src).invariantSeparatorsPath)
            FictionalDataPolicy.validateContent(source)
        }
    }
    @Test fun allSharedVectorFilesAreFictionalIncludingFutureSlices() {
        val shared = File(app, "../../shared").canonicalFile
        assertTrue(shared.isDirectory)
        val vectors = File(shared, "test-vectors").walkTopDown().filter { it.isFile && it.extension == "json" }.toList()
        assertTrue(vectors.isNotEmpty())
        vectors.forEach { FictionalDataPolicy.validateVector(it.relativeTo(shared).invariantSeparatorsPath, it.readText()) }
        shared.walkTopDown().filter { it.isFile && it !in vectors && it.name != "fictional-data.txt" }.forEach {
            FictionalDataPolicy.validateFixture(it.relativeTo(shared).invariantSeparatorsPath, it.readBytes(),
                File(it.parentFile, "fictional-data.txt").takeIf(File::isFile)?.readText())
        }
    }
    @Test fun debugSampleUsesOnlyDeclaredFixedSentinels() {
        val sample = File(app, "src/debug/java/com/ignacioli/finecoach/S0DebugApplication.kt")
        assertTrue(sample.isFile)
        FictionalDataPolicy.validateSample(sample.readText())
    }
    @Test fun packagedDebugDataAndSentinelsMatchDeclaredSources() {
        val apks = File(MergedPrivacyInputs.property("debugApk")).walkTopDown().filter { it.isFile && it.extension == "apk" }.toList()
        assertEquals(1, apks.size)
        ZipFile(apks.single()).use { zip ->
            val entries = zip.entries().asSequence().toList()
            val dex = entries.filter { Regex("classes[0-9]*\\.dex").matches(it.name) }
            assertTrue(dex.isNotEmpty())
            val strings = dex.joinToString("") { zip.getInputStream(it).use { stream -> String(stream.readBytes(), Charsets.ISO_8859_1) } }
            FictionalDataPolicy.sentinels.forEach { assertTrue("Missing packaged sentinel: $it", strings.contains(it)) }
            entries.filter { !it.isDirectory && (it.name.startsWith("assets/") || it.name.startsWith("res/raw/")) }.forEach { entry ->
                val bytes = zip.getInputStream(entry).use { it.readBytes() }
                val sidecar = zip.getEntry(entry.name.substringBeforeLast('/') + "/fictional-data.txt")
                    ?.let { zip.getInputStream(it).use { stream -> stream.readBytes().toString(Charsets.UTF_8) } }
                FictionalDataPolicy.validateFixture(entry.name, bytes, sidecar)
            }
        }
    }
    @Test fun syntheticSchemasContainDefinitionsAndNoSeedRows() {
        val schemas = File(app, "schemas-synthetic").walkTopDown().filter { it.isFile && it.extension == "json" }.toList()
        assertEquals(2, schemas.size)
        schemas.forEach { file ->
            FictionalDataPolicy.validateName(file.name)
            val database = JSONObject(file.readText()).getJSONObject("database")
            val sql = database.getJSONArray("setupQueries")
            for (i in 0 until sql.length()) {
                require(!Regex("(?i)INSERT").containsMatchIn(sql.getString(i)) || sql.getString(i).contains("room_master_table"))
            }
            val entities = database.getJSONArray("entities")
            for (i in 0 until entities.length()) assertEquals("synthetic_probe", entities.getJSONObject(i).getString("tableName"))
            FictionalDataPolicy.validateContent(file.readText())
        }
    }
    @Test fun rejectsUndeclaredFixtureAndChangedLegacyFixture() {
        listOf("fictional.json", "privacy/network.txt").forEach {
            assertThrows(IllegalArgumentException::class.java) { FictionalDataPolicy.validateFixture(it, "{}".toByteArray()) }
        }
    }
    @Test fun exactFontLicensePathsMatchIosOriginalWithoutFictionalDeclaration() {
        val license = File(app, "src/main/assets/fonts/OFL.txt").readBytes()
        listOf("main/assets/fonts/OFL.txt", "assets/fonts/OFL.txt").forEach {
            FictionalDataPolicy.validateFixture(it, license)
        }
    }
    @Test fun rejectsUndeclaredNeighborOfFontLicense() {
        listOf("main/assets/fonts/OTHER.txt", "assets/fonts/OTHER.txt", "fonts/OTHER.txt").forEach {
            assertThrows(IllegalArgumentException::class.java) {
                FictionalDataPolicy.validateFixture(it, "Undeclared neighboring fixture".toByteArray())
            }
        }
        val license = File(app, "src/main/assets/fonts/OFL.txt").readBytes()
        listOf("fonts/OFL.txt", "main/assets/other/OFL.txt", "assets/other/OFL.txt").forEach {
            assertThrows(IllegalArgumentException::class.java) { FictionalDataPolicy.validateFixture(it, license) }
        }
    }
    @Test fun rejectsChangedFontLicenseEvenWithFictionalDeclaration() {
        val changed = File(app, "src/main/assets/fonts/OFL.txt").readBytes() +
            "\nfictional-data deliberately modified license fixture\n".toByteArray()
        listOf("main/assets/fonts/OFL.txt", "assets/fonts/OFL.txt").forEach {
            assertThrows(IllegalArgumentException::class.java) {
                FictionalDataPolicy.validateFixture(it, changed, FictionalDataPolicy.DECLARATION)
            }
        }
    }
    @Test fun rejectsVectorWithoutFictionalTag() {
        assertThrows(IllegalArgumentException::class.java) { FictionalDataPolicy.validateVector("fictional.json", """{"meta":{"tags":[]}}""") }
    }
    @Test fun rejectsSensitiveFilenameAndUnapprovedContactShape() {
        // Reserved example domains and a synthetic phone pattern; never real data.
        val syntheticPhone = "138" + "0000" + "0000"
        listOf("S0SENTINEL-recents.png", "student_$syntheticPhone.json", "FICTIONAL_SENSITIVE_LOG_SENTINEL.txt").forEach {
            assertThrows(IllegalArgumentException::class.java) { FictionalDataPolicy.validateName(it) }
        }
        assertThrows(IllegalArgumentException::class.java) { FictionalDataPolicy.validateContent("fictional@" + "unapproved.invalid") }
        assertThrows(IllegalArgumentException::class.java) { FictionalDataPolicy.validateContent("fictional phone: $syntheticPhone") }
    }
    @Test fun rejectsSentinelDriftAndMissingSampleDeclaration() {
        assertThrows(IllegalArgumentException::class.java) { FictionalDataPolicy.validateSample("fictional-data S0SENTINEL-unapproved") }
        assertThrows(IllegalArgumentException::class.java) { FictionalDataPolicy.validateSample("S0SENTINEL-recents S0SENTINEL-recents-dialog") }
    }
    @Test fun discoversNewSeedLocationsWithoutEditingAnAllowlist() {
        val root = java.nio.file.Files.createTempDirectory("fictional-policy").toFile()
        try {
            val files = listOf("debug/assets/new-seed.json", "test/resources/new-fixture.json", "debug/seeds/new.json")
                .map { File(root, it).apply { requireNotNull(parentFile).mkdirs(); writeText("fictional-data") } }
            assertEquals(files.toSet(), FictionalDataPolicy.fixtureFiles(root).toSet())
            files.forEach { FictionalDataPolicy.validateFixture(it.name, it.readBytes()) }
        } finally { root.deleteRecursively() }
    }
}
