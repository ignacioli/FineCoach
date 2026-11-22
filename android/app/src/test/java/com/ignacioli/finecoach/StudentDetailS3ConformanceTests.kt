// fictional-data: approved synthetic screen examples; no real coach/student data.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.appointment.Appointment
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.insights.InsightBoardState
import com.ignacioli.finecoach.features.students.StudentDetailScreen
import com.ignacioli.finecoach.features.students.StudentDetailViewModel
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.local.InsightLocalStateStore
import com.ignacioli.finecoach.storage.repository.*
import java.io.File
import java.security.MessageDigest
import java.time.*
import java.util.UUID
import org.junit.*
import org.junit.runner.RunWith
import org.json.JSONArray
import org.json.JSONObject
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h1243dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StudentDetailS3ConformanceTests {
    @get:Rule(order = 0) val privacy: org.junit.rules.TestRule = InsightTestPrivacyRule()
    @get:Rule(order = 1) val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: StudentDetailS3Fixture? = null
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    @After fun close() {
        compose.mainClock.autoAdvance = true
        compose.runOnUiThread { compose.activity.setContent {} }
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        fixture?.close(); fixture = null
    }
    private fun render(out: File): JSONArray {
        val f = StudentDetailS3Fixture().also { fixture = it }
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { Box(Modifier.requiredSize(390.dp, 1243.dp).background(FcColors.surfacePage).testTag("conformance-viewport")) {
                    Box(Modifier.fillMaxSize().background(FcColors.surfacePage).testTag("conformance:Rectangle")) {
                        StudentDetailScreen(f.state, {}, {}, autoLoad = false, insights = f.board)
                    }
                } }
            }
        } }
        compose.waitUntil(15_000) { exists("studentDetail.startTraining") && exists("studentDetail.insights") }
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        node("platform-content").assertTopPositionInRootIsEqualTo(52.dp)
        for (text in listOf("王小明", "训练目标 · 增肌", "需要留意", "杠铃深蹲 · 连续 3 节没有创新高", "估算 1RM 102.5 kg",
            "哑铃肩上推举 · 连续 3 节没有创新高", "最大 22.5 kg", "9月27日 周六 15:00 · 大腿、臀", "8",
            "/ 共 20 课时 · 有效期至 12月31日", "9月25日 · 大腿、臀 · 12 组", "训练历史", "训练趋势", "身体数据",
            "已隐藏 · 点击查看", "开始训练")) {
            compose.onNodeWithText(text, useUnmergedTree = true).assertIsDisplayed()
        }
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        check(image.width == 780 && image.height == 2486)
        File(out, "26-student-detail-s3.android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        val all = compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes().flatMap { root ->
            fun descendants(n: SemanticsNode): List<SemanticsNode> = listOf(n) + n.children.flatMap(::descendants)
            descendants(root)
        }.distinctBy { it.id }
        val nodes = JSONArray()
        for (n in all) {
            val texts = n.config.getOrNull(SemanticsProperties.Text)?.map { it.text }.orEmpty()
            val layouts = mutableListOf<TextLayoutResult>()
            n.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            val color = layouts.firstOrNull()?.layoutInput?.style?.color
            val argb = if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) "#%06x".format(color.toArgb() and 0xffffff) else null
            val bounds = n.boundsInRoot
            nodes.put(JSONObject().put("id", n.id).put("tag", n.config.getOrNull(SemanticsProperties.TestTag) ?: "")
                .put("heading", n.config.contains(SemanticsProperties.Heading))
                .put("ancestors", JSONArray(generateSequence(n.parent) { it.parent }.mapNotNull { it.config.getOrNull(SemanticsProperties.TestTag) }.toList()))
                .put("contentDescriptions", JSONArray(n.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty()))
                .put("clickable", n.config.contains(SemanticsActions.OnClick)).put("text", texts.joinToString("\n"))
                .put("placed", n.layoutInfo.isPlaced).put("attached", n.layoutInfo.isAttached)
                .put("unclipped", JSONObject().put("x", n.positionInRoot.x / 2).put("y", n.positionInRoot.y / 2).put("w", n.size.width / 2.0).put("h", n.size.height / 2.0))
                .put("scrollAncestors", JSONArray())
                .put("textAlign", layouts.firstOrNull()?.layoutInput?.style?.textAlign?.toString() ?: "Start")
                .put("hex", argb ?: JSONObject.NULL)
                .put("alpha", if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) color.alpha.toDouble() else 1.0)
                .put("x", bounds.left / 2).put("y", bounds.top / 2).put("w", bounds.width / 2).put("h", bounds.height / 2))
        }
        return nodes
    }
    @Test fun studentDetailS3Conformance() {
        val app = File(System.getProperty("finecoach.storageProjectDirectory"))
        val android = app.parentFile
        val out = File(app, "build/outputs/conformance/26-student-detail-s3").apply { mkdirs() }
        val hashes = mutableListOf<String>()
        var nodes = JSONArray()
        for (run in 1..2) {
            nodes = render(out)
            hashes += MessageDigest.getInstance("SHA-256").digest(File(out, "26-student-detail-s3.android.png").readBytes()).joinToString("") { "%02x".format(it) }
            close()
        }
        File(out, "26-student-detail-s3.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
        val result = ConformanceComparison.run(android, out, nodes, emptyMap(), "26-student-detail-s3", "design/m1-b-hifi/screens/26-student-detail-s3.png")
        result.put("stability", JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1))
        result.put("humanReadSummary", "批准 PNG 查看一次；未打开 Android capture。负责人视觉验收 PENDING。")
        ConformanceComparison.writeReports(out, result)
        Assert.assertEquals("VALID_FIXTURE", result.getString("artifactStatus"))
        Assert.assertEquals(1, hashes.distinct().size)
        Assert.assertTrue("Student detail S3 strict: " + "failed=${result.getInt("failed")} missing=${result.getInt("missing")}", result.getBoolean("gatePassed"))
    }
}

