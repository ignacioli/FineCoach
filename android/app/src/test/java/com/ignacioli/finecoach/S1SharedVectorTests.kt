// fictional-data: only deterministic, invented S1 scenarios.
package com.ignacioli.finecoach

import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.core.domain.credit.CoursePackage
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class S1SharedVectorTests {
    @Test fun required() = run("s1-student-required-fields")
    @Test fun optional() = run("s1-student-optional-fields-roundtrip")
    @Test fun sameName() = run("s1-student-same-name-distinct-ids")
    @Test fun start() = run("s1-session-start-reuses-student-active-session")
    @Test fun validity() = run("s1-set-completion-validity")
    @Test fun copy() = run("s1-set-copy-stays-pending")
    @Test fun end() = run("s1-package-ending-retains-history")
    @Test fun replace() = run("s1-package-replacement-confirmation-gate")
    @Test fun debit() = run("s1-package-session-debit-idempotent")
    @Test fun refund() = run("s1-package-reopen-refunds-once")
    @Test fun recent() = run("s1-history-most-recent-completed-session")
    @Test fun statistics() = run("s1-statistics-completed-only")
    @Test fun balance() = run("s1-package-ledger-balance")

    @Suppress("UNCHECKED_CAST")
    private fun run(id: String) {
        val manifestFile = File(VectorFiles.root, "s1-manifest.json")
        check(digest(manifestFile) == "223d58c463fd4a24ba64981516cff05835b5c28eab42d38d6773cdb50cf06f12")
        val manifest = VectorJSON(manifestFile.readText()).parse() as Map<String, Any?>
        val entries = manifest["vectors"] as List<Map<String, Any?>>
        check(manifest["count"] == 13L && entries.size == 13 && entries.map { it["id"] }.toSet().size == 13)
        val entry = entries.single { it["id"] == id }
        val file = File(VectorFiles.root, entry["path"] as String)
        check(file.canonicalPath.startsWith(VectorFiles.root.canonicalPath + File.separator))
        check(digest(file) == entry["sha256"])
        val root = VectorJSON(file.readText()).parse() as Map<String, Any?>
        check(root["id"] == id)
        val given = root["given"] as Map<String, Any?>
        val now = Instant.parse((given["clock"] as Map<*, *>)["now"] as String)
        val worker = Executors.newSingleThreadExecutor()
        try { worker.submit(Callable { runBlocking {
            val context = ApplicationProvider.getApplicationContext<android.content.Context>()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
            val db = FineCoachDatabaseFactory.create(context)
            try {
                val state = given["state"] as Map<String, Any?>
                val ids = VectorIDs((state["ids"] as? List<String>).orEmpty())
                val graph = S1AppGraph(db, MutableAppClock(now), ids,
                    UUID.fromString(requireNotNull(db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)).value),
                    context, ZoneId.of(if (entry["androidAdapter"] == "credit-ledger.balance") "UTC" else given["timeZone"] as String))
                val op = entry["androidAdapter"] as String
                val actual = if (op == "credit-ledger.balance") null else scenario(op, state, graph, ids, now)
                SharedVectorRunner(false, setOf(op)) { dispatched, resolved ->
                    check(dispatched == op && resolved == state) { "S1 vector args mismatch" }
                    actual
                }.run(file.readBytes(), file.name)
                VectorFiles.report(file)
                println("S1-MANIFEST sha256=${digest(manifestFile)} count=13")
            } finally { db.close(); context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME) }
        } }).get() } finally { worker.shutdownNow() }
    }

    @Suppress("UNCHECKED_CAST")
    private suspend fun scenario(op: String, a: Map<String, Any?>, g: S1AppGraph, ids: VectorIDs, now: Instant): Any {
        fun draft(a: Map<String, Any?>) = StudentDraft(a["displayName"] as String, (a["sex"] as? String)?.let(StudentSex::valueOf),
            a["trainingGoal"] as? String ?: "", a["injuryNotes"] as? String ?: "", a["privateCoachNote"] as? String ?: "",
            a["phone"] as? String ?: "", a["wechatID"] as? String ?: "")
        fun fields(s: com.ignacioli.finecoach.core.domain.student.Student) = listOf(s.trainingGoal?.value, s.injuryNotes?.value,
            s.privateCoachNote?.value, s.phone?.value, s.wechatID?.value)
        fun set(input: Map<String, Any?>) = TrainingSet.makeDraft(ids.newTrainingSetID(), ids.newSessionExerciseID(), 0u, vectorInput(input), now)
        suspend fun student() = g.students.create(StudentDraft("虚构甲", StudentSex.female)).requireSuccess()
        suspend fun pkg(s: StudentID) = g.credits.createActivePackage(s, null, a["totalCredits"] as Long).requireSuccess().requireSaved()
        suspend fun complete(s: StudentID): SessionRecord {
            val session = g.active.startOrOpen(s).requireSuccess()
            val eid = ids.newSessionExerciseID()
            val training = TrainingSet.makeDraft(ids.newTrainingSetID(), eid, 0u, vectorInput(a["input"] as Map<String, Any?>), now).confirmed(now)
            val exercise = SessionExerciseRecord(eid, session.sessionID, 0u, ExerciseSourceKind.sessionOnly, null, "虚构动作",
                training.recordMode, null, null, listOf(training.toRecord()))
            val content = g.active.saveContent(SaveSessionContentCommand(session.sessionID, session.revision, emptyList(), listOf(exercise))).requireSuccess()
            return g.active.complete(CompleteSessionCommand(session.sessionID, content.session.revision, g.clock.now(), false)).requireSuccess()
        }
        return when (op) {
            "student.required" -> mapOf("errors" to (a["drafts"] as List<Map<String, Any?>>).map {
                try { draft(it).makeStudent(ids.newStudentID(), now); error("Expected domain failure") }
                catch (e: com.ignacioli.finecoach.core.domain.student.StudentDomainException) { e.code.name }
            })
            "student.optional" -> {
                val filled = draft(a).makeStudent(ids.newStudentID(), now)
                val cleared = filled.updateFromDraft(StudentDraft(a["displayName"] as String, StudentSex.female), now)
                mapOf("filled" to fields(filled), "cleared" to fields(cleared), "sameID" to (filled.studentID == cleared.studentID))
            }
            "student.same-name" -> {
                val x = draft(a).makeStudent(ids.newStudentID(), now); val y = draft(a).makeStudent(ids.newStudentID(), now)
                mapOf("sameName" to (x.displayName == y.displayName), "distinctIDs" to (x.studentID != y.studentID))
            }
            "session.start" -> {
                val s = student(); val other = student()
                val x = g.active.startOrOpen(s.studentID).requireSuccess(); val y = g.active.startOrOpen(s.studentID).requireSuccess()
                val z = g.active.startOrOpen(other.studentID).requireSuccess()
                mapOf("sameID" to (x.sessionID == y.sessionID), "isolated" to (z.sessionID != x.sessionID), "activeCount" to g.sessions.listActiveSessions().requireSuccess().size.toLong())
            }
            "set.validity" -> mapOf("outcomes" to (a["inputs"] as List<Map<String, Any?>>).map {
                try { set(it).confirmed(now).state.name } catch (e: DomainException) { e.error.name }
            })
            "set.copy" -> {
                val original = set(a["input"] as Map<String, Any?>).confirmed(now)
                val copied = original.copiedAsPending(ids.newTrainingSetID(), 1u, now)
                mapOf("state" to copied.state.name, "contributes" to copied.contributesToStatistics,
                    "distinctID" to (original.trainingSetID != copied.trainingSetID), "completedAtUTC" to copied.completedAtUTC)
            }
            "package.end" -> {
                val original = CoursePackage(ids.newCoursePackageID(), ids.newStudentID(), totalCredits = a["totalCredits"] as Long, createdAtUTC = now, updatedAtUTC = now)
                val ended = original.ending(now)
                mapOf("status" to ended.status.name, "totalCredits" to ended.totalCredits, "sameID" to (original.coursePackageID == ended.coursePackageID))
            }
            "package.replace" -> {
                val s = student(); val old = pkg(s.studentID); val ctx = g.credits.loadCreationContext(s.studentID)
                val blocked = g.credits.createPackageWithContext(ctx, null, a["totalCredits"] as Long).requireSuccess() is SaveCoursePackageResult.RequiresReconfirmation
                g.credits.cancelPackageReplacement()
                val cancelCount = g.credits.packages(s.studentID).requireSuccess().size
                g.credits.createPackageWithContext(ctx, null, a["totalCredits"] as Long, confirmedByCoach = true).requireSuccess().requireSaved()
                val all = g.credits.packages(s.studentID).requireSuccess()
                mapOf("blocked" to blocked, "countAfterCancel" to cancelCount.toLong(), "countAfterConfirm" to all.size.toLong(),
                    "oldStatus" to all.single { it.coursePackageID == old.coursePackageID }.status.name, "activeCount" to all.count { it.status == CoursePackageStatus.active }.toLong())
            }
            "package.debit" -> {
                val s = student(); val p = pkg(s.studentID); val session = complete(s.studentID)
                repeat(2) { g.finisher.debitAdhoc(session.sessionID, p.coursePackageID).requireSuccess() }
                mapOf("sessionState" to session.state.name, "balance" to g.credits.balance(s.studentID, p.coursePackageID).requireSuccess(),
                    "ledgerCount" to g.credits.ledger(s.studentID).requireSuccess().size.toLong())
            }
            "package.refund" -> {
                val s = student(); val p = pkg(s.studentID); val sid = ids.newSessionID()
                g.credits.debitOnSessionComplete(p.coursePackageID, sid).requireSuccess()
                val x = g.packageRepository.refundOnSessionReopen(RefundOnSessionReopenCommand(sid, now)).requireSuccess()
                val y = g.packageRepository.refundOnSessionReopen(RefundOnSessionReopenCommand(sid, now)).requireSuccess()
                val none = g.packageRepository.refundOnSessionReopen(RefundOnSessionReopenCommand(ids.newSessionID(), now)).requireSuccess()
                mapOf("balance" to g.credits.balance(s.studentID, p.coursePackageID).requireSuccess(), "ledgerCount" to g.credits.ledger(s.studentID).requireSuccess().size.toLong(),
                    "sameRefundID" to (x?.creditAdjustmentID == y?.creditAdjustmentID), "noDebitRefund" to none)
            }
            "history.recent" -> {
                val s = student(); val empty = g.historyRepository.list(HistoryQuery(studentID = s.studentID)).requireSuccess().size
                complete(s.studentID)
                (g.clock as MutableAppClock).advanceSeconds(60)
                ids.index = 20
                complete(s.studentID)
                val list = g.historyRepository.list(HistoryQuery(studentID = s.studentID)).requireSuccess()
                mapOf("emptyCount" to empty.toLong(), "count" to list.size.toLong(), "latestID" to list.first().sessionID.value.lowercase())
            }
            "set.statistics" -> {
                val completed = set(a["input"] as Map<String, Any?>).confirmed(now)
                val pending = completed.copiedAsPending(ids.newTrainingSetID(), 1u, now)
                val draft = set(a["input"] as Map<String, Any?>).copy(sessionExerciseID = completed.sessionExerciseID, orderIndex = 2u)
                val base = Session.start(ids.newSessionID(), ids.newStudentID(), emptySet(), now)
                val session = base.copy(exercises = listOf(
                    SessionExercise(completed.sessionExerciseID, base.sessionID, 0u, ExerciseSourceKind.sessionOnly, null,
                        com.ignacioli.finecoach.core.domain.common.NormalizedName.parse("虚构动作"), RecordMode.weightReps, null, null, listOf(completed, pending, draft))))
                mapOf("count" to session.completedSetCount.toLong(), "volume" to session.statistics.ordinaryTrainingVolume?.canonicalString)
            }
            else -> error("Unmapped S1 op")
        }
    }
    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it.toInt() and 255) }
}

