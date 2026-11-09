package com.ignacioli.finecoach

import android.content.Context
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.repository.*
import com.ignacioli.finecoach.features.session.*
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Process-owned database; tests inject their isolated file database and own its lifetime. */
class S1AppGraph(val database: FineCoachDatabase, val clock: AppClock, val ids: StableIDGenerator,
    val generation: UUID, val context: Context, val zone: ZoneId = ZoneId.systemDefault()) {
    val studentRepository = StudentRepository(database, clock)
    val students = StudentUseCases(studentRepository, clock, ids)
    val exerciseRepository = ExerciseRepository(database, ExerciseCatalogLoader(context.assets), clock)
    val exercises = ExerciseUseCases(exerciseRepository, clock, ids)
    val sessions = SessionRepository(database, clock, ids, generation, exerciseRepository)
    val templateRepository = TemplateRepository(database, clock, ids, generation)
    val templates = TemplateUseCases(templateRepository, clock)
    val packageRepository = CoursePackageRepository(database, clock, ids, zone)
    val credits = CreditUseCases(packageRepository, clock, ids, zone)
    val historyRepository = HistoryRepository(database, clock, generation, zone)
    val history = HistoryUseCases(historyRepository, sessions, historyRepository, clock)
    val rests = RestTimerStore(clock)
    val active = ActiveSessionUseCases(sessions, clock, ids)
    val recovery = RecoveryCoordinator(sessions, clock)
    val finisher = FinishSessionUseCases(sessions, active, credits, historyRepository, clock, zone)
}

internal object S1Runtime {
    private val gate = Mutex()
    private var graph: S1AppGraph? = null
    suspend fun open(context: Context): ApplicationResult<S1AppGraph> = gate.withLock {
        graph?.let { return@withLock ApplicationResult.Success(it) }
        withContext(Dispatchers.IO) {
            val database = FineCoachDatabaseFactory.create(context)
            try {
                val generation = UUID.fromString(requireNotNull(database.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)).value)
                val value = S1AppGraph(database, AppClock { Instant.now() }, S1IDs(), generation, context.applicationContext)
                graph = value
                ApplicationResult.Success(value)
            } catch (cancelled: kotlinx.coroutines.CancellationException) { database.close(); throw cancelled
            } catch (_: Exception) { database.close(); ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed)) }
        }
    }
}

private class S1IDs : StableIDGenerator {
    override fun newStudentID() = StudentID.fromUUID(UUID.randomUUID())
    override fun newCoursePackageID() = CoursePackageID.fromUUID(UUID.randomUUID())
    override fun newCreditAdjustmentID() = CreditAdjustmentID.fromUUID(UUID.randomUUID())
    override fun newSessionID() = SessionID.fromUUID(UUID.randomUUID())
    override fun newTemplateID() = TemplateID.fromUUID(UUID.randomUUID())
    override fun newSectionID() = SectionID.fromUUID(UUID.randomUUID())
    override fun newSessionExerciseID() = SessionExerciseID.fromUUID(UUID.randomUUID())
    override fun newTemplateExerciseID() = TemplateExerciseID.fromUUID(UUID.randomUUID())
    override fun newTrainingSetID() = TrainingSetID.fromUUID(UUID.randomUUID())
    override fun newExerciseID() = StableExerciseID.parse(UUID.randomUUID().toString())
}

internal suspend fun S1AppGraph.packageOwner(id: CoursePackageID): ApplicationResult<StudentID?> {
    when (val listed = students.list(StudentQuery(includeArchived = true))) {
        is ApplicationResult.Failure -> return listed
        is ApplicationResult.Success -> for (student in listed.value) when (val packages = packageRepository.list(student.studentID, clock.today(zone))) {
            is ApplicationResult.Failure -> return packages
            is ApplicationResult.Success -> if (packages.value.any { it.coursePackageID == id }) return ApplicationResult.Success(student.studentID)
        }
    }
    return ApplicationResult.Success(null)
}
