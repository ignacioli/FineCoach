// fictional-data: synthetic S1 board students, packages and active session.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.features.students.StudentListViewModel
import com.ignacioli.finecoach.storage.repository.*
import java.time.ZoneId

internal class StudentListConformanceFixture : AutoCloseable {
    val room = T008Fixture()
    lateinit var state: StudentListViewModel
        private set
    private var seededSessionID: SessionID? = null
    val sessionID: SessionID get() = checkNotNull(seededSessionID)
    init {
        room.test {
            val students = StudentUseCases(StudentRepository(room.db, room.clock), room.clock, room.ids)
            val zone = ZoneId.systemDefault()
            val credits = CreditUseCases(CoursePackageRepository(room.db, room.clock, room.ids, zone), room.clock, room.ids, zone)
            val active = listOf("王小明", "张伟", "李娜").map { name ->
                room.ok(students.create(StudentDraft(name, StudentSex.undisclosed)))
            }
            for ((index, balance) in listOf(0 to 12L, 2 to 8L)) {
                check(room.ok(credits.createActivePackage(active[index].studentID, "虚构课包", balance)) is SaveCoursePackageResult.Saved)
            }
            for (name in listOf("虚构归档甲", "虚构归档乙")) {
                room.ok(students.archive(room.ok(students.create(StudentDraft(name, StudentSex.undisclosed))).studentID))
            }
            room.time = room.now.minusSeconds(32 * 60)
            seededSessionID = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(active[0].studentID, nowUTC = room.time))).sessionID
            room.time = room.now
            state = StudentListViewModel(students, sessionRepository = room.sessions, creditUseCases = credits, clock = room.clock, zoneId = zone)
            state.reload()
            check(state.uiState.archivedCount == 2 && state.uiState.students.size == 3)
        }
    }
    override fun close() = room.close()
}