internal fun vectorInput(a: Map<String, Any?>) = TrainingSetInput(RecordMode.valueOf(a["recordMode"] as String),
    a["weightValue"] as? String, a["repetitionCount"] as? String, a["durationSeconds"] as? String,
    MeasurementUnit.valueOf(a["unit"] as String), SetSide.valueOf(a["side"] as String), a["leftValue"] as? String,
    a["rightValue"] as? String, a["distanceValue"] as? String, a["speedValue"] as? String, a["resistanceValue"] as? String)

internal class VectorIDs(val values: List<String>) : StableIDGenerator {
    var index = 0
    private fun next() = values[index++]
    override fun newStudentID() = StudentID.parse(next())
    override fun newCoursePackageID() = CoursePackageID.parse(next())
    override fun newCreditAdjustmentID() = CreditAdjustmentID.parse(next())
    override fun newSessionID() = SessionID.parse(next())
    override fun newTemplateID() = TemplateID.parse(next())
    override fun newSectionID() = SectionID.parse(next())
    override fun newSessionExerciseID() = SessionExerciseID.parse(next())
    override fun newTemplateExerciseID() = TemplateExerciseID.parse(next())
    override fun newTrainingSetID() = TrainingSetID.parse(next())
    override fun newExerciseID() = StableExerciseID.parse(next())
}
