// fictional-data: synthetic legacy rows and fictional appointment round trips.
package com.ignacioli.finecoach

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.migration.*
import com.ignacioli.finecoach.storage.repository.*
import java.io.File
import java.time.*
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class RoomMigrationV3Tests {
    private val now = Instant.parse("2026-03-08T10:00:00Z")
    private fun run(action: (Context) -> Unit) {
        val worker = Executors.newSingleThreadExecutor()
        try { worker.submit(Callable {
            val context = ApplicationProvider.getApplicationContext<Context>()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
            try { action(context) } finally { context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME) }
        }).get() } finally { worker.shutdownNow() }
    }
    private fun legacy(context: Context) {
        val path = context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME)
        path.parentFile!!.mkdirs()
        val schema = JSONObject(File("schemas/com.ignacioli.finecoach.storage.FineCoachDatabase/2.json").readText()).getJSONObject("database")
        SQLiteDatabase.openOrCreateDatabase(path, null).use { db ->
            val entities = schema.getJSONArray("entities")
            for (i in 0 until entities.length()) {
                val e = entities.getJSONObject(i)
                db.execSQL(e.getString("createSql").replace("\${TABLE_NAME}", e.getString("tableName")))
                val indices = e.optJSONArray("indices") ?: org.json.JSONArray()
                for (j in 0 until indices.length()) db.execSQL(indices.getJSONObject(j).getString("createSql").replace("\${TABLE_NAME}", e.getString("tableName")))
            }
            db.execSQL("INSERT INTO store_metadata VALUES ('retained', 'fictional-v2')")
            db.execSQL("INSERT INTO students VALUES (?, '虚构迁移', 'female', NULL, NULL, NULL, NULL, NULL, 'active', ?, ?)", arrayOf(UUID(0, 2).toString(), now.toString(), now.toString()))
            db.execSQL("INSERT INTO sessions VALUES (?, ?, 'inProgress', ?, ?, '0', NULL, 0, NULL, NULL, NULL, '0', ?, ?, NULL, NULL, NULL)", arrayOf(UUID(0, 3).toString(), UUID(0, 2).toString(), now.toString(), now.toString(), now.toString(), now.toString()))
            db.version = 2
        }
    }
    @Test fun migrationPreservesLegacyAndRoundTripsEveryAppointmentField() = run { context ->
        legacy(context)
        val db = FineCoachDatabaseFactory.create(context)
        try {
            assertEquals(4, db.openHelper.writableDatabase.version)
            assertEquals("fictional-v2", db.storeMetadataDao().find("retained")?.value)
            assertNotNull(db.s1Dao().findSession(UUID(0, 3)))
            val s = RecurrenceSeries(UUID(0, 4), StudentID.fromUUID(UUID(0, 2)), RecurrenceInterval.everyTwoDays,
                RecurrenceTermination.EndDate(LocalDate.parse("2026-03-30")), LocalTime.NOON, createdAtUTC = now, updatedAtUTC = now)
            db.appointmentDao().insert(s.toEntity())
            val a = Appointment(UUID(0, 5), s.studentID, s.id, LocalDate.parse("2026-03-08"), LocalTime.of(1, 30), 90,
                AppointmentStatus.absent, AbsentCreditChoice.charged, "虚构原因", true, false, ReminderLeadMinutes.thirty,
                UUID(0, 3), setOf(BodyPart.back, BodyPart.thighs), now, now.plusSeconds(5))
            db.appointmentDao().insert(a.toEntity())
            db.close()
            val reopened = FineCoachDatabaseFactory.create(context)
            try {
                assertEquals(a, reopened.appointmentDao().find(a.id.toString())!!.toDomain())
                assertEquals(s, reopened.appointmentDao().series(s.id.toString())!!.toDomain())
                assertNotNull(reopened.s1Dao().findSession(UUID(0, 3)))
            } finally { reopened.close() }
        } finally { db.close() }
    }
    @Test fun failedMigrationRollsBackDdlAndOldRows() = run { context ->
        legacy(context)
        fun sessionRow(db: SQLiteDatabase): List<String?> = db.rawQuery("SELECT * FROM sessions WHERE id = ?", arrayOf(UUID(0, 3).toString())).use { c ->
            assertTrue(c.moveToFirst())
            (0 until c.columnCount).map { if (c.isNull(it)) null else c.getString(it) }
        }
        val before = SQLiteDatabase.openDatabase(context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).path, null, SQLiteDatabase.OPEN_READONLY).use { sessionRow(it) }
        val failure = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                MIGRATION_2_3.migrate(db)
                db.execSQL("UPDATE store_metadata SET value = 'should-rollback' WHERE `key` = 'retained'")
                error("fictional migration interruption")
            }
        }
        val broken = Room.databaseBuilder(context, FineCoachDatabase::class.java, FineCoachDatabaseFactory.DATABASE_NAME).addMigrations(failure).build()
        try { assertThrows(IllegalStateException::class.java) { broken.openHelper.writableDatabase } } finally { broken.close() }
        SQLiteDatabase.openDatabase(context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            assertEquals(2, db.version)
            assertEquals(before, sessionRow(db))
            db.rawQuery("SELECT displayName FROM students WHERE id = ?", arrayOf(UUID(0, 2).toString())).use { assertTrue(it.moveToFirst()); assertEquals("虚构迁移", it.getString(0)) }
            db.rawQuery("SELECT value FROM store_metadata WHERE `key` = 'retained'", null).use { assertTrue(it.moveToFirst()); assertEquals("fictional-v2", it.getString(0)) }
            db.rawQuery("SELECT count(*) FROM sqlite_master WHERE name = 'appointments'", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) }
        }
        val valid = FineCoachDatabaseFactory.create(context)
        try { assertEquals(4, valid.openHelper.writableDatabase.version) } finally { valid.close() }
    }
    @Test fun migratedStudentDeletionClearsScheduleAndSessionDeletionNullsLinks() = run { context ->
        legacy(context)
        val db = FineCoachDatabaseFactory.create(context)
        try {
            val dao = db.appointmentDao()
            val student = StudentID.fromUUID(UUID(0, 2))
            val series = RecurrenceSeries(UUID(0, 4), student, RecurrenceInterval.everyWeek,
                RecurrenceTermination.RepeatCount(2), LocalTime.NOON, createdAtUTC = now, updatedAtUTC = now)
            dao.insert(series.toEntity())
            val row = Appointment(UUID(0, 5), student, series.id, LocalDate.parse("2026-03-09"), LocalTime.NOON,
                status = AppointmentStatus.completed, linkedSessionID = UUID(0, 3), createdAtUTC = now, updatedAtUTC = now)
            dao.insert(row.toEntity())
            val oldSession = db.s1Dao().findSession(UUID(0, 3))!!
            db.openHelper.writableDatabase.execSQL("DELETE FROM sessions WHERE id = ?", arrayOf(UUID(0, 3).toString()))
            assertNull(dao.find(row.id.toString())!!.linkedSessionID)
            assertEquals(AppointmentStatus.completed, dao.find(row.id.toString())!!.toDomain().status)
            db.s1Dao().insert(oldSession.copy(state = SessionState.completed, completedAtUTC = now))
            dao.update(row.toEntity())
            assertEquals(1, dao.linkSession(oldSession.id.toString(), row.id.toString()))
            kotlinx.coroutines.runBlocking {
                val result = StudentRepository(db, com.ignacioli.finecoach.core.application.AppClock { now }).delete(student, "虚构迁移")
                assertTrue(result is com.ignacioli.finecoach.core.application.ApplicationResult.Success)
            }
            assertTrue(dao.all().isEmpty())
            assertNull(dao.series(series.id.toString()))
            assertNull(db.s1Dao().findStudent(UUID(0, 2)))
            assertNull(db.storeMetadataDao().find("s2.deletingStudent"))
        } finally { db.close() }
    }
    @Test fun freshAndMigratedReferencesRejectDanglingWrites() = run { context ->
        for (migrate in listOf(false, true)) {
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
            if (migrate) legacy(context)
            val db = FineCoachDatabaseFactory.create(context)
            try {
                val sql = db.openHelper.writableDatabase
                assertThrows(android.database.sqlite.SQLiteConstraintException::class.java) {
                    sql.execSQL("INSERT INTO appointments VALUES ('missing', 'missing', NULL, '2026-03-08', '01:00', 60, 'scheduled', NULL, NULL, 0, 1, 60, NULL, '', ?, ?)", arrayOf(now.toString(), now.toString()))
                }
                if (!migrate) {
                    sql.execSQL("INSERT INTO students VALUES (?, '虚构迁移', 'female', NULL, NULL, NULL, NULL, NULL, 'active', ?, ?)", arrayOf(UUID(0, 2).toString(), now.toString(), now.toString()))
                    sql.execSQL("INSERT INTO sessions VALUES (?, ?, 'inProgress', ?, ?, '0', NULL, 0, NULL, NULL, NULL, '0', ?, ?, NULL, NULL, NULL)", arrayOf(UUID(0, 3).toString(), UUID(0, 2).toString(), now.toString(), now.toString(), now.toString(), now.toString()))
                }
                assertThrows(android.database.sqlite.SQLiteConstraintException::class.java) {
                    sql.execSQL("UPDATE sessions SET appointmentID = 'missing'")
                }
                val linked = Appointment(UUID(0, 9), StudentID.fromUUID(UUID(0, 2)), date = LocalDate.parse("2026-03-09"),
                    startTime = LocalTime.NOON, status = AppointmentStatus.inProgress, linkedSessionID = UUID(0, 3), createdAtUTC = now, updatedAtUTC = now)
                db.appointmentDao().insert(linked.toEntity())
                sql.execSQL("DELETE FROM sessions WHERE id = ?", arrayOf(UUID(0, 3).toString()))
                assertNull(db.appointmentDao().find(linked.id.toString())!!.linkedSessionID)
                assertEquals(AppointmentStatus.inProgress, db.appointmentDao().find(linked.id.toString())!!.toDomain().status)
            } finally { db.close() }
        }
    }
}
