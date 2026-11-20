// fictional-data: test-owned file databases and invented walkthrough data only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.seed.S1SeedFixture
import com.ignacioli.finecoach.seed.objects
import com.ignacioli.finecoach.seed.strings
import com.ignacioli.finecoach.core.domain.common.CreditLedgerSourceEventKeyFactory
import com.ignacioli.finecoach.core.domain.common.StudentID
import org.json.JSONObject
import org.json.JSONArray
import com.ignacioli.finecoach.seed.S1DebugSeed
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class S1DebugSeedTests {
    private val worker=Executors.newSingleThreadExecutor()
    private val context get()=ApplicationProvider.getApplicationContext<Context>()
    private fun <T> off(action: suspend () -> T): T=worker.submit(Callable { runBlocking { action() } }).get()
    private val fixture get() = S1SeedFixture.read(context)
    private fun student(index: Int) = StudentID.parse(fixture.uuid(fixture.records("students")[index].getInt("id")))
    @Before fun prepare() { context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME) }
    @After fun close() { worker.shutdownNow(); context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME) }
    @Test fun fixtureParsesAndCoversEveryT019Scenario() {
        val f = fixture
        assertEquals(setOf("empty", "single", "multi"), f.records("scenarios").map { it.getString("key") }.toSet())
        val students = f.records("students")
        assertTrue(students.groupBy { it.getString("name") }.values.any { it.size == 2 })
        assertTrue(students.any { it.getString("name").length >= 20 })
        assertEquals(setOf("active", "archived"), students.map { it.getString("lifecycle") }.toSet())
        assertTrue(students.any { student -> f.records("packages").none { it.getInt("studentID") == student.getInt("id") } })
        assertTrue(f.records("packages").map { it.getString("key") }.toSet().containsAll(setOf("available", "expired", "exhausted", "ended", "replacement-old", "replacement-new")))
        assertEquals(1, f.selected("sessions", "single").count { it.getString("state") == "inProgress" })
        assertEquals(2, f.selected("sessions", "multi").count { it.getString("state") == "inProgress" })
        assertTrue(f.selected("sessions", "empty").isEmpty())
        assertTrue(f.records("sessions").any { it.getString("state") == "completed" && it.has("summary") })
        assertEquals(setOf("manualCorrection", "adhocDebit"), f.records("ledger").map { it.getString("kind") }.toSet())
        val sessionsAndTemplates = f.records("sessions") + f.records("templates")
        for (row in sessionsAndTemplates) {
            assertTrue(row.getString("scenario").isNotBlank())
            assertTrue(row.objects("sections").isNotEmpty())
        }
        assertEquals(setOf("weightReps", "reps", "duration", "cardio"), sessionsAndTemplates.flatMap { it.objects("exercises") }.map { it.getString("recordMode") }.toSet())
        assertEquals(setOf("completed", "pending", "draft"), f.records("sessions").flatMap { it.objects("exercises") }.flatMap { it.objects("sets") }.map { it.getString("state") }.toSet())
    }

    @Test fun fixtureContainsNoBodyDataOrShareFields() {
        val forbidden = setOf("bodyData", "bodyMeasurements", "bodyWeight", "height", "waist", "bodyFat", "shareReport", "shareReports")
        fun inspect(value: Any) {
            when (value) {
                is JSONObject -> value.keys().forEach { key -> assertFalse("Forbidden fixture field", key in forbidden); inspect(value.get(key)) }
                is JSONArray -> (0 until value.length()).forEach { inspect(value.get(it)) }
            }
        }
        inspect(fixture.json)
        val altered = JSONObject(fixture.json.toString())
        altered.getJSONArray("students").getJSONObject(0).put("bodyWeight", "fictional-forbidden")
        assertThrows(IllegalArgumentException::class.java) { S1SeedFixture.decode(altered.toString()) }
    }

    @Test fun missingBuiltInReferenceFailsRatherThanSubstitutingAnotherExercise() = off {
        val db = FineCoachDatabaseFactory.create(context)
        try {
            val graph = S1DebugSeed.graph(db, context)
            graph.prepareExerciseCatalog()
            val row = JSONObject(fixture.records("sessions").first().objects("exercises").first().toString())
            row.put("canonicalName", "虚构不存在的内置动作")
            val catalog = graph.exerciseRepository.listCatalog().requireSuccess()
            assertThrows(IllegalStateException::class.java) { S1DebugSeed.source(row, catalog) }
            assertTrue(graph.students.list(StudentQuery(includeArchived = true)).requireSuccess().isEmpty())
        } finally { db.close() }
    }

    @Test fun multiScenarioPersistsAllRequiredStatesAcrossReopen() = off {
        val result=S1DebugSeed.load(context)
        assertEquals(fixture.version,result.version); assertEquals(fixture.json.getJSONObject("expectedRows").getInt("multi"),result.rows)
        val db=FineCoachDatabaseFactory.create(context)
        try { S1DebugSeed.verifyInitial(S1DebugSeed.graph(db,context)); assertEquals(result,S1DebugSeed.storedResult(db,fixture)) }
        finally { db.close() }
    }
    @Test fun singleScenarioHasExactlyOneActiveSession() = off {
        val result=S1DebugSeed.load(context,"single")
        assertEquals(fixture.json.getJSONObject("expectedRows").getInt("single"),result.rows)
        val db=FineCoachDatabaseFactory.create(context)
        try { S1DebugSeed.verifyInitial(S1DebugSeed.graph(db,context),"single"); assertEquals(result,S1DebugSeed.storedResult(db,fixture)) }
        finally { db.close() }
    }
    @Test fun emptyScenarioIsExplicitAndDurable() = off {
        val result=S1DebugSeed.load(context,"empty")
        assertEquals(fixture.json.getJSONObject("expectedRows").getInt("empty"),result.rows)
        val db=FineCoachDatabaseFactory.create(context)
        try { S1DebugSeed.verifyInitial(S1DebugSeed.graph(db,context),"empty"); assertEquals(1083,S1DebugSeed.businessRows(db)) }
        finally { db.close() }
        assertEquals(result,S1DebugSeed.load(context,"empty"))
    }
    @Test fun reinstallPreservesCoachEditsAndDoesNotAddRows() = off {
        val result=S1DebugSeed.load(context)
        val db=FineCoachDatabaseFactory.create(context)
        val before: Int
        try {
            val graph=S1DebugSeed.graph(db,context)
            val original=graph.students.find(student(0)).requireSuccess()!!
            graph.students.update(original.studentID,StudentDraft("虚构体验修改",original.sex)).requireSuccess()
            // User may delete a nonactive seeded student; repeating install must not resurrect it.
            graph.students.delete(student(6),fixture.records("students")[6].getString("name")).requireSuccess()
            before=S1DebugSeed.businessRows(db)
        } finally { db.close() }
        assertEquals(result,S1DebugSeed.load(context))
        val reopened=FineCoachDatabaseFactory.create(context)
        try {
            val graph=S1DebugSeed.graph(reopened,context)
            assertEquals("虚构体验修改",graph.students.find(student(0)).requireSuccess()!!.displayName)
            assertNull(graph.students.find(student(6)).requireSuccess())
            assertEquals(before,S1DebugSeed.businessRows(reopened))
        } finally { reopened.close() }
    }
    @Test fun existingNonSeedEvenEmptyIsRejectedWithoutMutation() = off {
        val db=FineCoachDatabaseFactory.create(context)
        // Force creation of an ordinary user database.
        db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)
        db.storeMetadataDao().insert(com.ignacioli.finecoach.storage.StoreMetadata("fictional-user-metadata", "retained")); db.close()
        var failed=false
        try { S1DebugSeed.load(context) } catch (_: IllegalStateException) { failed=true }
        assertTrue(failed)
        val reopened=FineCoachDatabaseFactory.create(context)
        try { assertNull(reopened.storeMetadataDao().find(S1DebugSeed.DATASET_KEY)); assertEquals(0,S1DebugSeed.businessRows(reopened)) }
        finally { reopened.close() }
    }
    @Test fun reminderOnlyStartupStoreCanBeSeededWithoutReplacingGeneration() = off {
        val db = FineCoachDatabaseFactory.create(context)
        val generation = db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value
        db.storeMetadataDao().insert(com.ignacioli.finecoach.storage.StoreMetadata("appointment-reminders-v1", "{}"))
        db.close()
        S1DebugSeed.load(context)
        val reopened = FineCoachDatabaseFactory.create(context)
        try {
            assertEquals(generation, reopened.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
            val g = S1DebugSeed.graph(reopened, context)
            val rows = g.appointments.all().requireSuccess()
            val today = java.time.LocalDate.now(java.time.ZoneId.systemDefault())
            assertEquals(15, rows.size)
            assertTrue(rows.count { it.date == today } >= 7)
            val series = rows.mapNotNull { it.seriesID }.distinct().map { g.appointments.series(it).requireSuccess()!! }
            assertEquals(2, series.size)
            assertTrue(series.any { it.termination is com.ignacioli.finecoach.core.domain.appointment.RecurrenceTermination.RepeatCount })
            assertTrue(series.any { it.termination is com.ignacioli.finecoach.core.domain.appointment.RecurrenceTermination.EndDate })
            for (row in fixture.selected("appointments", "multi")) {
                val actual = rows.single { it.id.toString() == fixture.uuid(row.getInt("id")) }
                assertEquals(today.plusDays(row.getLong("dayOffset")), actual.date)
                assertEquals(row.getString("state"), actual.status.name)
            }
            assertTrue(rows.any { it.status.name == "inProgress" && it.linkedSessionID != null })
            assertEquals(setOf("charged", "notCharged"), rows.mapNotNull { it.absentCreditChoice?.name }.toSet())
            assertEquals(1, g.credits.ledger(student(1)).requireSuccess().count { it.sourceEventKey?.value == CreditLedgerSourceEventKeyFactory.appointmentAbsent(rows.single { it.absentCreditChoice?.name == "charged" }.id.toString()).value })
        } finally { reopened.close() }
    }

    @Test fun startupKeyRemovedAfterPreflightIsNotAdopted() = off {
        val db = FineCoachDatabaseFactory.create(context)
        db.storeMetadataDao().insert(com.ignacioli.finecoach.storage.StoreMetadata("appointment-reminders-v1", "{}"))
        val generation = db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value
        db.close()
        var boundaryReached = false
        var rejected = false
        try {
            S1DebugSeed.load(context, beforeOwnershipTransaction = { opened ->
                boundaryReached = true
                opened.openHelper.writableDatabase.execSQL("DELETE FROM store_metadata WHERE `key`='appointment-reminders-v1'")
            })
        } catch (_: IllegalStateException) { rejected = true }
        assertTrue(boundaryReached); assertTrue(rejected)
        val reopened = FineCoachDatabaseFactory.create(context)
        try {
            assertEquals(generation, reopened.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
            assertNull(reopened.storeMetadataDao().find(S1DebugSeed.DATASET_KEY))
            assertNull(reopened.storeMetadataDao().find("appointment-reminders-v1"))
            assertEquals(0, S1DebugSeed.businessRows(reopened))
            reopened.openHelper.readableDatabase.query("SELECT COUNT(*) FROM store_metadata").use { it.moveToFirst(); assertEquals(2, it.getInt(0)) }
        } finally { reopened.close() }
    }

    @Test fun existingLegacyNonSeedIsRejectedBeforeAnyRoomMigration() = off {
        val path=context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME)
        path.parentFile!!.mkdirs()
        android.database.sqlite.SQLiteDatabase.openOrCreateDatabase(path,null).use { raw ->
            raw.execSQL("CREATE TABLE store_metadata (`key` TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
            raw.execSQL("INSERT INTO store_metadata (`key`,value) VALUES ('fictional-retained','fictional-data')")
            raw.version=1
        }
        var failed=false
        try { S1DebugSeed.load(context) } catch (_: IllegalStateException) { failed=true }
        assertTrue(failed)
        android.database.sqlite.SQLiteDatabase.openDatabase(path.absolutePath,null,android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { raw ->
            assertEquals(1,raw.version)
            raw.rawQuery("SELECT value FROM store_metadata WHERE `key`='fictional-retained'",null).use {
                assertTrue(it.moveToFirst()); assertEquals("fictional-data",it.getString(0))
            }
            raw.rawQuery("SELECT COUNT(*) FROM store_metadata",null).use { it.moveToFirst(); assertEquals(1,it.getInt(0)) }
        }
    }
    @Test fun existingUserRecordsAreNotAdoptedOrOverwritten() = off {
        val db=FineCoachDatabaseFactory.create(context)
        val count: Int
        try {
            val graph=S1DebugSeed.graph(db,context)
            graph.students.create(StudentDraft("虚构非seed资料",com.ignacioli.finecoach.core.domain.common.StudentSex.other)).requireSuccess()
            db.storeMetadataDao().insert(com.ignacioli.finecoach.storage.StoreMetadata("appointment-reminders-v1", "{}"))
            count=S1DebugSeed.businessRows(db)
        } finally { db.close() }
        var failed=false
        try { S1DebugSeed.load(context) } catch (_: IllegalStateException) { failed=true }
        assertTrue(failed)
        val reopened=FineCoachDatabaseFactory.create(context)
        try { assertEquals(count,S1DebugSeed.businessRows(reopened)); assertNull(reopened.storeMetadataDao().find(S1DebugSeed.DATASET_KEY)) }
        finally { reopened.close() }
    }
    @Test fun scenarioMismatchRefusesAndDoesNotResetTheDataset() = off {
        S1DebugSeed.load(context,"single")
        var failed=false
        try { S1DebugSeed.load(context,"multi") } catch (_: IllegalStateException) { failed=true }
        assertTrue(failed)
        val db=FineCoachDatabaseFactory.create(context)
        try { S1DebugSeed.verifyInitial(S1DebugSeed.graph(db,context),"single") } finally { db.close() }
    }
    @Test fun incompleteOrFutureVersionRejectsWithoutRepair() = off {
        S1DebugSeed.load(context)
        val db=FineCoachDatabaseFactory.create(context)
        try { db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value='installing' WHERE `key`=?",arrayOf(S1DebugSeed.STATUS_KEY)) }
        finally { db.close() }
        var failed=false
        try { S1DebugSeed.load(context) } catch (_: IllegalStateException) { failed=true }
        assertTrue(failed)
        val reopened=FineCoachDatabaseFactory.create(context)
        try {
            assertEquals("installing",reopened.storeMetadataDao().find(S1DebugSeed.STATUS_KEY)?.value)
            reopened.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value='complete' WHERE `key`=?",arrayOf(S1DebugSeed.STATUS_KEY))
            reopened.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value='999' WHERE `key`=?",arrayOf(S1DebugSeed.VERSION_KEY))
        } finally { reopened.close() }
        failed=false
        try { S1DebugSeed.load(context) } catch (_: IllegalStateException) { failed=true }
        assertTrue(failed)
    }
}
