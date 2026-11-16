// fictional-data: fixture labels and callback counters exist only in memory.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
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
class EntryLayoutHarnessTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private var calls = 0

    private fun fixture(hidden: Boolean = false, enabled: Boolean = true, narrow: Boolean = false) {
        compose.setContent { FineCoachTheme {
            Box(Modifier.fillMaxWidth().testTag("outer").padding(16.dp)) {
                Box(Modifier.fillMaxWidth().testTag("content")) {
                    Box(if (narrow) Modifier.width(100.dp) else Modifier.fillMaxWidth()) {
                        FcButton("虚构入口", Modifier.testTag("entry").then(
                            if (hidden) Modifier.offset(y = 1000.dp) else Modifier
                        ), enabled = enabled) { calls++ }
                    }
                }
            }
        } }
    }

    private fun rejected(reason: String, assertion: () -> Unit) {
        val failure = assertThrows(AssertionError::class.java) { assertion() }
        assertTrue("failure must identify $reason: ${failure.message}", failure.message.orEmpty().contains(reason))
        compose.runOnIdle { assertEquals(0, calls) }
    }

    @Test fun componentClickMutatesExactlyOnceAndFillsPaddedContent() {
        fixture()
        compose.assertEntryClick("entry") { calls }
        compose.assertFullContentWidth("entry", "content")
    }
    @Test fun missingTagRejected() { fixture(); rejected("missing tag") { compose.assertEntryClick("absent") { calls } } }
    @Test fun hiddenRejected() { fixture(hidden = true); rejected("not visible") { compose.assertEntryClick("entry") { calls } } }
    @Test fun disabledRejected() { fixture(enabled = false); rejected("disabled") { compose.assertEntryClick("entry") { calls } } }
    @Test fun narrowRejected() { fixture(narrow = true); rejected("must equal parent content") { compose.assertFullContentWidth("entry", "content") } }

    @OptIn(ExperimentalFoundationApi::class)
    @Test fun longPressOnlyRejected() {
        compose.setContent { FineCoachTheme {
            Box(Modifier.size(80.dp).testTag("entry").pointerInput(Unit) { detectTapGestures(onLongPress = { calls++ }) }
                .semantics { onLongClick { calls++; true } })
        } }
        rejected("no single-click action") { compose.assertEntryClick("entry") { calls } }
    }
    @Test fun clickWithoutMutationRejected() {
        compose.setContent { FineCoachTheme { FcButton("虚构入口", Modifier.testTag("entry")) {} } }
        rejected("single click must mutate") { compose.assertEntryClick("entry") { calls } }
    }
    @OptIn(ExperimentalFoundationApi::class)
    @Test fun longPressWithNoOpClickRejectedByMutation() {
        compose.setContent { FineCoachTheme {
            Box(Modifier.size(80.dp).testTag("entry")
                .combinedClickable(onLongClick = { calls++ }, onClick = {}))
        } }
        rejected("single click must mutate") { compose.assertEntryClick("entry") { calls } }
    }

    @Test fun zeroSizeRejected() {
        compose.setContent { Box(Modifier.size(0.dp).testTag("entry").clickable { calls++ }) }
        rejected("not visible") { compose.assertEntryClick("entry") { calls } }
    }

    @Test fun parentClippedEmptyBoundsRejected() {
        compose.setContent {
            Box(Modifier.size(0.dp).clipToBounds()) {
                Box(Modifier.requiredSize(80.dp).testTag("entry").clickable { calls++ })
            }
        }
        rejected("not visible") { compose.assertEntryClick("entry") { calls } }
    }

    @Test fun coveringClickableNodeInterceptsRealCenterClick() {
        var blockerCalls = 0
        compose.setContent { FineCoachTheme {
            Box(Modifier.fillMaxWidth()) {
                FcButton("虚构入口", Modifier.testTag("entry")) { calls++ }
                Box(Modifier.matchParentSize().clickable { blockerCalls++ })
            }
        } }
        rejected("single click must mutate") { compose.assertEntryClick("entry") { calls } }
        compose.runOnIdle { assertEquals(1, blockerCalls) }
    }

    @Test fun parentTagOutsidePaddingDeliberatelyFailsWidthCheck() {
        fixture()
        rejected("must equal parent content") { compose.assertFullContentWidth("entry", "outer") }
    }

}
