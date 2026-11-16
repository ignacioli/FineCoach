// fictional-data: callers supply in-memory fixture counters only.
package com.ignacioli.finecoach

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.ComposeTestRule
import org.junit.Assert.assertEquals

/** Tags must identify the actual clickable node, not a surrounding label/container. */
fun ComposeTestRule.assertEntryClick(tag: String, callbackCount: () -> Int) {
    val node = onNodeWithTag(tag, useUnmergedTree = true)
    fun requireStage(reason: String, assertion: () -> Unit) {
        try { assertion() } catch (failure: AssertionError) {
            throw AssertionError("entry[$tag]: $reason", failure)
        }
    }
    requireStage("missing tag") { node.assertExists() }
    requireStage("not visible") { node.assertIsDisplayed() }
    requireStage("disabled") { node.assertIsEnabled() }
    requireStage("no single-click action (long-press alone is insufficient)") { node.assertHasClickAction() }
    runOnIdle { assertEquals("entry[$tag]: callback must start at zero", 0, callbackCount()) }
    node.performTouchInput { click(center) }
    runOnIdle { assertEquals("entry[$tag]: single click must mutate callback count to one", 1, callbackCount()) }
}

/**
 * Compare actual pixel bounds with the caller's tagged parent content area.
 * parentContentTag must be on a content container INSIDE padding, not on the
 * padded outer container; the latter includes padding and deliberately fails.
 */
fun ComposeTestRule.assertFullContentWidth(tag: String, parentContentTag: String) {
    val child = onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
    val parent = onNodeWithTag(parentContentTag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
    assertEquals("width[$tag]: must equal parent content[$parentContentTag] pixels", parent.width, child.width, 0f)
}
