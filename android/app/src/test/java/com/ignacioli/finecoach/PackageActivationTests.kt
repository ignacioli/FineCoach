// fictional-data: All student IDs, package names, dates, and credit records in this file are fictional test fixtures.
package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.ApplicationError
import com.ignacioli.finecoach.core.application.ApplicationErrorCode
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CoursePackageRepositoryPort
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.SaveCoursePackageCommand
import com.ignacioli.finecoach.core.application.SaveCoursePackageResult
import com.ignacioli.finecoach.core.application.StableIDGenerator
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CoursePackageStatus
import com.ignacioli.finecoach.core.domain.common.CreditAdjustmentID
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.core.domain.common.SectionID
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.TemplateExerciseID
import com.ignacioli.finecoach.core.domain.common.TemplateID
import com.ignacioli.finecoach.core.domain.common.TrainingSetID
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.repository.CoursePackageRepository
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class PackageActivationTests {
    private val worker = Executors.newSingleThreadExecutor()
    private val defaultZone: ZoneId = ZoneId.of("Asia/Shanghai")
    private lateinit var context: Context
    private lateinit var database: FineCoachDatabase
    private lateinit var clock: MutableAppClock
    private lateinit var ids: SequentialIDGenerator
    private lateinit var repository: CoursePackageRepository
    private lateinit var useCases: CreditUseCases

    private val studentA = StudentID.parse("10000000-0000-4000-8000-000000000001")
    private val studentB = StudentID.parse("10000000-0000-4000-8000-000000000002")

    private fun <T> offMain(action: suspend () -> T): T =
        worker.submit(Callable { runBlocking { action() } }).get(30, TimeUnit.SECONDS)

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        clock = MutableAppClock(Instant.parse("2026-11-06T09:00:00Z"))
        ids = SequentialIDGenerator()
        openFreshStack()
    }

    @After
    fun tearDown() {
        try {
            if (::database.isInitialized && database.isOpen) {
                offMain { database.close() }
            }
        } finally {
            worker.shutdownNow()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    private fun openFreshStack(zone: ZoneId = defaultZone) {
        database = FineCoachDatabaseFactory.create(context)
        repository = CoursePackageRepository(
            database = database,
            clock = clock,
            ids = ids,
            zoneID = zone,
        )
        useCases = CreditUseCases(
            repository = repository,
            clock = clock,
            ids = ids,
            zoneID = zone,
        )
    }

    private fun closeAndReopenStack(zone: ZoneId = defaultZone) {
        database.close()
        openFreshStack(zone)
    }

    @Test
    fun createFirstActivePackagePersistsAndSurvivesCloseAndReopen(): Unit = offMain {
        val contextResult = useCases.loadCreationContext(studentA)
        val creationCtx = contextResult.requireSuccess("loadCreationContext")
        assertNull(creationCtx.existingActivePackage)
        assertFalse(creationCtx.requiresConfirmation)

        val saveResult = useCases.createPackageWithContext(
            contextResult = contextResult,
            name = "  虚构基础课包  ",
            totalCredits = 10L,
            startDate = LocalDate.of(2026, 11, 1),
            endDate = LocalDate.of(2027, 5, 1),
            confirmedByCoach = false,
        )
        val saved = saveResult.requireSuccess("createPackageWithContext").requireSaved("createPackageWithContext")
        assertEquals("虚构基础课包", saved.name)
        assertEquals(10L, saved.totalCredits)
        assertEquals(10L, saved.remainingCreditsCache)
        assertEquals(CoursePackageStatus.active, saved.status)

        closeAndReopenStack()

        val activeAfterReopen = useCases.activePackage(studentA).requireSuccess("activePackage")
        assertEquals(saved, activeAfterReopen)
        val listedAfterReopen = useCases.packages(studentA).requireSuccess("packages")
        assertEquals(listOf(saved), listedAfterReopen)
    }

    @Test
    fun existingUnexpiredNonZeroActivePackageRequiresConfirmationAndCancelLeavesZeroChanges(): Unit = offMain {
        val firstSaved = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构旧课包",
            totalCredits = 8L,
            startDate = LocalDate.of(2026, 10, 1),
            endDate = LocalDate.of(2026, 12, 31),
        )

        val ctxResult = useCases.loadCreationContext(studentA)
        val ctx = ctxResult.requireSuccess("loadCreationContext")
        assertEquals(firstSaved.coursePackageID, ctx.existingActivePackage?.coursePackageID)
        assertEquals(8L, ctx.existingActivePackageBalance)
        assertTrue(ctx.requiresConfirmation)

        // Attempting to save without confirmation returns RequiresReconfirmation and performs zero writes.
        val unconfirmed = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构新课包",
            totalCredits = 12L,
            observedActivePackageID = firstSaved.coursePackageID,
            confirmReplaceActivePackage = false,
        )
        val reconfirm = unconfirmed.requireSuccess("unconfirmedSave").requireReconfirmation("unconfirmedSave")
        assertEquals(firstSaved.coursePackageID, reconfirm.currentActivePackage?.coursePackageID)

        // Cancelling confirmation leaves original package active and creates no second package.
        useCases.cancelPackageReplacement()

        val packagesAfterCancel = useCases.packages(studentA).requireSuccess("packagesAfterCancel")
        assertEquals(1, packagesAfterCancel.size)
        assertEquals(firstSaved, packagesAfterCancel.single())
        val activeAfterCancel = useCases.activePackage(studentA).requireSuccess("activeAfterCancel")
        assertEquals(firstSaved, activeAfterCancel)
    }

    @Test
    fun confirmedReplacementAtomicallyEndsOldPackageAndActivatesNewOneAcrossReopen(): Unit = offMain {
        val firstSaved = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构旧课包",
            totalCredits = 8L,
            startDate = LocalDate.of(2026, 10, 1),
            endDate = LocalDate.of(2026, 12, 31),
        )
        useCases.recordManualCorrection(
            coursePackageID = firstSaved.coursePackageID,
            direction = CreditDirection.debit,
            amount = 3L,
            reasonText = "虚构课耗扣减",
        ).requireSuccess("recordManualCorrection")

        clock.advanceSeconds(60)
        val ctxResult = useCases.loadCreationContext(studentA)
        val ctx = ctxResult.requireSuccess("loadCreationContext")
        assertEquals(5L, ctx.existingActivePackageBalance)
        assertTrue(ctx.requiresConfirmation)

        val confirmedResult = useCases.createPackageWithContext(
            contextResult = ctxResult,
            name = "虚构新课包",
            totalCredits = 16L,
            startDate = LocalDate.of(2026, 11, 6),
            endDate = LocalDate.of(2027, 6, 6),
            confirmedByCoach = true,
        )
        val secondSaved = confirmedResult.requireSuccess("confirmedSave").requireSaved("confirmedSave")
        assertEquals(CoursePackageStatus.active, secondSaved.status)
        assertEquals(16L, secondSaved.totalCredits)

        closeAndReopenStack()

        val active = useCases.activePackage(studentA).requireSuccess("activePackage")
        assertEquals(secondSaved.coursePackageID, active?.coursePackageID)
        assertEquals(CoursePackageStatus.active, active?.status)

        val allPackages = useCases.packages(studentA).requireSuccess("packages")
        assertEquals(2, allPackages.size)
        assertEquals(1, allPackages.count { it.status == CoursePackageStatus.active })
        val endedOld = allPackages.first { it.coursePackageID == firstSaved.coursePackageID }
        assertEquals(CoursePackageStatus.ended, endedOld.status)
        assertEquals(5L, endedOld.remainingCreditsCache)
        val claimRow = database.s1Dao().findActivePackageClaim(UUID.fromString(studentA.value))
        assertEquals(UUID.fromString(secondSaved.coursePackageID.value), claimRow?.packageID)
    }

    @Test
    fun booleanConfirmWithoutMatchingObservedPackageIDCannotBypassConfirmationGate(): Unit = offMain {
        val firstSaved = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构有效包",
            totalCredits = 6L,
            startDate = LocalDate.of(2026, 11, 1),
            endDate = LocalDate.of(2026, 12, 31),
        )

        // Passing confirmReplaceActivePackage = true with null observedActivePackageID must be rejected as RequiresReconfirmation.
        val nullTokenAttempt = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构绕过包A",
            totalCredits = 10L,
            observedActivePackageID = null,
            confirmReplaceActivePackage = true,
        )
        val nullTokenOutcome = nullTokenAttempt.requireSuccess("nullTokenAttempt").requireReconfirmation("nullTokenAttempt")
        assertEquals(
            firstSaved.coursePackageID,
            nullTokenOutcome.currentActivePackage?.coursePackageID,
        )

        val packages = useCases.packages(studentA).requireSuccess("packages")
        assertEquals(listOf(firstSaved), packages)
    }

    @Test
    fun samePackageIdCannotOverwriteExistingActiveOrEndedPackageOrBypassConfirmationGate(): Unit = offMain {
        val pkg1 = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构原课包",
            totalCredits = 8L,
            startDate = LocalDate.of(2026, 10, 1),
            endDate = LocalDate.of(2026, 12, 31),
        )

        // 1. Passing the same coursePackageID without confirmation is blocked by the confirmation gate (zero writes).
        val unconfirmedSameId = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构试图改写名称",
            totalCredits = 99L,
            startDate = LocalDate.of(2027, 1, 1),
            endDate = LocalDate.of(2027, 12, 31),
            observedActivePackageID = pkg1.coursePackageID,
            confirmReplaceActivePackage = false,
            coursePackageID = pkg1.coursePackageID,
        )
        val reconfirm = unconfirmedSameId.requireSuccess("unconfirmedSameId").requireReconfirmation("unconfirmedSameId")
        assertEquals(pkg1, reconfirm.currentActivePackage)
        assertEquals(pkg1, useCases.activePackage(studentA).requireSuccess("activeAfterUnconfirmedSameId"))

        // 2. Even with confirmation, reusing the active package's ID to overwrite totalCredits/dates is rejected with conflict.
        val confirmedSameId = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构试图改写名称",
            totalCredits = 99L,
            startDate = LocalDate.of(2027, 1, 1),
            endDate = LocalDate.of(2027, 12, 31),
            observedActivePackageID = pkg1.coursePackageID,
            confirmReplaceActivePackage = true,
            coursePackageID = pkg1.coursePackageID,
        )
        val conflictError = confirmedSameId.requireFailure("confirmedSameId")
        assertEquals(ApplicationErrorCode.conflict, conflictError.code)
        assertEquals("coursePackageID", conflictError.field)

        // Verify pkg1 was neither ended nor overwritten in storage.
        val activeAfterConflict = useCases.activePackage(studentA).requireSuccess("activeAfterConflict")
        assertEquals(pkg1, activeAfterConflict)
        val rawEntity = database.s1Dao().findCoursePackage(UUID.fromString(pkg1.coursePackageID.value))
        assertEquals(8L, rawEntity?.totalCredits)
        assertEquals(LocalDate.of(2026, 10, 1), rawEntity?.startDate)
        assertEquals(LocalDate.of(2026, 12, 31), rawEntity?.endDate)
        assertEquals(CoursePackageStatus.active, rawEntity?.status)

        // 3. After pkg1 is ended, reusing its ID for a new package is also rejected with conflict.
        useCases.endPackage(pkg1.coursePackageID).requireSuccess("endPkg1")
        val reuseEndedId = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构复用历史ID",
            totalCredits = 20L,
            coursePackageID = pkg1.coursePackageID,
        )
        assertEquals(ApplicationErrorCode.conflict, reuseEndedId.requireFailure("reuseEndedId").code)
        assertNull(useCases.activePackage(studentA).requireSuccess("stillNoActive"))
    }

    @Test
    fun activePackageDriftAfterConfirmationPromptRequiresReconfirmationWithZeroWrites(): Unit = offMain {
        val pkgA = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构课包A",
            totalCredits = 6L,
            startDate = LocalDate.of(2026, 11, 1),
            endDate = LocalDate.of(2026, 12, 31),
        )

        // Coach loads creation context seeing pkgA.
        val staleCtxResult = useCases.loadCreationContext(studentA)
        val staleCtx = staleCtxResult.requireSuccess("staleCtxResult")
        assertEquals(pkgA.coursePackageID, staleCtx.observedActivePackageID)

        // Before the coach confirms, pkgA is replaced by pkgB (e.g., another action completed).
        clock.advanceSeconds(30)
        val pkgBResult = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构课包B",
            totalCredits = 8L,
            startDate = LocalDate.of(2026, 11, 2),
            endDate = LocalDate.of(2027, 1, 31),
            observedActivePackageID = pkgA.coursePackageID,
            confirmReplaceActivePackage = true,
        )
        val pkgB = pkgBResult.requireSuccess("pkgBResult").requireSaved("pkgBResult")

        // Now the stale confirmation referencing pkgA is submitted.
        clock.advanceSeconds(30)
        val driftAttempt = useCases.createPackageWithContext(
            contextResult = staleCtxResult,
            name = "虚构课包C",
            totalCredits = 20L,
            confirmedByCoach = true,
        )
        val driftResult = driftAttempt.requireSuccess("driftAttempt").requireReconfirmation("driftAttempt")
        assertEquals(pkgB.coursePackageID, driftResult.currentActivePackage?.coursePackageID)

        // Verify zero writes occurred for pkgC: pkgB remains the sole active package.
        val allPackages = useCases.packages(studentA).requireSuccess("allPackages")
        assertEquals(2, allPackages.size)
        assertEquals(pkgB, useCases.activePackage(studentA).requireSuccess("activePackage"))
    }

    @Test
    fun activePackageEndedBeforeStaleConfirmationRequiresReconfirmationWithNullActive(): Unit = offMain {
        val pkgA = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构课包A",
            totalCredits = 4L,
        )
        val staleCtxResult = useCases.loadCreationContext(studentA)
        staleCtxResult.requireSuccess("staleCtxResult")

        // pkgA is explicitly ended before the confirmation is submitted.
        clock.advanceSeconds(10)
        val ended = useCases.endPackage(pkgA.coursePackageID).requireSuccess("endPackage")
        assertEquals(CoursePackageStatus.ended, ended.status)

        val attempt = useCases.createPackageWithContext(
            contextResult = staleCtxResult,
            name = "虚构课包B",
            totalCredits = 10L,
            confirmedByCoach = true,
        )
        val reconfirm = attempt.requireSuccess("attempt").requireReconfirmation("attempt")
        assertNull(reconfirm.currentActivePackage)

        // Still only pkgA (ended) in storage.
        val allPackages = useCases.packages(studentA).requireSuccess("allPackages")
        assertEquals(1, allPackages.size)
        assertNull(useCases.activePackage(studentA).requireSuccess("activePackage"))
    }

    @Test
    fun activePackageAppearingAfterNullObservationRequiresReconfirmationEvenForExpiredOrDepleted(): Unit = offMain {
        // Coach initially observes no active package (observedActivePackageID == null).
        val initialCtxResult = useCases.loadCreationContext(studentA)
        val initialCtx = initialCtxResult.requireSuccess("initialCtxResult")
        assertNull(initialCtx.observedActivePackageID)

        // 1. Meanwhile, a concurrent active package is created and depleted to 0 balance.
        val concurrentDepleted = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构并发耗尽课包",
            totalCredits = 2L,
        )
        useCases.recordManualCorrection(
            coursePackageID = concurrentDepleted.coursePackageID,
            direction = CreditDirection.debit,
            amount = 2L,
            reasonText = "虚构耗尽",
        ).requireSuccess("recordManualCorrection")

        // Submitting via the null-observation context must return RequiresReconfirmation and perform zero writes.
        val nullContextAttempt = useCases.createPackageWithContext(
            contextResult = initialCtxResult,
            name = "虚构新包A",
            totalCredits = 10L,
            confirmedByCoach = false,
        )
        val nullContextReconfirm = nullContextAttempt.requireSuccess("nullContextAttempt").requireReconfirmation("nullContextAttempt")
        assertEquals(concurrentDepleted.coursePackageID, nullContextReconfirm.currentActivePackage?.coursePackageID)
        assertEquals(CoursePackageStatus.active, useCases.activePackage(studentA).requireSuccess("stillActive")?.status)
        assertEquals(1, useCases.packages(studentA).requireSuccess("packages").size)

        // Direct call with observedActivePackageID = null also returns RequiresReconfirmation for a 0-balance active package.
        val directNullOnDepleted = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构新包B",
            totalCredits = 10L,
            observedActivePackageID = null,
            confirmReplaceActivePackage = false,
        )
        assertEquals(
            concurrentDepleted.coursePackageID,
            directNullOnDepleted.requireSuccess("directNullOnDepleted").requireReconfirmation("directNullOnDepleted")
                .currentActivePackage?.coursePackageID,
        )

        // 2. Replace with an already-expired active package (endDate = 2026-11-01 < today 2026-11-06) and test null observation again.
        val expiredPkg = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构并发过期课包",
            totalCredits = 5L,
            endDate = LocalDate.of(2026, 11, 1),
            observedActivePackageID = concurrentDepleted.coursePackageID,
            confirmReplaceActivePackage = false,
        ).requireSuccess("replaceWithExpired").requireSaved("replaceWithExpired")

        val nullAttemptOnExpired = useCases.createPackageWithContext(
            contextResult = initialCtxResult,
            name = "虚构新包C",
            totalCredits = 10L,
            confirmedByCoach = false,
        )
        assertEquals(
            expiredPkg.coursePackageID,
            nullAttemptOnExpired.requireSuccess("nullAttemptOnExpired").requireReconfirmation("nullAttemptOnExpired")
                .currentActivePackage?.coursePackageID,
        )
        assertEquals(expiredPkg.coursePackageID, useCases.activePackage(studentA).requireSuccess("expiredStillActive")?.coursePackageID)
        assertEquals(2, useCases.packages(studentA).requireSuccess("packagesAfterExpired").size)
    }

    @Test
    fun localTimeZoneDayBoundaryRequiresConfirmationWhenUtcHasAlreadyCrossedMidnight(): Unit = offMain {
        // Use America/Los_Angeles (UTC-8): at 2026-11-06T02:00:00Z, UTC is already 2026-11-06,
        // while the coach's local date is still 2026-11-05 (18:00 local).
        val laZone = ZoneId.of("America/Los_Angeles")
        clock = MutableAppClock(Instant.parse("2026-11-06T02:00:00Z"))
        closeAndReopenStack(laZone)

        // Package ends on 2026-11-05: expired in UTC (2026-11-06 > 2026-11-05), but NOT expired in LA (2026-11-05 == 2026-11-05).
        val pkg = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构跨日边界课包",
            totalCredits = 4L,
            startDate = LocalDate.of(2026, 10, 1),
            endDate = LocalDate.of(2026, 11, 5),
        )

        val ctx = useCases.loadCreationContext(studentA).requireSuccess("laContext")
        assertEquals(LocalDate.of(2026, 11, 5), ctx.asOf)
        assertTrue("Package is still valid on its local endDate and must require confirmation", ctx.requiresConfirmation)

        // Attempting to save without confirmation must NOT silently end the locally unexpired package.
        val unconfirmed = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构未确认新包",
            totalCredits = 10L,
            observedActivePackageID = pkg.coursePackageID,
            confirmReplaceActivePackage = false,
        )
        val reconfirm = unconfirmed.requireSuccess("unconfirmedInLa").requireReconfirmation("unconfirmedInLa")
        assertEquals(pkg.coursePackageID, reconfirm.currentActivePackage?.coursePackageID)
        assertEquals(pkg, useCases.activePackage(studentA).requireSuccess("stillActiveInLa"))
        assertEquals(1, useCases.packages(studentA).requireSuccess("onlyOnePackageInLa").size)

        // Also verify with Asia/Shanghai (UTC+8): at 2026-11-05T15:30:00Z (23:30 Shanghai), local date is 2026-11-05 (requires confirmation);
        // 1 hour later at 2026-11-05T16:30:00Z (00:30 Nov 6 Shanghai, while UTC is still Nov 5), local date is 2026-11-06 (expired).
        clock = MutableAppClock(Instant.parse("2026-11-05T15:30:00Z"))
        closeAndReopenStack(defaultZone)
        val beforeShanghaiMidnight = useCases.loadCreationContext(studentA).requireSuccess("beforeShanghaiMidnight")
        assertEquals(LocalDate.of(2026, 11, 5), beforeShanghaiMidnight.asOf)
        assertTrue(beforeShanghaiMidnight.requiresConfirmation)

        clock.advanceSeconds(3600)
        val afterShanghaiMidnight = useCases.loadCreationContext(studentA).requireSuccess("afterShanghaiMidnight")
        assertEquals(LocalDate.of(2026, 11, 6), afterShanghaiMidnight.asOf)
        assertFalse(afterShanghaiMidnight.requiresConfirmation)
    }

    @Test
    fun activePackageLookupFailureForbidsSaveAndReturnsRetryableErrorWithZeroWrites(): Unit = offMain {
        val existing = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构原课包",
            totalCredits = 6L,
        )

        val failingPort = FailingActiveLookupPort(delegate = repository)
        val useCasesWithFailingLookup = CreditUseCases(
            repository = failingPort,
            clock = clock,
            ids = ids,
            zoneID = defaultZone,
        )

        val ctxFailure = useCasesWithFailingLookup.loadCreationContext(studentA)
        assertEquals(
            ApplicationErrorCode.persistenceFailed,
            ctxFailure.requireFailure("ctxFailure").code,
        )
        assertEquals(1, failingPort.activeCallCount.get())

        // Saving via context Result fails and never calls repository.save or a duplicate repository.active.
        val saveViaCtx = useCasesWithFailingLookup.createPackageWithContext(
            contextResult = ctxFailure,
            name = "虚构不得写入课包",
            totalCredits = 10L,
            confirmedByCoach = false,
        )
        assertEquals(
            ApplicationErrorCode.persistenceFailed,
            saveViaCtx.requireFailure("saveViaCtx").code,
        )
        assertEquals(0, failingPort.saveCallCount.get())
        assertEquals(1, failingPort.activeCallCount.get())

        // Direct createActivePackage performs exactly one pre-read and does not call save when active lookup fails.
        val directSave = useCasesWithFailingLookup.createActivePackage(
            studentID = studentA,
            name = "虚构不得写入课包2",
            totalCredits = 10L,
        )
        assertEquals(
            ApplicationErrorCode.persistenceFailed,
            directSave.requireFailure("directSave").code,
        )
        assertEquals(0, failingPort.saveCallCount.get())
        assertEquals(2, failingPort.activeCallCount.get())

        // Underlying Room DB still has only the original package active.
        val packages = useCases.packages(studentA).requireSuccess("packages")
        assertEquals(listOf(existing), packages)
    }

    @Test
    fun expiredExistingActivePackageSavesAndEndsOldPackageWithoutExtraConfirmation(): Unit = offMain {
        // Clock is 2026-11-06 in Asia/Shanghai; endDate 2026-11-05 is expired.
        val expiredOld = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构已过期课包",
            totalCredits = 5L,
            startDate = LocalDate.of(2026, 10, 1),
            endDate = LocalDate.of(2026, 11, 5),
        )

        // Reading alone never auto-ends an expired package (FR-011/FR-012).
        val activeBeforeSave = useCases.activePackage(studentA).requireSuccess("activeBeforeSave")
        assertEquals(CoursePackageStatus.active, activeBeforeSave?.status)

        val ctxResult = useCases.loadCreationContext(studentA)
        val ctx = ctxResult.requireSuccess("loadCreationContext")
        assertFalse(ctx.requiresConfirmation)
        assertEquals(5L, ctx.existingActivePackageBalance)

        clock.advanceSeconds(30)
        val saveRes = useCases.createPackageWithContext(
            contextResult = ctxResult,
            name = "虚构接续新包",
            totalCredits = 10L,
            confirmedByCoach = false,
        )
        val created = saveRes.requireSuccess("saveRes").requireSaved("saveRes")
        assertEquals(CoursePackageStatus.active, created.status)

        val all = useCases.packages(studentA).requireSuccess("packages")
        assertEquals(2, all.size)
        val endedOld = all.first { it.coursePackageID == expiredOld.coursePackageID }
        assertEquals(CoursePackageStatus.ended, endedOld.status)
        assertEquals(5L, endedOld.remainingCreditsCache)
    }

    @Test
    fun zeroBalanceExistingActivePackageSavesAndEndsOldPackageWithoutExtraConfirmation(): Unit = offMain {
        val depletedOld = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构零余额课包",
            totalCredits = 3L,
            startDate = LocalDate.of(2026, 11, 1),
            endDate = LocalDate.of(2027, 11, 1),
        )
        useCases.recordManualCorrection(
            coursePackageID = depletedOld.coursePackageID,
            direction = CreditDirection.debit,
            amount = 3L,
            reasonText = "虚构全部用完",
        ).requireSuccess("recordManualCorrection")

        // Depletion alone never auto-ends the package.
        assertEquals(
            CoursePackageStatus.active,
            useCases.activePackage(studentA).requireSuccess("activePackage")?.status,
        )

        val ctxResult = useCases.loadCreationContext(studentA)
        val ctx = ctxResult.requireSuccess("loadCreationContext")
        assertEquals(0L, ctx.existingActivePackageBalance)
        assertFalse(ctx.requiresConfirmation)

        clock.advanceSeconds(30)
        val saveRes = useCases.createPackageWithContext(
            contextResult = ctxResult,
            name = "虚构续费课包",
            totalCredits = 8L,
            confirmedByCoach = false,
        )
        val created = saveRes.requireSuccess("saveRes").requireSaved("saveRes")
        assertEquals(CoursePackageStatus.active, created.status)

        val all = useCases.packages(studentA).requireSuccess("packages")
        assertEquals(2, all.size)
        val endedOld = all.first { it.coursePackageID == depletedOld.coursePackageID }
        assertEquals(CoursePackageStatus.ended, endedOld.status)
        assertEquals(0L, endedOld.remainingCreditsCache)
    }

    @Test
    fun reverseDatesWhereEndDatePrecedesStartDateAreSavedVerbatimPerD02(): Unit = offMain {
        val start = LocalDate.of(2026, 12, 15)
        val end = LocalDate.of(2026, 11, 1)
        val saved = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构反向日期课包",
            totalCredits = 6L,
            startDate = start,
            endDate = end,
        )
        assertEquals(start, saved.startDate)
        assertEquals(end, saved.endDate)
        assertEquals(CoursePackageStatus.active, saved.status)

        closeAndReopenStack()

        val reopened = useCases.activePackage(studentA).requireSuccess("activePackage")
        assertNotNull(reopened)
        assertEquals(start, reopened?.startDate)
        assertEquals(end, reopened?.endDate)
        assertEquals(CoursePackageStatus.active, reopened?.status)
    }

    @Test
    fun failedReplacementTransactionViaSqliteTriggerRollsBackOldPackageStatusAndClaim(): Unit = offMain {
        val original = createActivePackageDirectly(
            studentID = studentA,
            name = "虚构受保护旧包",
            totalCredits = 6L,
            startDate = LocalDate.of(2026, 11, 1),
            endDate = LocalDate.of(2027, 1, 1),
        )
        useCases.recordManualCorrection(
            coursePackageID = original.coursePackageID,
            direction = CreditDirection.debit,
            amount = 1L,
            reasonText = "虚构扣减",
        ).requireSuccess("recordManualCorrection")

        // Inject a failure AFTER old package UPDATE + claim DELETE, when inserting the new course_packages row.
        val sqlite = database.openHelper.writableDatabase
        sqlite.execSQL(
            """
            CREATE TRIGGER abort_new_package_insert
            BEFORE INSERT ON course_packages
            BEGIN
                SELECT RAISE(ABORT, 'injected course_packages insert failure');
            END
            """.trimIndent(),
        )

        clock.advanceSeconds(60)
        val failedSave = useCases.createActivePackage(
            studentID = studentA,
            name = "虚构失败新包",
            totalCredits = 10L,
            observedActivePackageID = original.coursePackageID,
            confirmReplaceActivePackage = true,
        )
        assertEquals(
            ApplicationErrorCode.persistenceFailed,
            failedSave.requireFailure("failedSave").code,
        )

        sqlite.execSQL("DROP TRIGGER abort_new_package_insert")

        // Verify in-memory and after reopen: original package is still active, claim intact, ledger intact.
        val activeNow = useCases.activePackage(studentA).requireSuccess("activeNow")
        assertEquals(original.coursePackageID, activeNow?.coursePackageID)
        assertEquals(CoursePackageStatus.active, activeNow?.status)
        assertEquals(5L, activeNow?.remainingCreditsCache)

        closeAndReopenStack()

        val activeAfterReopen = useCases.activePackage(studentA).requireSuccess("activeAfterReopen")
        assertEquals(original.coursePackageID, activeAfterReopen?.coursePackageID)
        assertEquals(CoursePackageStatus.active, activeAfterReopen?.status)
        assertEquals(5L, activeAfterReopen?.remainingCreditsCache)

        val packagesAfterReopen = useCases.packages(studentA).requireSuccess("packagesAfterReopen")
        assertEquals(1, packagesAfterReopen.size)
        val ledgerAfterReopen = useCases.ledger(studentA).requireSuccess("ledgerAfterReopen")
        assertEquals(1, ledgerAfterReopen.size)
    }

    @Test
    fun explicitEndPackageRetainsHistoryReleasesClaimAndRejectsDoubleEnd(): Unit = offMain {
        val pkg = createActivePackageDirectly(
            studentID = studentB,
            name = "虚构待结束课包",
            totalCredits = 4L,
        )
        clock.advanceSeconds(20)

        val endRes = useCases.endPackage(pkg.coursePackageID)
        val ended = endRes.requireSuccess("endPackage")
        assertEquals(CoursePackageStatus.ended, ended.status)
        assertNull(useCases.activePackage(studentB).requireSuccess("activePackage"))
        assertNull(database.s1Dao().findActivePackageClaim(UUID.fromString(studentB.value)))

        // Ending an already-ended package is rejected with invalidState.
        val secondEnd = useCases.endPackage(pkg.coursePackageID)
        assertEquals(
            ApplicationErrorCode.invalidState,
            secondEnd.requireFailure("secondEnd").code,
        )

        closeAndReopenStack()

        val listed = useCases.packages(studentB).requireSuccess("packages")
        assertEquals(listOf(ended), listed)
    }

    private suspend fun createActivePackageDirectly(
        studentID: StudentID,
        name: String?,
        totalCredits: Long,
        startDate: LocalDate? = null,
        endDate: LocalDate? = null,
    ): CoursePackageRecord {
        val res = useCases.createActivePackage(
            studentID = studentID,
            name = name,
            totalCredits = totalCredits,
            startDate = startDate,
            endDate = endDate,
        )
        return res.requireSuccess("createActivePackageDirectly").requireSaved("createActivePackageDirectly")
    }

    private class FailingActiveLookupPort(
        private val delegate: CoursePackageRepositoryPort,
    ) : CoursePackageRepositoryPort by delegate {
        val activeCallCount = AtomicInteger(0)
        val saveCallCount = AtomicInteger(0)

        override suspend fun active(
            studentID: StudentID,
            asOf: LocalDate,
        ): ApplicationResult<CoursePackageRecord?> {
            activeCallCount.incrementAndGet()
            return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
        }

        override suspend fun save(
            command: SaveCoursePackageCommand,
        ): ApplicationResult<SaveCoursePackageResult> {
            saveCallCount.incrementAndGet()
            return delegate.save(command)
        }
    }
}

