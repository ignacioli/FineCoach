// fictional-data: test-owned file databases and invented walkthrough data only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
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
    @Before fun prepare() { context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME) }
    @After fun close() { worker.shutdownNow(); context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME) }
    @Test fun multiScenarioPersistsAllRequiredStatesAcrossReopen() = off {
        val result=S1DebugSeed.load(context)
        assertEquals(1,result.version); assertEquals(66,result.rows)
        val db=FineCoachDatabaseFactory.create(context)
        try { S1DebugSeed.verifyInitial(S1DebugSeed.graph(db,context)); assertEquals(result,S1DebugSeed.storedResult(db)) }
        finally { db.close() }
    }
    @Test fun singleScenarioHasExactlyOneActiveSession() = off {
        val result=S1DebugSeed.load(context,"single")
        assertEquals(55,result.rows)
        val db=FineCoachDatabaseFactory.create(context)
        try { S1DebugSeed.verifyInitial(S1DebugSeed.graph(db,context),"single"); assertEquals(result,S1DebugSeed.storedResult(db)) }
        finally { db.close() }
    }
    @Test fun emptyScenarioIsExplicitAndDurable() = off {
        val result=S1DebugSeed.load(context,"empty")
        assertEquals(5,result.rows)
        val db=FineCoachDatabaseFactory.create(context)
        try { S1DebugSeed.verifyInitial(S1DebugSeed.graph(db,context),"empty"); assertEquals(0,S1DebugSeed.businessRows(db)) }
        finally { db.close() }
        assertEquals(result,S1DebugSeed.load(context,"empty"))
    }
    @Test fun reinstallPreservesCoachEditsAndDoesNotAddRows() = off {
        val result=S1DebugSeed.load(context)
        val db=FineCoachDatabaseFactory.create(context)
        val before: Int
        try {
            val graph=S1DebugSeed.graph(db,context)
            val original=graph.students.find(S1DebugSeed.studentIDs[0]).requireSuccess()!!
            graph.students.update(original.studentID,StudentDraft("虚构体验修改",original.sex)).requireSuccess()
            // User may delete a nonactive seeded student; repeating install must not resurrect it.
            graph.students.delete(S1DebugSeed.studentIDs[6],"虚构学员7").requireSuccess()
            before=S1DebugSeed.businessRows(db)
        } finally { db.close() }
        assertEquals(result,S1DebugSeed.load(context))
        val reopened=FineCoachDatabaseFactory.create(context)
        try {
            val graph=S1DebugSeed.graph(reopened,context)
            assertEquals("虚构体验修改",graph.students.find(S1DebugSeed.studentIDs[0]).requireSuccess()!!.displayName)
            assertNull(graph.students.find(S1DebugSeed.studentIDs[6]).requireSuccess())
            assertEquals(before,S1DebugSeed.businessRows(reopened))
        } finally { reopened.close() }
    }
    @Test fun existingNonSeedEvenEmptyIsRejectedWithoutMutation() = off {
        val db=FineCoachDatabaseFactory.create(context)
        // Force creation of an ordinary user database.
        db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY); db.close()
        var failed=false
        try { S1DebugSeed.load(context) } catch (_: IllegalStateException) { failed=true }
        assertTrue(failed)
        val reopened=FineCoachDatabaseFactory.create(context)
        try { assertNull(reopened.storeMetadataDao().find(S1DebugSeed.DATASET_KEY)); assertEquals(0,S1DebugSeed.businessRows(reopened)) }
        finally { reopened.close() }
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
