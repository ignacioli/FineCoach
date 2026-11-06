package com.ignacioli.finecoach

import android.view.Window
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
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
class PlatformShellTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)

    @Test fun systemBackDispatcherAndHeaderUseTheSameRoute() {
        var calls = 0
        val back = { calls++; Unit }
        compose.setContent { FineCoachTheme { FcPlatformShell(back) { FcPageHeader("样例", onBack = back, tag = "shell") } } }
        node("shell-back").assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals(1, calls); compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.runOnIdle { assertEquals(2, calls) }
        // Dispatcher is the system-back delivery boundary, not a physical gesture animation.
    }

    @Test fun contentConsumesTopBottomAndSideInsetsExactlyOnce() {
        compose.setContent {
            FineCoachTheme {
                FcPlatformShell({}, insets = WindowInsets(left = 8.dp, top = 24.dp, right = 12.dp, bottom = 32.dp)) {
                    Box(Modifier.fillMaxSize().testTag("leaf"))
                }
            }
        }
        val shell = node("platform-shell").getUnclippedBoundsInRoot()
        val leaf = node("leaf").getUnclippedBoundsInRoot()
        assertEquals(shell.top + 24.dp, leaf.top); assertEquals(shell.bottom - 32.dp, leaf.bottom)
        assertEquals(shell.left + 8.dp + 16.dp, leaf.left)
        assertEquals(shell.right - 12.dp - 16.dp, leaf.right)
    }

    @Test fun fullWidthControlFillsInsetContentRatherThanScreen() {
        compose.setContent {
            FineCoachTheme { FcPlatformShell({}, insets = WindowInsets(0, 0, 0, 0)) {
                FcButton("样例", Modifier.testTag("full")) { }
            } }
        }
        val shell = node("platform-shell").getUnclippedBoundsInRoot()
        val button = node("full").getUnclippedBoundsInRoot()
        assertEquals(shell.width - 32.dp, button.width)
        node("full").assertIsDisplayed().assertHasClickAction()
    }

    @Test fun catalogVisibleEntriesReachComponentsAndReturnWithoutProductNavigation() {
        compose.setContent { FineCoachTheme { S0ComponentCatalog { } } }
        node("catalog-DS-BUTTON").assertIsDisplayed().performClick()
        node("DS-BUTTON-default").assertIsDisplayed().performClick()
        node("DS-BUTTON-default-count").assertTextEquals("样例交互计数：1")
        node("catalog-back").performClick()
        node("catalog-DS-BUTTON").assertIsDisplayed()
        node("catalog-DS-BASE").performClick()
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        node("catalog-DS-BASE").assertIsDisplayed()
    }

    @Test fun independentOverlayWindowsRegisterAndUnregisterWithPrivacyRegistry() {
        val active = mutableSetOf<Window>()
        val registry = FcWindowRegistry({ active += it }, { active -= it })
        var overlay by mutableStateOf("confirm")
        compose.setContent {
            FineCoachTheme { CompositionLocalProvider(LocalFcWindowRegistry provides registry) {
                when (overlay) {
                    "confirm" -> FcConfirmationDialog("虚构确认", "样例", "确认", { overlay = "sheet" }, { overlay = "none" })
                    "sheet" -> FcBottomSheet("虚构面板", { overlay = "none" }) {
                        FcActionRow("关闭", Modifier.testTag("sheet-close")) { overlay = "none" }
                    }
                }
            } }
        }
        compose.runOnIdle { assertEquals(1, active.size) }
        node("confirm-accept").performClick()
        node("sheet-close").assertIsDisplayed()
        compose.runOnIdle { assertEquals(1, active.size) }
        node("sheet-close").performClick()
        compose.runOnIdle { assertTrue(active.isEmpty()) }
    }
}
