// fictional-data: synthetic student, course credits and completed training only.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.features.students.StudentDetailViewModel
import com.ignacioli.finecoach.storage.repository.StudentRepository
import java.time.Instant

internal class StudentDetailConformanceFixture : AutoCloseable {
    val room = T009Fixture()
    lateinit var state: StudentDetailViewModel
        private set
    init {
        room.test {
            room.now = Instant.parse("2026-09-25T19:00:00Z")
            val students = StudentUseCases(StudentRepository(room.db, room.clock), room.clock, room.ids)
            val student = room.ok(students.create(StudentDraft("王小明", StudentSex.male,
                trainingGoal = "增肌", injuryNotes = "左膝旧伤，避免深屈膝跳跃")))
            val started = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(student.studentID,
                setOf(BodyPart.thighs, BodyPart.glutes), room.now)))
            val exerciseID = room.ids.newSessionExerciseID()
            val sets = (0 until 12).map { index ->
                TrainingSet.makeDraft(room.ids.newTrainingSetID(), exerciseID, index.toUInt(),
                    TrainingSetInput(RecordMode.weightReps, weightValue = "20", repetitionCount = "10",
                        unit = MeasurementUnit.kilograms), room.now).confirmed(room.now)
            }
            val exercise = SessionExercise(exerciseID, started.sessionID, 0u, ExerciseSourceKind.sessionOnly,
                null, NormalizedName.parse("虚构腿部训练"), RecordMode.weightReps, null, null, sets)
            val content = room.ok(room.sessions.saveContent(SaveSessionContentCommand(started.sessionID,
                started.revision, emptyList(), listOf(exercise.toRecord()))))
            room.finish(content)
            room.now = Instant.parse("2026-09-26T19:00:00Z")
            val pkg = (room.ok(room.credits.createActivePackage(student.studentID, "虚构课包", 20,
                endDate = java.time.LocalDate.of(2026, 12, 31))) as SaveCoursePackageResult.Saved).record
            room.ok(room.credits.recordManualCorrection(pkg.coursePackageID, CreditDirection.debit, 12, "虚构历史课时"))
            state = StudentDetailViewModel(student.studentID, students, room.sessions, room.credits,
                room.history, room.clock, room.zone)
            state.reload()
            check(state.uiState.recent?.completedSetCount == 12)
            check(state.uiState.packageSummary?.balance == 8L)
            check(state.uiState.showsStartTraining && state.uiState.errorMessage == null)
        }
    }
    override fun close() = room.close()
}
