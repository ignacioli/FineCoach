package com.ignacioli.finecoach.features.trends

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.designsystem.*

@Composable
fun TrendsScreen(state: TrendsState, onBack: () -> Unit) {
    val content = state.content
    FcPlatformShell(onBack) {
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("trends-root"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            FcPageHeader("训练趋势", Modifier.padding(bottom = FcSpacing.space2), onBack = onBack, tag = "trends")
            if (state.error) FcText("加载失败，请返回重试", Modifier.testTag("trends-error"), style = FcTypography.caption, color = FcColors.statusDestructive)
            if (content == null && state.busy) FcText("正在加载", Modifier.testTag("trends-loading"), style = FcTypography.caption, color = FcColors.textSecondary)
            content?.let { page ->
                var inspecting by remember(page) { mutableStateOf(false) }
                val dateDrop = FcSpacing.space1 / 2
                Column(Modifier.fillMaxWidth()) {
                    FcListRowDivider(Modifier.testTag("conformance:Divider"))
                    FcLabelValueRow("动作", Modifier.testTag("trends-exercise"), onClick = { state.pickerOpen = true }) {
                        FcText(page.exerciseName, Modifier.testTag("trends-exercise-name"), style = FcTypography.body, color = FcColors.textPrimary)
                    }
                    FcListRowDivider(Modifier.testTag("conformance:Divider"))
                }
                if (page.metrics.size >= 2) FcSegmentedSwitch(page.metrics.map { it.label }, page.metrics.indexOf(page.metric),
                    state::selectMetric, Modifier.testTag("trends-metric"), tag = "trends-metric")
                if (page.assisted) FcText("辅助器械 · 配重下降 = 进步", Modifier.testTag("trends-assisted"),
                    style = FcTypography.sectionLabel, color = FcColors.statusWarning)
                when {
                    page.emptyText != null -> FcText(page.emptyText, Modifier.testTag("trends-empty"), style = FcTypography.body, color = FcColors.textSecondary)
                    page.density == com.ignacioli.finecoach.core.domain.progress.Comparison.TrendSampleDensity.single -> Column(Modifier.fillMaxWidth().testTag("trends-single"),
                        verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
                        FcText(page.singleValue.orEmpty(), style = FcTypography.numeralLarge, color = FcColors.textPrimary)
                        page.singleDate?.let { FcText(it, style = FcTypography.caption, color = FcColors.textSecondary) }
                        FcText(TrendsPresentation.SINGLE, style = FcTypography.caption, color = FcColors.textSecondary)
                    }
                    page.rows.isNotEmpty() -> Column(Modifier.fillMaxWidth().testTag("trends-rows"), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                        page.rows.forEach { (day, value) ->
                            Row(Modifier.fillMaxWidth()) {
                                FcText(day, Modifier.weight(1f), style = FcTypography.body, color = FcColors.textPrimary)
                                FcText(value, style = FcTypography.body, color = FcColors.textPrimary)
                            }
                        }
                    }
                    else -> Column(verticalArrangement = Arrangement.spacedBy(FcSpacing.space2 + FcSpacing.space1 + dateDrop)) {
                        Box(Modifier.fillMaxWidth().height(FcSpacing.space8 * 4 + FcSpacing.space3 + dateDrop).testTag("trends-chart-block")) {
                            Box(Modifier.fillMaxSize().padding(top = FcSpacing.space4, bottom = FcSpacing.space4 + FcSpacing.space1 + dateDrop)) {
                                FcTrendChart(page.values, page.dashed, Modifier.fillMaxSize(), page.chartX, page.chartSamples) { inspecting = it }
                            }
                            page.maxLabel?.takeUnless { inspecting }?.let { FcText(it, Modifier.align(Alignment.TopStart).testTag("trends-max"), style = FcTypography.caption, color = FcColors.textSecondary) }
                            Row(Modifier.fillMaxWidth().align(Alignment.BottomCenter)) {
                                page.firstDate?.let { FcText(it, style = FcTypography.caption, color = FcColors.textSecondary) }
                                Spacer(Modifier.weight(1f))
                                page.lastDate?.let { FcText(it, Modifier.testTag("trends-last-date"), style = FcTypography.caption, color = FcColors.textSecondary) }
                            }
                        }
                        page.caption?.let { FcText(it, Modifier.fillMaxWidth().testTag("trends-caption"), style = FcTypography.caption, color = FcColors.textSecondary) }
                    }
                }
                if (page.bests.isNotEmpty()) Column(Modifier.fillMaxWidth().padding(top = if (page.caption == null) FcSpacing.space4 + dateDrop else FcSpacing.space4 + FcSpacing.space1).testTag("trends-bests")) {
                    FcSectionLabel("个人最佳", Modifier.padding(bottom = FcSpacing.space2))
                    FcListRowDivider(Modifier.testTag("conformance:Divider"))
                    page.bests.forEachIndexed { index, row ->
                        PersonalBestRow(row, Modifier.testTag("trends-best-$index"))
                        FcListRowDivider(Modifier.testTag("conformance:Divider"))
                    }
                }
            }
        }
    }
    if (state.pickerOpen) FcBottomSheet("动作", { state.pickerOpen = false }, skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().heightIn(max = FcComponentMetrics.row * 6).verticalScroll(rememberScrollState()).testTag("trends-picker")) {
            content?.options?.forEach { option ->
                FcActionRow(option.name, Modifier.testTag("trends-pick-${option.id.value}"),
                    detail = if (option.id == content.selected?.id) "已选" else null) { state.selectExercise(option.id) }
                FcListRowDivider()
            }
        }
    }
}

@Composable
private fun PersonalBestRow(row: TrendBestRow, modifier: Modifier = Modifier) {
    // Divider-to-text is space.2 + half of space.1. The two line boxes meet, so there is no extra space.1.
    val inset = FcSpacing.space2 + FcSpacing.space1 / 2
    val detailGap = FcSpacing.space1 / 2
    val valueStart = FcSpacing.space8 * 4 + FcSpacing.space1 + detailGap
    Row(modifier.fillMaxWidth().padding(vertical = inset), verticalAlignment = Alignment.Top) {
        Column(Modifier.width(valueStart)) {
            FcText(row.name, style = FcTypography.headline, color = FcColors.textPrimary)
            FcText(row.kind, style = FcTypography.caption, color = FcColors.textSecondary)
        }
        FcText(row.value, Modifier.align(Alignment.CenterVertically), style = FcTypography.titleEmphasis, color = FcColors.textPrimary)
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(detailGap)) {
            row.day?.let { FcText(it, style = FcTypography.caption, color = FcColors.textSecondary) }
            row.detail?.let { FcText(it, style = FcTypography.caption, color = FcColors.textSecondary) }
        }
    }
}
