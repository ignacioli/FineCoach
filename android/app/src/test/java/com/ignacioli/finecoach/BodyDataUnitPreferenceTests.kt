// fictional-data: synthetic measurements and private temporary preferences; diagnostics contain no values.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.features.body.BodyDataState
import com.ignacioli.finecoach.storage.local.BodyDataUnitPreferences
import com.ignacioli.finecoach.storage.repository.BodyDataRepository
import java.io.File
import java.nio.file.Files
import java.util.UUID
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class BodyDataUnitPreferenceTests {
    private val f = T009Fixture()
    private val dir = Files.createTempDirectory("body-preferences-").toFile()
    @After fun close() { f.close(); dir.deleteRecursively() }
    private fun cases() = BodyDataUseCases(BodyDataRepository(f.db, f.clock), f.clock, f.zone) { UUID.randomUUID() }
    private fun state(preferences: BodyDataUnitPreferences = BodyDataUnitPreferences(dir), student: StudentID = f.studentID) = BodyDataState(student, cases(), preferences)

    @Test fun listDetailAndChartLabelSharePrecisionWithoutChangingStoredValue() = f.test {
        val cases = cases()
        f.ok(cases.recordMeasurement(f.studentID, BuiltInBodyMetric.weight.id, "62.9994", "kg"))
        val state = state(); state.load(); state.open(BuiltInBodyMetric.weight.id)
        val row = state.rows.first { it.metric.id == BuiltInBodyMetric.weight.id }
        check(row.value == "63") { "List precision mismatch" }
        check(state.measurementLabel(state.history.single()) == row.shown && state.chartSamples().single().quantity == row.shown) { "Detail and chart label precision mismatch" }
        check(f.ok(cases.history(f.studentID, BuiltInBodyMetric.weight.id)).single().value.canonicalString == "62.9994") { "Display changed stored precision" }
        check(state.chartValues().single() != 63f) { "Display changed chart computation" }
    }

    @Test fun allBuiltInEntryUnitsAndCustomRoundTripWithoutDisplayRewritingStorage() = f.test {
        val cases = cases()
        val custom = f.ok(cases.createCustomMetric(f.studentID, "虚构指标", "格"))
        val scenarios = listOf(
            Triple(BuiltInBodyMetric.weight.id, "kg", "70"), Triple(BuiltInBodyMetric.weight.id, "lb", "150"),
            Triple(BuiltInBodyMetric.waist.id, "cm", "80"), Triple(BuiltInBodyMetric.waist.id, "in", "30"),
            Triple(BuiltInBodyMetric.bodyFatPercent.id, "%", "20"), Triple(custom.id, "格", "3"))
        for ((id, unit, input) in scenarios) {
            val state = state(); state.load(); state.open(id)
            if (unit in setOf("kg", "lb", "cm", "in")) state.showUnit(unit)
            state.draft = input; state.save()
            check(!state.error) { "Entry failed" }
            val stored = f.ok(cases.history(f.studentID, id)).single()
            val expected = when (unit) {
                "lb" -> BuiltInUnitConversion.canonicalKilograms(DecimalValue.parse(input), unit)
                "in" -> BuiltInUnitConversion.canonicalCentimeters(DecimalValue.parse(input), unit)
                else -> DecimalValue.parse(input)
            }
            val canonical = when (unit) { "lb" -> "kg"; "in" -> "cm"; else -> unit }
            check(stored.enteredUnit == canonical && stored.value == expected) { "Canonical entry mismatch" }
            check(state.displayUnit == unit) { "Save reset display preference" }
            val chart = state.chartValues().single()
            check(kotlin.math.abs(chart - input.toFloat()) < 0.02f) { "Display conversion mismatch" }
            if (unit in setOf("kg", "lb", "cm", "in")) {
                state.showUnit(when (unit) { "kg" -> "lb"; "lb" -> "kg"; "cm" -> "in"; else -> "cm" })
                val after = f.ok(cases.history(f.studentID, id)).single()
                check(after.id == stored.id && after.value == stored.value && after.enteredUnit == stored.enteredUnit) { "Display switch rewrote measurement" }
            }
        }
        f.reopen()
        check(f.ok(cases().history(f.studentID, custom.id)).single().enteredUnit == "格") { "Custom entry did not survive reopen" }
    }

    @Test fun choicesSurviveLoadOpenMetricStudentAndStoreReconstruction() = f.test {
        val first = state(); first.load(); first.open(BuiltInBodyMetric.weight.id); first.showUnit("lb")
        first.load(); check(first.displayUnit == "lb") { "Load reset preference" }
        first.close(); first.open(BuiltInBodyMetric.weight.id)
        check(first.displayUnit == "lb") { "Open reset preference" }
        first.open(BuiltInBodyMetric.waist.id); first.showUnit("in")
        first.open(BuiltInBodyMetric.height.id)
        check(first.displayUnit == "in") { "Length preference was metric scoped" }
        first.open(BuiltInBodyMetric.weight.id)
        check(first.displayUnit == "lb") { "Length preference overwrote weight preference" }
        val other = state(student = StudentID.parse("abcdef09-0000-4000-8000-000000000002"))
        other.load(); other.open(BuiltInBodyMetric.weight.id)
        check(other.displayUnit == "lb") { "Preference was student scoped" }
        f.reopen()
        val restarted = state(); restarted.load(); restarted.open(BuiltInBodyMetric.waist.id)
        check(restarted.displayUnit == "in") { "Preference did not survive reconstruction" }
    }

    @Test fun listAndTrendUseRememberedUnitsWithoutMutatingMeasurements() = f.test {
        val cases = cases()
        f.ok(cases.metrics(f.studentID))
        f.ok(cases.recordMeasurement(f.studentID, BuiltInBodyMetric.weight.id, "70", "kg"))
        val state = state(); state.load(); state.open(BuiltInBodyMetric.weight.id); state.showUnit("lb"); state.close(); state.load()
        check(state.rows.first { it.metric.id == BuiltInBodyMetric.weight.id }.shown.endsWith(" lb")) { "List ignored preference" }
        state.open(BuiltInBodyMetric.weight.id)
        check(kotlin.math.abs(state.chartValues().single() - 154.32f) < 0.01f) { "Trend ignored preference" }
        check(f.ok(cases.history(f.studentID, BuiltInBodyMetric.weight.id)).single().value.canonicalString == "70") { "Preference changed storage" }
    }

    @Test fun invalidUnitsAndCorruptionFailSafelyAndWriteFailureIsVisible() = f.test {
        val store = BodyDataUnitPreferences(dir)
        check(store.saveWeight("lb") is ApplicationResult.Success) { "Preference save failed" }
        check(store.saveLength("kg") is ApplicationResult.Failure) { "Invalid unit accepted" }
        check(store.read().weight == "lb") { "Rejected unit changed preference" }
        File(dir, "BodyData/display-units.json").writeText("{broken")
        check(store.read() == BodyDataUnitPreferences.Units()) { "Corruption fallback failed" }
        val blocked = File(dir, "blocked").also { it.writeText("fictional-data") }
        val state = state(BodyDataUnitPreferences(blocked)); state.load(); state.open(BuiltInBodyMetric.weight.id); state.showUnit("lb")
        check(state.error && state.displayUnit == "kg") { "Preference failure was reported as success" }
        val regular = state(); regular.load(); regular.open(BuiltInBodyMetric.weight.id); regular.showUnit("in")
        check(regular.error && regular.displayUnit == "kg") { "Wrong unit family accepted" }
    }
}
