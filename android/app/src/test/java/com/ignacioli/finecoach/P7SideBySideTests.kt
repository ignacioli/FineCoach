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

    private fun measure(id: String, composable: String, fixture: String, mismatches: String, sheetTag: String? = null, scrollTag: String? = null, render: () -> String) {
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
        scroll.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, viewport) }
        compose.waitForIdle()
        val after = scroll.fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange].value()
        val second = node("conformance-viewport").captureToImage().asAndroidBitmap()
        File(p7Output(), "$id.scroll.txt").writeText("requested=$viewport px; before=$before; after=$after; max=${range.maxValue()}; two complete viewports, including repeated chrome/content if scroll range is shorter")
        Bitmap.createBitmap(780, 3376, Bitmap.Config.ARGB_8888).also {
            Canvas(it).apply { drawBitmap(first, 0f, 0f, null); drawBitmap(second, 0f, 1688f, null) }
            first.recycle(); second.recycle()
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
        P7SheetWriter.write(id, bitmap, composable, fixture, mismatches, reason)
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
        "Android 使用训练中组合页面，另有学员/时间/添加动作/结束训练；有氧为 inline fields，确认为按钮文案，无 PNG 必填提示。",
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
        "设计的课程比较/个人最佳不在 S1 HistoryListScreen；保留清除筛选及未扣课说明。右侧为滚动尝试前后两个完整 viewport；4条记录全部适配首屏，scroll range=0，故两屏重复；实际滚动量另记。",
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
}
