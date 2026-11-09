package com.ignacioli.finecoach

import android.content.Context
import android.database.sqlite.SQLiteConstraintException
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.StoreMetadata
import com.ignacioli.finecoach.storage.entity.*
import com.ignacioli.finecoach.storage.value.StorageValueConverters
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class S1EntityRoundtripTests {
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var context: Context
    private lateinit var database: FineCoachDatabase
    private val dao get() = database.s1Dao()
    private val now = Instant.parse("2026-11-06T08:09:10.123456789Z")
    private fun id(n: Int): UUID = UUID.fromString("00000000-0000-4000-8000-${n.toString().padStart(12, '0')}")
    private fun student(n: Int = 1) = StudentEntity(id(n), "虚构学员", StudentSex.undisclosed,
        "虚构目标", "虚构伤情", "虚构私密备注", "fictional-phone", "fictional-wechat",
        StudentLifecycle.active, now, now)
    private fun session(n: Int = 2, student: Int = 1) = SessionEntity(id(n), id(student), SessionState.inProgress,
        now, now, BigDecimal("123.456789"), now, true, BigDecimal("125.25"), "虚构公开总结", "虚构私密备注",
        "18446744073709551615", now, now, null, null, "noActivePackage")
    private fun coursePackage(n: Int = 3) = CoursePackageEntity(id(n), id(1), "虚构课包", 12, 9,
        LocalDate.of(2026, 12, 1), LocalDate.of(2026, 1, 1), CoursePackageStatus.active, now, now)
    private fun exercise(n: Int = 5, order: Long = 1) = SessionExerciseEntity(id(n), id(2), order,
        ExerciseSourceKind.sessionOnly, null, "虚构动作快照", RecordMode.cardio, "虚构动作备注", null)
    private fun <T> offMain(action: () -> T): T = worker.submit(Callable { action() }).get(30, TimeUnit.SECONDS)

    @Before fun prepare() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        database = FineCoachDatabaseFactory.create(context)
    }

    @After fun cleanUp() {
        try { offMain { database.close() } } finally {
            worker.shutdownNow()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    @Test fun studentAndMetadataSurviveReopenWithOptionalTextAndSameNames(): Unit = offMain {
        val full = student()
        val empty = student(10).copy(trainingGoal = null, injuryNotes = null, privateCoachNote = null,
            phone = null, wechatID = null, lifecycle = StudentLifecycle.archived)
        dao.insert(full)
        dao.insert(empty)
        database.storeMetadataDao().insert(StoreMetadata("fictional_marker", "unchanged"))
        database.close()
        database = FineCoachDatabaseFactory.create(context)
        assertEquals(full, dao.findStudent(full.id))
        assertEquals(empty, dao.findStudent(empty.id))
        assertEquals("unchanged", database.storeMetadataDao().find("fictional_marker")?.value)
    }

    @Test fun packagesClaimsAndLedgerPreserveReverseDatesAndEventIdentity(): Unit = offMain {
        val pkg = coursePackage()
        // Packages are scalar student references: no Student row is required here.
        dao.insert(pkg)
        val claim = ActivePackageClaimEntity(id(1), pkg.id)
        dao.insert(claim)
        val ledger = CreditAdjustmentEntity(id(4), pkg.id, CreditDirection.credit, 2,
            CreditReasonKind.manualCorrection, "虚构修正原因", id(2), id(99), "fictional-event", now)
        dao.insert(ledger)
        assertEquals(pkg, dao.findCoursePackage(pkg.id))
        assertEquals(claim, dao.findActivePackageClaim(id(1)))
        assertEquals(ledger, dao.findCreditAdjustment(ledger.id))
        assertThrows(SQLiteConstraintException::class.java) { dao.insert(ledger.copy(id = id(40))) }
        assertEquals(ledger, dao.findCreditAdjustment(ledger.id))
        assertThrows(IllegalArgumentException::class.java) { dao.insert(claim.copy(studentID = id(10))) }
        val empty = pkg.copy(id = id(30), name = null, startDate = null, endDate = null, status = CoursePackageStatus.ended)
        dao.insert(empty)
        assertEquals(empty, dao.findCoursePackage(empty.id))
    }

    @Test fun sessionsPointersAndFocusPreserveInstantDecimalAndUnsignedRevision(): Unit = offMain {
        dao.insert(student())
        val full = session()
        dao.insert(full)
        val pointer = ActiveSessionPointerEntity(id(1).toString(), full.id)
        dao.insert(pointer)
        val focus = BodyPart.entries.map { SessionTrainingFocusEntity(full.id, it) }
        focus.forEach { dao.insert(it) }
        assertEquals(full, dao.findSession(full.id))
        assertEquals(pointer, dao.findActiveSessionPointer(pointer.key))
        assertEquals(focus.toSet(), dao.sessionFocus(full.id).toSet())
        assertThrows(SQLiteConstraintException::class.java) { dao.insert(focus.first()) }
        val empty = full.copy(id = id(20), state = SessionState.completed, interruptionStartedAtUTC = null,
            durationNeedsReview = false, coachAdjustedDurationSeconds = null, studentFacingSummary = null,
            privateCoachNote = null, revision = "1", completedAtUTC = now, appointmentID = id(99), creditSettlementNote = null)
        dao.insert(empty)
        assertEquals(empty, dao.findSession(empty.id))
    }

    @Test fun sessionExercisesAndAllSetColumnsRoundtripInStableOrder(): Unit = offMain {
        dao.insert(student())
        dao.insert(session())
        val ex = exercise()
        dao.insert(ex)
        assertEquals(ex, dao.findSessionExercise(ex.id))
        val rows = RecordMode.entries.mapIndexed { i, mode ->
            TrainingSetEntity(id(50 + i), ex.id, i.toLong(), SetRecordingState.completed, mode,
                BigDecimal("42.125"), BigDecimal("12"), BigDecimal("90.5"), BigDecimal("11.25"),
                BigDecimal("12.75"), BigDecimal("123.45"), BigDecimal("6.75"), BigDecimal("4"),
                MeasurementUnit.kilograms, SetSide.bilateral, now, now, now)
        }
        rows.reversed().forEach { dao.insert(it) }
        assertEquals(rows, dao.trainingSets(ex.id))
        val empty = rows.first().copy(id = id(59), orderIndex = 4294967295L, state = SetRecordingState.pending,
            weightValue = null, repetitionCount = null, durationSeconds = null, leftValue = null, rightValue = null,
            distanceValue = null, speedValue = null, resistanceValue = null, completedAtUTC = null)
        dao.insert(empty)
        assertEquals(empty, dao.findTrainingSet(empty.id))
        assertThrows(SQLiteConstraintException::class.java) { dao.insert(rows.first().copy(id = id(60))) }
    }

    @Test fun templatesSectionsFocusAndPlannedSetsRoundtripWithoutSharedIdentity(): Unit = offMain {
        val template = TrainingTemplateEntity(id(6), "虚构模板", createdAtUTC = now, updatedAtUTC = now)
        assertEquals("0", template.revision)
        dao.insert(template)
        val maxRevision = template.copy(id = id(61), revision = "18446744073709551615")
        dao.insert(maxRevision)
        database.close()
        database = FineCoachDatabaseFactory.create(context)
        assertEquals(maxRevision, dao.findTrainingTemplate(maxRevision.id))
        val section = SessionSectionEntity(id(7), SessionSectionOwnerKind.template, template.id, "虚构分段", 0)
        dao.insert(section)
        val ex = TemplateExerciseEntity(id(8), template.id, section.id, 1, ExerciseSourceKind.builtIn,
            "fictional-bundled-id", "虚构模板动作", RecordMode.weightReps)
        dao.insert(ex)
        val sets = (0L..1L).map { position -> TemplatePlannedSetEntity(ex.id, position, RecordMode.weightReps,
            MeasurementUnit.kilograms, SetSide.left, BigDecimal("42.125"), BigDecimal("8"), BigDecimal("45"),
            BigDecimal("12.25"), BigDecimal("13.75"), BigDecimal("100.25"), BigDecimal("6.5"), BigDecimal("3")) }
        sets.reversed().forEach { dao.insert(it) }
        val focus = TemplateTrainingFocusEntity(template.id, BodyPart.back)
        dao.insert(focus)
        assertEquals(template, dao.findTrainingTemplate(template.id))
        assertEquals(listOf(section), dao.sections(SessionSectionOwnerKind.template, template.id))
        assertEquals(ex, dao.findTemplateExercise(ex.id))
        assertEquals(sets, dao.plannedSets(ex.id))
        assertEquals(listOf(focus), dao.templateFocus(template.id))
        assertThrows(SQLiteConstraintException::class.java) { dao.insert(sets.first()) }
        val empty = sets.first().copy(position = 2, weightValue = null, repetitionCount = null, durationSeconds = null,
            leftValue = null, rightValue = null, distanceValue = null, speedValue = null, resistanceValue = null)
        dao.insert(empty)
        assertEquals(empty, dao.findTemplatePlannedSet(ex.id, 2))
    }

    @Test fun catalogPreferencesAndNameClaimsKeepStableIDsAndNullableUnilateral(): Unit = offMain {
        val catalog = ExerciseCatalogEntity("fictional-bundled-id", ExerciseKind.builtIn, "虚构动作", "虚构动作",
            RecordMode.reps, "fictional-v1", ExerciseLifecycle.active, false, "fictional-license-ref", now, now)
        dao.insert(catalog)
        val preference = ExercisePreferenceEntity(catalog.id, "虚构别名", true, false, true, null)
        dao.insert(preference)
        val claim = ExerciseNameClaimEntity(catalog.normalizedName, ExerciseSourceKind.builtIn, catalog.id,
            ExerciseClaimScope.activeCatalog)
        dao.insert(claim)
        assertEquals(catalog, dao.findExerciseCatalog(catalog.id))
        assertEquals(preference, dao.findExercisePreference(catalog.id))
        assertEquals(claim, dao.findExerciseNameClaim(claim.normalizedName))
        val custom = catalog.copy(id = "fictional-custom-id", kind = ExerciseKind.custom,
            canonicalName = "虚构自定义动作", normalizedName = "虚构自定义动作", lifecycle = ExerciseLifecycle.archived,
            isRetired = true, provenanceRef = null)
        dao.insert(custom)
        val explicitFalse = preference.copy(exerciseID = custom.id, alias = null, isUnilateral = false)
        dao.insert(explicitFalse)
        assertEquals(custom, dao.findExerciseCatalog(custom.id))
        assertEquals(explicitFalse, dao.findExercisePreference(custom.id))
    }

    @Test fun pointerRejectsMissingCrossStudentAndTerminalSessionWithoutWrites(): Unit = offMain {
        dao.insert(student())
        dao.insert(student(10))
        dao.insert(session())
        val pointer = ActiveSessionPointerEntity(id(1).toString(), id(2))
        assertThrows(IllegalArgumentException::class.java) { dao.insert(pointer.copy(sessionID = id(99))) }
        assertThrows(IllegalArgumentException::class.java) { dao.insert(pointer.copy(key = id(10).toString())) }
        dao.insert(session(20).copy(state = SessionState.completed, completedAtUTC = now))
        assertThrows(IllegalArgumentException::class.java) { dao.insert(pointer.copy(sessionID = id(20))) }
        assertNull(dao.findActiveSessionPointer(pointer.key))
        assertNull(dao.findActiveSessionPointer(id(10).toString()))
    }

    @Test fun failedPointerValidationRollsBackEnclosingSessionTransaction(): Unit = offMain {
        dao.insert(student())
        assertThrows(IllegalArgumentException::class.java) {
            database.runInTransaction(Runnable {
                dao.insert(session())
                dao.insert(ActiveSessionPointerEntity(id(10).toString(), id(2)))
            })
        }
        assertNull(dao.findSession(id(2)))
        assertNull(dao.findActiveSessionPointer(id(10).toString()))
    }

    @Test fun fkRestrictsRealParentsButScalarResidueDoesNotBlockStudentDeletion(): Unit = offMain {
        assertThrows(SQLiteConstraintException::class.java) { dao.insert(session()) }
        dao.insert(student())
        dao.insert(session())
        dao.insert(exercise())
        val sqlite = database.openHelper.writableDatabase
        assertThrows(SQLiteConstraintException::class.java) { sqlite.execSQL("DELETE FROM students") }
        assertThrows(SQLiteConstraintException::class.java) { sqlite.execSQL("DELETE FROM sessions") }
        dao.insert(coursePackage())
        dao.insert(ActivePackageClaimEntity(id(1), id(3)))
        dao.insert(ActiveSessionPointerEntity(id(1).toString(), id(2)))
        dao.insert(SessionSectionEntity(id(7), SessionSectionOwnerKind.session, id(2), "虚构保留分段", 0))
        sqlite.execSQL("DELETE FROM session_exercises")
        sqlite.execSQL("DELETE FROM sessions")
        sqlite.execSQL("DELETE FROM students")
        assertNotNull(dao.findCoursePackage(id(3)))
        assertNotNull(dao.findActivePackageClaim(id(1)))
        assertNotNull(dao.findActiveSessionPointer(id(1).toString()))
        assertNotNull(dao.findSessionSection(id(7)))
    }

    @Test fun sharedOrderAxisAndSectionOwnershipRejectConflictingInserts(): Unit = offMain {
        dao.insert(student())
        dao.insert(session())
        val section = SessionSectionEntity(id(7), SessionSectionOwnerKind.session, id(2), "虚构分段", 0)
        dao.insert(section)
        assertThrows(IllegalArgumentException::class.java) { dao.insert(exercise(order = 0)) }
        dao.insert(exercise(order = 4294967295L).copy(sectionID = section.id))
        assertThrows(SQLiteConstraintException::class.java) { dao.insert(exercise(51, 4294967295L)) }
        assertThrows(IllegalArgumentException::class.java) { dao.insert(section.copy(id = id(70), orderIndex = 4294967295L)) }
        dao.insert(TrainingTemplateEntity(id(6), "虚构模板", createdAtUTC = now, updatedAtUTC = now))
        assertThrows(IllegalArgumentException::class.java) {
            dao.insert(TemplateExerciseEntity(id(8), id(6), section.id, 1,
                ExerciseSourceKind.custom, "fictional-custom", "虚构动作", RecordMode.reps))
        }
        assertThrows(IllegalArgumentException::class.java) { dao.insert(section.copy(id = id(71), ownerID = id(99))) }
    }

    @Test fun primitiveStorageBoundsRejectInvalidOrderRevisionAndText() {
        assertThrows(IllegalArgumentException::class.java) { exercise(order = -1) }
        assertThrows(IllegalArgumentException::class.java) { exercise(order = 4294967296L) }
        assertThrows(IllegalArgumentException::class.java) { session().copy(revision = "18446744073709551616") }
        assertThrows(IllegalArgumentException::class.java) { session().copy(revision = "01") }
        val template = TrainingTemplateEntity(id(6), "虚构模板", createdAtUTC = now, updatedAtUTC = now)
        for (revision in listOf("18446744073709551616", "01", "-1", "")) {
            assertThrows(IllegalArgumentException::class.java) { template.copy(revision = revision) }
        }
        assertThrows(IllegalArgumentException::class.java) { student().copy(displayName = " 虚构学员 ") }
        assertThrows(IllegalArgumentException::class.java) { student().copy(phone = " ") }
    }

    @Test fun primitiveConvertersPreservePrecisionAndRejectInvalidValues() {
        val cv = StorageValueConverters()
        assertEquals(id(1), cv.stringToUuid(cv.uuidToString(id(1))))
        assertEquals(now, cv.stringToInstant(cv.instantToString(now)))
        val date = LocalDate.of(2024, 2, 29)
        assertEquals(date, cv.stringToLocalDate(cv.localDateToString(date)))
        val time = LocalTime.of(8, 45)
        assertEquals(time, cv.stringToLocalTime(cv.localTimeToString(time)))
        val decimal = BigDecimal("12345678901234567890.1234567890123456789")
        assertEquals(decimal, cv.stringToDecimal(cv.decimalToString(decimal)))
        assertEquals("0", cv.decimalToString(BigDecimal("0.000")))
        assertEquals("12.5", cv.decimalToString(BigDecimal("12.500")))
        assertThrows(IllegalArgumentException::class.java) { cv.intToBoolean(2) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToUuid("1-1-1-1-1") }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToInstant("2026-11-06T08:09:10.000Z") }
    }

    @Test fun enumConvertersUseExactLiteralsAndRejectUnknownValues() {
        val cv = StorageValueConverters()
        StudentSex.entries.forEach { assertEquals(it, cv.stringToStudentSex(cv.studentSexToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToStudentSex("unknown") }
        StudentLifecycle.entries.forEach { assertEquals(it, cv.stringToStudentLifecycle(cv.studentLifecycleToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToStudentLifecycle("unknown") }
        CoursePackageStatus.entries.forEach { assertEquals(it, cv.stringToCoursePackageStatus(cv.coursePackageStatusToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToCoursePackageStatus("unknown") }
        CreditDirection.entries.forEach { assertEquals(it, cv.stringToCreditDirection(cv.creditDirectionToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToCreditDirection("unknown") }
        CreditReasonKind.entries.forEach { assertEquals(it, cv.stringToCreditReasonKind(cv.creditReasonKindToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToCreditReasonKind("unknown") }
        SessionState.entries.forEach { assertEquals(it, cv.stringToSessionState(cv.sessionStateToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToSessionState("unknown") }
        ExerciseKind.entries.forEach { assertEquals(it, cv.stringToExerciseKind(cv.exerciseKindToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToExerciseKind("unknown") }
        ExerciseLifecycle.entries.forEach { assertEquals(it, cv.stringToExerciseLifecycle(cv.exerciseLifecycleToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToExerciseLifecycle("unknown") }
        ExerciseSourceKind.entries.forEach { assertEquals(it, cv.stringToExerciseSourceKind(cv.exerciseSourceKindToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToExerciseSourceKind("unknown") }
        ExerciseClaimScope.entries.forEach { assertEquals(it, cv.stringToExerciseClaimScope(cv.exerciseClaimScopeToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToExerciseClaimScope("unknown") }
        RecordMode.entries.forEach { assertEquals(it, cv.stringToRecordMode(cv.recordModeToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToRecordMode("unknown") }
        MeasurementUnit.entries.forEach { assertEquals(it, cv.stringToMeasurementUnit(cv.measurementUnitToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToMeasurementUnit("unknown") }
        SetSide.entries.forEach { assertEquals(it, cv.stringToSetSide(cv.setSideToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToSetSide("unknown") }
        SetRecordingState.entries.forEach { assertEquals(it, cv.stringToSetRecordingState(cv.setRecordingStateToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToSetRecordingState("unknown") }
        SessionSectionOwnerKind.entries.forEach { assertEquals(it, cv.stringToSessionSectionOwnerKind(cv.sessionSectionOwnerKindToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToSessionSectionOwnerKind("unknown") }
        BodyPart.entries.forEach { assertEquals(it, cv.stringToBodyPart(cv.bodyPartToString(it))) }
        assertThrows(IllegalArgumentException::class.java) { cv.stringToBodyPart("unknown") }
        assertTrue(cv.intToBoolean(cv.booleanToInt(true)))
        assertFalse(cv.intToBoolean(cv.booleanToInt(false)))
    }
}
