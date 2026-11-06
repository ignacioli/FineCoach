package com.ignacioli.finecoach

import android.database.sqlite.SQLiteConstraintException
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.migration.MIGRATION_1_2
import java.util.UUID
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class S1MigrationTests {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val name = FineCoachDatabaseFactory.DATABASE_NAME
    private val folder = FineCoachDatabase::class.java.canonicalName!!
    private val generationKey = FineCoachDatabaseFactory.GENERATION_KEY
    private val fixedGeneration = "00000000-0000-4000-8000-000000000090"
    private val studentID = "00000000-0000-4000-8000-000000000001"
    private val sessionID = "00000000-0000-4000-8000-000000000002"
    private val secondSessionID = "00000000-0000-4000-8000-000000000003"
    private val oldRows = mapOf("created_at" to "2026-11-01T01:02:03.123456789Z",
        "fictional_marker" to "  retained exactly  ", "archive.studentID.fictional" to "fictional-private-setting")

    @Suppress("DEPRECATION")
    @get:Rule val helper = MigrationTestHelper(InstrumentationRegistry.getInstrumentation(),
        FineCoachDatabase::class.java.canonicalName!!)

    @Before fun prepare() {
        context.deleteDatabase(name)
        // Missing compiler exports must fail before any negative migration assertion.
        for (version in 1..2) {
            InstrumentationRegistry.getInstrumentation().context.assets.open("$folder/$version.json").use {
                assertTrue("Missing/empty real Room schema v$version", it.read() != -1)
            }
        }
    }

    @After fun cleanUp() { context.deleteDatabase(name) }

    private fun <T> withProductionDatabase(action: (FineCoachDatabase) -> T): T {
        val room = FineCoachDatabaseFactory.create(context)
        try { return action(room) }
        finally { room.close() }
    }

    private fun createV1(generation: String? = null) {
        helper.createDatabase(name, 1).use { db ->
            oldRows.forEach { (key, value) ->
                db.execSQL("INSERT INTO store_metadata (`key`, value) VALUES (?, ?)", arrayOf(key, value))
            }
            if (generation != null) db.execSQL("INSERT INTO store_metadata (`key`, value) VALUES (?, ?)",
                arrayOf(generationKey, generation))
        }
    }

    private fun metadata(db: SupportSQLiteDatabase): Map<String, String> = buildMap {
        db.query("SELECT `key`, value FROM store_metadata").use { cursor ->
            while (cursor.moveToNext()) put(cursor.getString(0), cursor.getString(1))
        }
    }

    private fun tableNames(db: SupportSQLiteDatabase): Set<String> = buildSet {
        db.query("SELECT name FROM sqlite_master WHERE type = 'table'").use { cursor ->
            while (cursor.moveToNext()) add(cursor.getString(0))
        }
    }

    private val businessTables = setOf("store_metadata", "students", "course_packages", "active_package_claims",
        "credit_adjustments", "sessions", "active_session_pointers", "session_training_focus", "session_exercises",
        "training_sets", "training_templates", "template_training_focus", "template_exercises", "template_planned_sets",
        "session_sections", "exercise_catalog", "exercise_preferences", "exercise_name_claims")

    private fun assertV2Structure(db: SupportSQLiteDatabase) {
        assertEquals(2, db.version)
        db.query("PRAGMA foreign_keys").use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(1, cursor.getInt(0))
        }
        assertEquals(businessTables, tableNames(db) - setOf("room_master_table", "android_metadata", "sqlite_sequence"))
        for (table in listOf("sessions", "training_templates")) {
            db.query("PRAGMA table_info(`$table`)").use { cursor ->
                var found = false
                while (cursor.moveToNext()) if (cursor.getString(cursor.getColumnIndexOrThrow("name")) == "revision") {
                    assertEquals("TEXT", cursor.getString(cursor.getColumnIndexOrThrow("type")))
                    assertEquals(1, cursor.getInt(cursor.getColumnIndexOrThrow("notnull")))
                    found = true
                }
                assertTrue("Missing revision column: $table", found)
            }
        }
        val parents = mapOf("sessions" to ("students" to "studentID"),
            "session_exercises" to ("sessions" to "sessionID"),
            "training_sets" to ("session_exercises" to "sessionExerciseID"),
            "credit_adjustments" to ("course_packages" to "packageID"),
            "session_training_focus" to ("sessions" to "sessionID"),
            "template_exercises" to ("training_templates" to "templateID"),
            "template_training_focus" to ("training_templates" to "templateID"),
            "template_planned_sets" to ("template_exercises" to "templateExerciseID"))
        for (table in businessTables) {
            db.query("PRAGMA foreign_key_list(`$table`)").use { cursor ->
                val expected = parents[table]
                assertEquals(if (expected == null) 0 else 1, cursor.count)
                if (expected != null) {
                    assertTrue(cursor.moveToFirst())
                    assertEquals(expected.first, cursor.getString(cursor.getColumnIndexOrThrow("table")))
                    assertEquals(expected.second, cursor.getString(cursor.getColumnIndexOrThrow("from")))
                    assertEquals("id", cursor.getString(cursor.getColumnIndexOrThrow("to")))
                    assertEquals("NO ACTION", cursor.getString(cursor.getColumnIndexOrThrow("on_delete")))
                    assertEquals("NO ACTION", cursor.getString(cursor.getColumnIndexOrThrow("on_update")))
                }
            }
        }
        for ((table, columns) in listOf(
            "active_session_pointers" to listOf("sessionID"),
            "credit_adjustments" to listOf("sourceEventKey"),
            "session_exercises" to listOf("sessionID", "orderIndex"),
            "training_sets" to listOf("sessionExerciseID", "orderIndex"),
            "template_exercises" to listOf("templateID", "orderIndex"),
            "session_sections" to listOf("ownerKind", "ownerID", "orderIndex"),
        )) {
            val index = "index_${table}_${columns.joinToString("_")}"
            db.query("PRAGMA index_list(`$table`)").use { cursor ->
                var found = false
                while (cursor.moveToNext()) if (cursor.getString(cursor.getColumnIndexOrThrow("name")) == index) {
                    assertEquals(1, cursor.getInt(cursor.getColumnIndexOrThrow("unique")))
                    found = true
                }
                assertTrue("Missing unique index: $index", found)
            }
            db.query("PRAGMA index_info(`$index`)").use { cursor ->
                val actual = buildList { while (cursor.moveToNext()) add(cursor.getString(cursor.getColumnIndexOrThrow("name"))) }
                assertEquals(columns, actual)
            }
        }
        db.query("PRAGMA foreign_key_check").use { assertEquals(0, it.count) }
    }

    private fun assertOriginalV1(generation: String? = null) {
        val path = context.getDatabasePath(name)
        assertTrue(path.isFile)
        SQLiteDatabase.openDatabase(path.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            assertEquals(1, db.version)
            val rows = buildMap {
                db.rawQuery("SELECT `key`, value FROM store_metadata", null).use { cursor ->
                    while (cursor.moveToNext()) put(cursor.getString(0), cursor.getString(1))
                }
            }
            assertEquals(if (generation == null) oldRows else oldRows + (generationKey to generation), rows)
            val tables = buildSet {
                db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'", null).use { cursor ->
                    while (cursor.moveToNext()) add(cursor.getString(0))
                }
            }
            assertEquals(setOf("store_metadata"), tables - setOf("room_master_table", "android_metadata", "sqlite_sequence"))
        }
    }

    @Test fun freshProductionDatabaseCreatesCompleteV2AndStableGeneration() {
        val generation = withProductionDatabase { room ->
            val db = room.openHelper.writableDatabase
            assertV2Structure(db)
            val rows = metadata(db)
            assertEquals(setOf("created_at", generationKey), rows.keys)
            assertEquals(rows.getValue("created_at"), java.time.Instant.parse(rows.getValue("created_at")).toString())
            rows.getValue(generationKey).also { assertEquals(it, UUID.fromString(it).toString()) }
        }
        withProductionDatabase { room ->
            assertEquals(generation, metadata(room.openHelper.writableDatabase)[generationKey])
        }
        helper.runMigrationsAndValidate(name, 2, true, MIGRATION_1_2).close()
    }

    @Test fun realV1MigrationPreservesEveryOldRowInitializesGenerationAndReopens() {
        createV1()
        helper.runMigrationsAndValidate(name, 2, true, MIGRATION_1_2).close()
        // The helper validates schema; connection-local FK enforcement belongs to Room's production onOpen.
        val generation = withProductionDatabase { room ->
            val db = room.openHelper.writableDatabase
            assertV2Structure(db)
            val rows = metadata(db)
            assertEquals(oldRows, rows - generationKey)
            rows.getValue(generationKey).also { assertEquals(it, UUID.fromString(it).toString()) }
        }
        withProductionDatabase { room ->
            assertEquals(oldRows + (generationKey to generation), metadata(room.openHelper.writableDatabase))
            assertV2Structure(room.openHelper.writableDatabase)
        }
    }

    @Test fun registeredFactoryMigrationPreservesExistingGenerationVerbatim() {
        createV1(fixedGeneration)
        withProductionDatabase { room ->
            assertEquals(oldRows + (generationKey to fixedGeneration), metadata(room.openHelper.writableDatabase))
            assertV2Structure(room.openHelper.writableDatabase)
        }
        helper.runMigrationsAndValidate(name, 2, true, MIGRATION_1_2).close()
    }

    @Test fun migrationExceptionRollsBackDdlMetadataAndVersion() {
        createV1()
        val broken = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                MIGRATION_1_2.migrate(db)
                db.execSQL("UPDATE store_metadata SET value = 'fictional-mutated'")
                throw IllegalStateException("fictional migration interruption")
            }
        }
        val failure = assertThrows(IllegalStateException::class.java) {
            helper.runMigrationsAndValidate(name, 2, true, broken).close()
        }
        assertTrue(failure.message.orEmpty().contains("fictional migration interruption"))
        assertOriginalV1()
    }

    @Test fun schemaValidationFailureRollsBackUpgradeAndExistingGeneration() {
        createV1(fixedGeneration)
        val broken = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                MIGRATION_1_2.migrate(db)
                db.execSQL("DROP TABLE exercise_preferences")
            }
        }
        val failure = assertThrows(IllegalStateException::class.java) {
            helper.runMigrationsAndValidate(name, 2, true, broken).close()
        }
        assertTrue(failure.message.orEmpty(), failure.message.orEmpty().contains("Migration didn't properly handle"))
        assertOriginalV1(fixedGeneration)
    }

    @Test fun missingMigrationIsRejectedByProductionRoomWithoutDestroyingV1() {
        createV1(fixedGeneration)
        val room = Room.databaseBuilder(context, FineCoachDatabase::class.java,
            context.getDatabasePath(name).absolutePath).build()
        try {
            val failure = assertThrows(IllegalStateException::class.java) { room.openHelper.writableDatabase }
            assertTrue(failure.message.orEmpty(), failure.message.orEmpty().contains("A migration from 1 to 2 was required but not found"))
        } finally { room.close() }
        assertOriginalV1(fixedGeneration)
    }

    @Test fun directDuplicatePointerStudentKeyIsRejectedWithoutReplacement() {
        assertDuplicatePointerRejected(studentID, secondSessionID)
    }

    @Test fun directDuplicatePointerSessionIDIsRejectedWithoutReplacement() {
        assertDuplicatePointerRejected("00000000-0000-4000-8000-000000000010", sessionID)
    }

    private fun assertDuplicatePointerRejected(key: String, linkedSession: String) {
        withProductionDatabase { room ->
            val db = room.openHelper.writableDatabase
            // Raw SQL intentionally bypasses DAO ownership guards to prove both DB constraints.
            db.execSQL("INSERT INTO active_session_pointers (`key`, sessionID) VALUES (?, ?)", arrayOf(studentID, sessionID))
            assertThrows(SQLiteConstraintException::class.java) {
                db.execSQL("INSERT INTO active_session_pointers (`key`, sessionID) VALUES (?, ?)", arrayOf(key, linkedSession))
            }
        }
        withProductionDatabase { room ->
            room.openHelper.writableDatabase.query("SELECT `key`, sessionID FROM active_session_pointers").use { cursor ->
                assertEquals(1, cursor.count)
                assertTrue(cursor.moveToFirst())
                assertEquals(studentID, cursor.getString(0))
                assertEquals(sessionID, cursor.getString(1))
            }
        }
    }
}
