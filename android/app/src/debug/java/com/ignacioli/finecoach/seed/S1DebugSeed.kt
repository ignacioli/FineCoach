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
import com.ignacioli.finecoach.core.domain.appointment.*
import java.io.RandomAccessFile
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID
import org.json.JSONObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Explicit shell-only installation; never called by Application.onCreate or by Release code. */
internal object S1DebugSeed {
    const val PREFIX = "s1_debug_seed."
    const val VERSION_KEY = "${PREFIX}version"
    const val STATUS_KEY = "${PREFIX}status"
    const val ROWS_KEY = "${PREFIX}rows"
    const val DATASET_KEY = "${PREFIX}dataset"
    suspend fun load(context: Context, scenario: String = "multi", beforeOwnershipTransaction: (FineCoachDatabase) -> Unit = {}): SeedResult = withContext(Dispatchers.IO) {
        val fixture = S1SeedFixture.read(context)
        require(scenario in fixture.records("scenarios").map { it.getString("key") })
        val app = context.applicationContext
        require(!context.isDeviceProtectedStorage && !app.isDeviceProtectedStorage)
        // Cross-process lock protects explicit installers; it is not a product startup hook.
        RandomAccessFile(java.io.File(app.filesDir, "s1-debug-seed.lock"), "rw").channel.use { channel ->
            val lock = checkNotNull(channel.tryLock()) { "Seed installer is already running" }
            try {
                val existed = app.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).exists()
                val startupEmpty = existed && preflight(app, scenario, fixture)
                val database = FineCoachDatabaseFactory.create(app)
                try {
                    val metadata = database.storeMetadataDao()
                    if (existed && !startupEmpty) {
                        check(metadata.find("${PREFIX}scenario")?.value == scenario) { "Seed scenario mismatch" }
                        // Even an empty non-seed database belongs to its user. Never adopt or clear it.
                        check(metadata.find(DATASET_KEY)?.value == fixture.dataset) { "Non-seed database rejected" }
                        check(metadata.find(VERSION_KEY)?.value == fixture.version.toString()) { "Seed version mismatch" }
                        check(metadata.find(STATUS_KEY)?.value == "complete") { "Incomplete seed rejected" }
                        return@withContext storedResult(database, fixture)
                    }
                    check(businessRows(database) == 0) { "Non-empty database rejected" }
                    val generation = UUID.fromString(checkNotNull(metadata.find(FineCoachDatabaseFactory.GENERATION_KEY)).value)
                    // Debug-only deterministic race seam; ownership must be rechecked after this boundary.
                    beforeOwnershipTransaction(database)
                    database.runInTransaction {
                        if (startupEmpty) {
                            check(businessRows(database) == 0) { "Non-empty database rejected" }
                            val current = mutableMapOf<String, String>()
                            database.openHelper.readableDatabase.query("SELECT `key`, value FROM store_metadata").use { cursor ->
                                while (cursor.moveToNext()) current[cursor.getString(0)] = cursor.getString(1)
                            }
                            check(database.openHelper.readableDatabase.version == 3 && startupMetadataSet(current)) { "Non-seed database rejected" }
                        }
                        metadata.insert(StoreMetadata(DATASET_KEY, fixture.dataset))
                        metadata.insert(StoreMetadata(VERSION_KEY, fixture.version.toString()))
                        metadata.insert(StoreMetadata(STATUS_KEY, "installing"))
                        metadata.insert(StoreMetadata("${PREFIX}scenario", scenario))
                    }
                    val graph = graph(database, app, generation)
                    graph.prepareExerciseCatalog()
                    check(!graph.exerciseRepository.catalogUnavailable) { "Seed catalog unavailable" }
                    if (scenario != "empty") populate(graph, scenario, fixture)
                    verifyInitial(graph, scenario)
                    val ownedMetadata = database.openHelper.readableDatabase.query(
                        "SELECT COUNT(*) FROM store_metadata WHERE substr(`key`,1,?)=?", arrayOf<Any>(PREFIX.length, PREFIX)
                    ).use { it.moveToFirst(); it.getInt(0) }
                    val rows = businessRows(database) + ownedMetadata + 1 // include the not-yet-inserted rows key
                    check(rows == fixture.json.getJSONObject("expectedRows").getInt(scenario)) { "Seed inventory mismatch" }
                    // Success is visible only after all repository writes and integrity reads succeeded.
                    database.runInTransaction {
                        metadata.insert(StoreMetadata(ROWS_KEY, rows.toString()))
                        check(metadata.update(StoreMetadata(STATUS_KEY, "complete")) == 1)
                    }
                    storedResult(database, fixture)
                } finally { database.close() }
            } finally { lock.release() }
        }
    }

    // Inspect ownership before Room can run a migration or otherwise write an existing file.
    private fun preflight(context: Context, scenario: String, fixture: S1SeedFixture): Boolean {
        return android.database.sqlite.SQLiteDatabase.openDatabase(
            context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).absolutePath, null,
            android.database.sqlite.SQLiteDatabase.OPEN_READONLY,
        ).use { raw ->
            check(raw.version == 2 || raw.version == 3) { "Non-seed schema rejected" }
            val metadata = mutableMapOf<String, String>()
            raw.rawQuery("SELECT `key`, value FROM store_metadata", null).use { cursor ->
                while (cursor.moveToNext()) metadata[cursor.getString(0)] = cursor.getString(1)
            }
            if (raw.version == 3 && startupMetadataSet(metadata)) {
                val tables = mutableListOf<String>()
                raw.rawQuery("SELECT name FROM sqlite_master WHERE type='table'", null).use { cursor ->
                    while (cursor.moveToNext()) {
                        val table = cursor.getString(0)
                        if (table !in setOf("store_metadata", "room_master_table", "android_metadata", "sqlite_sequence") && !table.startsWith("sqlite_")) {
                            check(Regex("[a-z_]+(?:[0-9]+)?").matches(table))
                            tables += table
                        }
                    }
                }
                check(tables.isNotEmpty() && tables.all { table ->
                    raw.rawQuery("SELECT COUNT(*) FROM `$table`", null).use { it.moveToFirst(); it.getInt(0) == 0 }
                }) { "Non-empty database rejected" }
                return@use true
            }
            val expected = mapOf(DATASET_KEY to fixture.dataset, VERSION_KEY to fixture.version.toString(),
                STATUS_KEY to "complete", "${PREFIX}scenario" to scenario)
            for ((key, value) in expected) {
                raw.rawQuery("SELECT value FROM store_metadata WHERE `key`=?", arrayOf(key)).use {
                    check(it.moveToFirst() && it.getString(0) == value) { "Non-seed or incomplete database rejected" }
                }
            }
            false
        }
    }

    private fun startupMetadataSet(metadata: Map<String, String>) =
        metadata.keys == setOf("created_at", "store_generation", "appointment-reminders-v1") &&
            metadata.all { (key, value) -> startupMetadata(key, value) }

    private fun startupMetadata(key: String, value: String) = when (key) {
        "created_at" -> runCatching { Instant.parse(value) }.isSuccess
        "store_generation" -> runCatching { UUID.fromString(value) }.isSuccess
        "appointment-reminders-v1" -> value == "{}"
        else -> false
    }

    /** Reopen verification is read-only and permits walkthrough edits/deletions after initialization. */
    fun storedResult(database: FineCoachDatabase, fixture: S1SeedFixture): SeedResult {
        val metadata = database.storeMetadataDao()
        check(metadata.find(DATASET_KEY)?.value == fixture.dataset)
        check(metadata.find(VERSION_KEY)?.value == fixture.version.toString())
        check(metadata.find(STATUS_KEY)?.value == "complete")
        val rows = checkNotNull(metadata.find(ROWS_KEY)?.value?.toIntOrNull())
        check(rows > 0)
        return SeedResult(fixture.version, rows)
    }

    fun graph(db: FineCoachDatabase, context: Context, generation: UUID = UUID.fromString(
        checkNotNull(db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)).value)) =
        S1SeedFixture.read(context).let { fixture ->
            S1AppGraph(db, S1FixtureClock(fixture), S1SeedIDs(fixture), generation, context, ZoneOffset.UTC)
        }

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

    private suspend fun populate(g: S1AppGraph, variant: String, fixture: S1SeedFixture) {
        val clock = g.clock as S1FixtureClock
        fun at(row: JSONObject, field: String = "offsetSeconds") { clock.offsetSeconds = row.getLong(field) }
        val catalog = success(g.exerciseRepository.listCatalog())
        // Resolve every built-in reference before the first business write. Never silently substitute.
        (fixture.selected("sessions", variant) + fixture.selected("templates", variant))
            .flatMap { it.objects("exercises") }.forEach { source(it, catalog) }
        for (row in fixture.selected("students", variant)) {
            at(row)
            val sid = StudentID.parse(fixture.uuid(row.getInt("id")))
            val draft = StudentDraft(row.getString("name"), StudentSex.valueOf(row.getString("sex")),
                row.optional("trainingGoal").orEmpty(), row.optional("injuryNotes").orEmpty(), row.optional("privateCoachNote").orEmpty(),
                row.optional("phone").orEmpty(), row.optional("wechatID").orEmpty())
            val d = draft.makeStudent(sid, clock.now())
            success(g.studentRepository.save(StudentRecord(sid, d.displayName.value, d.sex, d.trainingGoal?.value,
                d.injuryNotes?.value, d.privateCoachNote?.value, d.phone?.value, d.wechatID?.value,
                d.lifecycle, clock.now(), clock.now())))
            when (StudentLifecycle.valueOf(row.getString("lifecycle"))) {
                StudentLifecycle.archived -> success(g.students.archive(sid))
                StudentLifecycle.active -> Unit
            }
        }
        val packages = mutableMapOf<String, CoursePackageRecord>()
        for (row in fixture.selected("packages", variant)) {
            at(row)
            val sid = StudentID.parse(fixture.uuid(row.getInt("studentID")))
            val context = g.credits.loadCreationContext(sid)
            val saved = success(g.credits.createPackageWithContext(context, row.optional("name"), row.getLong("totalCredits"),
                row.optional("startDate")?.let(LocalDate::parse), row.optional("endDate")?.let(LocalDate::parse),
                confirmedByCoach = row.getBoolean("confirmedReplacement")))
            val record = (saved as? SaveCoursePackageResult.Saved)?.record ?: error("Seed package rejected")
            packages[row.getString("key")] = record
            when (CoursePackageStatus.valueOf(row.getString("state"))) {
                CoursePackageStatus.ended -> success(g.credits.endPackage(record.coursePackageID))
                CoursePackageStatus.active -> Unit
            }
        }
        val sessions = mutableMapOf<String, SessionRecord>()
        for (row in fixture.selected("sessions", variant)) {
            at(row, "startOffsetSeconds")
            val started = success(g.active.startOrOpen(StudentID.parse(fixture.uuid(row.getInt("studentID"))),
                row.strings("trainingFocus").map { BodyPart.valueOf(it) }.toSet()))
            val sections = row.objects("sections").map {
                SectionRecord(SectionID.parse(fixture.uuid(it.getInt("id"))), SessionSectionOwnerKind.session,
                    started.sessionID, null, it.getString("name"), it.getInt("orderIndex").toUInt())
            }
            val exercises = row.objects("exercises").map { exercise ->
                val id = SessionExerciseID.parse(fixture.uuid(exercise.getInt("id")))
                val mode = RecordMode.valueOf(exercise.getString("recordMode"))
                val item = source(exercise, catalog)
                SessionExerciseRecord(id, started.sessionID, exercise.getInt("orderIndex").toUInt(),
                    ExerciseSourceKind.valueOf(exercise.getString("sourceKind")), item?.exerciseID,
                    item?.canonicalName ?: exercise.getString("canonicalName"), mode, null,
                    SectionID.parse(fixture.uuid(exercise.getInt("sectionID"))),
                    exercise.objects("sets").map { training(it, mode, id, fixture).toRecord() })
            }
            val content = success(g.active.saveContent(SaveSessionContentCommand(started.sessionID, started.revision, sections, exercises)))
            val record = when (SessionState.valueOf(row.getString("state"))) {
                SessionState.inProgress -> content.session
                SessionState.completed -> {
                    at(row, "finishOffsetSeconds")
                    success(g.active.complete(CompleteSessionCommand(started.sessionID, content.session.revision, clock.now(), false)))
                }
                else -> error("Unsupported seed session state")
            }
            sessions[row.getString("key")] = record
            row.optJSONObject("summary")?.let { summary ->
                check(record.state == SessionState.completed)
                at(summary)
                success(g.sessions.saveCompletedSummary(SaveCompletedSessionSummaryCommand(record.sessionID, record.revision,
                    record.trainingFocus, summary.optional("publicSummary"), summary.optional("privateCoachNote"), clock.now())))
            }
        }
        for (row in fixture.selected("ledger", variant)) {
            at(row)
            val pkg = packages.getValue(row.getString("packageKey"))
            when (row.getString("kind")) {
                "manualCorrection" -> success(g.credits.recordManualCorrection(pkg.coursePackageID,
                    CreditDirection.valueOf(row.getString("direction")), row.getLong("amount"), row.optional("note")))
                "adhocDebit" -> success(g.finisher.debitAdhoc(sessions.getValue(row.getString("sessionKey")).sessionID, pkg.coursePackageID))
                else -> error("Unsupported seed ledger kind")
            }
        }
        for (row in fixture.selected("templates", variant)) {
            at(row)
            val template = success(g.templates.save(SaveTemplateCommand(null, row.getString("name"),
                row.strings("trainingFocus").map { BodyPart.valueOf(it) }.toSet(), null)))
            val sections = row.objects("sections").map {
                SectionRecord(SectionID.parse(fixture.uuid(it.getInt("id"))), SessionSectionOwnerKind.template,
                    null, template.templateID, it.getString("name"), it.getInt("orderIndex").toUInt())
            }
            val exercises = row.objects("exercises").map { exercise ->
                val item = source(exercise, catalog)
                val mode = RecordMode.valueOf(exercise.getString("recordMode"))
                val owner = SessionExerciseID.parse(fixture.uuid(exercise.getInt("id")))
                TemplateExerciseRecord(TemplateExerciseID.parse(fixture.uuid(exercise.getInt("id"))), template.templateID,
                    SectionID.parse(fixture.uuid(exercise.getInt("sectionID"))), exercise.getInt("orderIndex").toUInt(),
                    ExerciseSourceKind.valueOf(exercise.getString("sourceKind")), item?.exerciseID,
                    item?.canonicalName ?: exercise.getString("canonicalName"), mode,
                    exercise.objects("sets").map { TemplatePlannedSet.copyingValuesFrom(training(it, mode, owner, fixture)).toRecord() })
            }
            success(g.templateRepository.saveContent(SaveTemplateContentCommand(template.templateID, template.revision, sections, exercises)))
        }
        val today = LocalDate.now(java.time.ZoneId.systemDefault())
        for (row in fixture.selected("appointments", variant)) {
            val student = StudentID.parse(fixture.uuid(row.getInt("studentID")))
            val date = today.plusDays(row.getLong("dayOffset"))
            val time = java.time.LocalTime.parse(row.getString("startTime"))
            val created = fixture.now
            val base = com.ignacioli.finecoach.core.domain.appointment.Appointment(
                UUID.fromString(fixture.uuid(row.getInt("id"))), student, date = date, startTime = time,
                reminderEnabled = false, createdAtUTC = created, updatedAtUTC = created)
            val appointments = if (row.has("termination")) {
                val termination = if (row.getString("termination") == "RepeatCount") RecurrenceTermination.RepeatCount(row.getInt("count"))
                    else RecurrenceTermination.EndDate(today.plusDays(row.getLong("endDayOffset")))
                val series = RecurrenceSeries(UUID.fromString(fixture.uuid(row.getInt("seriesID"))), student,
                    RecurrenceInterval.everyOtherDay, termination, time, defaultReminderEnabled = false,
                    createdAtUTC = created, updatedAtUTC = created)
                var next = row.getInt("id")
                success(g.appointments.createRecurring(series, date, overrideConflict = true) { UUID.fromString(fixture.uuid(next++)) })
            } else success(g.appointments.createSingle(base, overrideConflict = true))
            val first = appointments.first()
            when (row.getString("state")) {
                "cancelled" -> success(g.appointments.cancel(first.id))
                "absent" -> {
                    val choice = AbsentCreditChoice.valueOf(row.getString("absentCreditChoice"))
                    val result = success(g.appointments.markAbsent(first.id, choice, true))
                    success(result.settlement)
                }
                "inProgress" -> check(success(g.appointments.startTraining(first.id)) is AppointmentTrainingStartResult.Started)
                "scheduled" -> Unit
                else -> error("Unsupported seed appointment state")
            }
        }
        clock.offsetSeconds = 0
    }

    internal fun source(row: JSONObject, catalog: List<ExerciseRecord>): ExerciseRecord? {
        if (row.getString("sourceKind") == ExerciseSourceKind.sessionOnly.name) return null
        check(row.getString("sourceKind") == ExerciseSourceKind.builtIn.name)
        val matches = catalog.filter {
            it.kind == ExerciseKind.builtIn && !it.isRetired && it.lifecycle == ExerciseLifecycle.active &&
                if (row.has("stableID")) it.exerciseID.value == row.getString("stableID")
                else it.canonicalName == row.getString("canonicalName")
        }
        val item = matches.singleOrNull() ?: error("Seed catalog reference unavailable")
        check(item.recordMode.name == row.getString("recordMode")) { "Seed catalog mode mismatch" }
        return item
    }

    private fun training(row: JSONObject, mode: RecordMode, owner: SessionExerciseID, fixture: S1SeedFixture): TrainingSet {
        val input = TrainingSetInput(mode, weightValue = row.optional("weightValue"), repetitionCount = row.optional("repetitionCount"),
            durationSeconds = row.optional("durationSeconds"), unit = MeasurementUnit.valueOf(row.getString("unit")),
            distanceValue = row.optional("distanceValue"), speedValue = row.optional("speedValue"), resistanceValue = row.optional("resistanceValue"))
        val id = TrainingSetID.parse(fixture.uuid(row.getInt("id")))
        val time = fixture.at(row.getLong("offsetSeconds"))
        val draft = TrainingSet.makeDraft(id, owner, row.getInt("orderIndex").toUInt(), input, time)
        return when (SetRecordingState.valueOf(row.getString("state"))) {
            SetRecordingState.completed -> draft.confirmed(time)
            SetRecordingState.pending -> draft.confirmed(time).copiedAsPending(id, row.getInt("orderIndex").toUInt(), time)
            SetRecordingState.draft -> draft
        }
    }

    suspend fun verifyInitial(g: S1AppGraph, scenario: String = "multi") {
        val fixture = S1SeedFixture.read(g.context)
        val catalog = success(g.exerciseRepository.listCatalog())
        check(catalog.count { it.kind == ExerciseKind.builtIn } == fixture.json.getInt("catalogCount"))
        val students = success(g.students.list(StudentQuery(includeArchived = true)))
        val expectedStudents = fixture.selected("students", scenario)
        check(students.size == expectedStudents.size)
        for (row in expectedStudents) {
            val student = students.single { it.studentID.value == fixture.uuid(row.getInt("id")) }
            check(student.displayName == row.getString("name") && student.lifecycle.name == row.getString("lifecycle"))
            check(student.trainingGoal == row.optional("trainingGoal") && student.privateCoachNote == row.optional("privateCoachNote"))
        }
        val expectedSessions = fixture.selected("sessions", scenario)
        val active = success(g.sessions.listActiveSessions())
        check(active.size == expectedSessions.count { it.getString("state") == SessionState.inProgress.name })
        check(success(g.templates.list()).size == fixture.selected("templates", scenario).size)
        for (row in expectedSessions) {
            val sid = StudentID.parse(fixture.uuid(row.getInt("studentID")))
            val record = if (row.getString("state") == SessionState.completed.name) {
                val history = success(g.historyRepository.list(HistoryQuery(studentID = sid)))
                history.single { it.completedAtUTC == fixture.at(row.getLong("finishOffsetSeconds")) }.let { success(g.sessions.find(it.sessionID))!! }
            } else success(g.sessions.active(sid))!!
            val content = success(g.sessions.loadContent(record.sessionID))!!
            check(record.state.name == row.getString("state"))
            check(content.sections.map { it.name } == row.objects("sections").sortedBy { it.getInt("orderIndex") }.map { it.getString("name") })
            check(content.exercises.size == row.objects("exercises").size)
            for (exercise in row.objects("exercises")) {
                val actual = content.exercises.single { it.sessionExerciseID.value == fixture.uuid(exercise.getInt("id")) }
                check(actual.displayNameSnapshot == (source(exercise, catalog)?.canonicalName ?: exercise.getString("canonicalName")))
                check(actual.sets == exercise.objects("sets").map { training(it, actual.recordModeSnapshot, actual.sessionExerciseID, fixture).toRecord() })
            }
            row.optJSONObject("summary")?.let { check(record.studentFacingSummary == it.optional("publicSummary") && record.privateCoachNote == it.optional("privateCoachNote")) }
        }
        for (student in students) {
            val expected = fixture.selected("packages", scenario).filter { fixture.uuid(it.getInt("studentID")) == student.studentID.value }
            val packages = success(g.credits.packages(student.studentID))
            check(packages.size == expected.size)
            for ((index, row) in expected.withIndex()) {
                val actual = packages.single { it.name == row.optional("name") }
                val ended = row.getString("state") == CoursePackageStatus.ended.name || index < expected.lastIndex
                check(actual.status == if (ended) CoursePackageStatus.ended else CoursePackageStatus.active)
                check(actual.totalCredits == row.getLong("totalCredits") && actual.endDate == row.optional("endDate")?.let(LocalDate::parse))
                if (!ended) {
                    val adjustments = fixture.selected("ledger", scenario).filter { it.getString("packageKey") == row.getString("key") }
                    val absenceDebits = fixture.selected("appointments", scenario).count { it.getInt("studentID").let(fixture::uuid) == student.studentID.value && it.optString("absentCreditChoice") == "charged" }
                    val remaining = row.getLong("totalCredits") - absenceDebits - adjustments.sumOf { if (it.getString("kind") == "adhocDebit") 1L else it.getLong("amount") * if (it.getString("direction") == "debit") 1 else -1 }
                    check(actual.remainingCreditsCache == remaining)
                }
            }
        }
        for (row in fixture.selected("templates", scenario)) {
            val template = success(g.templates.list()).single { it.name == row.getString("name") }
            val content = success(g.templates.load(template.templateID))!!
            check(content.sections.size == row.objects("sections").size && content.exercises.size == row.objects("exercises").size)
            check(content.exercises.all { actual -> actual.plannedSets.size == row.objects("exercises").single { it.getInt("id").let(fixture::uuid) == actual.templateExerciseID.value }.objects("sets").size })
        }
    }

    private fun <T> success(result: ApplicationResult<T>): T = when(result) {
        is ApplicationResult.Success -> result.value
        is ApplicationResult.Failure -> error("Seed repository operation failed")
    }
}

private class S1SeedIDs(private val fixture: S1SeedFixture) : StableIDGenerator {
    private var index=fixture.json.getInt("generatedIDStart")
    private fun next()=fixture.uuid(index++)
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

private class S1FixtureClock(private val fixture: S1SeedFixture) : AppClock {
    var offsetSeconds = 0L
    override fun now() = fixture.at(offsetSeconds)
}
