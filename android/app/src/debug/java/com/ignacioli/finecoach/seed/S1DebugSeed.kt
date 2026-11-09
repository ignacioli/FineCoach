// fictional-data: all IDs, people, notes and training values are invented walkthrough fixtures.
package com.ignacioli.finecoach.seed

import android.content.Context
import com.ignacioli.finecoach.S1AppGraph
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.core.domain.template.TemplatePlannedSet
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.StoreMetadata
import java.io.RandomAccessFile
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Explicit shell-only installation; never called by Application.onCreate or by Release code. */
internal object S1DebugSeed {
    const val VERSION = 1
    const val PREFIX = "s1_debug_seed."
    const val VERSION_KEY = "${PREFIX}version"
    const val STATUS_KEY = "${PREFIX}status"
    const val ROWS_KEY = "${PREFIX}rows"
    const val DATASET_KEY = "${PREFIX}dataset"
    const val DATASET = "fictional-s1-coach-core-v1"
    val NOW: Instant = Instant.parse("2026-11-09T00:00:00Z")
    val studentIDs = (1..7).map { StudentID.parse(uuid(it)) }
    fun uuid(n: Int) = "72000000-0000-4000-8000-${n.toString().padStart(12, '0')}"

    suspend fun load(context: Context, scenario: String = "multi"): SeedResult = withContext(Dispatchers.IO) {
        require(scenario in setOf("empty", "single", "multi"))
        val app = context.applicationContext
        require(!context.isDeviceProtectedStorage && !app.isDeviceProtectedStorage)
        // Cross-process lock protects explicit installers; it is not a product startup hook.
        RandomAccessFile(java.io.File(app.filesDir, "s1-debug-seed.lock"), "rw").channel.use { channel ->
            val lock = checkNotNull(channel.tryLock()) { "Seed installer is already running" }
            try {
                val existed = app.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).exists()
                if (existed) preflight(app, scenario)
                val database = FineCoachDatabaseFactory.create(app)
                try {
                    val metadata = database.storeMetadataDao()
                    if (existed) {
                        check(metadata.find("${PREFIX}scenario")?.value == scenario) { "Seed scenario mismatch" }
                        // Even an empty non-seed database belongs to its user. Never adopt or clear it.
                        check(metadata.find(DATASET_KEY)?.value == DATASET) { "Non-seed database rejected" }
                        check(metadata.find(VERSION_KEY)?.value == VERSION.toString()) { "Seed version mismatch" }
                        check(metadata.find(STATUS_KEY)?.value == "complete") { "Incomplete seed rejected" }
                        return@withContext storedResult(database)
                    }
                    check(businessRows(database) == 0) { "Non-empty database rejected" }
                    val generation = UUID.fromString(checkNotNull(metadata.find(FineCoachDatabaseFactory.GENERATION_KEY)).value)
                    database.runInTransaction {
                        metadata.insert(StoreMetadata(DATASET_KEY, DATASET))
                        metadata.insert(StoreMetadata(VERSION_KEY, VERSION.toString()))
                        metadata.insert(StoreMetadata(STATUS_KEY, "installing"))
                        metadata.insert(StoreMetadata("${PREFIX}scenario", scenario))
                    }
                    val graph = graph(database, app, generation)
                    if (scenario != "empty") populate(graph, scenario)
                    verifyInitial(graph, scenario)
                    val ownedMetadata = database.openHelper.readableDatabase.query(
                        "SELECT COUNT(*) FROM store_metadata WHERE substr(`key`,1,?)=?", arrayOf<Any>(PREFIX.length, PREFIX)
                    ).use { it.moveToFirst(); it.getInt(0) }
                    val rows = businessRows(database) + ownedMetadata + 1 // include the not-yet-inserted rows key
                    check(rows > 0)
                    // Success is visible only after all repository writes and integrity reads succeeded.
                    database.runInTransaction {
                        metadata.insert(StoreMetadata(ROWS_KEY, rows.toString()))
                        database.openHelper.writableDatabase.execSQL(
                            "UPDATE store_metadata SET value = ? WHERE `key` = ?", arrayOf("complete", STATUS_KEY))
                    }
                    storedResult(database)
                } finally { database.close() }
            } finally { lock.release() }
        }
    }

    // Inspect ownership before Room can run a migration or otherwise write an existing file.
    private fun preflight(context: Context, scenario: String) {
        android.database.sqlite.SQLiteDatabase.openDatabase(
            context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).absolutePath, null,
            android.database.sqlite.SQLiteDatabase.OPEN_READONLY,
        ).use { raw ->
            check(raw.version == 2) { "Non-seed schema rejected" }
            val expected = mapOf(DATASET_KEY to DATASET, VERSION_KEY to VERSION.toString(),
                STATUS_KEY to "complete", "${PREFIX}scenario" to scenario)
            for ((key, value) in expected) {
                raw.rawQuery("SELECT value FROM store_metadata WHERE `key`=?", arrayOf(key)).use {
                    check(it.moveToFirst() && it.getString(0) == value) { "Non-seed or incomplete database rejected" }
                }
            }
        }
    }

    /** Reopen verification is read-only and permits walkthrough edits/deletions after initialization. */
    fun storedResult(database: FineCoachDatabase): SeedResult {
        val metadata = database.storeMetadataDao()
        check(metadata.find(DATASET_KEY)?.value == DATASET)
        check(metadata.find(VERSION_KEY)?.value == VERSION.toString())
        check(metadata.find(STATUS_KEY)?.value == "complete")
        val rows = checkNotNull(metadata.find(ROWS_KEY)?.value?.toIntOrNull())
        check(rows > 0)
        return SeedResult(VERSION, rows)
    }

    fun graph(db: FineCoachDatabase, context: Context, generation: UUID = UUID.fromString(
        checkNotNull(db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)).value)) =
        S1AppGraph(db, AppClock { NOW }, S1SeedIDs(), generation, context, ZoneOffset.UTC)

    fun businessRows(db: FineCoachDatabase): Int {
        val tables = mutableListOf<String>()
        db.openHelper.readableDatabase.query("SELECT name FROM sqlite_master WHERE type='table'").use { cursor ->
            while (cursor.moveToNext()) {
                val table = cursor.getString(0)
                if (table !in setOf("store_metadata", "room_master_table", "android_metadata", "sqlite_sequence") && !table.startsWith("sqlite_")) {
                    check(Regex("[a-z_]+(?:[0-9]+)?").matches(table))
                    tables += table
                }
            }
        }
        return tables.sumOf { table ->
            db.openHelper.readableDatabase.query("SELECT COUNT(*) FROM `$table`").use { it.moveToFirst(); it.getInt(0) }
        }
    }

    private suspend fun populate(g: S1AppGraph, scenario: String) {
        studentIDs.forEachIndexed { i, sid ->
            val draft = StudentDraft(if (i < 2) "虚构同名学员" else "虚构学员${i + 1}",
                StudentSex.entries[i % StudentSex.entries.size], trainingGoal = "虚构训练目标", privateCoachNote = "虚构体验数据",
                phone = "000-010${i}", wechatID = "fictional-seed-${i + 1}")
            // Fixed IDs are supplied to the same repository used by StudentUseCases.
            val d = draft.makeStudent(sid, NOW)
            success(g.studentRepository.save(StudentRecord(sid, d.displayName.value, d.sex, d.trainingGoal?.value,
                d.injuryNotes?.value, d.privateCoachNote?.value, d.phone?.value, d.wechatID?.value, d.lifecycle, NOW, NOW)))
        }
        success(g.students.archive(studentIDs[6]))
        // Student1 has no package. Student2 available; 3 expired; 4 exhausted; 5 ended; 6 replacement history.
        for (i in 1..5) {
            val expired = i == 2
            val p = success(g.credits.createActivePackage(studentIDs[i], "虚构课包${i}", 8,
                LocalDate.of(2026, 11, 1), if (expired) LocalDate.of(2026, 11, 2) else LocalDate.of(2099, 12, 31)))
            val record = (p as? SaveCoursePackageResult.Saved)?.record ?: error("Seed package rejected")
            if (i == 3) success(g.credits.recordManualCorrection(record.coursePackageID, CreditDirection.debit, 8, "虚构耗尽演示"))
            if (i == 4) success(g.credits.endPackage(record.coursePackageID))
            if (i == 5) {
                val ctx = g.credits.loadCreationContext(studentIDs[i])
                success(g.credits.createPackageWithContext(ctx, "虚构替换课包", 12, confirmedByCoach = true))
            }
        }
        // Completed historical Session, including all record modes and a real ad-hoc ledger entry.
        val historical = session(g, studentIDs[1], allCompleted = true)
        val completed = success(g.active.complete(CompleteSessionCommand(historical.session.sessionID,
            historical.session.revision, NOW, false)))
        val p = checkNotNull(success(g.credits.activePackage(studentIDs[1])))
        success(g.finisher.debitAdhoc(completed.sessionID, p.coursePackageID))
        success(g.sessions.saveCompletedSummary(SaveCompletedSessionSummaryCommand(completed.sessionID, completed.revision,
            emptySet(), "虚构公开总结", "虚构私密备注", NOW)))
        // Two Students each have one active Session; each hero can be opened independently.
        session(g, studentIDs[0], allCompleted = false)
        if (scenario == "multi") session(g, studentIDs[1], allCompleted = false)
        val template = success(g.templates.save(SaveTemplateCommand(null, "虚构分段模板", emptySet(), null)))
        val section = SectionID.parse(uuid(900))
        val sections = listOf(SectionRecord(section, SessionSectionOwnerKind.template, null, template.templateID, "虚构分段", 0u))
        val exercises = RecordMode.entries.mapIndexed { i, mode ->
            val eid = TemplateExerciseID.parse(uuid(910 + i))
            val planned = TemplatePlannedSet.copyingValuesFrom(training(mode, SessionExerciseID.parse(uuid(920+i)),
                TrainingSetID.parse(uuid(930+i)), SetRecordingState.pending)).toRecord()
            TemplateExerciseRecord(eid, template.templateID, section, (i+1).toUInt(), ExerciseSourceKind.sessionOnly, null,
                "虚构计划动作${i+1}", mode, listOf(planned))
        }
        success(g.templateRepository.saveContent(SaveTemplateContentCommand(template.templateID, template.revision, sections, exercises)))
    }

    private suspend fun session(g: S1AppGraph, student: StudentID, allCompleted: Boolean): SessionContentRecord {
        val started = success(g.active.startOrOpen(student))
        val section = SectionID.parse(uuid(if (allCompleted) 800 else if (student==studentIDs[0]) 801 else 802))
        val sections = listOf(SectionRecord(section, SessionSectionOwnerKind.session, started.sessionID, null, "虚构训练分段", 0u))
        val exercises = RecordMode.entries.mapIndexed { i, mode ->
            val eid = g.ids.newSessionExerciseID()
            val state = if (allCompleted || i==0) SetRecordingState.completed else if (i==1) SetRecordingState.pending else SetRecordingState.draft
            val set = training(mode, eid, g.ids.newTrainingSetID(), state).toRecord()
            SessionExerciseRecord(eid, started.sessionID, (i+1).toUInt(), ExerciseSourceKind.sessionOnly, null,
                "虚构动作${i+1}", mode, null, section, listOf(set))
        }
        return success(g.active.saveContent(SaveSessionContentCommand(started.sessionID, started.revision, sections, exercises)))
    }

    private fun training(mode: RecordMode, eid: SessionExerciseID, sid: TrainingSetID, state: SetRecordingState): TrainingSet {
        val input = when(mode) {
            RecordMode.weightReps -> TrainingSetInput(mode, weightValue="20", repetitionCount="8", unit=MeasurementUnit.kilograms)
            RecordMode.reps -> TrainingSetInput(mode, repetitionCount="10", unit=MeasurementUnit.repetitions)
            RecordMode.duration -> TrainingSetInput(mode, durationSeconds="45", unit=MeasurementUnit.seconds)
            RecordMode.cardio -> TrainingSetInput(mode, durationSeconds="300", unit=MeasurementUnit.seconds, distanceValue="1.25", speedValue="15", resistanceValue="2")
        }
        val draft = TrainingSet.makeDraft(sid, eid, 0u, input, NOW)
        return when (state) {
            SetRecordingState.completed -> draft.confirmed(NOW)
            SetRecordingState.pending -> draft.confirmed(NOW).copiedAsPending(sid, 0u, NOW)
            SetRecordingState.draft -> draft
        }
    }

    suspend fun verifyInitial(g: S1AppGraph, scenario: String = "multi") {
        if (scenario == "empty") {
            check(success(g.students.list(StudentQuery(includeArchived=true))).isEmpty())
            check(success(g.sessions.listActiveSessions()).isEmpty())
            return
        }
        val students = success(g.students.list(StudentQuery(includeArchived=true)))
        check(students.size==7 && students.map { it.studentID }.toSet()==studentIDs.toSet())
        check(students.count { it.displayName == "虚构同名学员" }==2 && students.count { it.lifecycle==StudentLifecycle.archived }==1)
        check(success(g.sessions.listActiveSessions()).size==(if (scenario=="multi") 2 else 1))
        val active = success(g.sessions.listActiveSessions())
        val contents = active.map { checkNotNull(success(g.sessions.loadContent(it.sessionID))) }
        check(contents.all { it.sections.isNotEmpty() && it.exercises.map { e -> e.recordModeSnapshot }.toSet()==RecordMode.entries.toSet() })
        check(contents.all { it.exercises.flatMap { e -> e.sets }.map { s -> s.state }.toSet()==SetRecordingState.entries.toSet() })
        check(success(g.credits.packages(studentIDs[0])).isEmpty())
        check(checkNotNull(success(g.credits.activePackage(studentIDs[1]))).remainingCreditsCache==7L)
        check(checkNotNull(success(g.credits.activePackage(studentIDs[2]))).endDate!! < NOW.atZone(ZoneOffset.UTC).toLocalDate())
        check(checkNotNull(success(g.credits.activePackage(studentIDs[3]))).remainingCreditsCache==0L)
        check(success(g.credits.packages(studentIDs[4])).single().status==CoursePackageStatus.ended)
        check(success(g.credits.packages(studentIDs[5])).size==2)
        check(success(g.historyRepository.list(HistoryQuery(studentID=studentIDs[1]))).size==1)
        check(success(g.credits.ledger(studentIDs[1])).size==1)
        val templates=success(g.templates.list())
        check(templates.size==1)
        val template=checkNotNull(success(g.templates.load(templates.single().templateID)))
        check(template.sections.size==1 && template.exercises.size==4 && template.exercises.all { it.plannedSets.size==1 })
    }

    private fun <T> success(result: ApplicationResult<T>): T = when(result) {
        is ApplicationResult.Success -> result.value
        is ApplicationResult.Failure -> error("Seed repository operation failed")
    }
}

private class S1SeedIDs : StableIDGenerator {
    private var index=1000
    private fun next()=S1DebugSeed.uuid(index++)
    override fun newStudentID()=StudentID.parse(next())
    override fun newCoursePackageID()=CoursePackageID.parse(next())
    override fun newCreditAdjustmentID()=CreditAdjustmentID.parse(next())
    override fun newSessionID()=SessionID.parse(next())
    override fun newTemplateID()=TemplateID.parse(next())
    override fun newSectionID()=SectionID.parse(next())
    override fun newSessionExerciseID()=SessionExerciseID.parse(next())
    override fun newTemplateExerciseID()=TemplateExerciseID.parse(next())
    override fun newTrainingSetID()=TrainingSetID.parse(next())
    override fun newExerciseID()=StableExerciseID.parse(next())
}
