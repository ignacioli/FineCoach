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
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.appointments.AppointmentListState
import com.ignacioli.finecoach.features.insights.InsightBoardState
import com.ignacioli.finecoach.features.today.TodayS2Screen
import com.ignacioli.finecoach.features.today.TodayUiState
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
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h1013dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TodayS3ConformanceTests {
    @get:Rule(order = 0) val privacy: org.junit.rules.TestRule = InsightTestPrivacyRule()
    @get:Rule(order = 1) val compose = createAndroidComposeRule<ComponentActivity>()
    private var fixture: TodayS3Fixture? = null
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
        val f = TodayS3Fixture().also { fixture = it }
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                FineCoachTheme { Box(Modifier.requiredSize(390.dp, 1013.dp).background(FcColors.surfacePage).testTag("conformance-viewport")) {
                    Box(Modifier.fillMaxSize().background(FcColors.surfacePage).testTag("conformance:Rectangle")) {
                        TodayS2Screen(f.training, f.list, {}, {}, {}, {}, insights = f.board)
                    }
                } }
            }
        } }
        compose.waitUntil(15_000) { exists("hero-${f.sessionID.value}") && exists("today.insights") }
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        node("platform-content").assertTopPositionInRootIsEqualTo(52.dp)
        for (text in listOf("8月31日 · 周日", "王小明 · 大腿", "已训练 32 分钟", "15:00", "张伟", "李娜 · 胸", "赵强 · 背",
            "已处理 · 3", "需要留意", "李娜 · 课包剩 1 节", "有效期至 11月2日", "刘洋 · 21 天没来", "也没约下次课",
            "王小明 · 杠铃深蹲", "连续 3 节没有创新高", "全部 · 5")) {
            compose.onNodeWithText(text, useUnmergedTree = true).assertIsDisplayed()
        }
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        val image = node("conformance-viewport").captureToImage().asAndroidBitmap()
        check(image.width == 780 && image.height == 2026)
        File(out, "01-today-s3.android.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        val all = compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes().flatMap { root ->
            fun descendants(n: SemanticsNode): List<SemanticsNode> = listOf(n) + n.children.flatMap(::descendants)
            descendants(root)
        }.distinctBy { it.id }
        val nodes = JSONArray()
        for (n in all) {
            val texts = n.config.getOrNull(SemanticsProperties.Text)?.map { it.text }.orEmpty()
            val editable = n.config.getOrNull(SemanticsProperties.EditableText)?.text
            val layouts = mutableListOf<TextLayoutResult>()
            n.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            val color = layouts.firstOrNull()?.layoutInput?.style?.color
            val argb = if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) "#%06x".format(color.toArgb() and 0xffffff) else null
            val bounds = n.boundsInRoot
            val unclipped = JSONObject().put("x", n.positionInRoot.x / 2).put("y", n.positionInRoot.y / 2)
                .put("w", n.size.width / 2.0).put("h", n.size.height / 2.0)
            val scrollAncestors = JSONArray()
            generateSequence(n.parent) { it.parent }.filter { it.config.contains(SemanticsActions.ScrollBy) }.forEach { parent ->
                val b = parent.boundsInRoot
                scrollAncestors.put(JSONObject().put("tag", parent.config.getOrNull(SemanticsProperties.TestTag) ?: "")
                    .put("x", b.left / 2).put("y", b.top / 2).put("w", b.width / 2).put("h", b.height / 2))
            }
            val ancestors = generateSequence(n.parent) { it.parent }.mapNotNull { it.config.getOrNull(SemanticsProperties.TestTag) }.toList()
            nodes.put(JSONObject().put("id", n.id).put("tag", n.config.getOrNull(SemanticsProperties.TestTag) ?: "")
                .put("heading", n.config.contains(SemanticsProperties.Heading)).put("ancestors", JSONArray(ancestors))
                .put("contentDescriptions", JSONArray(n.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty()))
                .put("clickable", n.config.contains(SemanticsActions.OnClick)).put("text", editable ?: texts.joinToString("\n"))
                .put("placed", n.layoutInfo.isPlaced).put("attached", n.layoutInfo.isAttached)
                .put("unclipped", unclipped).put("scrollAncestors", scrollAncestors)
                .put("textAlign", layouts.firstOrNull()?.layoutInput?.style?.textAlign?.toString() ?: "Start")
                .put("hex", argb ?: JSONObject.NULL)
                .put("alpha", if (color != null && color != androidx.compose.ui.graphics.Color.Unspecified) color.alpha.toDouble() else 1.0)
                .put("x", bounds.left / 2).put("y", bounds.top / 2).put("w", bounds.width / 2).put("h", bounds.height / 2))
        }
        return nodes
    }
    @Test fun todayS3Conformance() {
        val app = File(System.getProperty("finecoach.storageProjectDirectory"))
        val android = app.parentFile
        val out = File(app, "build/outputs/conformance/01-today-s3").apply { mkdirs() }
        val hashes = mutableListOf<String>()
        var nodes = JSONArray()
        for (run in 1..2) {
            nodes = render(out)
            val bytes = File(out, "01-today-s3.android.png").readBytes()
            hashes += MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            File(out, "01-today-s3.run$run.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
            close()
        }
        File(out, "01-today-s3.nodes.json").writeText(JSONObject().put("nodes", nodes).toString(2))
        val result = ConformanceComparison.run(android, out, nodes, emptyMap(), "01-today-s3", "design/m1-b-hifi/screens/01-today-s3.png")
        result.put("stability", JSONObject().put("renderCount", 2).put("sha256", JSONArray(hashes)).put("stable", hashes.distinct().size == 1))
        result.put("humanReadSummary", "批准 PNG 查看一次；未打开 Android capture。负责人视觉验收 PENDING。")
        ConformanceComparison.writeReports(out, result)
        Assert.assertEquals("VALID_FIXTURE", result.getString("artifactStatus"))
        Assert.assertEquals("Fixture must be stable", 1, hashes.distinct().size)
        Assert.assertTrue("Today S3 strict: " + "failed=${result.getInt("failed")} missing=${result.getInt("missing")}", result.getBoolean("gatePassed"))
    }
}

