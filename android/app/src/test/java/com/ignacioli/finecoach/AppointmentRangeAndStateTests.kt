// fictional-data: isolated Room appointments and fixed Asia/Shanghai date ranges only.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.features.appointments.AppointmentListState
import com.ignacioli.finecoach.features.calendar.CalendarUiState
import com.ignacioli.finecoach.storage.repository.StudentRepository
import java.time.LocalDate
import kotlinx.coroutines.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AppointmentRangeAndStateTests {
    private lateinit var f: S2ScreenFixture
    @Before fun open() { f = S2ScreenFixture(LocalDate.of(2026,9,1),false) }
    @After fun close() { f.close() }
    @Test fun inclusiveRangeKeepsBothBoundariesAndExcludesOutsideDays() = f.room.test {
        val first = f.add(2,"09:00",day=f.date)
        val last = f.add(2,"09:00",day=f.date.withDayOfMonth(30))
        val before = f.add(2,"09:00",day=f.date.minusDays(1))
        val after = f.add(2,"09:00",day=f.date.plusMonths(1))
        val rows = f.room.ok(f.repository.inDateRange(f.date,f.date.withDayOfMonth(30)))
        assertTrue(rows.containsAll(listOf(first,last)))
        assertTrue(rows.none { it.id == before.id || it.id == after.id })
        assertEquals(rows.sortedWith(compareBy({ it.date },{ it.startTime },{ it.id.toString() })),rows)
        val names = f.room.ok(f.students.displayNames(setOf(f.room.studentID(2),f.room.studentID(999))))
        assertEquals(mapOf(f.room.studentID(2) to "张伟"),names)
    }
    @Test fun todayAndCalendarUseOnlyRequestedRangeAndOneDistinctNameBatch() = f.room.test {
        val ranges = mutableListOf<Pair<LocalDate,LocalDate>>()
        val ids = mutableListOf<Set<StudentID>>()
        val repository = object : AppointmentRepositoryPort by f.repository {
            override suspend fun all(): ApplicationResult<List<com.ignacioli.finecoach.core.domain.appointment.Appointment>> = error("Full appointment scan forbidden")
            override suspend fun inDateRange(first: LocalDate,last: LocalDate): ApplicationResult<List<com.ignacioli.finecoach.core.domain.appointment.Appointment>> {
                ranges += first to last; return f.repository.inDateRange(first,last)
            }
        }
        val real = StudentRepository(f.room.db,f.room.clock)
        val students = StudentUseCases(object : StudentRepositoryPort by real {
            override suspend fun find(studentID: StudentID): ApplicationResult<StudentRecord?> = error("N+1 forbidden")
            override suspend fun displayNames(requested: Set<StudentID>): ApplicationResult<Map<StudentID,String>> {
                ids += requested; return real.displayNames(requested)
            }
        },f.room.clock,f.room.ids)
        val state = AppointmentListState(AppointmentUseCases(repository),students,f.room.clock,f.zone)
        state.load()
        assertEquals(listOf(f.date to f.date),ranges)
        assertEquals(listOf(setOf(f.room.studentID(2),f.room.studentID(3))),ids)
        assertEquals(2,state.rows.size); assertNull(state.error)
        val october = f.add(2,"09:00",day=f.date.plusMonths(1))
        val calendar = CalendarUiState(state)
        calendar.load(); calendar.shiftMonth(1); calendar.load()
        assertEquals(listOf(f.date to f.date, f.date to f.date.withDayOfMonth(30), f.date.plusMonths(1) to LocalDate.of(2026,10,31)),ranges)
        assertEquals(3,ids.size); assertEquals(listOf(october),state.rows)
    }
    @Test fun olderRangeCompletingLastCannotReplaceNewerRows() = runBlocking {
        val september = f.room.ok(f.repository.inDateRange(f.date, f.date.withDayOfMonth(30)))
        val octoberRow = f.add(2, "09:00", day = f.date.plusMonths(1))
        val releaseOlder = CompletableDeferred<Unit>()
        val repository = object : AppointmentRepositoryPort by f.repository {
            override suspend fun inDateRange(first: LocalDate, last: LocalDate): ApplicationResult<List<com.ignacioli.finecoach.core.domain.appointment.Appointment>> {
                if (first.monthValue == 9) {
                    releaseOlder.await()
                    return ApplicationResult.Success(september)
                }
                return ApplicationResult.Success(listOf(octoberRow))
            }
        }
        val state = AppointmentListState(AppointmentUseCases(repository), f.students, f.room.clock, f.zone)
        val older = launch(start = CoroutineStart.UNDISPATCHED) { state.load(f.date, f.date.withDayOfMonth(30)) }
        state.load(f.date.plusMonths(1), f.date.plusMonths(1).withDayOfMonth(31))
        assertTrue(state.loaded); assertEquals(listOf(octoberRow), state.rows)
        val names = state.names
        releaseOlder.complete(Unit); older.join()
        assertTrue(state.loaded); assertNull(state.error)
        assertEquals(listOf(octoberRow), state.rows); assertEquals(names, state.names)
    }
    @Test fun sameRangeLoadingRequestCompletingLastCannotReplaceNewerResult() = runBlocking {
        val initial = f.room.ok(f.repository.inDateRange(f.date, f.date))
        val releaseOlder = CompletableDeferred<Unit>()
        var attempts = 0
        val repository = object : AppointmentRepositoryPort by f.repository {
            override suspend fun inDateRange(first: LocalDate, last: LocalDate): ApplicationResult<List<com.ignacioli.finecoach.core.domain.appointment.Appointment>> {
                if (++attempts == 1) { releaseOlder.await(); return ApplicationResult.Success(initial) }
                return ApplicationResult.Success(initial.take(1))
            }
        }
        val state = AppointmentListState(AppointmentUseCases(repository), f.students, f.room.clock, f.zone)
        val older = launch(start = CoroutineStart.UNDISPATCHED) { state.load() }
        state.load()
        val names = state.names
        assertTrue(state.loaded); assertEquals(initial.take(1), state.rows)
        releaseOlder.complete(Unit); older.join()
        assertTrue(state.loaded); assertNull(state.error)
        assertEquals(initial.take(1), state.rows); assertEquals(names, state.names)
    }
    @Test fun sameRangeFailuresKeepLoadedRowsAndNames() = runBlocking {
        var failQuery = false
        var failNames = false
        val failure = ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
        val repository = object : AppointmentRepositoryPort by f.repository {
            override suspend fun inDateRange(first: LocalDate, last: LocalDate): ApplicationResult<List<com.ignacioli.finecoach.core.domain.appointment.Appointment>> =
                if (failQuery) failure else f.repository.inDateRange(first, last)
        }
        val real = StudentRepository(f.room.db, f.room.clock)
        val students = StudentUseCases(object : StudentRepositoryPort by real {
            override suspend fun displayNames(ids: Set<StudentID>): ApplicationResult<Map<StudentID, String>> =
                if (failNames) failure else real.displayNames(ids)
        }, f.room.clock, f.room.ids)
        val state = AppointmentListState(AppointmentUseCases(repository), students, f.room.clock, f.zone)
        state.load()
        val rows = state.rows; val names = state.names
        failQuery = true
        state.load()
        assertTrue(state.loaded); assertEquals(rows, state.rows); assertEquals(names, state.names); assertEquals(failure.error, state.error)
        failQuery = false; failNames = true
        state.load()
        assertTrue(state.loaded); assertEquals(rows, state.rows); assertEquals(names, state.names); assertEquals(failure.error, state.error)
    }
    @Test fun todayRolloverClearsOldRowsWhileNewDateIsLoading() = runBlocking {
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        val repository = object : AppointmentRepositoryPort by f.repository {
            override suspend fun inDateRange(first: LocalDate, last: LocalDate): ApplicationResult<List<com.ignacioli.finecoach.core.domain.appointment.Appointment>> {
                if (first == f.date.plusDays(1)) { entered.complete(Unit); release.await() }
                return f.repository.inDateRange(first, last)
            }
        }
        val state = AppointmentListState(AppointmentUseCases(repository), f.students, f.room.clock, f.zone)
        state.load(); assertTrue(state.rows.isNotEmpty())
        f.room.time = f.room.time.plusSeconds(24 * 60 * 60)
        val reload = launch(start = CoroutineStart.UNDISPATCHED) { state.load() }
        assertTrue(entered.isCompleted)
        assertFalse(state.loaded); assertTrue(state.rows.isEmpty()); assertTrue(state.names.isEmpty())
        release.complete(Unit); reload.join()
        assertTrue(state.loaded); assertTrue(state.rows.isEmpty())
    }
}