internal fun <T> ApplicationResult<T>.requireSuccess(context: String = ""): T = when (this) {
    is ApplicationResult.Success -> value
    is ApplicationResult.Failure -> {
        val prefix = if (context.isEmpty()) "" else "$context: "
        throw AssertionError("${prefix}Expected Success but got Failure(code=${error.code})")
    }
}

internal fun <T> ApplicationResult<T>.requireFailure(context: String = ""): ApplicationError = when (this) {
    is ApplicationResult.Failure -> error
    is ApplicationResult.Success -> {
        val prefix = if (context.isEmpty()) "" else "$context: "
        throw AssertionError("${prefix}Expected Failure but got Success")
    }
}

internal fun SaveCoursePackageResult.requireSaved(context: String = ""): CoursePackageRecord = when (this) {
    is SaveCoursePackageResult.Saved -> record
    is SaveCoursePackageResult.RequiresReconfirmation -> {
        val prefix = if (context.isEmpty()) "" else "$context: "
        throw AssertionError("${prefix}Expected Saved but got RequiresReconfirmation")
    }
}

internal fun SaveCoursePackageResult.requireReconfirmation(
    context: String = "",
): SaveCoursePackageResult.RequiresReconfirmation = when (this) {
    is SaveCoursePackageResult.RequiresReconfirmation -> this
    is SaveCoursePackageResult.Saved -> {
        val prefix = if (context.isEmpty()) "" else "$context: "
        throw AssertionError("${prefix}Expected RequiresReconfirmation but got Saved")
    }
}

