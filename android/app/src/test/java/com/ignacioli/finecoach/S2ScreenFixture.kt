// fictional-data: synthetic appointments and names from the approved boards; fixed Asia/Shanghai clock.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.features.appointments.*
import com.ignacioli.finecoach.features.today.TodayUiState
import com.ignacioli.finecoach.storage.repository.*
import java.time.*
import java.util.UUID

internal class S2ScreenFixture(val date: LocalDate = LocalDate.of(2025, 8, 31), todayHero: Boolean = true) : AutoCloseable {
    val room = T008Fixture()
    val zone = ZoneId.of("Asia/Shanghai")
    val students = StudentUseCases(StudentRepository(room.db, room.clock), room.clock, room.ids)
    private val generation = run { var value: UUID? = null; room.test { value = room.generation }; checkNotNull(value) }
    private val sessions = run { var value: SessionRepository? = null; room.test { value = room.sessions }; checkNotNull(value) }
    val repository = AppointmentRepository(room.db, room.clock, room.ids, generation, sessions, zone)
    val appointments = AppointmentUseCases(repository)
    val list = AppointmentListState(appointments, students, room.clock, zone)
    val training = TodayUiState(sessions, students, room.clock, zone)
    private var seededSessionID: SessionID? = null
    val sessionID: SessionID get() = checkNotNull(seededSessionID)
    init {
        room.test {
            listOf("王小明", "张伟", "李娜", "赵强").forEachIndexed { i, name ->
                room.student(i + 1)
                room.db.openHelper.writableDatabase.execSQL("UPDATE students SET displayName = ? WHERE id = ?", arrayOf(name, room.studentID(i + 1).value))
            }
            room.time = date.atTime(12, 0).atZone(zone).toInstant()
            if (todayHero) {
                room.time = room.time.minusSeconds(32 * 60)
                seededSessionID = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(room.studentID(1), setOf(BodyPart.thighs), room.time))).sessionID
                room.time = room.time.plusSeconds(32 * 60)
                add(2, "15:00", setOf(BodyPart.thighs))
                add(3, "17:30", setOf(BodyPart.chest))
                add(4, "19:00", setOf(BodyPart.back))
                for (n in 1..3) {
                    val row = add(n, "0${n + 6}:00")
                    room.ok(appointments.cancel(row.id))
                }
            } else {
                add(2, "15:00", setOf(BodyPart.thighs, BodyPart.glutes))
                add(3, "17:30", setOf(BodyPart.chest, BodyPart.shoulders))
                for (d in listOf(4, 8, 12, 15, 20, 22, 29)) add(2, "09:00", day = date.withDayOfMonth(d))
            }
        }
    }
    suspend fun add(n: Int, time: String, focus: Set<BodyPart> = emptySet(), day: LocalDate = date): Appointment =
        room.ok(appointments.createSingle(Appointment(UUID.randomUUID(), room.studentID(n), date = day,
            startTime = LocalTime.parse(time), trainingFocus = focus, reminderEnabled = false,
            createdAtUTC = room.time, updatedAtUTC = room.time), overrideConflict = true)).single()
    override fun close() = room.close()
}
