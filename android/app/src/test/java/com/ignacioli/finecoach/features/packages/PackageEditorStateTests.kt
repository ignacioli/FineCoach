// fictional-data: in-memory Room data and invented students/packages only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.features.packages.CoursePackageEditorState
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.repository.*
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.ZoneId

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class PackageEditorStateTests {
    private lateinit var db: FineCoachDatabase
    private lateinit var useCases: CreditUseCases
    private lateinit var repository: CoursePackageRepository
    private var studentID = StudentID.parse("10000000-0000-4000-8000-000000000001")
    private lateinit var state: CoursePackageEditorState
    private val clock = AppClock { Instant.parse("2026-11-11T00:00:00Z") }
    private val zone = ZoneId.of("UTC")
    @Before fun prepare() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), FineCoachDatabase::class.java)
            .allowMainThreadQueries().build()
        val ids = SequentialIDGenerator()
        studentID = StudentUseCases(StudentRepository(db, clock), clock, ids)
            .create(StudentDraft("虚构学员", StudentSex.undisclosed)).requireSuccess().studentID
        repository = CoursePackageRepository(db, clock, ids, zone)
        useCases = CreditUseCases(repository, clock, ids, zone)
        state = CoursePackageEditorState(studentID, useCases, clock, zone)
    }
    @After fun close() { db.close() }
    @Test fun reloadConfirmationPromptsWithoutEndingCurrentPackage() = runBlocking {
        val old = useCases.createActivePackage(studentID, "虚构旧课包", 5).requireSuccess().requireSaved()
        state.name = "虚构新课包"
        state.saveWithoutConfirmation()
        assertEquals(old.coursePackageID, state.confirmation?.packageId)
        state.reloadConfirmation()
        assertEquals(old.coursePackageID, state.confirmation?.packageId)
        assertTrue(state.confirmation!!.message.contains("5"))
        assertFalse(state.saved)
        assertEquals(1, repository.list(studentID, clock.today(zone)).requireSuccess().size)
        assertEquals(CoursePackageStatus.active, repository.list(studentID, clock.today(zone)).requireSuccess().single().status)
        state.confirmShownPackage(old.coursePackageID)
        assertTrue(state.saved); assertNull(state.confirmation)
        val packages = repository.list(studentID, clock.today(zone)).requireSuccess()
        assertEquals(2, packages.size)
        assertEquals(CoursePackageStatus.ended, packages.single { it.coursePackageID == old.coursePackageID }.status)
    }
    @Test fun reloadWithoutCurrentPackageClearsConfirmationAndDoesNotCreate() = runBlocking {
        state.reloadConfirmation()
        assertTrue(state.ready); assertNull(state.confirmation); assertFalse(state.saved)
        assertTrue(repository.list(studentID, clock.today(zone)).requireSuccess().isEmpty())
    }
    @Test fun failedReloadPreservesOriginalContextBasedConfirmationAndDoesNotSave() = runBlocking {
        useCases.createActivePackage(studentID, "虚构旧课包", 5).requireSuccess().requireSaved()
        state.saveWithoutConfirmation()
        val pending = state.confirmation
        db.close()
        state.reloadConfirmation()
        assertTrue(state.loadError); assertFalse(state.ready)
        assertEquals(pending, state.confirmation); assertFalse(state.saved)
    }
}
