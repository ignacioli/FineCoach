package com.ignacioli.finecoach

import android.content.Context
import android.database.sqlite.SQLiteConstraintException
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.StoreMetadata
import com.ignacioli.finecoach.storage.value.StorageValueConverters
import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class RoomSkeletonTests {
    private lateinit var context: Context
    private val worker = Executors.newSingleThreadExecutor()
    private val databases = mutableListOf<FineCoachDatabase>()

    @Before fun prepare() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
    }

    @After fun cleanUp() {
        try {
            offMain { databases.forEach { it.close() } }
        } finally {
            worker.shutdownNow()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    private fun open(): FineCoachDatabase = FineCoachDatabaseFactory.create(context).also { databases += it }
    private fun <T> offMain(action: () -> T): T = worker.submit(Callable { action() }).get(30, TimeUnit.SECONDS)

    @Test fun diskWriteSurvivesReopenAndCreationTimeStaysStable() = offMain {
        val database = open()
        val dao = database.storeMetadataDao()
        val createdAt = requireNotNull(dao.find(FineCoachDatabaseFactory.CREATED_AT_KEY))
        val converter = StorageValueConverters()
        assertEquals(createdAt.value, converter.instantToString(converter.stringToInstant(createdAt.value)))
        val expected = StoreMetadata("fictional_marker", "fixture-v1")
        dao.insert(expected)
        assertTrue(context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).isFile)
        database.close()
        val reopened = open().storeMetadataDao()
        assertEquals(expected, reopened.find(expected.key))
        assertEquals(createdAt, reopened.find(createdAt.key))
    }

    @Test fun thrownTransactionRollsBackOnDisk() = offMain {
        val database = open()
        val dao = database.storeMetadataDao()
        dao.insert(StoreMetadata("retained", "before"))
        assertThrows(IllegalStateException::class.java) {
            database.runInTransaction(Runnable {
                dao.insert(StoreMetadata("rolled_back", "fictional"))
                throw IllegalStateException("fixture rollback")
            })
        }
        database.close()
        val reopened = open().storeMetadataDao()
        assertNull(reopened.find("rolled_back"))
        assertEquals(StoreMetadata("retained", "before"), reopened.find("retained"))
    }

    @Test fun duplicatePrimaryKeyRejectsWithoutReplacingValue() = offMain {
        val dao = open().storeMetadataDao()
        dao.insert(StoreMetadata("fictional_key", "original"))
        assertThrows(SQLiteConstraintException::class.java) {
            dao.insert(StoreMetadata("fictional_key", "replacement"))
        }
        assertEquals("original", dao.find("fictional_key")?.value)
    }

    @Test fun runtimeV2SchemaRetainsMetadataShapeAlongsideS1Tables() = offMain {
        val sqlite = open().openHelper.writableDatabase
        assertEquals(2, sqlite.version)
        val tables = mutableSetOf<String>()
        sqlite.query("SELECT name FROM sqlite_master WHERE type = 'table'").use { cursor ->
            while (cursor.moveToNext()) tables += cursor.getString(0)
        }
        assertTrue(tables.contains("store_metadata"))
        assertTrue(tables.contains("room_master_table"))
        val expected = setOf("store_metadata", "students", "course_packages", "active_package_claims",
            "credit_adjustments", "sessions", "active_session_pointers", "session_training_focus",
            "session_exercises", "training_sets", "training_templates", "template_training_focus",
            "template_exercises", "template_planned_sets", "session_sections", "exercise_catalog",
            "exercise_preferences", "exercise_name_claims")
        assertEquals(expected, tables - setOf("room_master_table", "android_metadata", "sqlite_sequence"))
        val columns = mutableListOf<List<String>>()
        sqlite.query("PRAGMA table_info(`store_metadata`)").use { cursor ->
            while (cursor.moveToNext()) columns += listOf(
                cursor.getString(1), cursor.getString(2), cursor.getInt(3).toString(), cursor.getInt(5).toString(),
            )
        }
        assertEquals(listOf(listOf("key", "TEXT", "1", "1"), listOf("value", "TEXT", "1", "0")), columns)
    }

    @Test fun exportedSchemaIsRealVersionOneOnDisk() {
        val relative = "com.ignacioli.finecoach.storage.FineCoachDatabase/1.json"
        val root = requireNotNull(System.getProperty("finecoach.roomSchemaDirectory"))
        val file = File(root, relative)
        assertTrue("Host must generate the Room schema", file.isFile)
        val text = file.readText()
        val database = JSONObject(text).getJSONObject("database")
        assertEquals(1, database.getInt("version"))
        assertTrue(database.getString("identityHash").isNotBlank())
        // Room omits default empty collections; present values must be arrays.
        assertEquals(0, if (database.has("views")) database.getJSONArray("views").length() else 0)
        val entities = database.getJSONArray("entities")
        assertEquals(1, entities.length())
        val entity = entities.getJSONObject(0)
        assertEquals("store_metadata", entity.getString("tableName"))
        assertEquals(0, if (entity.has("foreignKeys")) entity.getJSONArray("foreignKeys").length() else 0)
        assertEquals(0, if (entity.has("indices")) entity.getJSONArray("indices").length() else 0)
        val fields = entity.getJSONArray("fields")
        assertEquals(2, fields.length())
        assertEquals(listOf("key", "value"), (0 until fields.length()).map {
            fields.getJSONObject(it).also { field ->
                assertEquals("TEXT", field.getString("affinity"))
                assertTrue(field.getBoolean("notNull"))
            }.getString("columnName")
        })
        val primary = entity.getJSONObject("primaryKey")
        assertFalse(primary.getBoolean("autoGenerate"))
        assertEquals("[\"key\"]", primary.getJSONArray("columnNames").toString())
    }
}
