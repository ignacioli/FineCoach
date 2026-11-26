package com.ignacioli.finecoach.features.body

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.ignacioli.finecoach.core.domain.body.BuiltInBodyMetric
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.domain.body.BodyMetricKind
import com.ignacioli.finecoach.core.domain.body.BodyMetricUnitRuleKind
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.features.trends.FcTrendChart
import kotlinx.coroutines.launch

@Composable
fun BodyDataScreen(state: BodyDataState, onBack: () -> Unit) {
    var custom by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var unit by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val selected = state.selected
    var inspecting by remember(state.history, state.displayUnit, selected) { mutableStateOf(false) }
    val samples = remember(state.history, state.displayUnit, selected) { state.chartSamples() }
    FcPlatformShell(onBack) {
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("body-list"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            FcPageHeader(if (selected == null) "身体数据" else selected.name.value, onBack = { if (selected == null) onBack() else state.close() }, tag = "body")
            if (state.error) FcText("没有完成，再试一次。", Modifier.testTag("body-error"), style = FcTypography.caption, color = FcColors.statusDestructive)
            if (selected == null) {
                FcText(state.studentName, Modifier.testTag("body-student"), style = FcTypography.headline, color = FcColors.textSecondary)
                val basic = listOf(BuiltInBodyMetric.weight, BuiltInBodyMetric.bodyFatPercent, BuiltInBodyMetric.height)
                val girths = listOf(BuiltInBodyMetric.chest, BuiltInBodyMetric.waist, BuiltInBodyMetric.hip, BuiltInBodyMetric.upperArm, BuiltInBodyMetric.thigh)
                val groups = listOf(
                    "基本指标" to basic.mapNotNull { metric -> state.rows.find { it.metric.id == metric.id } },
                    "围度" to girths.mapNotNull { metric -> state.rows.find { it.metric.id == metric.id } },
                    "自定义指标" to state.rows.filter { it.metric.kind == BodyMetricKind.custom })
                groups.forEach { (title, rows) ->
                    Column(Modifier.fillMaxWidth()) {
                        FcText(title, Modifier.padding(top = FcSpacing.space2, bottom = FcSpacing.space1),
                            style = FcTypography.sectionLabel, color = FcColors.textSecondary)
                        rows.forEach { row ->
                            BodyMetricValueRow(row) { scope.launch { state.open(row.metric.id) } }
                            FcListRowDivider()
                        }
                    }
                }
            } else {
                if (selected.kind == BodyMetricKind.builtIn && selected.unitRuleKind != BodyMetricUnitRuleKind.percent) {
                    val choices = if (selected.unitRuleKind == BodyMetricUnitRuleKind.weight) listOf("kg", "lb") else listOf("cm", "in")
                    Row(Modifier.fillMaxWidth().testTag("body-units"), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                        choices.forEach { choice ->
                            FcFilterChip(choice, state.displayUnit == choice, Modifier.testTag("body-unit-$choice")) { scope.launch { state.showUnit(choice) } }
                        }
                    }
                }
                val entryUnit = state.displayUnit ?: selected.currentUnit
                FcTextField(if (selected.kind == BodyMetricKind.custom || selected.unitRuleKind == BodyMetricUnitRuleKind.percent) "数值" else entryUnit,
                    state.draft, { state.draft = it }, Modifier.testTag("body-value"))
                FcButton("保存", Modifier.testTag("body-save"), state.draft.isNotBlank() && !state.busy) { scope.launch { state.save() } }
                if (state.history.size >= 2) {
                    FcText(state.measurementLabel(state.history.first()), Modifier.testTag("body-chart-label").then(if (inspecting) Modifier.alpha(0f).clearAndSetSemantics {} else Modifier), style = FcTypography.caption, color = FcColors.textSecondary)
                    FcTrendChart(state.chartValues(), state.density() == com.ignacioli.finecoach.core.domain.progress.Comparison.TrendSampleDensity.sparse,
                    Modifier.fillMaxWidth().height(FcSpacing.space8 * 4 + FcSpacing.space3).testTag("body-chart"), samples = samples) { inspecting = it }
                }
                else if (state.history.size == 1) FcText("再记一次就能看出趋势", Modifier.testTag("body-single"), style = FcTypography.caption, color = FcColors.textSecondary)
                else FcText("记下第一条后，这里会显示变化", Modifier.testTag("body-empty"), style = FcTypography.caption, color = FcColors.textSecondary)
                Column(Modifier.fillMaxWidth().testTag("body-history")) {
                    state.history.forEach { measurement ->
                        Row(Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            FcText(measurement.localCalendarDay.toString(), Modifier.weight(1f).testTag("body-day-${measurement.id}"),
                                style = FcTypography.body, color = FcColors.textPrimary)
                            FcText(state.measurementLabel(measurement), Modifier.testTag("body-history-value-${measurement.id}"), style = FcTypography.callout)
                            FcButton("删除", Modifier.weight(1f).testTag("body-delete-${measurement.id}")) { state.pendingDelete = measurement.id }
                        }
                    }
                }
            }
        }
        if (selected == null) Row(Modifier.fillMaxWidth().padding(vertical = FcSpacing.space2).testTag("body-footer"),
            verticalAlignment = Alignment.CenterVertically) {
            FcText(state.unitSummary, Modifier.weight(1f).testTag("body-unit-summary"), style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
            Spacer(Modifier.width(FcSpacing.space2))
            FcLinkButton("＋ 自定义指标", Modifier.testTag("body-custom"), contentAlignment = Alignment.CenterEnd) { custom = true }
        }
    }
    if (custom) FcBottomSheet("自定义指标", { custom = false }, skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().testTag("body-custom-sheet"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
            FcTextField("名称", name, { name = it }, Modifier.testTag("body-custom-name"))
            FcTextField("单位", unit, { unit = it }, Modifier.testTag("body-custom-unit"))
            FcButton("保存", Modifier.testTag("body-custom-save"), name.isNotBlank() && unit.isNotBlank()) {
                scope.launch { state.createCustom(name.trim(), unit.trim()); custom = false }
            }
        }
    }
    state.pendingDelete?.let {
        FcConfirmationDialog("删除这条记录？", "删除后趋势会按剩下的记录重算。", "删除",
            { scope.launch { state.confirmDelete() } }, { state.pendingDelete = null }, tag = "body-delete")
    }
}

/** Feature-owned value columns from the approved body-data anatomy. */
@Composable
private fun BodyMetricValueRow(row: BodyRow, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row)
        .clickable(onClick = onClick).testTag("body-open-${row.metric.id}")
        .padding(vertical = FcSpacing.space3)) {
        FcText(row.metric.name.value, Modifier.weight(1f).alignByBaseline(),
            style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
        FcText(row.value, Modifier.width(FcSpacing.space8 * 2 + FcSpacing.space6 + FcSpacing.space1 / 2).alignByBaseline().testTag("body-number-${row.metric.id}"),
            style = FcTypography.numeralLarge, color = FcColors.textPrimary)
        FcText(row.unit, Modifier.width(FcSpacing.space8 * 2 + FcSpacing.space4 + FcSpacing.space1).alignByBaseline().testTag("body-row-unit-${row.metric.id}"),
            style = FcTypography.caption, color = FcColors.textSecondary)
    }
}
