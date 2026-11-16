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
    }

    @After fun cleanUp() {
        try { offMain { databases.forEach { it.close() } } }
        finally {
            worker.shutdownNow()
            context.deleteDatabase(DebugSeed.DATABASE_NAME)
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
        assertEquals(2, database.openHelper.readableDatabase.version)
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
}
