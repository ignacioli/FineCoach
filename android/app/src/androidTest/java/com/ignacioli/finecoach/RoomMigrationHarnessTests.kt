package com.ignacioli.finecoach

import android.database.sqlite.SQLiteDatabase
import androidx.room.testing.MigrationTestHelper
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import androidx.test.ext.junit.runners.AndroidJUnit4

@RunWith(AndroidJUnit4::class)
class RoomMigrationHarnessTests {
    @Suppress("DEPRECATION")
    @get:Rule val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(), SyntheticMigrationDatabase.SCHEMA_FOLDER,
    )

    @Suppress("DEPRECATION")
    @get:Rule val v1Helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(), SyntheticMigrationDatabase.V1_SCHEMA_FOLDER,
    )

    private fun createV1(name: String) {
        // Require both compiler exports in the test APK, never target APK fallback.
        for ((folder, version) in listOf(
            SyntheticMigrationDatabase.V1_SCHEMA_FOLDER to SyntheticMigrationDatabase.V1,
            SyntheticMigrationDatabase.SCHEMA_FOLDER to SyntheticMigrationDatabase.V2,
        )) {
            InstrumentationRegistry.getInstrumentation().context.assets.open("$folder/$version.json").use {
                assertTrue("Test APK schema must be nonempty: $folder/$version.json", it.read() != -1)
            }
        }
        v1Helper.createDatabase(name, SyntheticMigrationDatabase.V1).use { database ->
            database.execSQL("INSERT INTO synthetic_probe (id, label) VALUES (?, ?)",
                arrayOf<Any>(41, "fictional-comet"))
        }
    }

    @Test fun migrationPreservesFictionalRowAndValidatesV2Default() {
        val name = "synthetic-migration-success.db"
        createV1(name)
        helper.runMigrationsAndValidate(name, SyntheticMigrationDatabase.V2, true,
            SyntheticMigrationDatabase.migration1To2).use { database ->
            assertEquals(2, database.version)
            database.query("SELECT id, label, fictional_rank FROM synthetic_probe").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(41, cursor.getInt(0))
                assertEquals("fictional-comet", cursor.getString(1))
                assertEquals(7, cursor.getInt(2))
                assertFalse(cursor.moveToNext())
            }
        }
    }

    @Test fun missingMigrationRejectsV2AndPreservesOldDatabaseAndRow() {
        val name = "synthetic-migration-missing.db"
        createV1(name)
        val path = InstrumentationRegistry.getInstrumentation().targetContext.getDatabasePath(name)
        assertTrue(path.isFile)
        val failure = assertThrows(IllegalStateException::class.java) {
            helper.runMigrationsAndValidate(name, SyntheticMigrationDatabase.V2, true).close()
        }
        // Do not count an assets/initialization error as missing-migration proof.
        assertTrue(failure.message.orEmpty(),
            failure.message.orEmpty().contains("A migration from 1 to 2 was required but not found"))
        assertTrue("Failed upgrade must preserve the old database file", path.isFile)
        // Read-only inspection cannot recreate a missing database or migrate it.
        SQLiteDatabase.openDatabase(path.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use { database ->
            assertEquals(1, database.version)
            database.rawQuery("SELECT id, label FROM synthetic_probe", null).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(41, cursor.getInt(0))
                assertEquals("fictional-comet", cursor.getString(1))
                assertFalse(cursor.moveToNext())
            }
            database.rawQuery("PRAGMA table_info(synthetic_probe)", null).use { cursor ->
                val columns = mutableListOf<String>()
                while (cursor.moveToNext()) columns += cursor.getString(1)
                assertEquals(listOf("id", "label"), columns)
            }
        }
    }
}
