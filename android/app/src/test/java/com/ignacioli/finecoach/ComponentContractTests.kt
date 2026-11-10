// fictional-data: Component labels are fictional and contain no personal data.
package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.designsystem.*
import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ComponentContractTests {
    @get:Rule val compose = createComposeRule()
    private val icon = object : androidx.compose.ui.graphics.painter.Painter() {
        override val intrinsicSize = androidx.compose.ui.geometry.Size.Unspecified
        override fun androidx.compose.ui.graphics.drawscope.DrawScope.onDraw() = Unit
    }
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun touch(tag: String) { node(tag).assertWidthIsAtLeast(44.dp).assertHeightIsAtLeast(44.dp) }
    private fun full(tag: String, parent: String = "parent") {
        assertEquals(node(parent).getUnclippedBoundsInRoot().width, node(tag).getUnclippedBoundsInRoot().width)
    }
    private fun show(content: @Composable ColumnScope.() -> Unit) {
        compose.setContent { FineCoachTheme { Column(Modifier.fillMaxWidth().testTag("parent"), content = content) } }
    }

    @Test fun tokenUsage() {
        val app = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))
        val files = File(app, "src/main/java/com/ignacioli/finecoach/designsystem").walkTopDown().filter { it.extension == "kt" }.toList() +
            File(app, "src/debug/java/com/ignacioli/finecoach").walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue(files.isNotEmpty())
        val raw = Regex("(?<![A-Za-z0-9_])(?:[1-9][0-9]*(?:\\.[0-9]+)?|0\\.[0-9]*[1-9][0-9]*)\\.(?:dp|sp)\\b|(?<![A-Za-z])Color\\s*\\(")
        files.forEach { assertFalse(it.path, raw.containsMatchIn(it.readText())) }
        assertEquals(44.dp, FcComponentMetrics.touch); assertEquals(52.dp, FcComponentMetrics.row)
        assertEquals(48.dp, FcComponentMetrics.field); assertEquals(96.dp, FcComponentMetrics.label)
        assertEquals(1.5.dp, FcComponentMetrics.stroke); assertEquals(300.dp, FcComponentMetrics.dialogWidth)
        // DS-LAUNCH uses this empty shell; real startup failures/retries are covered by navigation tests.
        assertEquals(androidx.compose.ui.graphics.Color.White, FcColors.surfacePage)
        compose.setContent { FineCoachTheme { FcPlatformShell({}) {} } }
        node("platform-shell").assertIsDisplayed().assertHasNoClickAction()
        assertEquals(compose.onRoot().getUnclippedBoundsInRoot(), node("platform-shell").getUnclippedBoundsInRoot())
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.Text), useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodes(hasClickAction(), useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun buttons() {
        var calls = 0
        show {
            FcButton("主按钮", Modifier.testTag("primary")) { calls++ }
            FcButton("禁用", Modifier.testTag("disabled"), false) { calls++ }
            FcSecondaryButton("次按钮", Modifier.testTag("secondary")) { calls++ }
            FcLinkButton("链接", Modifier.testTag("link")) { calls++ }
        }
        listOf("primary", "disabled", "secondary", "link").forEach(::touch)
        listOf("primary", "disabled", "secondary").forEach { full(it) }
        node("disabled").assertIsNotEnabled().performTouchInput { click() }
        compose.runOnIdle { assertEquals(0, calls) }
        compose.onNodeWithTag("primary").assertTextEquals("主按钮").performClick()
        node("secondary").performClick(); node("link").performClick()
        compose.runOnIdle { assertEquals(3, calls) }
        val source = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")), "src/main/java/com/ignacioli/finecoach/designsystem/FcControls.kt").readText()
        assertTrue(source.contains("pressed -> FcColors.actionPressed")); assertFalse(source.contains(".alpha("))
    }

    @Test fun titleActions() {
        var calls = 0
        show {
            FcTitleIconButton("设置", icon, Modifier.testTag("icon")) { calls++ }
            FcTitleAddButton("新建预约", icon, Modifier.testTag("add")) { calls++ }
        }
        touch("icon"); touch("add")
        node("icon").assertContentDescriptionEquals("设置").performClick()
        node("add").assertContentDescriptionEquals("新建预约").performClick()
        compose.runOnIdle { assertEquals(2, calls) }
    }

    @Test fun segmented() {
        show { var value by remember { mutableIntStateOf(0) }; FcSegmentedSwitch(listOf("甲", "乙"), value, { value = it }, tag = "seg") }
        touch("seg-0"); touch("seg-1")
        node("seg-0").assertIsSelected(); node("seg-1").assertIsNotSelected().performClick()
        node("seg-0").assertIsNotSelected(); node("seg-1").assertIsSelected()
    }

    @Test fun chips() {
        show {
            var selected by remember { mutableStateOf(false) }
            FcFilterChip("样例", selected, Modifier.testTag("chip")) { selected = !selected }
            FcBodyPartPicker(setOf(0), {}, tag = "body")
        }
        touch("chip"); node("chip").assertIsNotSelected().performClick(); node("chip").assertIsSelected()
        FcBodyParts.indices.forEach { touch("body-$it") }
        val rowTops = FcBodyParts.indices.map { node("body-$it").getUnclippedBoundsInRoot().top }.distinct().sorted()
        assertTrue(rowTops.size > 1)
        rowTops.zipWithNext().forEach { (a, b) -> assertEquals(36.dp, b - a) }
        assertEquals(listOf("胸", "肩", "背", "大腿", "小腿", "臂", "臀", "核心"), FcBodyParts)
        node("body-0").assertIsSelected(); node("body-1").assertIsNotSelected()
    }

    @Test fun toggle() {
        var disabledCalls = 0
        show {
            var on by remember { mutableStateOf(false) }
            FcToggle("开关", on, { on = it }, Modifier.testTag("toggle"))
            FcToggle("禁用开关", false, { disabledCalls++ }, Modifier.testTag("disabled"), false)
        }
        touch("toggle"); node("toggle").assertIsOff().assertContentDescriptionEquals("开关")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch)).performClick()
        node("toggle").assertIsOn(); node("disabled").assertIsNotEnabled().performTouchInput { click() }
        compose.runOnIdle { assertEquals(0, disabledCalls) }
    }

    @Test fun steppers() {
        show {
            var value by remember { mutableIntStateOf(0) }
            FcStepper("次数", value, 0..1, { value = it }, icon, icon, Modifier.testTag("step"), "step")
            var field by remember { mutableStateOf("0") }
            FcStepperField("重量", field, { field = it }, false, icon, icon, {}, { field = "2.5" }, Modifier.testTag("field"), "field")
        }
        listOf("step-minus", "step-plus", "field-minus", "field-plus").forEach(::touch)
        node("step-minus").assertIsNotEnabled(); node("step-plus").performClick(); node("step-plus").assertIsNotEnabled()
        node("step").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "1"))
        node("field-minus").assertIsNotEnabled(); node("field-plus").performClick(); node("field-input").assertTextEquals("2.5")
        node("field-input").performTextReplacement("3.5"); node("field-input").assertTextEquals("3.5"); full("field")
        assertEquals(0, fcStepped(0, -1, 0..2)); assertEquals(2, fcStepped(2, 1, 0..2))
        assertEquals(Int.MAX_VALUE, fcStepped(Int.MAX_VALUE, 1, 0..Int.MAX_VALUE))
        assertEquals(1, fcStepped(0, 1, 0..2))
    }

    @Test fun fields() {
        show {
            var text by remember { mutableStateOf("") }
            FcTextField("样例输入", text, { text = it }, Modifier.testTag("input"))
            FcTextField("样例口令", "fictional", {}, Modifier.testTag("secure"), secure = true)
            FcSearchField("搜索", "", {}, Modifier.testTag("search"))
        }
        listOf("input", "secure", "search").forEach { full(it); touch(it) }
        node("input").assertContentDescriptionEquals("样例输入").performTextInput("虚构")
        node("input").assertTextContains("虚构")
        node("secure").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Password))
        node("search").assertContentDescriptionEquals("搜索")
    }

    @Test fun listRows() {
        var calls = 0
        show {
            FcListRow("项目", Modifier.testTag("plain"), subtitle = "说明")
            FcListRow("可点", Modifier.testTag("action"), mode = FcRowMode.Action { calls++ })
            FcListRow("选择", Modifier.testTag("selection"), mode = FcRowMode.Selection(true) { calls++ })
            FcListRow("不可用", Modifier.testTag("unavailable"), mode = FcRowMode.Unavailable("缺少内容"))
            FcListGroupRow("分组", listOf(true, false), false, { calls++ }, { calls++ }, icon, icon, Modifier.testTag("group"))
        }
        listOf("plain", "action", "selection", "unavailable", "group").forEach { full(it) }
        node("plain").assertHasNoClickAction(); node("unavailable").assertHasNoClickAction()
        node("action").performClick(); node("selection").assertIsSelected().performClick()
        node("group-expand").performClick(); node("group-toggle").performClick()
        compose.runOnIdle { assertEquals(4, calls) }
        assertEquals(ToggleableState.Indeterminate, fcGroupState(listOf(true, false)))
        assertEquals(ToggleableState.On, fcGroupState(listOf(true, true)))
        assertEquals(ToggleableState.Off, fcGroupState(emptyList()))
        touch("group-expand"); touch("group-toggle")
    }

    @Test fun sections() {
        var calls = 0
        show { FcSectionLabel("区段", Modifier.testTag("label")); FcGroupEntryRow("分组", 2, Modifier.testTag("entry")) { calls++ } }
        node("label").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        full("label"); full("entry"); touch("entry"); node("entry").performClick()
        compose.runOnIdle { assertEquals(1, calls) }
    }

    @Test fun labelValue() {
        var calls = 0
        var picker by mutableStateOf(false)
        show {
            FcLabelValueText("标签", "值", Modifier.testTag("text"))
            FcLabelValueRow("日期", Modifier.testTag("date"), onClick = { picker = true }) { androidx.compose.material3.Text("选择日期") }
            FcLabelValueRow("开关", Modifier.testTag("slot")) { FcToggle("值开关", false, {}, Modifier.testTag("slot-toggle")) }
            if (picker) FcDatePickerDialog(null, { calls++; picker = false }, { picker = false })
        }
        listOf("text", "date", "slot").forEach { full(it) }
        node("text").assertHasNoClickAction(); touch("slot-toggle"); node("date").performClick()
        touch("date-accept"); touch("date-cancel"); node("date-accept").performClick()
        compose.runOnIdle { assertEquals(1, calls) }
    }

    @Test fun pageHeader() {
        var calls = 0
        show { FcPageHeader("很长的虚构标题", Modifier.testTag("header"), "副标题", { calls++ }, "header", "编辑", onTrailing = { calls++ }) }
        full("header"); touch("header-back"); touch("header-trailing")
        compose.onNodeWithText("很长的虚构标题").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        node("header-back").assertContentDescriptionEquals("返回").performClick(); node("header-trailing").performClick()
        compose.runOnIdle { assertEquals(2, calls) }
    }

    @Test fun hubRows() {
        var calls = 0
        show {
            FcHubRow("入口", icon, Modifier.testTag("action"), mode = FcRowMode.Action { calls++ })
            FcHubRow("信息", icon, Modifier.testTag("info"))
            FcHubRow("不可用", icon, Modifier.testTag("unavailable"), mode = FcRowMode.Unavailable("档案未包含"))
        }
        listOf("action", "info", "unavailable").forEach { full(it); touch(it) }
        node("action").performClick(); node("info").assertHasNoClickAction(); node("unavailable").assertHasNoClickAction()
        compose.runOnIdle { assertEquals(1, calls) }
    }

    @Test fun inlineResult() {
        var calls = 0
        show { FcResultVariant.entries.forEach { FcInlineResult(it, it.name, "虚构说明", icon, Modifier.testTag(it.name), onRetry = { calls++ }, tag = it.name) } }
        assertEquals(3, FcResultVariant.entries.size)
        FcResultVariant.entries.forEach { variant ->
            assertTrue(variant.glyph.isNotBlank()); full(variant.name); touch("${variant.name}-retry"); node("${variant.name}-retry").performClick()
        }
        compose.runOnIdle { assertEquals(3, calls) }
    }

    @Test fun actionRows() {
        var calls = 0
        var dialog by mutableStateOf(false)
        show {
            FcActionRow("归档学员", Modifier.testTag("short-detail"), detail = "可恢复") { }
            FcActionRow("普通", Modifier.testTag("normal")) { calls++ }
            FcActionRow("删除样例", Modifier.testTag("danger"), detail = "删除学员和训练记录；课包与课时流水仍保留，需二次确认", destructive = true, trash = icon) { dialog = true }
            FcActionRow("禁用", Modifier.testTag("disabled"), enabled = false) { calls++ }
            if (dialog) FcConfirmationDialog("确认删除？", "虚构数据", "删除", { calls++; dialog = false }, { dialog = false })
        }
        listOf("normal", "danger", "disabled", "short-detail").forEach { full(it); touch(it) }
        val shortTitle = compose.onNodeWithText("归档学员", useUnmergedTree = true).fetchSemanticsNode().layoutInfo.parentInfo!!
        val shortDetail = compose.onNodeWithText("可恢复", useUnmergedTree = true).fetchSemanticsNode().layoutInfo.parentInfo!!
        assertTrue("Short detail must not reserve half the row", shortTitle.width > shortDetail.width)
        val title = compose.onNodeWithText("删除样例", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue("Long trailing detail must reserve title width", title.width >= 64.dp)
        compose.onNodeWithText("删除学员和训练记录；课包与课时流水仍保留，需二次确认", useUnmergedTree = true).assertIsDisplayed()
        node("disabled").assertIsNotEnabled().performTouchInput { click() }
        node("danger").performClick(); node("confirm-accept").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, calls) }
        node("confirm-cancel").performClick(); node("normal").performClick()
        compose.runOnIdle { assertEquals(1, calls) }
    }

    @Test fun undoRow() {
        var calls = 0
        show { FcUndoRow("虚构对象已删除", Modifier.testTag("undo"), onUndo = { calls++ }) }
        full("undo"); touch("undo-action"); node("undo-action").assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals(1, calls) }
    }

    @Test fun bottomSheet() {
        var open by mutableStateOf(true)
        show { if (open) FcBottomSheet("虚构面板", { open = false }) { FcActionRow("关闭", Modifier.testTag("close")) { open = false } } }
        node("sheet-content").assertIsDisplayed(); touch("close"); full("close", "sheet-content")
        node("close").performClick(); node("sheet-content").assertDoesNotExist()
    }

    @Test fun bottomSheetFullyExpandedShowsLastControl() {
        show {
            FcBottomSheet("虚构长面板", {}, skipPartiallyExpanded = true) {
                repeat(8) { index ->
                    FcActionRow("虚构操作 ${index + 1}", Modifier.testTag("long-sheet-$index")) { }
                }
            }
        }
        node("long-sheet-7").assertIsDisplayed().assertHasClickAction()
    }

    @Test fun confirmation() {
        var confirmed = 0
        var open by mutableStateOf(true)
        show { if (open) FcConfirmationDialog("虚构确认", "虚构说明。".repeat(100), "确认", { confirmed++; open = false }, { open = false }) }
        touch("confirm-accept"); touch("confirm-cancel")
        node("confirm-card").assertWidthIsEqualTo(288.dp) // 320 - 2×16, smaller than the 300 cap.
        node("confirm-accept").performClick(); node("confirm-card").assertDoesNotExist()
        compose.runOnIdle { assertEquals(1, confirmed) }
    }

    @Test fun status() {
        show { FcStatus.entries.forEach { FcStatusLabel(it, icon, Modifier.testTag(it.name)) } }
        assertEquals(5, FcStatus.entries.size)
        FcStatus.entries.forEach { assertTrue(it.text.isNotBlank() && it.glyph.isNotBlank()); node(it.name).assertContentDescriptionEquals(it.text) }
    }

    @Test fun saveStatus() {
        show { FcSaveState.entries.forEach { FcSaveStatusView(it, icon, Modifier.testTag(it.name)) } }
        assertEquals(3, FcSaveState.entries.size)
        FcSaveState.entries.forEach { node(it.name).assertContentDescriptionEquals(it.text).assertHeightIsAtLeast(44.dp) }
    }

    @Test fun avatar() {
        show { FcAvatar("虚构", Modifier.testTag("avatar")) }
        node("avatar").assertWidthIsEqualTo(44.dp).assertHeightIsEqualTo(44.dp)
        node("avatar").assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.ContentDescription))
    }

    @Test fun symbols() {
        show { FcGlyph.entries.forEach { FcSymbol(it, Modifier.testTag(it.name)) }; FcAssetSymbol.entries.forEach { FcSymbol(it, icon, Modifier.testTag(it.name)) } }
        assertEquals(5, FcGlyph.entries.size)
        assertEquals(setOf("‹", "›", "✓"), FcGlyph.entries.map { it.glyph }.toSet())
        FcGlyph.entries.forEach { node(it.name).assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.ContentDescription)) }
        assertEquals(3, FcAssetSymbol.entries.size)
        FcAssetSymbol.entries.forEach {
            node(it.name).assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.ContentDescription))
                .assertWidthIsEqualTo(if (it == FcAssetSymbol.Collapse) 15.dp else 20.dp)
        }
    }

    @Test fun hintBar() {
        var calls = 0
        show {
            FcHintBar("虚构提示", Modifier.testTag("hint"))
            FcHintBar("虚构训练中", Modifier.testTag("active"), actionTitle = "继续", onClick = { calls++ })
        }
        full("hint")
        node("hint").assertHeightIsAtLeast(44.dp).assertContentDescriptionEquals("虚构提示")
        full("active")
        touch("active")
        node("active").performClick()
        compose.runOnIdle { assertEquals(1, calls) }
    }

    @Test fun heroCard() {
        var calls = 0
        show {
            FcHeroCard(
                badgeText = "进行中",
                title = "虚构标题",
                subtitle = "虚构副标题",
                modifier = Modifier.testTag("hero"),
                actionTitle = "继续样例",
                onClick = { calls++ },
            )
        }
        full("hero")
        node("hero").assertHeightIsAtLeast(100.dp).assertHasClickAction().performClick()
        compose.onNodeWithText("虚构标题").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        compose.runOnIdle { assertEquals(1, calls) }
    }
    @Test fun setRow() {
        var confirms = 0; var edits = 0
        var completed by mutableStateOf(false)
        var undos = 0
        show { FcSetRow(1, "12.5 × 8", completed, !completed, { confirms++ }, { edits++ }, Modifier.testTag("set"), tag = "set",
            onUndo = if (completed) ({ undos++ }) else null) }
        full("set"); touch("set-confirm"); touch("set-edit")
        node("set-edit").assertContentDescriptionEquals("编辑组")
        node("set-confirm").assertIsDisplayed().performClick(); node("set-edit").assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals(1, confirms); assertEquals(1, edits); completed = true }
        node("set-confirm").assertIsNotEnabled()
        node("set-undo").assertIsDisplayed().assertHasClickAction().performClick()
        node("set-edit").assertIsDisplayed().assertHasClickAction()
        full("set"); touch("set-undo")
        compose.runOnIdle { assertEquals(1, undos) }
    }
    @Test fun multiHeroCard() {
        var opened = ""
        show { FcMultiHeroCard(listOf(FcHeroEntry("a", "虚构甲", "训练中"), FcHeroEntry("b", "虚构乙", "训练中")), { opened = it }, Modifier.testTag("multi")) }
        full("multi"); touch("hero-a"); touch("hero-b")
        node("hero-a").assertIsDisplayed().performClick(); assertEquals("a", opened)
        node("hero-b").assertIsDisplayed().performClick(); assertEquals("b", opened)
    }
}
