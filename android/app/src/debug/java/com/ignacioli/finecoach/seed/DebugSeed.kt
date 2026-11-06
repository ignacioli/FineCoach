package com.ignacioli.finecoach.seed

import android.content.Context
import androidx.room.Room
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.StoreMetadata
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID

// fictional-data: deterministic infrastructure invented for S0; no real people.
internal object DebugSeed {
    const val VERSION = 1
    const val ROWS = 5
    const val DATABASE_NAME = "finecoach-debug-seed.db"
    const val PREFIX = "debug_seed."
    const val VERSION_KEY = "${PREFIX}version"
    const val ROWS_KEY = "${PREFIX}rows"
    const val DECLARATION = "fictional-data"
    val datasetID: UUID = UUID.fromString("00000000-0000-4000-8000-000000000025")
    val clock: Clock = Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC)
    val contributors: List<SeedContributor> = listOf(MetadataSeedContributor)

    // Deliberately separate from FineCoachDatabaseFactory's user database.
    fun open(context: Context): FineCoachDatabase {
        val application = context.applicationContext
        require(!context.isDeviceProtectedStorage && !application.isDeviceProtectedStorage)
        return Room.databaseBuilder(application, FineCoachDatabase::class.java, DATABASE_NAME).build()
    }

    fun insertMetadata(database: FineCoachDatabase, key: String, value: String) {
        require(key.startsWith(PREFIX) && key !in setOf(VERSION_KEY, ROWS_KEY))
        val dao = database.storeMetadataDao()
        val existing = dao.find(key)
        if (existing == null) dao.insert(StoreMetadata(key, value))
        else check(existing.value == value) { "Seed metadata conflict" }
    }
}

// Every contributor runs inside the loader's transaction, off the main thread.
// S1 adds idempotent writes and a verified count of its owned fictional rows.
internal interface SeedContributor {
    fun install(database: FineCoachDatabase)
    fun verifiedRows(database: FineCoachDatabase): Int
}

private object MetadataSeedContributor : SeedContributor {
    private val values get() = mapOf(
        "${DebugSeed.PREFIX}declaration" to DebugSeed.DECLARATION,
        "${DebugSeed.PREFIX}dataset_id" to DebugSeed.datasetID.toString(),
        "${DebugSeed.PREFIX}clock" to DebugSeed.clock.instant().toString(),
    )

    override fun install(database: FineCoachDatabase) {
        values.forEach { (key, value) -> DebugSeed.insertMetadata(database, key, value) }
    }

    override fun verifiedRows(database: FineCoachDatabase): Int {
        values.forEach { (key, value) -> check(database.storeMetadataDao().find(key)?.value == value) }
        return values.size
    }
}

internal data class SeedResult(val version: Int, val rows: Int) {
    init { require(version > 0 && rows >= 2) }
    val logLine: String get() = "SEED version=$version rows=$rows status=ok"
}

internal class DebugSeedLoader(
    private val version: Int = DebugSeed.VERSION,
    private val contributors: List<SeedContributor> = DebugSeed.contributors,
) {
    init { require(version > 0 && contributors.isNotEmpty()) }

    fun load(database: FineCoachDatabase): SeedResult {
        lateinit var result: SeedResult
        database.runInTransaction(Runnable {
            val dao = database.storeMetadataDao()
            val storedVersion = dao.find(DebugSeed.VERSION_KEY)?.value?.toInt()
            check(storedVersion == null || storedVersion in 1..version) { "Seed downgrade rejected" }
            check((storedVersion == null) == (dao.find(DebugSeed.ROWS_KEY) == null)) { "Incomplete seed metadata" }
            if (storedVersion != version) contributors.forEach { it.install(database) }
            val counts = contributors.map { it.verifiedRows(database).also { count -> check(count >= 0) } }
            val rows = counts.fold(2, Math::addExact)
            if (storedVersion == version) {
                check(dao.find(DebugSeed.ROWS_KEY)?.value == rows.toString()) { "Seed row count mismatch" }
            } else {
                for ((key, value) in listOf(DebugSeed.VERSION_KEY to version.toString(), DebugSeed.ROWS_KEY to rows.toString())) {
                    database.openHelper.writableDatabase.execSQL(
                        "INSERT OR REPLACE INTO store_metadata (`key`, value) VALUES (?, ?)", arrayOf(key, value),
                    )
                }
            }
            result = SeedResult(version, rows)
        })
        // Return only after commit; verify the same version/count on a fresh connection at the entry point.
        return result
    }
}
