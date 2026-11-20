// fictional-data: synthetic legacy rows and body samples; assertions never print body values.
package com.ignacioli.finecoach

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.migration.*
import com.ignacioli.finecoach.storage.repository.*
import java.io.File
import java.time.*
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class RoomMigrationV4Tests {
    private val now = S3Fixtures.now
    private fun run(action: suspend (Context) -> Unit) {
        val worker = Executors.newSingleThreadExecutor()
        try { worker.submit(Callable {
            val context = ApplicationProvider.getApplicationContext<Context>()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
            try { runBlocking { action(context) } } finally { context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME) }
        }).get() } finally { worker.shutdownNow() }
    }
    private fun legacy(context: Context) {
        val path = context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME); path.parentFile!!.mkdirs()
        val schema = JSONObject(File("schemas/com.ignacioli.finecoach.storage.FineCoachDatabase/3.json").readText()).getJSONObject("database")
        SQLiteDatabase.openOrCreateDatabase(path, null).use { db ->
            val entities = schema.getJSONArray("entities")
            for (i in 0 until entities.length()) {
                val e = entities.getJSONObject(i)
                db.execSQL(e.getString("createSql").replace("\${TABLE_NAME}", e.getString("tableName")))
                val indices = e.optJSONArray("indices") ?: org.json.JSONArray()
                for (j in 0 until indices.length()) db.execSQL(indices.getJSONObject(j).getString("createSql").replace("\${TABLE_NAME}", e.getString("tableName")))
            }
            db.execSQL("INSERT INTO store_metadata VALUES ('retained', 'fictional-v3')")
            db.execSQL("INSERT INTO students VALUES (?, '虚构迁移', 'female', NULL, NULL, NULL, NULL, NULL, 'active', ?, ?)", arrayOf(S3Fixtures.student.value, now.toString(), now.toString()))
            db.execSQL("INSERT INTO sessions VALUES (?, ?, 'inProgress', ?, ?, '0', NULL, 0, NULL, NULL, NULL, '0', ?, ?, NULL, NULL, NULL)", arrayOf(UUID(0, 3).toString(), S3Fixtures.student.value, now.toString(), now.toString(), now.toString(), now.toString()))
            db.version = 3
        }
    }
    private fun <T> ApplicationResult<T>.success(): T { assertTrue(this is ApplicationResult.Success); return (this as ApplicationResult.Success).value }
    @Test fun preservesLegacyAndRoundTripsEveryFcbkBodyFieldAfterReopen() = run { context ->
        legacy(context)
        var db = FineCoachDatabaseFactory.create(context)
        try {
            assertTrue(db.openHelper.writableDatabase.version == 4)
            assertTrue(db.storeMetadataDao().find("retained")?.value == "fictional-v3")
            assertNotNull(db.s1Dao().findSession(UUID(0, 3)))
            val repo = BodyDataRepository(db, AppClock { now })
            assertTrue(repo.metrics(S3Fixtures.student).success().size == 8)
            val metric = BodyMetricDefinition(UUID(0, 40), S3Fixtures.student, BodyMetricKind.custom, NormalizedName.parse("虚构指标"), BodyMetricUnitRuleKind.customUnit, "单位甲", BodyMetricLifecycle.active, now.minusSeconds(5), now)
            repo.saveMetric(metric).success()
            val point = BodyMeasurement.recordedNow(UUID(0, 41), S3Fixtures.student, metric.id, now, S3Fixtures.zone, DecimalValue.parse("12.345"), "单位甲")
            repo.recordMeasurement(point).success()
            val edited = repo.recordMeasurement(BodyMeasurement.recordedNow(UUID(0, 42), point.studentID, point.metricID, now.plusSeconds(1), S3Fixtures.zone, DecimalValue.parse("13.5"), "单位乙")).success()
            assertTrue(edited.id == point.id && edited.createdAtUTC == point.createdAtUTC)
            db.close(); db = FineCoachDatabaseFactory.create(context)
            val reopened = BodyDataRepository(db, AppClock { now })
            val m = reopened.metrics(S3Fixtures.student).success().single { it.id == metric.id }
            assertTrue(m.studentID == metric.studentID && m.kind == metric.kind && m.name == metric.name && m.unitRuleKind == metric.unitRuleKind && m.currentUnit == metric.currentUnit && m.lifecycle == metric.lifecycle && m.createdAtUTC == metric.createdAtUTC && m.updatedAtUTC == metric.updatedAtUTC)
            val v = reopened.history(point.studentID, point.metricID).success().single()
            assertTrue(v.id == edited.id && v.studentID == edited.studentID && v.metricID == edited.metricID && v.localCalendarDay == edited.localCalendarDay && v.value.compareTo(edited.value) == 0 && v.enteredUnit == edited.enteredUnit && v.createdAtUTC == edited.createdAtUTC && v.updatedAtUTC == edited.updatedAtUTC)
            assertTrue(reopened.deleteCustomMetricIfUnused(metric.id) is ApplicationResult.Failure)
            reopened.deleteMeasurement(v.id).success()
            assertTrue(reopened.history(v.studentID, v.metricID).success().isEmpty())
            reopened.deleteCustomMetricIfUnused(metric.id).success()
        } finally { db.close() }
    }
    @Test fun migrationFailureRollsBackTablesAndAllOldRows() = run { context ->
        legacy(context)
        val path = context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).path
        fun rows(db: SQLiteDatabase): Map<String, List<List<String?>>> {
            val tables = db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name", null).use { c -> buildList { while(c.moveToNext()) add(c.getString(0)) } }
            return tables.associateWith { name -> db.rawQuery("SELECT * FROM `$name`", null).use { c -> buildList { while(c.moveToNext()) add((0 until c.columnCount).map { if(c.isNull(it)) null else c.getString(it) }) } } }
        }
        val before = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY).use(::rows)
        val failure = object: Migration(3, 4) { override fun migrate(db: SupportSQLiteDatabase) { MIGRATION_3_4.migrate(db); db.execSQL("UPDATE store_metadata SET value = 'rollback' WHERE `key` = 'retained'"); error("Fictional migration interruption") } }
        val broken = Room.databaseBuilder(context, FineCoachDatabase::class.java, FineCoachDatabaseFactory.DATABASE_NAME).addMigrations(failure).build()
        try { assertThrows(IllegalStateException::class.java) { broken.openHelper.writableDatabase } } finally { broken.close() }
        SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY).use { db -> assertTrue(db.version == 3); assertTrue(rows(db) == before) }
        val valid = FineCoachDatabaseFactory.create(context)
        try { assertTrue(valid.openHelper.writableDatabase.version == 4) } finally { valid.close() }
    }
    @Test fun uniqueDayForeignKeysAndStudentDeletion() = run { context ->
        legacy(context); val db = FineCoachDatabaseFactory.create(context)
        try {
            val repo = BodyDataRepository(db, AppClock { now }); repo.metrics(S3Fixtures.student).success()
            val point = BodyMeasurement.recordedNow(UUID(0, 60), S3Fixtures.student, BuiltInBodyMetric.weight.id, now, S3Fixtures.zone, DecimalValue.parse("70"), "kg")
            repo.recordMeasurement(point).success()
            assertThrows(android.database.sqlite.SQLiteConstraintException::class.java) { db.bodyDataDao().insert(point.entity().copy(id = UUID(0, 61).toString())) }
            val custom = BodyMetricDefinition(UUID(0, 70), point.studentID, BodyMetricKind.custom, NormalizedName.parse("虚构指标"), BodyMetricUnitRuleKind.customUnit, "u", BodyMetricLifecycle.active, now, now)
            repo.saveMetric(custom).success(); repo.recordMeasurement(BodyMeasurement.recordedNow(UUID(0, 71), point.studentID, custom.id, now, S3Fixtures.zone, point.value, "u")).success()
            db.openHelper.writableDatabase.execSQL("DELETE FROM sessions")
            StudentRepository(db, AppClock { now }).delete(point.studentID, "虚构迁移").success()
            assertTrue(db.bodyDataDao().allMeasurements(point.studentID.value).isEmpty())
            assertNull(db.bodyDataDao().metric(custom.id.toString()))
        } finally { db.close() }
    }    @Test fun applicationUsesLiveLedgerAndBodyFailuresAreResults() = s2Run {
        val sid = student()
        val credit = graph.credits
        val saved = credit.createActivePackage(sid, null, 10).requireSuccess() as SaveCoursePackageResult.Saved
        repeat(8) { index -> credit.recordManualCorrection(saved.record.coursePackageID, CreditDirection.debit, 1, "虚构调整").requireSuccess() }
        db.openHelper.writableDatabase.execSQL("UPDATE course_packages SET remainingCreditsCache = 999")
        val progress = ProgressUseCases(graph.historyRepository, graph.sessions)
        val useCases = InsightUseCases(StudentRepository(db, clock), progress, repository, credit,
            { ApplicationResult.Success(emptySet()) }, { _, _ -> emptySet() })
        val insights = useCases.load(now, zone, sid).requireSuccess()
        assertTrue(insights.single().kind == com.ignacioli.finecoach.core.domain.insight.Insight.Kind.packageLow)
        assertTrue(insights.single().balance == 2L)
        val missing = useCases.load(now, zone, StudentID.fromUUID(UUID(0, 999))).requireSuccess()
        assertTrue(missing.isEmpty())
        val bodies = BodyDataUseCases(BodyDataRepository(db, clock), clock, zone) { UUID(0, 888) }
        val result = bodies.recordMeasurement(sid, BuiltInBodyMetric.weight.id, "invalid", "kg")
        assertTrue(result is ApplicationResult.Failure && result.error.code == ApplicationErrorCode.invalidDecimal)
    }

}
