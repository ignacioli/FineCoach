// fictional-data: isolated synthetic database and debug-seed fixtures only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.seed.DebugSeed
import com.ignacioli.finecoach.seed.DebugSeedLoader
import com.ignacioli.finecoach.seed.SeedContributor
import com.ignacioli.finecoach.seed.SeedResult
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.StoreMetadata
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import com.ignacioli.finecoach.seed.S1DebugSeed
import com.ignacioli.finecoach.seed.S1SeedFixture
import com.ignacioli.finecoach.seed.S3SeedFixture
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.progress.*
import com.ignacioli.finecoach.core.domain.insight.*
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.features.trends.*
import com.ignacioli.finecoach.storage.repository.BodyDataRepository
import kotlinx.coroutines.runBlocking

// fictional-data: isolated temporary databases and invented metadata only.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class DebugSeedTests {
    private lateinit var context: Context
    private val worker = Executors.newSingleThreadExecutor()
    private val databases = mutableListOf<FineCoachDatabase>()

    @Before fun prepare() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(DebugSeed.DATABASE_NAME)
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
    }

    @After fun cleanUp() {
        try { offMain { databases.forEach { it.close() } } }
        finally {
            worker.shutdownNow()
            context.deleteDatabase(DebugSeed.DATABASE_NAME)
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    private fun <T> offMain(action: () -> T): T = worker.submit(Callable { action() }).get(30, TimeUnit.SECONDS)
    private fun open() = DebugSeed.open(context).also { databases += it }
    private fun snapshot(database: FineCoachDatabase): Map<String, String> = buildMap {
        database.openHelper.readableDatabase.query("SELECT `key`, value FROM store_metadata ORDER BY `key`").use {
            while (it.moveToNext()) put(it.getString(0), it.getString(1))
        }
    }

    @Test fun fixedIdentityAndClock() {
        assertEquals(UUID.fromString("00000000-0000-4000-8000-000000000025"), DebugSeed.datasetID)
        assertEquals(Instant.parse("2026-01-01T00:00:00Z"), DebugSeed.clock.instant())
        assertEquals(ZoneOffset.UTC, DebugSeed.clock.zone)
        assertNotEquals(FineCoachDatabaseFactory.DATABASE_NAME, DebugSeed.DATABASE_NAME)
    }

    @Test fun loadsOnlyFiveMetadataRowsInSchemaTwo() = offMain {
        val database = open()
        assertEquals(SeedResult(1, 5), DebugSeedLoader().load(database))
        assertEquals(4, database.openHelper.readableDatabase.version)
        assertEquals(5, snapshot(database).size)
        assertEquals("1", database.storeMetadataDao().find(DebugSeed.VERSION_KEY)?.value)
        assertEquals("5", database.storeMetadataDao().find(DebugSeed.ROWS_KEY)?.value)
    }

    @Test fun secondLoadAndReopenDoNotInsertOrChangeRows() = offMain {
        val database = open()
        val first = DebugSeedLoader().load(database)
        val rows = snapshot(database)
        assertEquals(first, DebugSeedLoader().load(database))
        assertEquals(rows, snapshot(database))
        database.close()
        val reopened = open()
        assertEquals(first, DebugSeedLoader().load(reopened))
        assertEquals(rows, snapshot(reopened))
    }

    private fun extension(fail: Boolean = false) = object : SeedContributor {
        override fun install(database: FineCoachDatabase) {
            DebugSeed.insertMetadata(database, "${DebugSeed.PREFIX}fictional_extension", "fictional-data:v2")
            check(!fail) { "Fictional upgrade failure" }
        }
        override fun verifiedRows(database: FineCoachDatabase): Int {
            check(database.storeMetadataDao().find("${DebugSeed.PREFIX}fictional_extension")?.value == "fictional-data:v2")
            return 1
        }
    }

    @Test fun versionUpgradeAddsOnceAndPreservesUnrelatedMetadata() = offMain {
        val database = open()
        DebugSeedLoader().load(database)
        database.storeMetadataDao().insert(StoreMetadata("fictional_unrelated", "fictional-data:retained"))
        val upgrade = DebugSeedLoader(2, DebugSeed.contributors + extension())
        assertEquals(SeedResult(2, 6), upgrade.load(database))
        val rows = snapshot(database)
        assertEquals(SeedResult(2, 6), upgrade.load(database))
        assertEquals(rows, snapshot(database))
        assertEquals(7, rows.size)
        assertEquals("fictional-data:retained", rows["fictional_unrelated"])
    }

    @Test fun failedUpgradeRollsBackRowsAndVersion() = offMain {
        val database = open()
        DebugSeedLoader().load(database)
        val before = snapshot(database)
        assertThrows(IllegalStateException::class.java) {
            DebugSeedLoader(2, DebugSeed.contributors + extension(fail = true)).load(database)
        }
        assertEquals(before, snapshot(database))
    }

    @Test fun downgradeFailsWithoutMutation() = offMain {
        val database = open()
        DebugSeedLoader(2).load(database)
        val before = snapshot(database)
        assertThrows(IllegalStateException::class.java) { DebugSeedLoader().load(database) }
        assertEquals(before, snapshot(database))
    }

    @Test fun sameVersionCountMismatchFailsWithoutRepair() = offMain {
        val database = open()
        DebugSeedLoader().load(database)
        database.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value = '99' WHERE `key` = ?", arrayOf(DebugSeed.ROWS_KEY))
        val before = snapshot(database)
        assertThrows(IllegalStateException::class.java) { DebugSeedLoader().load(database) }
        assertEquals(before, snapshot(database))
    }

    @Test fun conflictingFixtureDoesNotOverwriteExistingRows() = offMain {
        val database = open()
        database.storeMetadataDao().insert(StoreMetadata("${DebugSeed.PREFIX}declaration", "fictional-data:conflict"))
        val before = snapshot(database)
        assertThrows(IllegalStateException::class.java) { DebugSeedLoader().load(database) }
        assertEquals(before, snapshot(database))
    }

    @Test fun declarationAndValuesFollowFictionalDataPolicy() = offMain {
        val database = open()
        DebugSeedLoader().load(database)
        assertEquals(FictionalDataPolicy.DECLARATION, database.storeMetadataDao().find("${DebugSeed.PREFIX}declaration")?.value)
        snapshot(database).forEach { (key, value) ->
            FictionalDataPolicy.validateName(key)
            FictionalDataPolicy.validateContent(value)
        }
    }

    @Test fun logContainsOnlyNumericVersionCountAndFixedStatus() {
        assertEquals("SEED version=1 rows=5 status=ok", SeedResult(1, 5).logLine)
        assertThrows(IllegalArgumentException::class.java) { SeedResult(0, 5) }
        assertThrows(IllegalArgumentException::class.java) { SeedResult(1, -1) }
    }

    private fun s3(action: suspend (com.ignacioli.finecoach.S1AppGraph, S1SeedFixture) -> Unit) = offMain {
        runBlocking {
            val first = S1DebugSeed.load(context, "multi")
            check(first == S1DebugSeed.load(context, "multi")) { "Seed reinstall changed inventory" }
            val db = FineCoachDatabaseFactory.create(context)
            try { action(S1DebugSeed.graph(db, context), S1SeedFixture.read(context)) } finally { db.close() }
        }
    }
    private fun <T> value(result: ApplicationResult<T>): T = when (result) {
        is ApplicationResult.Success -> result.value
        is ApplicationResult.Failure -> error("Seed domain read failed")
    }

    @Test fun assetMetadataMatchesInstalledVersionDatasetAndActualInventoryForEveryScenario() = offMain {
        runBlocking {
            val asset = org.json.JSONObject(context.assets.open(S1SeedFixture.PATH).bufferedReader().use { it.readText() })
            val fixture = S1SeedFixture.read(context)
            val app = java.io.File(System.getProperty("finecoach.storageProjectDirectory"))
            val source = java.io.File(app, "src/debug/assets/seed/s1-seed.json").readBytes()
            val merged = java.io.File(app, "build/intermediates/assets/debug/mergeDebugAssets/seed/s1-seed.json").readBytes()
            val runtime = context.assets.open(S1SeedFixture.PATH).use { it.readBytes() }
            check(source.contentEquals(runtime) && source.contentEquals(merged)) { "Seed asset bytes mismatch" }
            check(fixture.version == asset.getInt("seedVersion") && fixture.dataset == asset.getString("dataset")) { "Seed metadata source mismatch" }
            for (scenario in listOf("empty", "single", "multi")) {
                context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
                val installed = S1DebugSeed.load(context, scenario)
                val db = FineCoachDatabaseFactory.create(context)
                try {
                    val expectedRows = asset.getJSONObject("expectedRows").getInt(scenario)
                    val expectedTables = com.ignacioli.finecoach.seed.S1SeedInventory.expected(context, fixture, scenario)
                    val actualTables = S1DebugSeed.businessRowCounts(db)
                    check(expectedTables.keys == actualTables.keys) { "Seed inventory table mismatch" }
                    for ((table, expected) in expectedTables) {
                        check(actualTables[table] == expected) { "$table $expected ${actualTables[table]}" }
                    }
                    check(expectedRows == expectedTables.values.sum() + com.ignacioli.finecoach.seed.S1SeedInventory.METADATA_ROWS) { "Seed inventory derivation mismatch" }
                    val metadata = db.storeMetadataDao()
                    val ownedMetadata = db.openHelper.readableDatabase.query(
                        "SELECT COUNT(*) FROM store_metadata WHERE substr(`key`,1,?)=?",
                        arrayOf<Any>(S1DebugSeed.PREFIX.length, S1DebugSeed.PREFIX),
                    ).use { it.moveToFirst(); it.getInt(0) }
                    check(installed.version == asset.getInt("seedVersion") && installed.rows == expectedRows) { "Installed seed metadata mismatch" }
                    check(metadata.find(S1DebugSeed.VERSION_KEY)?.value == asset.getInt("seedVersion").toString()) { "Persisted seed version mismatch" }
                    check(metadata.find(S1DebugSeed.DATASET_KEY)?.value == asset.getString("dataset")) { "Persisted seed dataset mismatch" }
                    check(metadata.find(S1DebugSeed.ROWS_KEY)?.value == expectedRows.toString()) { "Persisted seed inventory mismatch" }
                    check(S1DebugSeed.businessRows(db) + ownedMetadata == expectedRows) { "Actual seed inventory mismatch" }
                    check(S1DebugSeed.storedResult(db, fixture) == installed) { "Reopened seed metadata mismatch" }
                } finally { db.close() }
            }
        }
    }

    @Test fun multiHistoryComputesRecordsProgressAndBothMilestones() = s3 { g, f ->
        val sid = S3SeedFixture.studentID(f, S3SeedFixture.Role.gains)
        val progress = ProgressUseCases(g.historyRepository, g.sessions)
        val snapshot = value(progress.load(sid))
        val latest = snapshot.completed.last()
        val gains = SessionGains.evaluate(latest, snapshot.completed, g.zone)
        check(gains.records.isNotEmpty()) { "Record gain missing" }
        check(gains.progress.isNotEmpty()) { "Progress gain missing" }
        check(gains.milestoneSessionNumber == 10) { "Session milestone missing" }
        check(gains.attendanceStreakWeeks == 4) { "Attendance milestone missing" }
        check(snapshot.completed.size == 10) { "Dedicated gains history mismatch" }
    }

    @Test fun multiComputesAllInsightGroupsFromStoredHistoryAndLedger() = s3 { g, f ->
        val cases = InsightUseCases(g.studentRepository, ProgressUseCases(g.historyRepository, g.sessions),
            g.appointmentRepository, g.credits, { ApplicationResult.Success(emptySet()) }, { _, _ -> emptySet() })
        // Validate the deterministic seed clock and the walkthrough date without substituting UI text.
        for (now in listOf(f.now, java.time.Instant.parse("2026-11-25T12:00:00Z"))) {
            val insights = value(cases.load(now, g.zone))
            check(insights.any { it.studentID == S3SeedFixture.studentID(f, S3SeedFixture.Role.coursePackage) && it.kind == Insight.Kind.packageLow }) { "Dedicated package insight missing" }
            val inactiveID = S3SeedFixture.studentID(f, S3SeedFixture.Role.inactive)
            check(insights.any { it.studentID == inactiveID && it.kind == Insight.Kind.inactive && !it.hasNeverTrained }) { "Dedicated inactive insight missing" }
            check(value(g.appointments.all()).none { it.studentID == inactiveID }) { "Inactive role has an appointment" }
            val stagnantID = S3SeedFixture.studentID(f, S3SeedFixture.Role.stagnant)
            check(insights.any { it.studentID == stagnantID && it.kind == Insight.Kind.stagnant }) { "Dedicated stagnation insight missing" }
            check(value(ProgressUseCases(g.historyRepository, g.sessions).load(stagnantID)).completed.size >= 4) { "Stagnation history missing" }
        }
    }

    @Test fun multiComputesListedEstimateAndUnlistedExerciseTrends() = s3 { g, f ->
        val sessions = value(ProgressUseCases(g.historyRepository, g.sessions).load(S3SeedFixture.studentID(f, S3SeedFixture.Role.trends))).completed
        val options = TrendsPresentation.options(sessions, emptySet())
        val listed = options.first { it.id in EstimatedOneRepMax.exerciseIDs }
        val unlisted = options.first { it.id !in EstimatedOneRepMax.exerciseIDs }
        check(sessions.size >= 20 && sessions.first().completedAtUTC.atZone(g.zone).toLocalDate().plusMonths(3) <= sessions.last().completedAtUTC.atZone(g.zone).toLocalDate()) { "Long trend history missing" }
        val weights = Comparison.exerciseTrend(listed.id, listed.mode, sessions).mapNotNull { it.maxWeight }
        val reps = Comparison.exerciseTrend(unlisted.id, unlisted.mode, sessions).mapNotNull { it.bestReps }
        check(weights.zipWithNext().all { (a, b) -> b > a } && reps.zipWithNext().all { (a, b) -> b > a }) { "Progressive trend missing" }
        check(Comparison.personalRecords(listed.id, listed.mode, sessions).highestWeight?.sessionID == sessions.last().sessionID) { "Personal best missing" }
        check(Comparison.compareSessions(sessions[1], sessions[2]) is Comparison.SessionComparisonResult.Compatible) { "Compatible comparison missing" }
        check(Comparison.compareSessions(sessions[0], sessions[1]) is Comparison.SessionComparisonResult.IncompatibleTrainingFocus) { "Incompatible comparison missing" }
        check(TrendsPresentation.estimatedPoints(listed.id, sessions).size >= 3) { "Estimated trend missing" }
        check(Comparison.exerciseTrend(listed.id, listed.mode, sessions).size >= 3) { "Listed trend missing" }
        check(Comparison.exerciseTrend(unlisted.id, unlisted.mode, sessions).size >= 3) { "Unlisted trend missing" }
        check(TrendMetric.estimatedOneRepMax in TrendMetric.options(listed.id)) { "Estimated segment missing" }
        check(TrendMetric.estimatedOneRepMax !in TrendMetric.options(unlisted.id)) { "Unexpected estimated segment" }
    }

    @Test fun multiBodyHistoryHasDistinctUnitsAndCustomMetricAfterReopen() = s3 { g, f ->
        val cases = BodyDataUseCases(BodyDataRepository(g.database, g.clock), g.clock, g.zone) { UUID.randomUUID() }
        val sid = S3SeedFixture.studentID(f, S3SeedFixture.Role.trends)
        val metrics = value(cases.metrics(sid))
        val histories = metrics.map { it to value(cases.history(sid, it.id)) }.filter { it.second.isNotEmpty() }
        check(histories.size == 4 && histories.any { it.first.id == BuiltInBodyMetric.bodyFatPercent.id }) { "Body metric coverage missing" }
        check(histories.any { it.first.kind == BodyMetricKind.custom && it.second.size >= 8 }) { "Custom history missing" }
        check(histories.flatMap { it.second }.map { it.enteredUnit }.toSet().size >= 2) { "Distinct units missing" }
        check(histories.all { it.second.size >= 8 && it.second.map { m -> m.localCalendarDay }.distinct().size == it.second.size }) { "Body trend missing" }
        check(S3SeedFixture.bodyInputs().map { it.unit }.toSet().containsAll(setOf("kg", "lb", "cm", "in", "%"))) { "Entry unit coverage missing" }
        for (input in S3SeedFixture.bodyInputs()) {
            val metric = input.metric?.id ?: histories.single { it.first.kind == BodyMetricKind.custom }.first.id
            val stored = histories.single { it.first.id == metric }.second.single { it.localCalendarDay == f.at(-input.daysAgo * 86400).atZone(g.zone).toLocalDate() }
            val entered = com.ignacioli.finecoach.core.domain.training.DecimalValue.parse(input.value)
            val expected = when (input.metric?.rule) {
                BodyMetricUnitRuleKind.weight -> BuiltInUnitConversion.canonicalKilograms(entered, input.unit)
                BodyMetricUnitRuleKind.length -> BuiltInUnitConversion.canonicalCentimeters(entered, input.unit)
                else -> entered
            }
            check(stored.value == expected && stored.enteredUnit == (input.metric?.canonicalUnit ?: input.unit)) { "Seed canonical measurement mismatch" }
        }
    }

    @Test fun pageRolesAreUniqueAndBaseBusinessRecordsAreUnchanged() {
        val raw = org.json.JSONObject(context.assets.open(S1SeedFixture.PATH).bufferedReader().use { it.readText() })
        val fixture = S1SeedFixture.read(context)
        fun same(a: Any, b: Any): Boolean = when {
            a is org.json.JSONObject && b is org.json.JSONObject -> {
                val keys = a.keys().asSequence().toSet()
                keys == b.keys().asSequence().toSet() && keys.all { same(a.get(it), b.get(it)) }
            }
            a is org.json.JSONArray && b is org.json.JSONArray -> a.length() == b.length() && (0 until a.length()).all { same(a.get(it), b.get(it)) }
            else -> a == b
        }
        for (group in listOf("students", "packages", "sessions", "ledger", "templates", "appointments")) {
            val base = raw.getJSONArray(group)
            val identity = if (group in setOf("students", "appointments")) "id" else "key"
            for (i in 0 until base.length()) {
                val record = base.getJSONObject(i)
                check(same(record, fixture.records(group).single { it.get(identity) == record.get(identity) })) { "Base fixture changed" }
            }
        }
        val roles = S3SeedFixture.Role.entries.map { role -> fixture.records("students").single { it.getInt("id") == role.number } }
        check(roles.map { it.getString("name") }.distinct().size == roles.size && roles.all { it.getString("name").startsWith("虚构") }) { "Dedicated role identity mismatch" }
    }
}
