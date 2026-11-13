// fictional-data: names, dates and injury notes reproduce synthetic design examples only.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.semantics.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.core.domain.template.*
import com.ignacioli.finecoach.features.exercises.*
import com.ignacioli.finecoach.features.templates.*
import com.ignacioli.finecoach.features.session.*
import com.ignacioli.finecoach.features.history.*
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import javax.imageio.ImageIO
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.packages.*
import com.ignacioli.finecoach.features.students.*
import com.ignacioli.finecoach.storage.entity.CreditAdjustmentEntity
import com.ignacioli.finecoach.storage.repository.StudentRepository
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class P7SideBySideTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var releaseFixture: (() -> Unit)? = null
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun await(tag: String) = compose.waitUntil(15_000) {
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

    @After fun close() {
        compose.mainClock.autoAdvance = true
        compose.runOnUiThread { compose.activity.setContent {} }
        compose.mainClock.advanceTimeByFrame()
        compose.waitForIdle()
        releaseFixture?.invoke()
        releaseFixture = null
    }

    private fun show(content: @Composable () -> Unit) {
        compose.runOnUiThread {
            compose.activity.setContent {
                CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                    FineCoachTheme { ConformanceViewport { content() } }
                }
            }
        }
    }

    private fun measure(id: String, composable: String, fixture: String, mismatches: String, sheetTag: String? = null, scrollTag: String? = null, designPath: String? = null, render: () -> String) {
        var reason: String? = null
        val bitmap = try {
            await(render())
            compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
            compose.waitForIdle()
            compose.mainClock.autoAdvance = false
            compose.mainClock.advanceTimeBy(1000)
            compose.waitForIdle()
val first = node("conformance-viewport").captureToImage().asAndroidBitmap()
when {
    sheetTag != null -> captureSheet(first, sheetTag)
    scrollTag != null -> {
        val scroll = node(scrollTag)
        val range = scroll.fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange]
        val before = range.value()
        val viewport = scroll.fetchSemanticsNode().boundsInRoot.height
        val frames = mutableListOf(first)
        val positions = mutableListOf(before)
        while (range.value() < range.maxValue() && frames.size < 10) {
            val old = range.value()
            scroll.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, viewport) }
            compose.mainClock.advanceTimeBy(500)
            compose.waitForIdle()
            if (range.value() <= old) break
            positions += range.value()
            frames += node("conformance-viewport").captureToImage().asAndroidBitmap()
        }
        check(range.value() >= range.maxValue()) { "Scroll did not reach end: ${range.value()} / ${range.maxValue()}" }
        File(p7Output(), "$id.scroll.txt").writeText("requested=$viewport px; before=$before; after=${range.value()}; max=${range.maxValue()}; positions=$positions; viewports=${frames.size}; full viewports retain repeated chrome")
        if (frames.size == 1) first else Bitmap.createBitmap(780, 1688 * frames.size, Bitmap.Config.ARGB_8888).also {
            val canvas = Canvas(it)
            frames.forEachIndexed { n, frame -> canvas.drawBitmap(frame, 0f, n * 1688f, null); frame.recycle() }
        }
    }

    else -> first
}
        } catch (failure: Exception) {
            reason = "${failure.javaClass.simpleName}: ${failure.message.orEmpty()}"
            P7SheetWriter.placeholder(reason)
        } catch (failure: AssertionError) {
            reason = "${failure.javaClass.simpleName}: ${failure.message.orEmpty()}"
            P7SheetWriter.placeholder(reason)
        }
        P7SheetWriter.write(id, bitmap, composable, fixture, mismatches, reason, designPath)
        bitmap.recycle()
    }

private fun p7Output() = File(checkNotNull(System.getProperty("finecoach.storageProjectDirectory")), "build/outputs/p7").apply { mkdirs() }

private fun buffered(bitmap: Bitmap) = ByteArrayOutputStream().use { bytes ->
    check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes))
    ImageIO.read(ByteArrayInputStream(bytes.toByteArray()))
}

