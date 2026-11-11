// fictional-data: deterministic component contracts, no product persistence.
package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.designsystem.*
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
class S1ComponentTests {
    @get:Rule val compose = createComposeRule()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun show(content: @Composable ColumnScope.() -> Unit) {
        compose.setContent { FineCoachTheme { Column(Modifier.fillMaxWidth().testTag("parent"), content = content) } }
    }
    private fun full(tag: String) = assertEquals(node("parent").getUnclippedBoundsInRoot().width, node(tag).getUnclippedBoundsInRoot().width)
    private fun touch(tag: String) { node(tag).assertWidthIsAtLeast(44.dp).assertHeightIsAtLeast(44.dp) }

    @Test fun ambientScene() {
        show { FcAmbientScene(size = FcComponentMetrics.calendarIllustration) }
        node("today-empty-scene").assertWidthIsEqualTo(160.dp).assertHeightIsEqualTo(160.dp).assertHasNoClickAction()
        assertFalse(node("today-empty-scene").fetchSemanticsNode().config.contains(SemanticsProperties.ContentDescription))
        assertFalse(ambientMotionRunning(false, false, false)); assertFalse(ambientMotionRunning(true, true, false))
        assertFalse(ambientMotionRunning(true, false, true)); assertTrue(ambientMotionRunning(true, false, false))
        val still = ambientFrame(5.05, listOf(5.0), reducedMotion = true)
        assertEquals(2, still.steam.size); assertTrue(still.steam.all { it.opacity == 0.45f && it.x == 0f && it.y == 0f })
        assertEquals(1f, still.breathScale); assertFalse(still.closedEyes)
        assertFalse(ambientFrame(5.05, listOf(5.0), paused = true).closedEyes)
    }

    @Test fun setRow() {
        var confirms = 0; var edits = 0; var undos = 0
        show {
            FcSetRow(1, "20 kg × 8", false, true, { confirms++ }, { edits++ }, Modifier.testTag("pending"), tag = "pending")
            FcSetRow(2, "20 kg × 8", true, false, { confirms++ }, {}, tag = "complete", onUndo = { undos++ })
            FcSetRow(3, "20 kg × 8", false, false, { confirms++ }, { edits++ }, enabled = false, tag = "disabled")
        }
        full("pending"); node("pending").assertHeightIsEqualTo(38.dp)
        touch("pending-confirm"); touch("pending-edit"); node("pending-confirm").assertContentDescriptionEquals("确认本组").performClick()
        node("complete-circle").assertWidthIsEqualTo(22.dp).assertHeightIsEqualTo(22.dp)
        node("complete-edit-icon").assertWidthIsEqualTo(20.dp).assertHeightIsEqualTo(20.dp)
        touch("complete-confirm"); touch("complete-edit"); touch("complete-undo")
        node("pending-edit").assertContentDescriptionEquals("编辑组").performClick()
        node("complete-confirm").assertIsNotEnabled(); node("complete-undo").performClick()
        node("disabled-confirm").assertIsNotEnabled().performClick(); node("disabled-edit").assertIsNotEnabled().performClick()
        assertEquals(1, confirms); assertEquals(1, edits); assertEquals(1, undos)
    }

    @Test fun equipmentIcons() {
        show { FcEquipmentIconView(FcEquipmentIcon.barbell, Modifier.testTag("equipment")) }
        node("equipment").assertWidthIsEqualTo(24.dp).assertHeightIsEqualTo(24.dp).assertHasNoClickAction()
        assertFalse(node("equipment").fetchSemanticsNode().config.contains(SemanticsProperties.ContentDescription))
        assertEquals(21, FcEquipmentIcon.entries.size)
        val expected = mapOf("杠铃" to FcEquipmentIcon.barbell, "哑铃" to FcEquipmentIcon.dumbbell, "徒手" to FcEquipmentIcon.bodyweight,
            "绳索" to FcEquipmentIcon.cable_crossover, "史密斯机" to FcEquipmentIcon.smith_machine, "壶铃" to FcEquipmentIcon.kettlebell,
            "哈克机" to FcEquipmentIcon.hack_squat, "悍马机" to FcEquipmentIcon.plate_loaded, "悬挂带" to FcEquipmentIcon.suspension_trainer,
            "单杠" to FcEquipmentIcon.pull_up_bar, "弹力带" to FcEquipmentIcon.resistance_band)
        expected.forEach { (equipment, icon) -> assertEquals(icon, FcEquipmentIcon.icon(equipment, "核心")) }
        mapOf("胸" to FcEquipmentIcon.pec_deck, "肩" to FcEquipmentIcon.shoulder_press, "大腿" to FcEquipmentIcon.leg_extension,
            "臀" to FcEquipmentIcon.hip_adduction, "小腿" to FcEquipmentIcon.hack_squat, "背" to FcEquipmentIcon.tbar_row)
            .forEach { (muscle, icon) -> assertEquals(icon, FcEquipmentIcon.icon("固定器械", muscle)) }
        listOf("臂", "核心", "未知").forEach { assertNull(FcEquipmentIcon.icon("固定器械", it)) }
        assertNull(FcEquipmentIcon.icon(null, null)); assertNull(FcEquipmentIcon.icon("其他", "胸"))
    }

