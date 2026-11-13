// fictional-data: names, dates and injury notes reproduce synthetic design examples only.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.asAndroidBitmap
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

    private fun measure(id: String, composable: String, fixture: String, mismatches: String, render: () -> String) {
        var reason: String? = null
        val bitmap = try {
            await(render())
            compose.runOnIdle { simulateConformanceStatusBar(compose.activity) }
            compose.waitForIdle()
            compose.mainClock.autoAdvance = false
            compose.mainClock.advanceTimeBy(1000)
            compose.waitForIdle()
            node("conformance-viewport").captureToImage().asAndroidBitmap()
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
}