internal class MutableAppClock(initial: Instant) : AppClock {
    @Volatile
    private var current: Instant = initial

    override fun now(): Instant = current

    fun advanceSeconds(seconds: Long) {
        current = current.plusSeconds(seconds)
    }
}

internal class SequentialIDGenerator : StableIDGenerator {
    private val counter = AtomicInteger(0)

    private fun nextUUIDString(prefix: String): String {
        val n = counter.incrementAndGet()
        return "$prefix-0000-4000-8000-${n.toString().padStart(12, '0')}"
    }

    override fun newStudentID(): StudentID = StudentID.parse(nextUUIDString("11111111"))
    override fun newCoursePackageID(): CoursePackageID = CoursePackageID.parse(nextUUIDString("22222222"))
    override fun newCreditAdjustmentID(): CreditAdjustmentID = CreditAdjustmentID.parse(nextUUIDString("33333333"))
    override fun newSessionID(): SessionID = SessionID.parse(nextUUIDString("44444444"))
    override fun newTemplateID(): TemplateID = TemplateID.parse(nextUUIDString("55555555"))
    override fun newSectionID(): SectionID = SectionID.parse(nextUUIDString("66666666"))
    override fun newSessionExerciseID(): SessionExerciseID = SessionExerciseID.parse(nextUUIDString("77777777"))
    override fun newTemplateExerciseID(): TemplateExerciseID = TemplateExerciseID.parse(nextUUIDString("88888888"))
    override fun newTrainingSetID(): TrainingSetID = TrainingSetID.parse(nextUUIDString("99999999"))
    override fun newExerciseID(): StableExerciseID =
        StableExerciseID.parse("fictional-exercise-${counter.incrementAndGet()}")
}