    @Test fun emptyStepperFieldRetainsVisibleEditorAndFullTouchArea() {
        var value by androidx.compose.runtime.mutableStateOf("")
        show { FcStepperField("次数", value, { value = it }, false,
            androidx.compose.ui.res.painterResource(com.ignacioli.finecoach.R.drawable.ic_ms_remove),
            androidx.compose.ui.res.painterResource(com.ignacioli.finecoach.R.drawable.ic_ms_add), {}, {}, tag = "empty-field") }
        node("empty-field-input").assertIsDisplayed().performTextReplacement("8")
        node("empty-field-input").assertTextEquals("8")
        touch("empty-field-input-touch")
    }

    @Test fun neighboringCompactRowsKeepIndependentRealTouchTargets() {
        val hits = IntArray(6)
        show {
            Column(Modifier.padding(16.dp)) {
                repeat(2) { row ->
                    FcSetRow(row + 1, "20 kg × 8", false, true, { hits[row * 3]++ }, { hits[row * 3 + 1]++ },
                        Modifier.testTag("compact-$row"), tag = "compact-$row", onUndo = { hits[row * 3 + 2]++ })
                }
            }
        }
        val first = node("compact-0").getUnclippedBoundsInRoot()
        val second = node("compact-1").getUnclippedBoundsInRoot()
        assertEquals(38.dp, second.top - first.top)
        repeat(2) { row ->
            listOf("confirm", "edit", "undo").forEach { touch("compact-$row-$it") }
            listOf("circle", "edit-icon", "undo").forEachIndexed { action, target ->
                hits.fill(0)
                node("compact-$row-$target").performTouchInput { click(center) }
                assertArrayEquals(IntArray(6).also { it[row * 3 + action] = 1 }, hits)
            }
        }
    }
    // S1-D38 (amended 2026-11-10): each 44dp hit box is centered on its visible graphic. The circle sits 3dp
    // below the row center, so its box spans row top..+44 (6dp into the next row); the edit box spans ±3dp.
    // Inside an overlap band the lower (later-placed) row wins; the band never covers a visible graphic.
    @Test fun overlapBandsBetweenAdjacentRowsResolveToTheLowerRow() {
        val hits = IntArray(4)
        show {
            Column(Modifier.padding(16.dp)) {
                repeat(2) { row ->
                    FcSetRow(row + 1, "20 kg × 8", false, true, { hits[row * 2]++ }, { hits[row * 2 + 1]++ },
                        Modifier.testTag("band-$row"), tag = "band-$row")
                }
            }
        }
        val boundary = node("band-1").getUnclippedBoundsInRoot().top
        val circleX = node("band-0-circle").getUnclippedBoundsInRoot().let { (it.left + it.right) / 2 }
        val editX = node("band-0-edit-icon").getUnclippedBoundsInRoot().let { (it.left + it.right) / 2 }
        listOf(node("band-0-circle"), node("band-1-circle"), node("band-0-edit-icon"), node("band-1-edit-icon")).forEach {
            val b = it.getUnclippedBoundsInRoot()
            assertTrue("graphic outside overlap bands", b.bottom <= boundary - 3.dp || b.top >= boundary + 6.dp)
        }
        fun tap(x: androidx.compose.ui.unit.Dp, y: androidx.compose.ui.unit.Dp): IntArray {
            hits.fill(0)
            compose.onRoot().performTouchInput { click(androidx.compose.ui.geometry.Offset(x.toPx(), y.toPx())) }
            return hits.copyOf()
        }
        // Circle band: 0..6dp below the boundary is inside both circle boxes and belongs to row 2.
        assertArrayEquals(intArrayOf(0, 0, 1, 0), tap(circleX, boundary + 5.dp))
        assertArrayEquals(intArrayOf(1, 0, 0, 0), tap(circleX, boundary - 1.dp))
        // Edit band: boundary ±3dp is inside both edit boxes and belongs to row 2.
        assertArrayEquals(intArrayOf(0, 0, 0, 1), tap(editX, boundary - 2.dp))
        assertArrayEquals(intArrayOf(0, 0, 0, 1), tap(editX, boundary + 2.dp))
        assertArrayEquals(intArrayOf(0, 1, 0, 0), tap(editX, boundary - 4.dp))
    }
    // S1-D40 R4: the AD-01 Material symbol is drawn at its natural 20dp bounds (no design-glyph frame).
    @Test fun fieldSymbolsDrawRealInkInsideTheirNaturalBounds() {
        show { FcStepperField("次数", "8", {}, true,
            androidx.compose.ui.res.painterResource(com.ignacioli.finecoach.R.drawable.ic_ms_remove),
            androidx.compose.ui.res.painterResource(com.ignacioli.finecoach.R.drawable.ic_ms_add), {}, {}, tag = "ink") }
        listOf("minus", "plus").forEach { symbol ->
            val glyph = node("ink-$symbol-glyph")
            glyph.assertWidthIsEqualTo(20.dp).assertHeightIsEqualTo(20.dp)
            touch("ink-$symbol")
            val pixels = glyph.captureToImage().toPixelMap()
            val ink = mutableListOf<Pair<Int, Int>>()
            for (y in 0 until pixels.height) for (x in 0 until pixels.width) {
                if (pixels[x, y] == FcColors.textPrimary) ink += x to y
            }
            assertTrue("The symbol must draw actual vector ink", ink.isNotEmpty())
            assertTrue("The vector must not be cut at its bounds", ink.all {
                it.first > 0 && it.first < pixels.width - 1 && it.second > 0 && it.second < pixels.height - 1
            })
        }
    }

