package com.ignacioli.finecoach.features.body

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.BodyDataUseCases
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.progress.Comparison
import com.ignacioli.finecoach.features.trends.FcTrendChart
import java.util.UUID

data class BodyRow(val metric: BodyMetricDefinition, val latest: BodyMeasurement?, val shown: String)

class BodyDataState(val studentID: StudentID, private val useCases: BodyDataUseCases) {
    var rows by mutableStateOf<List<BodyRow>>(emptyList()); private set
    var history by mutableStateOf<List<BodyMeasurement>>(emptyList()); private set
    var selected by mutableStateOf<BodyMetricDefinition?>(null); private set
    var displayUnit by mutableStateOf<String?>(null); private set
    var pendingDelete by mutableStateOf<UUID?>(null)
    var error by mutableStateOf(false); private set
    var busy by mutableStateOf(false); private set
    var draft by mutableStateOf("")

    suspend fun load() {
        busy = true
        val metrics = when (val result = useCases.metrics(studentID)) {
            is ApplicationResult.Failure -> { error = true; busy = false; return }
            is ApplicationResult.Success -> result.value.filter { it.lifecycle == BodyMetricLifecycle.active }
        }
        val latest = when (val result = useCases.latestMeasurements(studentID)) {
            is ApplicationResult.Failure -> { error = true; busy = false; return }
            is ApplicationResult.Success -> result.value
        }
        error = false
        rows = metrics.map { metric -> BodyRow(metric, latest[metric.id], display(metric, latest[metric.id])) }
        selected?.let { open(it.id) }
        busy = false
    }

    suspend fun open(id: UUID) {
        val metric = rows.firstOrNull { it.metric.id == id }?.metric ?: return
        selected = metric
        displayUnit = metric.currentUnit
        draft = ""
        history = when (val result = useCases.history(studentID, id)) {
            is ApplicationResult.Failure -> { error = true; emptyList() }
            is ApplicationResult.Success -> result.value
        }
    }

    fun close() { selected = null; pendingDelete = null }

    /** Display-only. Stored measurements keep the unit they were entered with. */
    fun showUnit(unit: String) {
        val metric = selected ?: return
        if (metric.kind == BodyMetricKind.custom) return
        displayUnit = unit
        rows = rows.map { row -> if (row.metric.id == metric.id) row.copy(shown = display(row.metric, row.latest)) else row }
    }

    suspend fun save() {
        val metric = selected ?: return
        val stored = try {
            canonicalEntry(metric, draft.trim())
        } catch (_: IllegalArgumentException) {
            error = true
            return
        }
        when (useCases.recordMeasurement(studentID, metric.id, stored.first, stored.second)) {
            is ApplicationResult.Failure -> error = true
            is ApplicationResult.Success -> { draft = ""; load() }
        }
    }

    /** iOS `canonicalInputForSave`: built-ins persist the canonical kg/cm value; custom keeps the typed unit. */
    private fun canonicalEntry(metric: BodyMetricDefinition, text: String): Pair<String, String> {
        if (metric.kind != BodyMetricKind.builtIn) return text to metric.currentUnit
        val shown = displayUnit ?: metric.canonicalUnit()
        val parsed = com.ignacioli.finecoach.core.domain.training.DecimalValue.parse(text)
        val canonical = when (metric.unitRuleKind) {
            BodyMetricUnitRuleKind.weight -> BuiltInUnitConversion.canonicalKilograms(parsed, shown)
            BodyMetricUnitRuleKind.length -> BuiltInUnitConversion.canonicalCentimeters(parsed, shown)
            else -> return text to metric.currentUnit
        }
        return canonical.canonicalString to metric.canonicalUnit()
    }

    suspend fun createCustom(name: String, unit: String) {
        when (val result = useCases.createCustomMetric(studentID, name, unit)) {
            is ApplicationResult.Failure -> error = true
            is ApplicationResult.Success -> { load(); open(result.value.id) }
        }
    }

    suspend fun confirmDelete() {
        val id = pendingDelete ?: return
        pendingDelete = null
        when (useCases.deleteMeasurement(id)) {
            is ApplicationResult.Failure -> error = true
            is ApplicationResult.Success -> load()
        }
    }

    fun chartValues(): List<Float> = history.map { measurement ->
        val unit = displayUnit ?: measurement.enteredUnit
        shownValue(selected, measurement, unit).toFloat()
    }

    fun density() = when (history.size) { 0 -> Comparison.TrendSampleDensity.empty; 1 -> Comparison.TrendSampleDensity.single; 2 -> Comparison.TrendSampleDensity.sparse; else -> Comparison.TrendSampleDensity.sufficient }

    private fun display(metric: BodyMetricDefinition, measurement: BodyMeasurement?): String {
        measurement ?: return "还没有记录"
        val unit = if (metric.id == selected?.id) displayUnit ?: metric.currentUnit else metric.currentUnit
        return format(shownValue(metric, measurement, unit), unit)
    }

    private fun shownValue(metric: BodyMetricDefinition?, measurement: BodyMeasurement, unit: String): java.math.BigDecimal {
        if (metric == null || metric.kind == BodyMetricKind.custom || unit == measurement.enteredUnit) return measurement.value.decimal
        return try {
            when (metric.unitRuleKind) {
                BodyMetricUnitRuleKind.weight -> BuiltInUnitConversion.weight(BuiltInUnitConversion.canonicalKilograms(measurement.value, measurement.enteredUnit), unit).decimal
                BodyMetricUnitRuleKind.length -> BuiltInUnitConversion.length(BuiltInUnitConversion.canonicalCentimeters(measurement.value, measurement.enteredUnit), unit).decimal
                else -> measurement.value.decimal
            }
        } catch (_: IllegalArgumentException) { measurement.value.decimal }
    }

    private fun format(value: java.math.BigDecimal, unit: String) = "${value.stripTrailingZeros().toPlainString()} $unit"
    private fun BodyMetricDefinition.canonicalUnit() = when (unitRuleKind) {
        BodyMetricUnitRuleKind.weight -> "kg"
        BodyMetricUnitRuleKind.percent -> "%"
        BodyMetricUnitRuleKind.length -> "cm"
        BodyMetricUnitRuleKind.customUnit -> currentUnit
    }
}

object BodyRoutes {
    const val PATTERN = "students/{studentID}/body"
    fun open(studentID: StudentID) = "students/${studentID.value}/body"
}
