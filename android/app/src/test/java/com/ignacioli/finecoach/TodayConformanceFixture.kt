// fictional-data: synthetic student/session matching the approved example where domain-valid.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.features.today.TodayUiState
import com.ignacioli.finecoach.storage.repository.StudentRepository
import java.time.LocalDate
import java.time.ZoneId

internal class TodayConformanceFixture : AutoCloseable {
    val room = T008Fixture()
    private var seededSessionID: SessionID? = null
    val sessionID: SessionID get() = checkNotNull(seededSessionID)
    lateinit var state: TodayUiState
        private set
    init {
        room.test {
            room.student(1)
            room.db.openHelper.writableDatabase.execSQL("UPDATE students SET displayName = ?", arrayOf("王小明"))
            val fixedNow = LocalDate.of(2025, 8, 31).atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
            room.time = fixedNow.minusSeconds(32 * 60)
            seededSessionID = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(
                room.studentID(1), setOf(BodyPart.thighs), room.time))).sessionID
            room.time = fixedNow
            state = TodayUiState(room.sessions, StudentUseCases(StudentRepository(room.db, room.clock), room.clock, room.ids), room.clock)
        }
    }
    override fun close() = room.close()
}
