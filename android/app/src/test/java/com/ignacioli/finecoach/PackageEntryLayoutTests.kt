// fictional-data: course package names, dates, balances, and ledger reasons in this file are fictional fixtures.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.ApplicationError
import com.ignacioli.finecoach.core.application.ApplicationErrorCode
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CoursePackageRecord
import com.ignacioli.finecoach.core.application.CoursePackageRepositoryPort
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.SaveCoursePackageCommand
import com.ignacioli.finecoach.core.application.SaveCoursePackageResult
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CoursePackageStatus
import com.ignacioli.finecoach.core.domain.common.CreditDirection
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.packages.CoursePackageEditorScreen
import com.ignacioli.finecoach.features.packages.ManualCreditAdjustmentScreen
import com.ignacioli.finecoach.features.packages.PackageRouteHost
import com.ignacioli.finecoach.features.packages.packageIdFromDetailRoute
import com.ignacioli.finecoach.navigation.S1Routes
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.repository.CoursePackageRepository
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Callable
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w360dp-h800dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PackageEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var context: Context
    private lateinit var database: FineCoachDatabase
    private lateinit var clock: MutableAppClock
    private lateinit var ids: SequentialIDGenerator
    private lateinit var repository: CoursePackageRepository
    private lateinit var useCases: CreditUseCases
    private lateinit var zone: ZoneId

    private val student = StudentID.parse("10000000-0000-4000-8000-0000000000a1")

    private fun <T> offMain(action: suspend () -> T): T =
        worker.submit(Callable { runBlocking { action() } }).get(20, TimeUnit.SECONDS)

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        zone = ZoneId.of("Asia/Shanghai")
        clock = MutableAppClock(Instant.parse("2026-11-06T04:00:00Z"))
        ids = SequentialIDGenerator()
        openFresh()
    }

    @After
    fun tearDown() {
        try {
            if (::database.isInitialized && database.isOpen) offMain { database.close() }
        } finally {
            worker.shutdownNow()
            if (::context.isInitialized) context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    private fun openFresh() {
        database = FineCoachDatabaseFactory.create(context)
        repository = CoursePackageRepository(database, clock, ids, zone)
        useCases = CreditUseCases(repository, clock, ids, zone)
    }

    private fun reopen() {
        if (::database.isInitialized && database.isOpen) offMain { database.close() }
        openFresh()
    }

    private fun useZone(zoneID: ZoneId, instant: Instant) {
        zone = zoneID
        clock = MutableAppClock(instant)
        reopen()
    }

    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)

    private fun awaitTag(tag: String) {
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun awaitText(text: String) {
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun packages(): List<CoursePackageRecord> = offMain { useCases.packages(student).requireSuccess("packages") }

    private fun createPackage(
        name: String,
        totalCredits: Long,
        startDate: LocalDate? = null,
        endDate: LocalDate? = null,
        cases: CreditUseCases = useCases,
    ): CoursePackageRecord = offMain {
        cases.createActivePackage(
            studentID = student,
            name = name,
            totalCredits = totalCredits,
            startDate = startDate,
            endDate = endDate,
            observedActivePackageID = null,
            confirmReplaceActivePackage = false,
        ).requireSuccess("create").requireSaved("create")
    }

    private fun showHost(cases: CreditUseCases = useCases, onExit: () -> Unit = {}) {
        compose.setContent {
            FineCoachTheme {
                PackageRouteHost(student, cases, clock, zone, onExit)
            }
        }
    }

    @Test(timeout = 30_000)
    fun noActivePackageCopyIsVisibleWithoutAnyMutation() {
        showHost(); awaitTag("package-list-none")
        node("package-list-none").performScrollTo().assertIsDisplayed()
        assertTrue(packages().isEmpty())
    }

    @Test(timeout = 30_000)
    fun cancelReplacementLeavesTheActivePackage() {
        val original = createPackage("虚构旧课包", 8, LocalDate.of(2026, 10, 1), LocalDate.of(2026, 12, 31))
        showHost()
        awaitTag("package-list-add")
        node("package-list-add").assertIsDisplayed().assertHasClickAction().performClick()
        awaitTag("package-editor-save")
        awaitTag("package-editor-warning")
        node("package-editor-warning").performScrollTo().assertIsDisplayed()
        node("package-editor-name").performTextInput("虚构未确认课包")
        node("package-editor-save").performScrollTo().assertIsEnabled().performClick()
        awaitTag("package-replace-cancel")
        node("package-replace-accept").assertIsDisplayed().assertHasClickAction()
        node("package-replace-cancel").assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitForIdle()
        val afterCancel = packages()
        assertEquals(1, afterCancel.size)
        assertEquals(original.coursePackageID, afterCancel.single().coursePackageID)
        assertEquals(CoursePackageStatus.active, afterCancel.single().status)
        node("package-editor-back").performClick()
        awaitTag("package-list-root")
        assertEquals(listOf(original.coursePackageID), packages().map { it.coursePackageID })
    }

    @Test(timeout = 30_000)
    fun confirmReplacementEndsTheShownPackage() {
        val original = createPackage("虚构旧课包", 8, LocalDate.of(2026, 10, 1), LocalDate.of(2026, 12, 31))
        showHost()
        awaitTag("package-list-add")
        node("package-list-add").performClick()
        awaitTag("package-editor-save")
        node("package-editor-name").performTextInput("虚构新课包")
        node("package-editor-save").performScrollTo().performClick()
        awaitText("该学员已有有效课包「虚构旧课包」，剩余 8 课时。新建将结束当前课包，历史记录会保留。确认继续？")
        node("package-replace-accept").performClick()
        awaitTag("package-list-manual")
        val loaded = packages()
        assertEquals(2, loaded.size)
        val ended = loaded.single { it.coursePackageID == original.coursePackageID }
        assertEquals(CoursePackageStatus.ended, ended.status)
        val active = loaded.filter { it.status == CoursePackageStatus.active }
        assertEquals(1, active.size)
        assertEquals("虚构新课包", active.single().name)
        assertFalse(active.single().coursePackageID == original.coursePackageID)
    }

    @Test(timeout = 30_000)
    fun changedActivePackageIsConfirmedAgainWithoutASilentWrite() {
        val original = createPackage("虚构旧课包", 8, LocalDate.of(2026, 10, 1), LocalDate.of(2026, 12, 31))
        showHost()
        awaitTag("package-list-add")
        node("package-list-add").performClick()
        awaitTag("package-editor-name")
        node("package-editor-name").performTextInput("虚构替换课包")
        node("package-editor-save").performScrollTo().performClick()
        awaitTag("package-replace-accept")
        val replacement = offMain {
            useCases.endPackage(original.coursePackageID).requireSuccess("end")
            useCases.createActivePackage(
                studentID = student,
                name = "虚构并发课包",
                totalCredits = 4,
                observedActivePackageID = null,
                confirmReplaceActivePackage = false,
            ).requireSuccess("replace").requireSaved("replace")
        }
        node("package-replace-accept").performClick()
        awaitText("该学员已有有效课包「虚构并发课包」，剩余 4 课时。新建将结束当前课包，历史记录会保留。确认继续？")
        assertEquals(
            0,
            compose.onAllNodesWithText("虚构旧课包", substring = true, useUnmergedTree = true).fetchSemanticsNodes().size,
        )
        val beforeSecondConfirm = packages()
        assertEquals(2, beforeSecondConfirm.size)
        assertTrue(beforeSecondConfirm.none { it.name == "虚构替换课包" })
        assertEquals(CoursePackageStatus.active, beforeSecondConfirm.single { it.coursePackageID == replacement.coursePackageID }.status)
        node("package-replace-accept").performClick()
        awaitTag("package-list-manual")
        val after = packages()
        assertEquals(3, after.size)
        assertEquals(CoursePackageStatus.ended, after.single { it.coursePackageID == replacement.coursePackageID }.status)
        val created = after.single { it.name == "虚构替换课包" }
        assertEquals(CoursePackageStatus.active, created.status)
        assertEquals(1, after.count { it.status == CoursePackageStatus.active })
    }

    @Test(timeout = 30_000)
    fun expiredPackageReplacesWithoutConfirmationAndReverseDatesPersist() {
        showHost()
        awaitTag("package-list-add")
        node("package-list-add").performClick()
        awaitTag("package-editor-has-start")
        node("package-editor-has-start").performClick()
        node("package-editor-has-end").performScrollTo().performClick()
        node("package-editor-end").performScrollTo().performClick()
        selectNovemberFirst()
        node("date-accept").performClick()
        awaitText("2026年11月1日")
        node("package-editor-name").performTextInput("虚构反向日期课包")
        node("package-editor-save").performScrollTo().performClick()
        awaitTag("package-list-manual")
        val reversed = packages().single()
        assertEquals(LocalDate.of(2026, 11, 6), reversed.startDate)
        assertEquals(LocalDate.of(2026, 11, 1), reversed.endDate)
        assertEquals(CoursePackageStatus.active, reversed.status)
        node("package-list-add").performScrollTo().performClick()
        awaitTag("package-editor-save")
        node("package-editor-name").performTextInput("虚构接续课包")
        node("package-editor-save").performScrollTo().performClick()
        awaitTag("package-list-manual")
        assertEquals(0, compose.onAllNodesWithTag("package-replace-accept", useUnmergedTree = true).fetchSemanticsNodes().size)
        val loaded = packages()
        assertEquals(CoursePackageStatus.ended, loaded.single { it.coursePackageID == reversed.coursePackageID }.status)
        val successor = loaded.single { it.status == CoursePackageStatus.active }
        assertEquals("虚构接续课包", successor.name)
        assertEquals(1, loaded.count { it.status == CoursePackageStatus.active })
    }

    @Test(timeout = 30_000)
    fun localCalendarDayStaysPutAndAnInEffectPackageStillNeedsConfirmation() {
        val previousZone = TimeZone.getDefault()
        val previousLocale = Locale.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
            Locale.setDefault(Locale.US)
            useZone(ZoneId.of("America/Los_Angeles"), Instant.parse("2026-11-06T02:00:00Z"))
            val original = createPackage("虚构跨日课包", 4, LocalDate.of(2026, 10, 1), LocalDate.of(2026, 11, 5))
            compose.setContent {
                FineCoachTheme {
                    CoursePackageEditorScreen(student, useCases, clock, zone, onBack = {}, onSaved = {})
                }
            }
            awaitTag("package-editor-has-start")
            node("package-editor-has-start").performClick()
            awaitText("2026年11月5日")
            node("package-editor-start").performClick()
            awaitTag("date-picker")
            node("date-accept").performClick()
            awaitText("2026年11月5日")
            node("package-editor-save").performScrollTo().performClick()
            awaitTag("package-replace-cancel")
            node("package-replace-cancel").performClick()
            val after = packages()
            assertEquals(listOf(original.coursePackageID), after.map { it.coursePackageID })
            assertEquals(CoursePackageStatus.active, after.single().status)
        } finally {
            TimeZone.setDefault(previousZone)
            Locale.setDefault(previousLocale)
        }
    }

    @Test(timeout = 30_000)
    fun zeroBalanceReplacementEndsWithoutAnExtraConfirmation() {
        val depleted = createPackage("虚构零余额课包", 3, LocalDate.of(2026, 11, 1), LocalDate.of(2027, 11, 1))
        offMain {
            useCases.recordManualCorrection(
                coursePackageID = depleted.coursePackageID,
                direction = CreditDirection.debit,
                amount = 3,
                reasonText = "虚构全部用完",
            ).requireSuccess("debit")
        }
        showHost()
        awaitTag("package-list-add")
        node("package-list-add").performClick()
        awaitTag("package-editor-save")
        node("package-editor-name").performTextInput("虚构续费课包")
        node("package-editor-save").performScrollTo().performClick()
        awaitTag("package-list-manual")
        assertEquals(0, compose.onAllNodesWithTag("package-replace-card", useUnmergedTree = true).fetchSemanticsNodes().size)
        val loaded = packages()
        assertEquals(CoursePackageStatus.ended, loaded.single { it.coursePackageID == depleted.coursePackageID }.status)
        assertEquals(0L, loaded.single { it.coursePackageID == depleted.coursePackageID }.remainingCreditsCache)
        assertEquals("虚构续费课包", loaded.single { it.status == CoursePackageStatus.active }.name)
    }

    @Test(timeout = 30_000)
    fun lookupFailureDisablesSaveUntilRetry() {
        val original = createPackage("虚构原课包", 6)
        val failing = FailActivePort(repository)
        val failingCases = CreditUseCases(failing, clock, ids, zone)
        compose.setContent {
            FineCoachTheme {
                CoursePackageEditorScreen(student, failingCases, clock, zone, onBack = {}, onSaved = {})
            }
        }
        awaitTag("package-editor-load-retry")
        node("package-editor-save").assertIsDisplayed().assertIsNotEnabled()
        node("package-editor-load-retry").assertIsDisplayed().assertHasClickAction()
        assertEquals(listOf(original.coursePackageID), packages().map { it.coursePackageID })
        failing.failActive.set(false)
        node("package-editor-load-retry").performClick()
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodesWithTag("package-editor-save", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() &&
                compose.onAllNodesWithTag("package-editor-load-retry", useUnmergedTree = true).fetchSemanticsNodes().isEmpty()
        }
        node("package-editor-save").assertIsEnabled()
        assertEquals(CoursePackageStatus.active, packages().single().status)
        assertEquals(original.coursePackageID, packages().single().coursePackageID)
    }

    @Test(timeout = 30_000)
    fun saveInFlightRejectsAnotherClick() {
        val gate = GatedSavePort(repository)
        val gated = CreditUseCases(gate, clock, ids, zone)
        compose.setContent {
            FineCoachTheme {
                CoursePackageEditorScreen(student, gated, clock, zone, onBack = {}, onSaved = {})
            }
        }
        awaitTag("package-editor-save")
        compose.waitUntil(timeoutMillis = 5_000) {
            try {
                node("package-editor-save").assertIsEnabled()
                true
            } catch (_: AssertionError) {
                false
            }
        }
        node("package-editor-save").performClick()
        node("package-editor-save").assertIsNotEnabled()
        gate.entered.get(5, TimeUnit.SECONDS)
        assertEquals(1, gate.saveCalls.get())
        gate.release.complete(Unit)
        compose.waitUntil(timeoutMillis = 5_000) { packages().size == 1 }
        assertEquals(1, gate.saveCalls.get())
        assertEquals(CoursePackageStatus.active, packages().single().status)
    }

    @Test(timeout = 30_000)
    fun insufficientDebitIsRejectedAndCreditReturnPersists() {
        val original = createPackage("虚构小课包", 1)
        showHost()
        awaitTag("package-list-manual")
        node("package-list-manual").assertIsDisplayed().assertHasClickAction().performClick()
        awaitTag("manual-adjustment-direction-0")
        node("manual-adjustment-direction-0").assertIsDisplayed().assertHasClickAction()
        node("manual-adjustment-direction-1").assertIsDisplayed().assertHasClickAction()
        node("manual-adjustment-amount-plus").performClick()
        node("package-manual-reason").performTextInput("虚构多扣")
        node("package-manual-save").performScrollTo().assertIsEnabled().performClick()
        awaitTag("package-manual-error")
        node("package-manual-error").assertTextEquals("扣减后余额将为负，检查课时数。")
        val balanceAfterReject = offMain { useCases.balance(student, original.coursePackageID).requireSuccess("balance") }
        assertEquals(1L, balanceAfterReject)
        assertEquals(0, offMain { useCases.adjustmentsForPackage(student, original.coursePackageID).requireSuccess("ledger") }.size)
        node("manual-adjustment-direction-1").performClick()
        node("package-manual-save").performScrollTo().performClick()
        awaitTag("package-list-balance")
        node("package-list-balance").assertTextEquals("3")
        val ledger = offMain { useCases.adjustmentsForPackage(student, original.coursePackageID).requireSuccess("ledger") }
        assertEquals(1, ledger.size)
        assertEquals(CreditDirection.credit, ledger.single().direction)
        assertEquals(2L, ledger.single().amount)
        assertEquals(3L, offMain { useCases.balance(student, original.coursePackageID).requireSuccess("balance") })
    }

    @Test(timeout = 30_000)
    fun manualAdjustmentBackAndSystemBackWriteNothing() {
        val original = createPackage("虚构未保存调整", 6)
        val packageId = original.coursePackageID
        val balanceBefore = offMain { useCases.balance(student, packageId).requireSuccess("balance") }
        val ledgerBefore = offMain { useCases.adjustmentsForPackage(student, packageId).requireSuccess("ledger") }.size
        showHost()
        awaitTag("package-list-manual")
        node("package-list-manual").assertIsDisplayed().assertHasClickAction().performClick()
        fillManualDraft()
        node("package-manual-back").assertIsDisplayed().assertHasClickAction().performClick()
        awaitTag("package-list-manual")
        assertUnchangedAfterReopen(packageId, balanceBefore, ledgerBefore)
        node("package-list-manual").performClick()
        fillManualDraft()
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        awaitTag("package-list-manual")
        assertUnchangedAfterReopen(packageId, balanceBefore, ledgerBefore)
        reopen()
        assertEquals(balanceBefore, offMain { useCases.balance(student, packageId).requireSuccess("balance") })
        assertEquals(ledgerBefore, offMain { useCases.adjustmentsForPackage(student, packageId).requireSuccess("ledger") }.size)
    }

    @Test(timeout = 30_000)
    fun endPackageCancelKeepsItAndConfirmEndsIt() {
        val original = createPackage("虚构在用课包", 6)
        showHost()
        awaitTag("package-list-end")
        node("package-list-end").assertIsDisplayed().assertHasClickAction().performClick()
        awaitTag("package-end-cancel")
        node("package-end-accept").assertIsDisplayed().assertHasClickAction()
        node("package-end-cancel").assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitForIdle()
        assertEquals(CoursePackageStatus.active, packages().single().status)
        node("package-list-end").performClick()
        node("package-end-accept").performClick()
        awaitTag("package-row-${original.coursePackageID.value}")
        assertEquals(CoursePackageStatus.ended, packages().single().status)
        assertEquals(original.coursePackageID, packageIdFromDetailRoute(S1Routes.packageDetail(original.coursePackageID)))
    }

    @Test(timeout = 30_000)
    fun ledgerTrailShowsTheManualDebit() {
        val original = createPackage("虚构流水课包", 10, LocalDate.of(2026, 11, 1), null)
        showHost()
        awaitTag("package-list-manual")
        node("package-list-manual").performClick()
        awaitTag("package-manual-reason")
        node("package-manual-reason").performTextInput("虚构补记")
        node("package-manual-save").performScrollTo().performClick()
        awaitText("扣减 1 课时")
        node("package-list-end").performScrollTo().performClick()
        node("package-end-accept").performClick()
        awaitTag("package-row-${original.coursePackageID.value}")
        node("package-row-${original.coursePackageID.value}").assertHasClickAction().performClick()
        awaitTag("package-trail-root")
        awaitText("扣减 1 课时")
        awaitText("人工调整 · 虚构补记")
        node("package-trail-adjustment-${offMain {
            useCases.adjustmentsForPackage(student, original.coursePackageID).requireSuccess("ledger").single().creditAdjustmentID.value
        }}").assertIsDisplayed()
        node("package-trail-back").assertHasClickAction().performClick()
        awaitTag("package-list-root")
        assertEquals(CoursePackageStatus.ended, packages().single().status)
    }

    @Test(timeout = 30_000)
    fun controlsFillTheirParentWidth() {
        showHost()
        awaitTag("package-list-add")
        assertSameWidth("package-list-body", "package-list-add")
        node("package-list-add").performClick()
        awaitTag("package-editor-save")
        node("package-editor-name").performTextInput("虚构宽度课包")
        node("package-editor-save").performScrollTo()
        assertSameWidth("package-editor-form", "package-editor-save")
        assertSameWidth("package-editor-name-slot", "package-editor-name")
        node("package-editor-save").assertIsEnabled().performClick()
        awaitTag("package-list-manual")
        assertEquals("虚构宽度课包", packages().single().name)
        assertSameWidth("package-list-body", "package-list-manual")
        node("package-list-add").assertIsDisplayed()
        node("package-list-manual").performClick()
        awaitTag("package-manual-save")
        node("package-manual-save").performScrollTo()
        assertSameWidth("package-manual-form", "package-manual-save")
        assertSameWidth("package-manual-reason-slot", "package-manual-reason")
    }

    @Test(timeout = 30_000)
    fun primaryActionRemainsReachableAboveTheBottomInset() {
        compose.setContent {
            FineCoachTheme {
                CoursePackageEditorScreen(
                    studentID = student,
                    useCases = useCases,
                    clock = clock,
                    zoneID = zone,
                    onBack = {},
                    onSaved = {},
                    windowInsets = WindowInsets(0.dp, 0.dp, 0.dp, 520.dp),
                )
            }
        }
        awaitTag("package-editor-name")
        node("package-editor-name").performTextInput("虚构键盘课包")
        node("package-editor-save").performScrollTo().assertIsDisplayed().assertHasClickAction()
        val safe = node("platform-safe").getUnclippedBoundsInRoot()
        val save = node("package-editor-save").getUnclippedBoundsInRoot()
        assertTrue(save.top >= safe.top)
        assertTrue(save.bottom <= safe.bottom)
        node("package-editor-save").performClick()
        compose.waitUntil(timeoutMillis = 5_000) { packages().size == 1 }
        assertEquals("虚构键盘课包", packages().single().name)
        assertEquals(CoursePackageStatus.active, packages().single().status)
    }

    @Test(timeout = 30_000)
    fun backAndSystemBackWriteNothing() {
        val exits = AtomicInteger(0)
        showHost(onExit = { exits.incrementAndGet() })
        awaitTag("package-list-add")
        node("package-list-add").performClick()
        awaitTag("package-editor-name")
        node("package-editor-name").performTextInput("虚构返回课包")
        node("package-editor-back").assertHasClickAction().performClick()
        awaitTag("package-list-add")
        assertEquals(0, packages().size)
        node("package-list-add").performClick()
        awaitTag("package-editor-name")
        node("package-editor-name").performTextInput("虚构系统返回课包")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        awaitTag("package-list-add")
        assertEquals(0, packages().size)
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.waitUntil(timeoutMillis = 5_000) { exits.get() == 1 }
        assertEquals(0, packages().size)
    }

    private fun fillManualDraft() {
        awaitTag("manual-adjustment-direction-1")
        node("manual-adjustment-direction-1").assertIsDisplayed().assertHasClickAction().performClick()
        node("manual-adjustment-amount-plus").assertIsDisplayed().assertHasClickAction().performClick()
    }

    private fun assertUnchangedAfterReopen(packageId: CoursePackageID, balance: Long, ledgerSize: Int) {
        val fresh = FineCoachDatabaseFactory.create(context)
        try {
            val cases = CreditUseCases(CoursePackageRepository(fresh, clock, ids, zone), clock, ids, zone)
            assertEquals(balance, offMain { cases.balance(student, packageId).requireSuccess("balance") })
            assertEquals(ledgerSize, offMain { cases.adjustmentsForPackage(student, packageId).requireSuccess("ledger") }.size)
        } finally {
            offMain { if (fresh.isOpen) fresh.close() }
        }
    }

    private fun assertSameWidth(parent: String, child: String) {
        val parentBounds = node(parent).getUnclippedBoundsInRoot()
        val childBounds = node(child).getUnclippedBoundsInRoot()
        assertEquals(parentBounds.right - parentBounds.left, childBounds.right - childBounds.left)
    }

    private fun selectNovemberFirst() {
        awaitTag("date-picker")
        val day = hasAnyAncestor(hasTestTag("date-picker"))
            .and(hasText("2026年11月1日", substring = true))
            .and(hasClickAction())
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodes(day, useUnmergedTree = false).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onAllNodes(day, useUnmergedTree = false)[0].performClick()
    }

    private class FailActivePort(
        private val delegate: CoursePackageRepositoryPort,
    ) : CoursePackageRepositoryPort by delegate {
        val failActive = AtomicBoolean(true)

        override suspend fun active(
            studentID: StudentID,
            asOf: LocalDate,
        ): ApplicationResult<CoursePackageRecord?> {
            if (failActive.get()) {
                return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
            }
            return delegate.active(studentID, asOf)
        }
    }

    private class GatedSavePort(
        private val delegate: CoursePackageRepositoryPort,
    ) : CoursePackageRepositoryPort by delegate {
        val saveCalls = AtomicInteger(0)
        val entered = CompletableFuture<Unit>()
        val release = CompletableDeferred<Unit>()

        override suspend fun save(
            command: SaveCoursePackageCommand,
        ): ApplicationResult<SaveCoursePackageResult> {
            val call = saveCalls.incrementAndGet()
            if (call == 1) {
                entered.complete(Unit)
                release.await()
            }
            return delegate.save(command)
        }
    }
}
