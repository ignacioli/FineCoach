package com.ignacioli.finecoach.core.application

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.*
import com.ignacioli.finecoach.core.domain.insight.*
import com.ignacioli.finecoach.core.domain.training.CompletedSession
import java.time.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Reads authoritative ledger balances; evaluates and publishes one immutable snapshot off the UI thread. */
class InsightUseCases(
    private val students: StudentRepositoryPort,
    private val progress: ProgressUseCases,
    private val appointments: AppointmentRepositoryPort,
    private val credits: CreditUseCases,
    private val assistedIDs: suspend () -> ApplicationResult<Set<StableExerciseID>>,
    private val activeSnoozes: (Instant, ZoneId) -> Set<String>,
) {
    suspend fun load(now: Instant, zone: ZoneId, studentID: StudentID? = null): ApplicationResult<List<Insight>> = withContext(Dispatchers.IO) {
        val records = when (val r = students.list(StudentQuery())) {
            is ApplicationResult.Failure -> return@withContext r
            is ApplicationResult.Success -> r.value.filter { it.lifecycle == StudentLifecycle.active && (studentID == null || it.studentID == studentID) }
        }
        val domain = mutableListOf<Student>(); val history = mutableListOf<CompletedSession>()
        val packages = mutableMapOf<StudentID, InsightEngine.PackageBalance>()
        for (record in records) {
            val student = StudentDraft(record.displayName, record.sex).makeStudent(record.studentID, record.createdAtUTC)
            domain += student
            when (val r = progress.load(record.studentID, student.displayName)) {
                is ApplicationResult.Failure -> return@withContext r
                is ApplicationResult.Success -> history += r.value.completed
            }
            val active = when (val r = credits.activePackage(record.studentID, now.atZone(zone).toLocalDate())) {
                is ApplicationResult.Failure -> return@withContext r
                is ApplicationResult.Success -> r.value
            }
            if (active != null) {
                val balance = when (val r = credits.balance(record.studentID, active.coursePackageID, now.atZone(zone).toLocalDate())) {
                    is ApplicationResult.Failure -> return@withContext r
                    is ApplicationResult.Success -> r.value
                }
                packages[record.studentID] = InsightEngine.PackageBalance(balance, active.endDate)
            }
        }
        val booked = when (val r = appointments.all()) {
            is ApplicationResult.Failure -> return@withContext r
            is ApplicationResult.Success -> r.value
        }
        val assisted = when (val r = assistedIDs()) {
            is ApplicationResult.Failure -> return@withContext r
            is ApplicationResult.Success -> r.value
        }
        ApplicationResult.Success(InsightEngine.evaluate(InsightEngine.Input(domain, packages, booked, history, activeSnoozes(now, zone), assisted), now, zone))
    }
}