internal class TodayS3Fixture : AutoCloseable {
    val room = T008Fixture()
    val zone = ZoneId.of("Asia/Shanghai")
    val date: LocalDate = LocalDate.of(2025, 8, 31)
    lateinit var list: AppointmentListState
    lateinit var training: TodayUiState
    lateinit var board: InsightBoardState
    var sessionID: SessionID = SessionID.parse("00000000-0000-4000-8000-000000000099")
    init {
        room.test {
            val students = StudentUseCases(StudentRepository(room.db, room.clock), room.clock, room.ids)
            listOf("王小明", "张伟", "李娜", "赵强", "刘洋", "虚构戊", "虚构己").forEachIndexed { i, name ->
                room.student(i + 1)
                room.db.openHelper.writableDatabase.execSQL(
                    "UPDATE students SET displayName = ? WHERE id = ?", arrayOf(name, room.studentID(i + 1).value))
            }
            val exercises = room.exercises
            exercises.prepareCatalog()
            val squat = exercises.listCatalog().let { (it as ApplicationResult.Success).value }
                .single { it.canonicalName == "杠铃深蹲" }.exerciseID
            val sessions = room.sessions
            val credits = CreditUseCases(CoursePackageRepository(room.db, room.clock, room.ids, zone), room.clock, room.ids, zone)
            val history = HistoryRepository(room.db, room.clock, room.generation, zone)
            val finisher = FinishSessionUseCases(sessions, room.useCases, credits, history, room.clock, zone)
            suspend fun finished(n: Int, day: LocalDate, weight: String, reps: String, focus: Set<BodyPart> = emptySet()) {
                val at = day.atTime(12, 0).atZone(zone).toInstant()
                room.time = at
                val opened = room.ok(sessions.startOrOpen(StartOrOpenSessionCommand(room.studentID(n), focus, at)))
                val exerciseID = room.ids.newSessionExerciseID()
                val set = TrainingSet.makeDraft(room.ids.newTrainingSetID(), exerciseID, 0u, TrainingSetInput(RecordMode.weightReps,
                    weightValue = weight, repetitionCount = reps, unit = MeasurementUnit.kilograms), at).confirmed(at)
                val row = SessionExercise(exerciseID, opened.sessionID, 0u, ExerciseSourceKind.builtIn, squat,
                    NormalizedName.parse("杠铃深蹲"), RecordMode.weightReps, null, null, listOf(set)).toRecord()
                val saved = room.ok(sessions.saveContent(SaveSessionContentCommand(opened.sessionID, opened.revision, emptyList(), listOf(row))))
                room.ok(finisher.finish(saved.session.sessionID, saved.session.revision))
            }
            listOf(0, 8, 16, 24).forEachIndexed { index, offset ->
                finished(1, LocalDate.of(2025, 8, 1).plusDays(offset.toLong()), if (index == 0) "102.5" else "90", if (index == 0) "1" else "4")
            }
            finished(5, LocalDate.of(2025, 8, 10), "40", "8")
            for (n in listOf(6, 7)) {
                listOf(0, 8, 16, 24).forEachIndexed { index, offset ->
                    finished(n, LocalDate.of(2025, 8, 1).plusDays(offset.toLong()), if (index == 0) "80" else "70", "5")
                }
            }
            val appointments = AppointmentUseCases(AppointmentRepository(room.db, room.clock, room.ids, room.generation, sessions, zone))
            list = AppointmentListState(appointments, students, room.clock, zone)
            training = TodayUiState(sessions, students, room.clock, zone)
            room.time = date.atTime(12, 0).atZone(zone).toInstant()
            suspend fun add(n: Int, time: String, focus: Set<BodyPart> = emptySet()): Appointment =
                room.ok(appointments.createSingle(Appointment(UUID.randomUUID(), room.studentID(n), date = date,
                    startTime = LocalTime.parse(time), trainingFocus = focus, reminderEnabled = false,
                    createdAtUTC = room.time, updatedAtUTC = room.time), overrideConflict = true)).single()
            room.time = room.time.minusSeconds(32 * 60)
            sessionID = room.ok(sessions.startOrOpen(StartOrOpenSessionCommand(room.studentID(1), setOf(BodyPart.thighs), room.time))).sessionID
            room.time = room.time.plusSeconds(32 * 60)
            add(2, "15:00", setOf(BodyPart.thighs))
            add(3, "17:30", setOf(BodyPart.chest))
            add(4, "19:00", setOf(BodyPart.back))
            for (n in 1..3) room.ok(appointments.cancel(add(n, "0${n + 6}:00").id))
            room.ok(credits.createActivePackage(room.studentID(3), "虚构课包", 1, endDate = LocalDate.of(2025, 11, 2)))
            val folder = File(ApplicationProvider.getApplicationContext<Context>().cacheDir, "today-s3-${UUID.randomUUID()}").apply { mkdirs() }
            val store = InsightLocalStateStore(folder)
            store.markFirstNudgePlayed()
            val progress = ProgressUseCases(history, sessions)
            board = InsightBoardState(InsightUseCases(StudentRepository(room.db, room.clock), progress,
                AppointmentRepository(room.db, room.clock, room.ids, room.generation, sessions, zone), credits,
                { ApplicationResult.Success(emptySet()) }, store::activeKeys, store::snooze, store::unsnooze,
                store::firstNudgePlayed, store::markFirstNudgePlayed), students,
                { exercises.listCatalog() }, room.clock, zone)
            board.load()
            check(board.visible().size == 5)
        }
    }
    override fun close() = room.close()
}
