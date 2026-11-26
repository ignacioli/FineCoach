package com.ignacioli.finecoach.features.body

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.BodyDataUseCases
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.progress.Comparison
import com.ignacioli.finecoach.core.application.StudentUseCases
import java.util.UUID
import com.ignacioli.finecoach.storage.local.BodyDataUnitPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class BodyRow(val metric: BodyMetricDefinition, val latest: BodyMeasurement?, val value: String, val unit: String) { val shown get() = "$value $unit" }

class BodyDataState(val studentID: StudentID, private val useCases: BodyDataUseCases,
    private val unitPreferences: BodyDataUnitPreferences = BodyDataUnitPreferences(),
    private val students: StudentUseCases? = null) {
    private var units = BodyDataUnitPreferences.Units()
    var studentName by mutableStateOf(""); private set
    val unitSummary get() = "单位 · ${units.weight} / ${units.length}"
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
        students?.let { cases ->
            when (val result = cases.displayNames(setOf(studentID))) {
                is ApplicationResult.Success -> studentName = result.value[studentID].orEmpty()
                is ApplicationResult.Failure -> { error = true; busy = false; return }
            }
        }
        val metrics = when (val result = useCases.metrics(studentID)) {
            is ApplicationResult.Failure -> { error = true; busy = false; return }
            is ApplicationResult.Success -> result.value.filter { it.lifecycle == BodyMetricLifecycle.active }
        }
        val latest = when (val result = useCases.latestMeasurements(studentID)) {
            is ApplicationResult.Failure -> { error = true; busy = false; return }
            is ApplicationResult.Success -> result.value
        }
        error = false
        units = withContext(Dispatchers.IO) { unitPreferences.read() }
        rows = metrics.map { metric -> row(metric, latest[metric.id]) }
        selected?.let { open(it.id) }
        busy = false
    }

    suspend fun open(id: UUID) {
        val metric = rows.firstOrNull { it.metric.id == id }?.metric ?: return
        selected = metric
        units = withContext(Dispatchers.IO) { unitPreferences.read() }
        displayUnit = preferredUnit(metric)
        draft = ""
        history = when (val result = useCases.history(studentID, id)) {
            is ApplicationResult.Failure -> { error = true; emptyList() }
            is ApplicationResult.Success -> result.value
        }
    }

    fun close() { selected = null; pendingDelete = null }

    /** Display-only; publish the choice only after the local preference is durable. */
    suspend fun showUnit(unit: String) {
        val metric = selected ?: return
        if (metric.kind == BodyMetricKind.custom) return
        val result = withContext(Dispatchers.IO) {
            when (metric.unitRuleKind) {
                BodyMetricUnitRuleKind.weight -> unitPreferences.saveWeight(unit)
                BodyMetricUnitRuleKind.length -> unitPreferences.saveLength(unit)
                else -> ApplicationResult.Failure(com.ignacioli.finecoach.core.application.ApplicationError(
                    com.ignacioli.finecoach.core.application.ApplicationErrorCode.incompatibleInput))
            }
        }
        when (result) {
            is ApplicationResult.Failure -> { error = true; return }
            is ApplicationResult.Success -> units = result.value
        }
        error = false
        displayUnit = unit
        rows = rows.map { row -> row(row.metric, row.latest) }
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

    fun chartSamples(): List<com.ignacioli.finecoach.features.trends.TrendChartSample> = history.map { measurement ->
        val metric = selected
        val unit = if (metric?.kind == BodyMetricKind.custom) measurement.enteredUnit else displayUnit ?: measurement.enteredUnit
        val day = measurement.localCalendarDay
        com.ignacioli.finecoach.features.trends.TrendChartSample("${day.monthValue}月${day.dayOfMonth}日",
            shownValue(metric, measurement, unit), unit, metric?.kind == BodyMetricKind.custom)
    }

    fun density() = when (history.size) { 0 -> Comparison.TrendSampleDensity.empty; 1 -> Comparison.TrendSampleDensity.single; 2 -> Comparison.TrendSampleDensity.sparse; else -> Comparison.TrendSampleDensity.sufficient }

    private fun row(metric: BodyMetricDefinition, measurement: BodyMeasurement?): BodyRow {
        val unit = if (metric.kind == BodyMetricKind.custom) measurement?.enteredUnit ?: metric.currentUnit else preferredUnit(metric)
        return BodyRow(metric, measurement, measurement?.let {
            BodyDataDisplay.format(shownValue(metric, it, unit), unit, metric.kind == BodyMetricKind.custom)
        } ?: "—", unit)
    }

    fun measurementLabel(measurement: BodyMeasurement): String {
        val metric = selected ?: return "—"
        return row(metric, measurement).shown
    }

    private fun preferredUnit(metric: BodyMetricDefinition) = when {
        metric.kind == BodyMetricKind.custom -> metric.currentUnit
        metric.unitRuleKind == BodyMetricUnitRuleKind.weight -> units.weight
        metric.unitRuleKind == BodyMetricUnitRuleKind.length -> units.length
        else -> metric.currentUnit
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
