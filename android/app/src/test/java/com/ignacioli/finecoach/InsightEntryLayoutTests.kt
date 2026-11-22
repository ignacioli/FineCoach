// fictional-data: synthetic students, packages and catalog exercises only.
package com.ignacioli.finecoach

import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.width
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import com.ignacioli.finecoach.features.appointments.*
import com.ignacioli.finecoach.features.packages.CoursePackageListScreen
import com.ignacioli.finecoach.features.trends.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.insight.Insight
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.insights.*
import com.ignacioli.finecoach.features.students.StudentDetailScreen
import com.ignacioli.finecoach.navigation.S1Routes
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.local.InsightLocalStateStore
import com.ignacioli.finecoach.storage.repository.*
import java.io.File
import java.time.*
import java.util.UUID
import org.junit.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class InsightEntryLayoutTests {
    @get:Rule(order = 0) val privacy: org.junit.rules.TestRule = InsightTestPrivacyRule()
    @get:Rule(order = 1) val compose = createAndroidComposeRule<ComponentActivity>()
    private val zone = ZoneId.of("Asia/Shanghai")
    private var room: T009Fixture? = null
    private var directory: File? = null

    @After fun close() {
        Settings.Global.putString(ApplicationProvider.getApplicationContext<android.content.Context>().contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, null)
        compose.mainClock.autoAdvance = true
        room?.close(); room = null
        directory?.deleteRecursively()
    }

    @Test fun rowFillsWidthSnoozeUndoAndFullSwipeAndDisappearsAfterFourSeconds() {
        val harness = open()
        var student = StudentID.parse("00000000-0000-4000-8000-000000000000")
        harness.room.test {
            student = harness.student("虚构甲")
            harness.room.ok(harness.credits().createActivePackage(student, "虚构课包", 1, endDate = LocalDate.of(2025, 11, 2)))
            harness.store()
            harness.board.load()
        }
        val key = "package:${student.value}"
        show(harness.board)
        val row = compose.onNodeWithTag("insights.row.$key", useUnmergedTree = true)
        row.assertIsDisplayed().assertHasClickAction()
        compose.onNodeWithText("虚构甲 · 课包剩 1 节").assertIsDisplayed()
        compose.onNodeWithText("有效期至 11月2日").assertIsDisplayed()
        val parent = compose.onNodeWithTag("insight-parent").getUnclippedBoundsInRoot().width
        Assert.assertEquals(parent, row.getUnclippedBoundsInRoot().width)
        row.performClick()
        Assert.assertEquals(S1Routes.studentPackages(student), routes.single())
        compose.mainClock.autoAdvance = false
        val action = row.fetchSemanticsNode().config[SemanticsActions.CustomActions].single { it.label == "暂不提醒" }
        compose.runOnUiThread { Assert.assertTrue(action.action()) }
        pumpUntil("insights.undo.$key")
        val stored = File(harness.storeFile.parentFile, "local-state.json").readText()
        Assert.assertFalse(stored.contains("虚构"))
        Assert.assertTrue(stored.contains(key))
        compose.onNodeWithTag("insights.undo.$key-action").performClick()
        pumpUntil("insights.row.$key")
        Assert.assertFalse(File(harness.storeFile.parentFile, "local-state.json").readText().contains(key))
        compose.onNodeWithTag("insights.row.$key").performTouchInput { swipeLeft() }
        pumpUntil("insights.undo.$key")
        compose.mainClock.advanceTimeBy(4_100)
        compose.waitForIdle()
        compose.onAllNodesWithTag("insights.row.$key").assertCountEquals(0)
        compose.onAllNodesWithTag("today.insights").assertCountEquals(0)
    }

    @Test fun moreThanThreeShowsAllAndAResolvedConditionDisappearsOnNextLoad() {
        val harness = open()
        val ids = mutableListOf<StudentID>()
        harness.room.test {
            harness.room.now = Instant.parse("2025-08-01T04:00:00Z")
            repeat(4) { ids += harness.student("虚构${it + 1}") }
            harness.room.now = Instant.parse("2025-08-31T04:00:00Z")
            harness.store()
            harness.board.load()
        }
        show(harness.board)
        compose.onNodeWithTag("today.insights.all").assertIsDisplayed().assertHasClickAction()
        compose.onNodeWithText("全部 · 4").assertIsDisplayed()
        Assert.assertEquals(3, ids.count { compose.onAllNodesWithTag("insights.row.inactive:${it.value}").fetchSemanticsNodes().isNotEmpty() })
        compose.onNodeWithTag("today.insights.all").performClick()
        Assert.assertEquals(InsightRoutes.LIST, routes.single())
        harness.room.test {
            val appointments = harness.appointments()
            harness.room.ok(appointments.createSingle(com.ignacioli.finecoach.core.domain.appointment.Appointment(
                UUID.randomUUID(), ids[0], date = LocalDate.of(2025, 9, 2), startTime = LocalTime.of(15, 0),
                reminderEnabled = false, createdAtUTC = harness.room.now, updatedAtUTC = harness.room.now), overrideConflict = true))
            harness.board.load()
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("insights.row.inactive:${ids[0].value}").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithTag("today.insights.all").assertDoesNotExist()
        Assert.assertEquals(3, ids.count { compose.onAllNodesWithTag("insights.row.inactive:${it.value}").fetchSemanticsNodes().isNotEmpty() })
    }

    @Test fun threeDestinationsAndStudentDetailOmitsTheName() {
        val harness = open()
        var low = StudentID.parse("00000000-0000-4000-8000-000000000001")
        var away = StudentID.parse("00000000-0000-4000-8000-000000000002")
        var stuck = StudentID.parse("00000000-0000-4000-8000-000000000003")
        val squat = StableExerciseID.parse("a2f5b6ef-b780-49c0-8d96-fdaff23e27ce")
        harness.room.test {
            ExerciseRepository(harness.room.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<android.content.Context>().assets), harness.room.clock).prepareCatalog()
            low = harness.student("虚构甲")
            harness.room.now = Instant.parse("2025-08-01T04:00:00Z")
            away = harness.student("虚构乙")
            stuck = harness.student("虚构丙")
            repeat(4) { index ->
                val day = LocalDate.of(2025, 8, 1).plusDays((index * 8).toLong())
                harness.session(stuck, squat, "杠铃深蹲", if (index == 0) "102.5" else "90", if (index == 0) "1" else "4", day)
            }
            harness.room.now = Instant.parse("2025-08-31T04:00:00Z")
            harness.room.ok(harness.credits().createActivePackage(low, "虚构课包", 1, endDate = LocalDate.of(2025, 11, 2)))
            harness.store()
            harness.board.load()
        }
        showNavigation(harness)
        Assert.assertTrue("inactive accessible group", rowLabel("inactive:${away.value}").startsWith("很久没来，虚构乙，"))
        Assert.assertTrue("stagnant accessible group", rowLabel("stagnant:${stuck.value}:${squat.value}") == "进步停滞，虚构丙，杠铃深蹲，连续 3 节没有创新高")
        compose.onNodeWithTag("insights.row.package:${low.value}").performClick()
        compose.waitUntil(15_000) { exists("package-list-root") }
        compose.onNodeWithTag("package-list-root").assertIsDisplayed()
        page.value = "today"
        compose.onNodeWithTag("insights.row.inactive:${away.value}").performClick()
        compose.waitUntil(15_000) { exists("appointment-student") }
        Assert.assertTrue("prefilled student", editor?.studentID == away)
        Assert.assertTrue("create mode", editor?.editing == false)
        Assert.assertTrue("destination title", compose.onAllNodesWithText("新建课程安排").fetchSemanticsNodes().isNotEmpty())
        page.value = "today"
        compose.onNodeWithTag("insights.row.stagnant:${stuck.value}:${squat.value}").performClick()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("trends-exercise-name", useUnmergedTree = true).fetchSemanticsNodes().singleOrNull()?.config
                ?.getOrNull(SemanticsProperties.Text)?.singleOrNull()?.text == "杠铃深蹲"
        }
        Assert.assertTrue("trend destination", compose.onAllNodesWithText("训练趋势").fetchSemanticsNodes().isNotEmpty())
        Assert.assertTrue("selected exercise content", compose.onNodeWithTag("trends-exercise-name", useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsProperties.Text)?.singleOrNull()?.text == "杠铃深蹲")
        showDetail(harness.board, stuck)
        compose.onNodeWithText("杠铃深蹲 · 连续 3 节没有创新高").assertIsDisplayed()
        compose.onNodeWithText("估算 1RM 102.5 kg").assertIsDisplayed()
        compose.onNodeWithText("虚构丙", substring = true).assertDoesNotExist()
    }

    @Test fun nudgePlaysOnceAndIsSkippedWhenMotionIsOff() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        Settings.Global.putString(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, "0")
        val skipped = open()
        skipped.room.test {
            val student = skipped.student("虚构甲")
            skipped.room.ok(skipped.credits().createActivePackage(student, "虚构课包", 1))
            skipped.board.load()
        }
        show(skipped.board)
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(2_000)
        compose.waitForIdle()
        Assert.assertTrue("nudge skip", skipped.board.nudgePhase == "skipped")
        Assert.assertFalse(skipped.storeFile.exists() && skipped.storeFile.readText().contains("\"firstNudgePlayed\":true"))
        skipped.room.close(); room = null
        Settings.Global.putString(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, "1")
        val played = open()
        played.room.test {
            val student = played.student("虚构甲")
            played.room.ok(played.credits().createActivePackage(student, "虚构课包", 1))
            played.board.load()
        }
        show(played.board)
        compose.mainClock.autoAdvance = true
        compose.waitUntil(15_000) {
            played.board.nudgePhase == "done"
        }
        Assert.assertTrue("nudge completed", played.board.nudgePhase == "done")
        Assert.assertTrue(played.storeFile.readText().contains("\"firstNudgePlayed\":true"))
        played.room.test { played.board.load() }
        show(played.board)
        compose.mainClock.advanceTimeBy(2_000)
        compose.waitForIdle()
        Assert.assertTrue("nudge persisted", played.board.nudgePhase == "idle")
        val key = "package:${played.board.visible().single().studentID.value}"
        Assert.assertNull("internal phase is not exposed", compose.onNodeWithTag("insights.row.$key").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription))
    }

    @Test fun nextClassRowFillsWidthAndOpensTheScheduledClass() {
        val detail = StudentDetailS3Fixture()
        try {
            val opened = mutableListOf<java.util.UUID>()
            install {
                Box(Modifier.fillMaxWidth().testTag("insight-parent")) {
                    StudentDetailScreen(detail.state, {}, {}, autoLoad = false, insights = detail.board, onAppointment = { opened += it })
                }
            }
            val row = compose.onNodeWithTag("studentDetail.nextClass", useUnmergedTree = true)
            row.assertIsDisplayed().assertHasClickAction()
            Assert.assertEquals(compose.onNodeWithTag("platform-content", useUnmergedTree = true).getUnclippedBoundsInRoot().width, row.getUnclippedBoundsInRoot().width)
            row.performClick()
            Assert.assertEquals(detail.state.uiState.nextAppointment?.id, opened.single())
        } finally { detail.close() }
    }

    @Test fun allEntryRendersFullListAndRowOpensPrefilledAppointment() {
        val h = open()
        val ids = mutableListOf<StudentID>()
        h.room.test {
            h.room.now = Instant.parse("2025-08-01T04:00:00Z")
            repeat(4) { ids += h.student("虚构${it + 1}") }
            h.room.now = Instant.parse("2025-08-31T04:00:00Z")
            h.store(); h.board.load()
        }
        showNavigation(h)
        val all = compose.onNodeWithTag("today.insights.all")
        all.assertIsDisplayed().assertHasClickAction()
        Assert.assertEquals(compose.onNodeWithTag("insight-parent").getUnclippedBoundsInRoot().width, all.getUnclippedBoundsInRoot().width)
        all.performClick()
        compose.onNodeWithTag("insights-list-content").assertIsDisplayed()
        val row = compose.onNodeWithTag("insights.row.inactive:${ids.last().value}")
        row.performScrollTo().assertIsDisplayed().assertHasClickAction()
        Assert.assertEquals(compose.onNodeWithTag("insights-list-content").getUnclippedBoundsInRoot().width, row.getUnclippedBoundsInRoot().width)
        row.performClick()
        compose.waitUntil(15_000) { exists("appointment-student") }
        Assert.assertTrue("create destination", compose.onAllNodesWithText("新建课程安排").fetchSemanticsNodes().isNotEmpty())
        Assert.assertTrue("prefilled selected student", editor?.studentID == ids.last())
        Assert.assertTrue("student displayed", compose.onNodeWithTag("appointment-student").fetchSemanticsNode().config.getOrNull(SemanticsProperties.Text)?.any { it.text == "虚构4" } == true)
        h.room.test { Assert.assertTrue("navigation is read only", h.room.ok(h.appointments().all()).isEmpty()) }
    }

    @Test fun reloadAndListRoundTripKeepUndoUntilOriginalDeadline() {
        val h = open()
        var student = StudentID.parse("00000000-0000-4000-8000-000000000000")
        h.room.test {
            student = h.student("虚构甲")
            h.room.ok(h.credits().createActivePackage(student, "虚构课包", 1))
            h.store(); h.board.load()
        }
        val key = "package:${student.value}"
        show(h.board)
        compose.mainClock.autoAdvance = false
        compose.onNodeWithTag("insights.row.$key").performTouchInput { swipeLeft() }
        pumpUntil("insights.undo.$key")
        compose.mainClock.advanceTimeBy(1_000)
        h.room.test { h.board.load() }
        compose.onNodeWithTag("insights.undo.$key-action").assertIsDisplayed().performClick()
        pumpUntil("insights.row.$key")
        Assert.assertFalse("undo persisted", h.storeFile.readText().contains(key))
        compose.onNodeWithTag("insights.row.$key").performTouchInput { swipeLeft() }
        pumpUntil("insights.undo.$key")
        compose.mainClock.advanceTimeBy(2_000)
        install { InsightsListScreen(h.board, {}, {}) }
        h.room.test { h.board.load() }
        compose.onNodeWithTag("insights.undo.$key-action").assertIsDisplayed()
        show(h.board)
        compose.onNodeWithTag("insights.undo.$key-action").assertIsDisplayed()
        compose.mainClock.advanceTimeBy(2_100)
        compose.waitForIdle()
        Assert.assertTrue("expired pending removed", h.board.pending.isEmpty())
        Assert.assertTrue("snooze persisted", h.storeFile.readText().contains(key))
        compose.onNodeWithTag("today.insights").assertDoesNotExist()
    }

    @Test fun talkBackIncludesGroupCopyAndHidesDecorativeCapsule() {
        val h = open()
        var student = StudentID.parse("00000000-0000-4000-8000-000000000000")
        h.room.test {
            student = h.student("虚构甲")
            h.room.ok(h.credits().createActivePackage(student, "虚构课包", 1, endDate = LocalDate.of(2025, 11, 2)))
            h.board.load()
        }
        compose.mainClock.autoAdvance = false
        show(h.board)
        compose.mainClock.advanceTimeBy(320)
        compose.waitForIdle()
        val key = "package:${student.value}"
        val capsule = compose.onNodeWithTag("insights.nudge.$key", useUnmergedTree = true).fetchSemanticsNode()
        Assert.assertTrue("decorative capsule hidden", capsule.config.contains(SemanticsProperties.HideFromAccessibility))
        val label = compose.onNodeWithTag("insights.row.$key").fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)
        Assert.assertTrue("row accessible copy", label == listOf("课包，虚构甲，课包剩 1 节，有效期至 11月2日"))
        showDetail(h.board, student)
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        val detailLabel = compose.onNodeWithTag("insights.row.$key").fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)
        Assert.assertTrue("detail omits student", detailLabel == listOf("课包，课包剩 1 节，有效期至 11月2日"))
    }

    @Test fun nudgeFileReadRunsOffMainThread() {
        val observed = java.util.concurrent.atomic.AtomicReference<Boolean>()
        val h = open(readPlayed = {
            observed.set(android.os.Looper.myLooper() == android.os.Looper.getMainLooper())
            true
        })
        install { LaunchedEffect(Unit) { h.board.load() } }
        compose.waitUntil(15_000) { observed.get() != null }
        Assert.assertTrue("file read must run in background", observed.get() == false)
    }

    private fun rowLabel(key: String): String = compose.onNodeWithTag("insights.row.$key").fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.singleOrNull().orEmpty()

    private val page = mutableStateOf("today")
    private var editor: AppointmentEditorState? = null
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun showNavigation(h: Harness) = install {
        val route = page.value
        val parts = route.split('/')
        when {
            route == "today" -> Box(Modifier.fillMaxWidth().testTag("insight-parent")) {
                InsightTodaySection(h.board, { page.value = insightDestination(it, LocalDate.of(2025, 8, 31)).orEmpty() }, { page.value = "insights" })
            }
            route == "insights" -> InsightsListScreen(h.board, { page.value = "today" }, { page.value = insightDestination(it, LocalDate.of(2025, 8, 31)).orEmpty() })
            route.startsWith("appointments/create/") -> {
                val state = androidx.compose.runtime.remember(route) {
                    AppointmentEditorState(h.appointments(), h.students, h.room.clock, zone, LocalDate.parse(parts[2])).also {
                        it.studentID = StudentID.parse(parts[4]); editor = it
                    }
                }
                AppointmentEditorScreen(state, { page.value = "today" }, {})
            }
            route.contains("/trends/") -> {
                val state = androidx.compose.runtime.remember(route) {
                    TrendsState(StudentID.parse(parts[1]), h.progress, zone).also { it.selectExercise(StableExerciseID.parse(parts[3])) }
                }
                LaunchedEffect(state) { state.load() }
                TrendsScreen(state) { page.value = "today" }
            }
            route.endsWith("/packages") -> CoursePackageListScreen(StudentID.parse(parts[1]), h.credits(), zone, {}, {}, {}, {}, students = h.students)
            else -> error("Unexpected destination shape")
        }
    }

    private fun pumpUntil(tag: String) {
        val paused = !compose.mainClock.autoAdvance
        compose.mainClock.autoAdvance = true
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        if (paused) compose.mainClock.autoAdvance = false
    }

    private val screen = mutableStateOf<@Composable () -> Unit>({})
    private var composed = false
    private fun install(content: @Composable () -> Unit) {
        screen.value = content
        if (!composed) {
            composed = true
            compose.setContent { FineCoachTheme { screen.value() } }
        }
        compose.waitForIdle()
    }

    private fun show(board: InsightBoardState) = install {
        Box(Modifier.fillMaxWidth().testTag("insight-parent")) {
            InsightTodaySection(board, { boardDestination(it) }, { routesOf(board) })
        }
    }

    private fun showDetail(board: InsightBoardState, student: StudentID) = install {
        Box(Modifier.fillMaxWidth().testTag("insight-parent")) {
            InsightStudentSection(board, student) {}
        }
    }

    private val routes = mutableListOf<String>()
    private fun boardDestination(insight: Insight) { routes += insightDestination(insight, LocalDate.of(2025, 8, 31)).orEmpty() }
    private fun routesOf(board: InsightBoardState) { routes += InsightRoutes.LIST }

    private fun open(readPlayed: (() -> Boolean)? = null): Harness {
        routes.clear()
        val fixture = T009Fixture().also { room = it }
        val folder = File(ApplicationProvider.getApplicationContext<android.content.Context>().cacheDir, "insight-${UUID.randomUUID()}").also { directory = it; it.mkdirs() }
        fixture.now = Instant.parse("2025-08-31T04:00:00Z")
        lateinit var students: StudentUseCases
        lateinit var board: InsightBoardState
        lateinit var booked: AppointmentUseCases
        lateinit var progress: ProgressUseCases
        fixture.test {
            students = StudentUseCases(StudentRepository(fixture.db, fixture.clock), fixture.clock, fixture.ids)
            progress = ProgressUseCases(fixture.history, fixture.sessions)
            val repository = AppointmentRepository(fixture.db, fixture.clock, fixture.ids, generation(fixture), fixture.sessions, zone)
            booked = AppointmentUseCases(repository)
            val store = InsightLocalStateStore(folder)
            board = InsightBoardState(InsightUseCases(StudentRepository(fixture.db, fixture.clock), progress, repository, credits(fixture),
                { ApplicationResult.Success(emptySet()) }, store::activeKeys, store::snooze, store::unsnooze, readPlayed ?: store::firstNudgePlayed, store::markFirstNudgePlayed),
                students, { ExerciseRepository(fixture.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<android.content.Context>().assets), fixture.clock).listCatalog() },
                fixture.clock, zone, monotonicMillis = { compose.mainClock.currentTime })
        }
        return Harness(fixture, students, board, File(folder, "Insights/local-state.json"), booked, progress)
    }

    private fun credits(fixture: T009Fixture) = CreditUseCases(CoursePackageRepository(fixture.db, fixture.clock, fixture.ids, zone), fixture.clock, fixture.ids, zone)
    private fun generation(fixture: T009Fixture) = UUID.fromString(fixture.db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value)

    private class Harness(val room: T009Fixture, val students: StudentUseCases, val board: InsightBoardState, val storeFile: File, private val booked: AppointmentUseCases, val progress: ProgressUseCases) {
        suspend fun student(name: String): StudentID = room.ok(students.create(StudentDraft(name, StudentSex.undisclosed))).studentID
        fun credits() = CreditUseCases(CoursePackageRepository(room.db, room.clock, room.ids, ZoneId.of("Asia/Shanghai")), room.clock, room.ids, ZoneId.of("Asia/Shanghai"))
        suspend fun store() { InsightLocalStateStore(storeFile.parentFile!!.parentFile!!).markFirstNudgePlayed() }
        fun appointments() = booked
        suspend fun session(student: StudentID, source: StableExerciseID, name: String, weight: String, reps: String, day: LocalDate) {
            val at = day.atTime(12, 0).atZone(ZoneId.of("Asia/Shanghai")).toInstant()
            room.now = at
            val opened = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(student, nowUTC = at)))
            val exerciseID = room.ids.newSessionExerciseID()
            val set = TrainingSet.makeDraft(room.ids.newTrainingSetID(), exerciseID, 0u, TrainingSetInput(RecordMode.weightReps,
                weightValue = weight, repetitionCount = reps, unit = MeasurementUnit.kilograms), at).confirmed(at)
            val row = SessionExercise(exerciseID, opened.sessionID, 0u, ExerciseSourceKind.builtIn, source, NormalizedName.parse(name),
                RecordMode.weightReps, null, null, listOf(set)).toRecord()
            val saved = room.ok(room.sessions.saveContent(SaveSessionContentCommand(opened.sessionID, opened.revision, emptyList(), listOf(row))))
            room.ok(FinishSessionUseCases(room.sessions, room.active, credits(), room.history, room.clock, ZoneId.of("Asia/Shanghai")).finish(saved.session.sessionID, saved.session.revision))
        }
    }
}