    @Test fun primaryPage() {
        show { FcPagePrimary("虚构首页", Modifier.testTag("primary"), segments = {
            FcSegmentedSwitch(listOf("今日", "学员"), 0, {}, Modifier.testTag("segments"))
        }) { FcListRow("虚构内容", Modifier.testTag("content")) } }
        full("primary"); full("content")
        assertTrue(node("segments").getUnclippedBoundsInRoot().bottom <= compose.onNodeWithText("虚构首页").getUnclippedBoundsInRoot().top)
        compose.onNodeWithText("虚构首页").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
    }

    @Test fun secondaryPage() {
        var back = 0; var saves = 0
        compose.setContent { FineCoachTheme { FcPageSecondary("虚构详情", { back++ }, bottom = {
            FcButton("保存", Modifier.testTag("save")) { saves++ }
        }) { FcListRow("虚构内容", Modifier.testTag("content")) } } }
        compose.onNodeWithContentDescription("返回").performClick(); assertEquals(1, back)
        node("save").assertIsDisplayed().performClick(); assertEquals(1, saves)
        assertEquals(node("platform-content").getUnclippedBoundsInRoot().width, node("save").getUnclippedBoundsInRoot().width)
        node("content").assertExists()
    }

    @Test fun emptyState() {
        var calls = 0
        show { FcEmptyState("还没有学员", "虚构说明", Modifier.fillMaxSize().testTag("empty"), actionTitle = "新建学员", onAction = { calls++ }) }
        full("empty"); full("empty-action"); touch("empty-action")
        node("empty-mascot").assertWidthIsEqualTo(220.dp).assertHeightIsEqualTo(220.dp).assertHasNoClickAction()
        node("empty-action").assertIsDisplayed().performClick(); assertEquals(1, calls)
        compose.onNodeWithText("还没有学员").assertIsDisplayed(); compose.onNodeWithText("虚构说明").assertIsDisplayed()
    }

    @Test fun launch() {
        show { FcLaunch(Modifier.testTag("launch")) }
        full("launch"); node("launch").assertHasNoClickAction()
        compose.onAllNodes(hasText("", substring = true)).assertCountEquals(0)
        assertEquals(androidx.compose.ui.graphics.Color.White, FcColors.surfacePage)
    }

    @Test fun heroAndHint() {
        var single = 0; var hint = 0; var opened = ""
        show {
            FcHeroCard("进行中", "虚构学员", "已训练 1 分钟", Modifier.testTag("single"), "继续训练", { single++ })
            FcMultiHeroCard(listOf(FcHeroEntry("a", "虚构甲", "1 分钟"), FcHeroEntry("b", "虚构乙", "2 分钟")), { opened = it }, Modifier.testTag("multi"))
            FcHintBar("虚构提示", Modifier.testTag("hint"), "继续训练", { hint++ })
        }
        full("single"); node("single").assertHeightIsAtLeast(100.dp).performClick(); assertEquals(1, single)
        full("multi"); node("hero-a").assertHeightIsAtLeast(44.dp).performClick(); assertEquals("a", opened)
        node("hero-b").performClick(); assertEquals("b", opened)
        full("hint"); node("hint").assertHeightIsAtLeast(44.dp).performClick(); assertEquals(1, hint)
    }

    @Test fun favoritePrecedesDisclosureWithoutChangingRowAction() {
        var opens = 0
        show { FcListRow("虚构动作", Modifier.testTag("row"), mode = FcRowMode.Action { opens++ }, favorite = true) }
        full("row"); node("favorite-star").assertWidthIsEqualTo(24.dp).assertHasNoClickAction()
        assertFalse(node("favorite-star").fetchSemanticsNode().config.contains(SemanticsProperties.ContentDescription))
        val star = node("favorite-star").getUnclippedBoundsInRoot()
        val disclosure = node("list-row-disclosure").getUnclippedBoundsInRoot()
        assertTrue("Favorite must precede disclosure", star.right <= disclosure.left)
        node("row").performClick(); assertEquals(1, opens)
    }
}
