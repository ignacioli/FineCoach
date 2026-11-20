// fictional-data: invented body measurements; values stay out of assertion messages.
package com.ignacioli.finecoach

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.width
import com.ignacioli.finecoach.core.application.BodyDataUseCases
import com.ignacioli.finecoach.core.domain.body.BuiltInBodyMetric
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.body.BodyDataScreen
import com.ignacioli.finecoach.features.body.BodyDataState
import com.ignacioli.finecoach.storage.repository.BodyDataRepository
import java.util.UUID
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w390dp-h844dp-notnight-mdpi")
class BodyDataEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val f = T009Fixture()
    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)
    private fun exists(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    @After fun close() { compose.runOnUiThread { compose.activity.setContent {} }; f.close() }

    @Test fun sameDayEditDeleteConfirmationAndDisplayUnitDoNotRewriteStorage() {
        val cases = BodyDataUseCases(BodyDataRepository(f.db, f.clock), f.clock, f.zone) { UUID.randomUUID() }
        val state = BodyDataState(f.studentID, cases)
        val metric = BuiltInBodyMetric.weight.id
        f.test { state.load(); state.open(metric) }
        compose.setContent { FineCoachTheme { BodyDataScreen(state) {} } }
        compose.waitUntil(15_000) { exists("body-save") }
        node("body-value").performTextInput("70")
        node("body-save").assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitUntil(15_000) { !state.busy && state.history.size == 1 }
        node("body-value").performTextReplacement("71")
        node("body-save").performClick()
        compose.waitUntil(15_000) { state.history.size == 1 && state.history.single().value.canonicalString == "71" }
        f.test {
            val stored = (cases.history(f.studentID, metric) as com.ignacioli.finecoach.core.application.ApplicationResult.Success).value
            check(stored.size == 1) { "same-day record was not an edit" }
            check(stored.single().enteredUnit == "kg") { "display unit was written into storage" }
            check(stored.single().value.canonicalString == "71") { "edited record was not stored" }
        }
        node("body-unit-lb").assertIsDisplayed().assertHasClickAction().performClick()
        f.test {
            val stored = (cases.history(f.studentID, metric) as com.ignacioli.finecoach.core.application.ApplicationResult.Success).value.single()
            check(stored.enteredUnit == "kg") { "unit switch changed storage" }
            check(stored.value.canonicalString == "71") { "unit switch changed the stored number" }
        }
        val id = state.history.single().id
        node("body-delete-$id").performScrollTo().assertIsDisplayed().assertHasClickAction().performClick()
        node("body-delete-cancel").assertIsDisplayed().assertHasClickAction().performClick()
        check(state.history.size == 1) { "cancel removed a record" }
        node("body-delete-$id").performClick()
        node("body-delete-accept").assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitUntil(15_000) { state.history.isEmpty() }
        f.test {
            val stored = (cases.history(f.studentID, metric) as com.ignacioli.finecoach.core.application.ApplicationResult.Success).value
            check(stored.isEmpty()) { "confirmed delete did not remove the record" }
        }
        check(node("platform-content").getUnclippedBoundsInRoot().width == node("body-save").getUnclippedBoundsInRoot().width) { "save does not fill the page" }
    }

    @Test fun displayedUnitIsConvertedBeforeItIsStored() {
        val cases = BodyDataUseCases(BodyDataRepository(f.db, f.clock), f.clock, f.zone) { UUID.randomUUID() }
        val state = BodyDataState(f.studentID, cases)
        val metric = BuiltInBodyMetric.weight.id
        f.test { state.load(); state.open(metric) }
        compose.setContent { FineCoachTheme { BodyDataScreen(state) {} } }
        compose.waitUntil(15_000) { exists("body-unit-lb") }
        node("body-unit-lb").assertIsDisplayed().performClick()
        node("body-value").assertIsDisplayed()
        check(compose.onAllNodesWithText("lb", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()) { "entry unit is not visible" }
        node("body-value").performTextInput("150")
        node("body-save").performClick()
        compose.waitUntil(15_000) { state.history.size == 1 }
        f.test {
            val stored = (cases.history(f.studentID, metric) as com.ignacioli.finecoach.core.application.ApplicationResult.Success).value.single()
            val expected = com.ignacioli.finecoach.core.domain.body.BuiltInUnitConversion.canonicalKilograms(
                com.ignacioli.finecoach.core.domain.training.DecimalValue.parse("150"), "lb")
            check(stored.enteredUnit == "kg") { "built-in weight was not stored in the canonical unit" }
            check(stored.value.canonicalString == expected.canonicalString) { "built-in weight kept the displayed number" }
        }
        node("body-unit-kg").performClick()
        f.test {
            val stored = (cases.history(f.studentID, metric) as com.ignacioli.finecoach.core.application.ApplicationResult.Success).value.single()
            check(stored.enteredUnit == "kg") { "switching the display unit rewrote storage" }
            check(state.rows.first { it.metric.id == metric }.shown.endsWith(" kg")) { "canonical unit was not shown" }
        }
    }

    @Test fun openMetricAndSaveCustomMetricFromVisibleControls() {
        val cases = BodyDataUseCases(BodyDataRepository(f.db, f.clock), f.clock, f.zone) { UUID.randomUUID() }
        val state = BodyDataState(f.studentID, cases)
        f.test { state.load() }
        compose.setContent { FineCoachTheme { BodyDataScreen(state) {} } }
        compose.waitUntil(15_000) { state.rows.isNotEmpty() }
        val metric = state.rows.first().metric.id
        node("body-open-$metric").performScrollTo().assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitUntil(15_000) { exists("body-save") }
        compose.runOnUiThread { state.close() }
        compose.waitUntil(15_000) { exists("body-custom") }
        node("body-custom").assertIsDisplayed().assertHasClickAction().performClick()
        node("body-custom-name").performTextInput("虚构围度")
        node("body-custom-unit").performTextInput("fist")
        node("body-custom-save").assertIsDisplayed().assertHasClickAction().performClick()
        compose.waitUntil(15_000) { state.selected?.kind == com.ignacioli.finecoach.core.domain.body.BodyMetricKind.custom }
        f.test {
            val stored = (cases.metrics(f.studentID) as com.ignacioli.finecoach.core.application.ApplicationResult.Success).value
            check(stored.any { it.kind == com.ignacioli.finecoach.core.domain.body.BodyMetricKind.custom && it.currentUnit == "fist" }) { "custom metric was not stored" }
        }
        f.test {
            val created = (cases.createCustomMetric(f.studentID, "虚构围度", "fist") as com.ignacioli.finecoach.core.application.ApplicationResult.Success).value
            val saved = (cases.recordMeasurement(f.studentID, created.id, "3", "fist") as com.ignacioli.finecoach.core.application.ApplicationResult.Success).value
            check(saved.enteredUnit == "fist") { "custom unit was not kept" }
            check(saved.value.canonicalString == "3") { "custom value was not kept" }
        }
    }
}