internal class StudentDetailS3Fixture : AutoCloseable {
    val room = T009Fixture()
    val zone = ZoneId.of("Asia/Shanghai")
    lateinit var state: StudentDetailViewModel
    lateinit var board: InsightBoardState
    init {
        room.test {
            room.now = Instant.parse("2025-08-30T04:00:00Z")
            val students = StudentUseCases(StudentRepository(room.db, room.clock), room.clock, room.ids)
            val student = room.ok(students.create(StudentDraft("王小明", StudentSex.male, trainingGoal = "增肌", injuryNotes = "左膝旧伤，避免深屈膝跳跃")))
            val exercises = ExerciseRepository(room.db, ExerciseCatalogLoader(ApplicationProvider.getApplicationContext<Context>().assets), room.clock)
            exercises.prepareCatalog()
            val catalog = (exercises.listCatalog() as ApplicationResult.Success).value
            val squat = catalog.single { it.canonicalName == "杠铃深蹲" }.exerciseID
            val press = catalog.single { it.canonicalName == "哑铃肩上推举" }.exerciseID
            val generation = UUID.fromString(room.db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value)
            suspend fun session(day: LocalDate, squatWeight: String, squatReps: String, pressWeight: String) {
                val at = day.atTime(12, 0).atZone(zone).toInstant()
                room.now = at
                val opened = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(student.studentID, nowUTC = at)))
                fun row(index: Int, source: StableExerciseID, name: String, weight: String, reps: String): SessionExerciseRecord {
                    val exerciseID = room.ids.newSessionExerciseID()
                    val set = TrainingSet.makeDraft(room.ids.newTrainingSetID(), exerciseID, 0u, TrainingSetInput(RecordMode.weightReps,
                        weightValue = weight, repetitionCount = reps, unit = MeasurementUnit.kilograms), at).confirmed(at)
                    return SessionExercise(exerciseID, opened.sessionID, index.toUInt(), ExerciseSourceKind.builtIn, source,
                        NormalizedName.parse(name), RecordMode.weightReps, null, null, listOf(set)).toRecord()
                }
                val saved = room.ok(room.sessions.saveContent(SaveSessionContentCommand(opened.sessionID, opened.revision, emptyList(),
                    listOf(row(0, squat, "杠铃深蹲", squatWeight, squatReps), row(1, press, "哑铃肩上推举", pressWeight, "8")))))
                room.finish(saved)
            }
            session(LocalDate.of(2025, 8, 30), "102.5", "1", "22.5")
            for (day in listOf(LocalDate.of(2025, 9, 7), LocalDate.of(2025, 9, 15), LocalDate.of(2025, 9, 23))) session(day, "90", "4", "20")
            room.now = Instant.parse("2025-09-25T07:00:00Z")
            val started = room.ok(room.sessions.startOrOpen(StartOrOpenSessionCommand(student.studentID, setOf(BodyPart.thighs, BodyPart.glutes), room.now)))
            val exerciseID = room.ids.newSessionExerciseID()
            val sets = (0 until 12).map { index ->
                TrainingSet.makeDraft(room.ids.newTrainingSetID(), exerciseID, index.toUInt(), TrainingSetInput(RecordMode.weightReps,
                    weightValue = "20", repetitionCount = "10", unit = MeasurementUnit.kilograms), room.now).confirmed(room.now)
            }
            val content = room.ok(room.sessions.saveContent(SaveSessionContentCommand(started.sessionID, started.revision, emptyList(),
                listOf(SessionExercise(exerciseID, started.sessionID, 0u, ExerciseSourceKind.sessionOnly, null, NormalizedName.parse("虚构腿部训练"),
                    RecordMode.weightReps, null, null, sets).toRecord()))))
            room.finish(content)
            room.now = Instant.parse("2025-09-26T02:00:00Z")
            val pkg = (room.ok(room.credits.createActivePackage(student.studentID, "虚构课包", 20, endDate = LocalDate.of(2025, 12, 31))) as SaveCoursePackageResult.Saved).record
            room.ok(room.credits.recordManualCorrection(pkg.coursePackageID, CreditDirection.debit, 12, "虚构历史课时"))
            val appointments = AppointmentUseCases(AppointmentRepository(room.db, room.clock, room.ids, generation, room.sessions, zone))
            room.ok(appointments.createSingle(Appointment(UUID.randomUUID(), student.studentID, date = LocalDate.of(2025, 9, 27),
                startTime = LocalTime.of(15, 0), trainingFocus = setOf(BodyPart.thighs, BodyPart.glutes), reminderEnabled = false,
                createdAtUTC = room.now, updatedAtUTC = room.now), overrideConflict = true))
            state = StudentDetailViewModel(student.studentID, students, room.sessions, room.credits, room.history, room.clock, zone, appointments)
            state.reload()
            val folder = File(ApplicationProvider.getApplicationContext<Context>().cacheDir, "detail-s3-${UUID.randomUUID()}").apply { mkdirs() }
            val store = InsightLocalStateStore(folder)
            store.markFirstNudgePlayed()
            board = InsightBoardState(InsightUseCases(StudentRepository(room.db, room.clock), ProgressUseCases(room.history, room.sessions),
                AppointmentRepository(room.db, room.clock, room.ids, generation, room.sessions, zone), room.credits,
                { ApplicationResult.Success(emptySet()) }, store::activeKeys, store::snooze, store::unsnooze, store::firstNudgePlayed, store::markFirstNudgePlayed),
                students, { exercises.listCatalog() }, room.clock, zone)
            board.load()
            check(board.visible(student.studentID).size == 2)
        }
    }
    override fun close() = room.close()
}
