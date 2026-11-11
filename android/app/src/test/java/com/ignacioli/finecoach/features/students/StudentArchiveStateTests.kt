// fictional-data: in-memory Room data and invented students only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.features.students.DeleteStudentViewModel
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.repository.StudentRepository
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class StudentArchiveStateTests {
    private lateinit var db: FineCoachDatabase
    private lateinit var useCases: StudentUseCases
    @Before fun prepare() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), FineCoachDatabase::class.java)
            .allowMainThreadQueries().build()
        val clock = AppClock { Instant.parse("2026-11-11T00:00:00Z") }
        useCases = StudentUseCases(StudentRepository(db, clock), clock, SequentialIDGenerator())
    }
    @After fun close() { db.close() }
    @Test fun archiveSucceedsOnlyAfterDurableMutation() = runBlocking {
        val student = useCases.create(StudentDraft("虚构学员", StudentSex.undisclosed)).requireSuccess()
        val state = DeleteStudentViewModel(student.studentID, useCases)
        assertTrue(state.archive())
        assertEquals(StudentLifecycle.archived, useCases.find(student.studentID).requireSuccess()!!.lifecycle)
        assertFalse(state.uiState.isDeleting); assertNull(state.uiState.errorMessage)
        assertFalse(state.uiState.didDelete)
    }
    @Test fun missingStudentArchiveReportsFailureAndFinishesBusyState() = runBlocking {
        val state = DeleteStudentViewModel(StudentID.parse("10000000-0000-4000-8000-000000000001"), useCases)
        assertFalse(state.archive())
        assertNotNull(state.uiState.errorMessage); assertFalse(state.uiState.isDeleting)
        assertFalse(state.uiState.didDelete)
    }
}