private fun captureSheet(activity: Bitmap, panelTag: String): Bitmap {
    fun descendants(n: SemanticsNode): List<SemanticsNode> = listOf(n) + n.children.flatMap(::descendants)
    val dialogs = compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes()
        .flatMap(::descendants).distinctBy { it.id }.filter { it.config.contains(SemanticsProperties.IsDialog) }
    check(dialogs.isNotEmpty()) { "No real dialog window for $panelTag" }
    val windows = dialogs.map { dialog ->
        val image = compose.onNode(SemanticsMatcher("dialog id") { it.id == dialog.id }, useUnmergedTree = true)
            .captureToImage().asAndroidBitmap()
        ConformanceCapture.Window(buffered(image), dialog.boundsInWindow.left.toInt(), dialog.boundsInWindow.top.toInt()).also { image.recycle() }
    }
    val base = buffered(activity)
    val composite = ConformanceCapture.composite(base, windows)
    val panel = node(panelTag).fetchSemanticsNode().boundsInWindow
    var contributed = 0
    val colors = mutableSetOf<Int>()
    for (y in panel.top.toInt().coerceAtLeast(0) until panel.bottom.toInt().coerceAtMost(1688))
        for (x in panel.left.toInt().coerceAtLeast(0) until panel.right.toInt().coerceAtMost(780)) {
            if (base.getRGB(x, y) != composite.getRGB(x, y)) contributed++
            colors += composite.getRGB(x, y)
        }
    check(contributed > 0 && colors.size > 1) { "Sheet pixels absent/uniform: $panelTag; contribution=$contributed; colors=${colors.size}" }
    File(p7Output(), "$panelTag.capture.txt").writeText("windows=${windows.size}; panel=$panel; windowContributionPixels=$contributed; distinctColors=${colors.size}")
    activity.recycle()
    return Bitmap.createBitmap(composite.width, composite.height, Bitmap.Config.ARGB_8888).also {
        it.setPixels(composite.getRGB(0, 0, composite.width, composite.height, null, 0, composite.width), 0, composite.width, 0, 0, composite.width, composite.height)
    }
}

    @Test fun emptyState() = measure(
        "16-empty-state", "StudentListScreen",
        "T008Fixture 空数据库；showRootSwitch=true；0 students / 0 archived",
        "PNG 未见 S2+ 内容；Android 产品另有资料库入口。",
    ) {
        val f = T008Fixture().also { releaseFixture = it::close }
        val students = StudentUseCases(StudentRepository(f.db, f.clock), f.clock, f.ids)
        val state = StudentListViewModel(students, clock = f.clock)
        f.test { state.reload() }
        show { StudentListScreen(state, {}, showRootSwitch = true, autoLoad = false) }
        StudentTestTags.STUDENT_LIST_EMPTY
    }

    @Test fun editProfile() = measure(
        "27-edit-profile", "StudentEditorScreen (Edit)",
        "StudentDetailConformanceFixture；王小明 / 男 / 增肌 / 左膝旧伤，避免深屈膝跳跃；其余选填留空",
        "Android 另有其他/不透露性别、隐私说明；删除说明不同；保存学员 vs 保存。首屏可能无法展示完整管理区，保留真实布局。",
    ) {
        val f = StudentDetailConformanceFixture().also { releaseFixture = it::close }
        val student = checkNotNull(f.state.uiState.student)
        val students = StudentUseCases(StudentRepository(f.room.db, f.room.clock), f.room.clock, f.room.ids)
        val state = StudentEditorViewModel(StudentEditorMode.Edit(student.studentID), students, student)
        show { StudentEditorScreen(state, {}, {}, autoLoad = false) }
        StudentTestTags.EDITOR_ROOT
    }

    @Test fun packageDetail() = measure(
        "04-package-detail", "CoursePackageListScreen",
        "T009Fixture；张伟 / total 20 / balance 8 / 有效期 2026-12-31；三条可见流水匹配日期和原因",
        "为使余额 8 与 ledger 一致，另有 8月1日人工扣减 11 课时历史流水（PNG 仅展示三条最新记录）；Android 另有课包管理区。",
    ) {
        val f = T009Fixture().also { releaseFixture = it::close }
        val students = StudentUseCases(StudentRepository(f.db, f.clock), f.clock, f.ids)
        f.test {
            f.now = Instant.parse("2026-08-01T19:00:00Z")
            f.ok(students.update(f.studentID, StudentDraft("张伟", StudentSex.male)))
            val pkg = f.coursePackage(20, LocalDate.of(2026, 12, 31))
            f.ok(f.credits.recordManualCorrection(pkg.coursePackageID, CreditDirection.debit, 11, "虚构较早课时"))
            val events = listOf(
                Triple("2026-09-01", CreditDirection.debit, CreditReasonKind.sessionComplete),
                Triple("2026-08-28", CreditDirection.credit, CreditReasonKind.sessionReopen),
                Triple("2026-08-25", CreditDirection.debit, CreditReasonKind.appointmentAbsent),
            )
            for ((day, direction, kind) in events) {
                val id = f.ids.newCreditAdjustmentID()
                f.db.s1Dao().insert(CreditAdjustmentEntity(
                    UUID.fromString(id.value), UUID.fromString(pkg.coursePackageID.value), direction, 1,
                    kind, if (kind == CreditReasonKind.sessionComplete) "深蹲训练" else null,
                    null, null, CreditLedgerSourceEventKeyFactory.manualCorrection(id).value, Instant.parse("${day}T19:00:00Z"),
                ))
            }
            f.now = Instant.parse("2026-09-02T19:00:00Z")
            check(f.ok(f.credits.balance(f.studentID, pkg.coursePackageID)) == 8L)
        }
        show { CoursePackageListScreen(f.studentID, f.credits, f.zone, {}, {}, {}, {}, students = students) }
        "package-list-manual"
    }

    @Test fun newPackageStepper() = measure(
        "36-new-package-stepper", "CoursePackageEditorScreen (new)",
        "T009Fixture 无课包；私教20节 / 20；开始日期 on 2026-09-29；结束日期 off；AD-02 原生日期选择器（关闭）",
        "日期值匹配；日期行遵循 AD-02，Android 不显示 iOS chevron。",
    ) {
        val f = T009Fixture().also { releaseFixture = it::close }
        f.now = Instant.parse("2026-09-29T19:00:00Z")
        show { CoursePackageEditorScreen(f.studentID, f.credits, f.clock, f.zone, {}, {}) }
        await("package-editor-name")
        compose.waitUntil(15_000) {
            node("package-editor-save").fetchSemanticsNode().config.getOrNull(
                androidx.compose.ui.semantics.SemanticsProperties.Disabled,
            ) == null
        }
        node("package-editor-name").performTextInput("私教20节")
        repeat(10) { node("package-editor-credits-plus").performClick() }
        node("package-editor-has-start").performClick()
        compose.runOnIdle { compose.activity.currentFocus?.clearFocus() }
        "package-editor-start"
    }

    @Test fun manualAdjustmentStepper() = measure(
        "37-manual-adjustment-stepper", "ManualCreditAdjustmentScreen",
        "T009Fixture 有效课包；扣减 / 1 / 原因空；未保存",
        "匹配空原因与默认扣减 1；Android 保存调整为 disabled（原因必填），PNG 按钮绘为深色；保留产品状态。",
    ) {
        val f = T009Fixture().also { releaseFixture = it::close }
        lateinit var pkg: CoursePackageRecord
        f.test { pkg = f.coursePackage(20) }
        show { ManualCreditAdjustmentScreen(pkg.coursePackageID, f.credits, {}, {}) }
        "package-manual-save"
    }
    @Test fun exerciseFilterSheet() = measure(
        "33-exercise-filter-sheet", "ExerciseLibraryScreen / ExerciseFilterSheet",
        "ExerciseConformanceFixture；胸 21；器械全部；显示已隐藏 off",
        "保留现有 Android sheet 高度、器械分类与控件；合成真实 dialog window。", sheetTag = "exercise-library-filter-content",
    ) {
        val f = ExerciseConformanceFixture().also { releaseFixture = it::close }
        show { ExerciseLibraryScreen(f.state) {} }
        await("exercise-library-muscle-胸")
        node("exercise-library-muscle-胸").performClick()
        node("exercise-library-filter").performClick()
        "exercise-library-filter-content"
    }

    @Test fun exerciseOptionsSheet() = measure(
        "34-exercise-options-sheet", "ExerciseLibraryScreen / 动作选项",
        "ExerciseConformanceFixture；胸 21；杠铃平板卧推 favorite on / hidden off / assisted off",
        "PNG 为动作名/副标题及 toggles；Android 为动作选项标题、显示名编辑及 action rows，另有单侧记录和取消。",
        sheetTag = "exercise-options-content",
    ) {
        val f = ExerciseConformanceFixture().also { releaseFixture = it::close }
        f.room.test { f.room.ok(f.state.useCases.updatePreference(UpdateExercisePreferenceCommand(
            StableExerciseID.parse("fictional-conformance-0"), "杠铃平板卧推", true, false, false, null))) }
        show { ExerciseLibraryScreen(f.state) {} }
        await("exercise-options-fictional-conformance-0")
        compose.waitUntil(15_000) { f.state.preference(StableExerciseID.parse("fictional-conformance-0")).isFavorite }
        node("exercise-library-muscle-胸").performClick()
        node("exercise-options-fictional-conformance-0").performClick()
        "exercise-options-content"
    }

    @Test fun trainingTemplate() = measure(
        "05-training-template", "TemplateListScreen",
        "上肢推/胸/6 动作；下肢力量/大腿/5 动作；全身热身/无重点/4 动作；真实模板 repository",
        "S1 存在训练模板屏，无需 placeholder；副标题为跨学员使用说明；行不显示动作数，重点用大腿。",
    ) {
        val f = TrainingConformanceFixture().also { releaseFixture = it::close }
        f.room.test {
            listOf(Triple("上肢推", setOf(BodyPart.chest), 6), Triple("下肢力量", setOf(BodyPart.thighs), 5),
                Triple("全身热身", emptySet<BodyPart>(), 4)).asReversed().forEachIndexed { i, (name, focus, count) ->
                f.room.time = f.room.now.plusSeconds(i.toLong())
                val t = f.room.ok(f.room.templateUseCases.save(SaveTemplateCommand(null, name, focus, null)))
                val rows = (0 until count).map { n -> TemplateExercise(f.room.ids.newTemplateExerciseID(), t.templateID,
                    null, n.toUInt(), ExerciseSourceKind.sessionOnly, null, NormalizedName.parse("虚构计划动作 $n"), RecordMode.weightReps, emptyList()).toRecord() }
                f.room.ok(f.room.templates.saveContent(SaveTemplateContentCommand(t.templateID, t.revision, emptyList(), rows)))
            }
        }
        show { TemplateListScreen(f.templates, {}, {}) }
        compose.waitUntil(15_000) { f.templates.templates.size == 3 }
        "template-list-content"
    }

    @Test fun cardio() = measure(
        "15-cardio", "ActiveSessionScreen / SetEditor (cardio)",
        "王小明；跑步机；32:00 / 5.0 / 9.4 / 阻力空；未确认",
        "Android 使用训练中组合页面，另有学员/时间/添加动作/结束训练；有氧复用标签-值行，确认文案遵循 iOS；内联 editor 保持既有保存行为。",
    ) {
        val f = TrainingConformanceFixture().also { releaseFixture = it::close }
        f.room.test {
            val row = SessionExercise(f.room.ids.newSessionExerciseID(), f.content.session.sessionID, 0u,
                ExerciseSourceKind.sessionOnly, null, NormalizedName.parse("跑步机"), RecordMode.cardio, null, null, emptyList()).toRecord()
            f.content = f.room.ok(f.room.sessions.saveContent(SaveSessionContentCommand(f.content.session.sessionID,
                f.content.session.revision, emptyList(), listOf(row))))
        }
        show { ActiveSessionScreen(f.state, f.content.session.sessionID, f.exercises, f.templates, {}, {},
            students = StudentRepository(f.room.db, f.room.clock)) }
        await("set-duration")
        listOf("set-duration" to "32:00", "set-distance" to "5.0", "set-speed" to "9.4").forEach { (tag, value) -> node(tag).performTextInput(value) }
        compose.runOnIdle { compose.activity.currentFocus?.clearFocus() }
        "set-resistance"
    }

    @Test fun historyList() = measure(
        "32-training-history-v2", "HistoryListScreen",
        "王小明；2025-09-25/18/11/04（周四）；12/10/11/9 组；58/52/55/47 分钟；近30天；大腿、臀筛选",
        "设计的课程比较/个人最佳不在 S1 HistoryListScreen；保留清除筛选及未扣课说明。4条记录全部适配首屏；scroll range=0 时仅保留一个 viewport；实际滚动范围另记。",
        scrollTag = "history-list-content",
    ) {
        val f = T009Fixture().also { releaseFixture = it::close }
        val students = StudentUseCases(StudentRepository(f.db, f.clock), f.clock, f.ids)
        lateinit var state: HistoryUiState
        f.test {
            f.ok(students.update(f.studentID, StudentDraft("王小明", StudentSex.male)))
            listOf(Triple("04", 9, 47), Triple("11", 11, 55), Triple("18", 10, 52), Triple("25", 12, 58)).forEachIndexed { index, (day, count, minutes) ->
                f.now = Instant.parse("2025-09-${day}T18:00:00Z")
                val c = f.content()
                val row = c.exercises.single()
                val sets = (0 until count).map { n -> row.sets.single().copy(trainingSetID = f.ids.newTrainingSetID(), orderIndex = n.toUInt()) }
                val updated = f.ok(f.sessions.saveContent(SaveSessionContentCommand(c.session.sessionID, c.session.revision, emptyList(), listOf(row.copy(sets = sets)))))
                f.now = f.now.plusSeconds(minutes * 60L)
                f.finish(updated)
                val done = f.ok(f.sessions.loadContent(c.session.sessionID))!!
                val focus = when (index) { 0 -> setOf(BodyPart.thighs, BodyPart.calves); 1 -> setOf(BodyPart.thighs); else -> setOf(BodyPart.thighs, BodyPart.glutes) }
                f.ok(f.historyCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(done.session.sessionID, done.session.revision, focus)))
            }
            f.now = Instant.parse("2025-09-29T19:00:00Z")
            state = HistoryUiState(f.historyCases, f.studentID, students)
            state.list(HistoryQuery(f.studentID, HistoryWindowDays.days30, setOf(BodyPart.thighs, BodyPart.glutes)))
            check(state.records.size == 4 && state.error == null)
        }
        show { HistoryListScreen(state, f.zone, {}, {}) }
        "history-count"
    }
    private fun active(f: TrainingConformanceFixture) {
        show { ActiveSessionScreen(f.state, f.content.session.sessionID, f.exercises, f.templates, {}, {},
            students = StudentRepository(f.room.db, f.room.clock)) }
        await("session-add-exercise")
        compose.waitUntil(15_000) { !f.state.busy }
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
    }

    private fun swipe(tag: String) {
        compose.mainClock.autoAdvance = true
        node(tag).performScrollTo().assertIsDisplayed().performTouchInput { swipeLeft(startX = width * .9f, endX = width * .5f) }
        compose.mainClock.advanceTimeBy(500)
        compose.waitForIdle()
    }

    private fun crop(id: String, label: String, vararg tags: String, parent: Boolean = false): Bitmap {
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(320)
        val bounds = tags.map { if (parent) node(it).onParent().fetchSemanticsNode().boundsInRoot else node(it).fetchSemanticsNode().boundsInRoot }
        val top = bounds.minOf { it.top }.toInt().coerceAtLeast(0)
        val bottom = kotlin.math.ceil(bounds.maxOf { it.bottom }.toDouble()).toInt().coerceAtMost(1688)
        check(bottom > top) { "Empty crop for $label: $bounds" }
        val full = node("conformance-viewport").captureToImage().asAndroidBitmap()
        val result = Bitmap.createBitmap(full, 0, top, 780, bottom - top)
        if (result !== full) full.recycle()
        File(p7Output(), "$id.crops.txt").appendText("$label: x=0 y=$top width=780 height=${bottom - top}; tags=${tags.toList()} parent=$parent\n")
        return result
    }

    private fun board(id: String, path: String, composable: String, fixture: String, mismatches: String, capture: () -> List<Pair<String, Bitmap?>>) {
        File(p7Output(), "$id.crops.txt").writeText("Native-scale state crops in design order; labels are artifact annotations.\n")
        val bitmap = P7SheetWriter.stack(capture())
        P7SheetWriter.write(id, bitmap, composable, fixture, mismatches, designPath = path, board = true)
        bitmap.recycle()
    }

    @Test fun todayMultiSession() = board(
        "W08-a-today-multi-session", "design/m1-b-hifi/screens/W08-a-today-multi-session.png", "TodayScreen / 1, 2, 3 active sessions",
        "王小明32分钟；陈嘉怡5分钟（2人）/18分钟（3人）；李思远2分钟；真实 repository；按开始时间升序",
        "PNG 实际含1/2/3人卡片三态，逐态裁剪；S1 hero title 来自训练重点（大腿/胸）而非深蹲训练/上肢训练/卧推训练；保留真实标题。",
    ) {
        val f = TodayConformanceFixture().also { releaseFixture = it::close }
        val now = f.room.time
        val parts = mutableListOf<Pair<String, Bitmap?>>()
        show { com.ignacioli.finecoach.features.today.TodayScreen(f.state) {} }
        await("hero-${f.sessionID.value}")
        compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
        parts += "1人：王小明 / 32分钟" to crop("W08-a-today-multi-session", "1 person", "hero-${f.sessionID.value}")
        compose.mainClock.autoAdvance = true
        var second: SessionID? = null
        f.room.test {
            f.room.student(2)
            f.room.db.openHelper.writableDatabase.execSQL("UPDATE students SET displayName = ? WHERE id = ?", arrayOf("陈嘉怡", f.room.studentID(2).value))
            f.room.time = now.minusSeconds(5 * 60)
            second = f.room.ok(f.room.sessions.startOrOpen(StartOrOpenSessionCommand(f.room.studentID(2), setOf(BodyPart.chest), f.room.time))).sessionID
            f.room.time = now
            f.state.load()
        }
        await("today-hero")
        parts += "2人：王小明32 / 陈嘉怡5分钟" to crop("W08-a-today-multi-session", "2 people", "today-hero")
        compose.mainClock.autoAdvance = true
        f.room.test {
            f.room.db.openHelper.writableDatabase.execSQL("UPDATE sessions SET startedAtUTC = ?, lastCheckpointUTC = ? WHERE id = ?", arrayOf(now.minusSeconds(18 * 60).toString(), now.minusSeconds(18 * 60).toString(), checkNotNull(second).value))
            f.room.student(3)
            f.room.db.openHelper.writableDatabase.execSQL("UPDATE students SET displayName = ? WHERE id = ?", arrayOf("李思远", f.room.studentID(3).value))
            f.room.time = now.minusSeconds(2 * 60)
            f.room.ok(f.room.sessions.startOrOpen(StartOrOpenSessionCommand(f.room.studentID(3), setOf(BodyPart.chest), f.room.time)))
            f.room.time = now
            f.state.load()
        }
        parts += "3人：王小明32 / 陈嘉怡18 / 李思远2分钟" to crop("W08-a-today-multi-session", "3 people", "today-hero")
        parts
    }

    @Test fun unilateralPartialStates() = board(
        "P0-a2b-partial-states", "design/experience-p0/screens/P0-a2b-partial-states.png", "ActiveSessionScreen / SetEditor / swipe / recent undo",
        "单侧深蹲：每侧12.5×10；展开后左12.5右15×10；动作左滑；刚确认组4秒内",
        "四态均有 S1 实现；实际输入带 helper/确认按钮；动作操作顺序为删除/移入分区；刚确认组展示真实撤销；swipe 行高度/裁剪导致动作名及操作文案部分不可见，保留原始像素。",
    ) {
        val id = "P0-a2b-partial-states"
        val f = TrainingConformanceFixture().also { releaseFixture = it::close }
        f.room.test {
            val r = f.squat.copy(sets = listOf(f.squat.sets.single().copy(weightValue = "12.5".toBigDecimal(), repetitionCount = "10".toBigDecimal(), side = SetSide.bilateral, leftValue = "12.5".toBigDecimal(), rightValue = "12.5".toBigDecimal())))
            val section = SectionRecord(f.room.ids.newSectionID(), SessionSectionOwnerKind.session, f.content.session.sessionID, null, "辅助训练", 1u)
            f.content = f.room.ok(f.room.sessions.saveContent(SaveSessionContentCommand(f.content.session.sessionID, f.content.session.revision, listOf(section), listOf(r))))
            f.room.ok(f.exercises.useCases.updatePreference(UpdateExercisePreferenceCommand(checkNotNull(r.sourceID), "深蹲", false, false, false, true)))
        }
        active(f)
        await("set-split")
        val parts = mutableListOf<Pair<String, Bitmap?>>()
        parts += "单侧动作 · 默认左右相同" to crop(id, "same sides", "set-add-editor-content")
        compose.mainClock.autoAdvance = true
        node("set-split").performClick()
        node("set-right-input").performTextReplacement("15")
        compose.runOnIdle { compose.activity.currentFocus?.clearFocus() }
        parts += "单侧动作 · 左右不同（展开后）" to crop(id, "different sides", "set-add-editor-content")
        swipe("session-exercise-${f.squat.sessionExerciseID.value}-swipe")
        parts += "动作行 · 左滑后" to crop(id, "exercise swipe", "session-exercise-${f.squat.sessionExerciseID.value}-swipe")
        compose.mainClock.autoAdvance = true
        node("session-exercise-${f.squat.sessionExerciseID.value}-swipe").performTouchInput { swipeRight() }
        node("set-save").performScrollTo().performClick()
        compose.waitUntil(15_000) { !f.state.busy && f.state.undoableSetID != null }
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(320)
        val set = checkNotNull(f.state.undoableSetID)
        node("session-set-${set.value}").performScrollTo()
        parts += "刚确认的组 · 4秒内" to crop(id, "just confirmed", "session-set-${set.value}")
        parts
    }

    private fun sectionFixture(): TrainingConformanceFixture {
        val f = TrainingConformanceFixture().also { releaseFixture = it::close }
        f.room.test {
            f.room.db.openHelper.writableDatabase.execSQL("UPDATE students SET displayName = ?", arrayOf("李娜"))
            val sid = f.content.session.sessionID
            val auxiliary = SectionRecord(f.room.ids.newSectionID(), SessionSectionOwnerKind.session, sid, null, "辅助训练", 1u)
            val core = SectionRecord(f.room.ids.newSectionID(), SessionSectionOwnerKind.session, sid, null, "核心", 4u)
            fun row(name: String, order: UInt, section: SectionID, mode: RecordMode = RecordMode.weightReps) = SessionExercise(
                f.room.ids.newSessionExerciseID(), sid, order, ExerciseSourceKind.sessionOnly, null, NormalizedName.parse(name), mode, null, section, emptyList()).toRecord()
            val squat = f.squat.copy(sets = (0..2).map { n -> f.squat.sets.single().copy(trainingSetID = f.room.ids.newTrainingSetID(), orderIndex = n.toUInt()) })
            f.content = f.room.ok(f.room.sessions.saveContent(SaveSessionContentCommand(sid, f.content.session.revision, listOf(auxiliary, core), listOf(squat, row("哑铃飞鸟", 2u, auxiliary.sectionID), row("三头下压", 3u, auxiliary.sectionID), row("平板支撑", 5u, core.sectionID, RecordMode.duration)))))
        }
        return f
    }

    @Test fun sectionDeleteConfirmation() = measure(
        "B-a-section-swipe-delete-confirm", "ActiveSessionScreen / FcConfirmationDialog",
        "李娜；深蹲3组120×8；辅助训练含哑铃飞鸟/三头下压；核心含平板支撑；删除分区确认尚未提交",
        "通过真实分区左滑及可见删除分区按钮打开确认框；保留 Android 训练页和 dialog 布局；标题训练重点与PNG空白课不同；实际显示逐组明细及有氧输入。",
        sheetTag = "session-delete-section-confirm-card", designPath = "design/experience-t2/screens/B-a-section-swipe-delete-confirm.png",
    ) {
        val f = sectionFixture()
        active(f)
        swipe("session-section-${f.content.sections.first().sectionID.value}-swipe")
        node("session-section-delete").performClick()
        "session-delete-section-confirm-card"
    }

    @Test fun sectionPartialStates() = board(
        "B-b-partial-states", "design/experience-t2/screens/B-b-partial-states.png", "ActiveSessionScreen / section swipe / completed set swipe / undo",
        "辅助训练分区；深蹲第1组120kg×8；真实左滑、删除组、撤销行；其余状态逐项标 gap；分区标题左滑后名称移出左边界、操作区文案纵向裁剪是产品原状",
        "not in S1: 身体数据单条左滑、身体数据删除后4秒（S2）；not in S1: 模板动作行左滑删除（模板本身已在S1，但当前是动作菜单移除+确认，未实现图示swipe）。",
    ) {
        val id = "B-b-partial-states"
        val f = sectionFixture()
        active(f)
        val parts = mutableListOf<Pair<String, Bitmap?>>()
        val section = "session-section-${f.content.sections.first().sectionID.value}-swipe"
        swipe(section)
        parts += "分区标题 · 左滑后" to crop(id, "section swipe", section)
        val set = f.content.exercises.first().sets.first()
        swipe("session-set-${set.trainingSetID.value}-swipe")
        parts += "已完成的组 · 左滑后（Δ9）" to crop(id, "completed set swipe", "session-set-${set.trainingSetID.value}-swipe")
        compose.mainClock.autoAdvance = true
        node("session-set-delete").performClick()
        await("session-deleted-action")
        compose.waitUntil(15_000) { !f.state.busy }
        parts += "删除后4秒内（Δ9）" to crop(id, "deleted set undo", "session-deleted-action", parent = true)
        parts += "not in S1: 身体数据 · 单条记录左滑后（S2）" to null
        parts += "not in S1: 身体数据 · 删除后4秒内（S2）" to null
        parts += "not in S1: 模板 · 动作行左滑后（现有菜单移除）" to null
        parts
    }

    @Test fun sessionGains() = measure(
        "D-b-session-gains", "SessionSummaryScreen (S1)",
        "完成12组/58分钟；训练重点大腿、臀；私密备注：膝盖内扣，下次降到120kg练动作。；公开总结空",
        "S3-only 区域：本节收获（深蹲新纪录/上次120×8→本次125×5；卧推上次80×8→本次80×10；平板支撑60→75秒）、第25节课累计里程碑及PR badge。S1 时长显示3480秒而非58分钟；S1 summary 未实现生成训练报告/跳过分享，当前为保存并返回今日；templateSlot使用导航中的真实另存模板入口。滚动范围为0时只保留一个viewport，非0时滚到末尾竖拼。",
        scrollTag = "summary-content", designPath = "design/progress-milestones/screens/D-b-session-gains.png",
    ) {
        val f = T009Fixture().also { releaseFixture = it::close }
        lateinit var c: SessionContentRecord
        lateinit var state: SessionSummaryUiState
        f.test {
            state = SessionSummaryUiState(f.historyCases, f.clock)
            c = f.content()
            val r = c.exercises.single()
            c = f.ok(f.sessions.saveContent(SaveSessionContentCommand(c.session.sessionID, c.session.revision, emptyList(), listOf(r.copy(displayNameSnapshot = "深蹲", sets = (0 until 12).map { n -> r.sets.single().copy(trainingSetID = f.ids.newTrainingSetID(), orderIndex = n.toUInt()) } )))))
            f.now = f.now.plusSeconds(58 * 60)
            f.finish(c)
            val done = f.ok(f.sessions.loadContent(c.session.sessionID))!!
            f.ok(f.historyCases.saveSummary(SaveCompletedSessionSummaryCommand(done.session.sessionID, done.session.revision, setOf(BodyPart.thighs, BodyPart.glutes), "", "膝盖内扣，下次降到 120 kg 练动作。", f.now)))
        }
        lateinit var templates: HistoryTemplateState
        f.test { templates = HistoryTemplateState(TemplateUseCases(com.ignacioli.finecoach.storage.repository.TemplateRepository(f.db, f.clock, f.ids, java.util.UUID.fromString(f.db.storeMetadataDao().find(com.ignacioli.finecoach.storage.FineCoachDatabaseFactory.GENERATION_KEY)!!.value)), f.clock), f.clock, f.ids) }
        show { SessionSummaryScreen(state, c.session.sessionID, {}, {}) { state.detail?.let { HistoryTemplateEntry(templates, it.content) } } }
        await("summary-save")
        "summary-content"
    }
}
