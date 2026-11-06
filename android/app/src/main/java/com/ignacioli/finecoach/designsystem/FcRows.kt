package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.unit.dp
import androidx.compose.ui.draw.rotate

sealed interface FcRowMode {
    data object Informational : FcRowMode
    class Action(val onClick: () -> Unit) : FcRowMode
    class Selection(val selected: Boolean, val onClick: () -> Unit) : FcRowMode
    class Unavailable(val reason: String) : FcRowMode { init { require(reason.isNotBlank()) } }
}

private fun Modifier.rowInteraction(mode: FcRowMode): Modifier = when (mode) {
    is FcRowMode.Action -> clickable(role = Role.Button, onClick = mode.onClick)
    is FcRowMode.Selection -> semantics { selected = mode.selected }.clickable(role = Role.Checkbox, onClick = mode.onClick)
    is FcRowMode.Unavailable -> semantics { disabled() }
    FcRowMode.Informational -> this
}

@Composable
fun FcListRow(title: String, modifier: Modifier = Modifier, subtitle: String? = null,
    detail: String? = null, mode: FcRowMode = FcRowMode.Informational, leading: Painter? = null,
    reservesLeading: Boolean = false, indented: Boolean = false) {
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row).semantics(mergeDescendants = true) { }
        .rowInteraction(mode).padding(start = if (indented) FcSpacing.space4 else 0.dp,
            top = FcSpacing.space2, bottom = FcSpacing.space2),
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space3), verticalAlignment = Alignment.CenterVertically) {
        if (leading != null || reservesLeading) Box(Modifier.size(FcComponentMetrics.icon)) { leading?.let { FcSymbol(it) } }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
            Text(title, style = FcTypography.headline, color = if (mode is FcRowMode.Unavailable) FcColors.textDisabled else FcColors.textPrimary)
            subtitle?.let { Text(it, style = FcTypography.caption, color = FcColors.textSecondary) }
        }
        (if (mode is FcRowMode.Unavailable) mode.reason else detail)?.let { Text(it, style = FcTypography.caption, color = FcColors.textSecondary) }
        when (mode) {
            is FcRowMode.Action -> FcSymbol(FcGlyph.Forward)
            is FcRowMode.Selection -> FcSelectionMark(if (mode.selected) ToggleableState.On else ToggleableState.Off)
            else -> Unit
        }
    }
}

@Composable
private fun FcSelectionMark(state: ToggleableState, partial: Painter? = null) {
    Box(Modifier.size(FcComponentMetrics.badge).background(
        if (state == ToggleableState.Off) FcColors.surfaceSelected else FcColors.actionPrimary,
        androidx.compose.foundation.shape.CircleShape)
        .then(if (state == ToggleableState.Off) Modifier.border(FcComponentMetrics.stroke, FcColors.borderControl, androidx.compose.foundation.shape.CircleShape) else Modifier)
        .clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (state == ToggleableState.On) FcSymbol(FcGlyph.CheckOnFill)
        if (state == ToggleableState.Indeterminate) FcSymbol(requireNotNull(partial), tint = FcColors.actionOn)
    }
}

fun fcGroupState(children: List<Boolean>): ToggleableState = when {
    children.isEmpty() || children.none { it } -> ToggleableState.Off
    children.all { it } -> ToggleableState.On
    else -> ToggleableState.Indeterminate
}

@Composable
fun FcListGroupRow(title: String, childSelections: List<Boolean>, expanded: Boolean, onExpand: () -> Unit,
    onToggleAll: () -> Unit, collapse: Painter, minus: Painter, modifier: Modifier = Modifier, tag: String = "group") {
    val state = fcGroupState(childSelections)
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row)
        .semantics(mergeDescendants = true) {
            stateDescription = "${when (state) { ToggleableState.On -> "已全选"; ToggleableState.Off -> "未选"; else -> "部分选中" }}，${if (expanded) "已展开" else "已折叠"}"
        }, verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).heightIn(min = FcComponentMetrics.touch).testTag("$tag-expand")
            .clickable(role = Role.Button, onClick = onExpand), verticalAlignment = Alignment.CenterVertically) {
            Text(title, Modifier.weight(1f), style = FcTypography.headline, color = FcColors.textPrimary)
            FcSymbol(collapse, Modifier.rotate(if (expanded) 180f else 0f))
        }
        Box(Modifier.sizeIn(minWidth = FcComponentMetrics.touch, minHeight = FcComponentMetrics.touch)
            .testTag("$tag-toggle").semantics { contentDescription = "切换选择$title"; toggleableState = state }
            .clickable(role = Role.Checkbox, onClick = onToggleAll), contentAlignment = Alignment.Center) { FcSelectionMark(state, minus) }
    }
}

@Composable
fun FcListRowDivider(modifier: Modifier = Modifier, indented: Boolean = false) {
    Box(modifier.fillMaxWidth().padding(start = if (indented) FcSpacing.space4 else 0.dp)
        .height(FcComponentMetrics.hairline).background(FcColors.surfaceDivider))
}

@Composable
fun FcSectionLabel(title: String, modifier: Modifier = Modifier) {
    Text(title, modifier.fillMaxWidth().semantics { heading() }, style = FcTypography.sectionLabel, color = FcColors.textSecondary)
}

@Composable
fun FcGroupEntryRow(title: String, count: Int, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.touch).semantics(mergeDescendants = true) { }
        .clickable(role = Role.Button, onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        Text("$title · $count", Modifier.weight(1f), style = FcTypography.sectionLabel, color = FcColors.textSecondary)
        FcSymbol(FcGlyph.Forward)
    }
}

@Composable
fun FcLabelValueRow(label: String, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null,
    value: @Composable RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row)
        .then(if (onClick != null) Modifier.semantics(mergeDescendants = true) { }.clickable(role = Role.Button, onClick = onClick) else Modifier),
        verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.width(FcComponentMetrics.label), style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, content = value)
        if (onClick != null) FcSymbol(FcGlyph.Forward)
    }
}

@Composable
fun FcLabelValueText(label: String, value: String, modifier: Modifier = Modifier) {
    FcLabelValueRow(label, modifier.semantics(mergeDescendants = true) { }) {
        Text(value, style = FcTypography.body, color = FcColors.textPrimary)
    }
}

@Composable
fun FcPageHeader(title: String, modifier: Modifier = Modifier, subtitle: String? = null,
    onBack: (() -> Unit)? = null, tag: String = "page", trailingTitle: String? = null,
    trailingEnabled: Boolean = true, onTrailing: () -> Unit = {}) {
    Column(modifier.fillMaxWidth().padding(top = FcSpacing.space2)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            if (onBack != null) Box(Modifier.width(FcSpacing.space4).height(FcComponentMetrics.touch)) {
                Box(Modifier.requiredSize(FcComponentMetrics.touch)
                .testTag("$tag-back").semantics { contentDescription = "返回" }.clickable(role = Role.Button, onClick = onBack),
                contentAlignment = Alignment.Center) { FcSymbol(FcGlyph.PageBack) }
            }
            Column(Modifier.weight(1f)) {
                Text(title, Modifier.semantics { heading() }, style = FcTypography.titleLarge, color = FcColors.textPrimary)
                subtitle?.let { Text(it, Modifier.padding(top = FcSpacing.space2), style = FcTypography.style("callout", 400), color = FcColors.textSecondary) }
            }
            trailingTitle?.let { FcLinkButton(it, Modifier.testTag("$tag-trailing"), trailingEnabled, onTrailing) }
        }
    }
}

@Composable
fun FcHubRow(title: String, icon: Painter?, modifier: Modifier = Modifier, subtitle: String? = null,
    detail: String? = null, mode: FcRowMode = FcRowMode.Informational) {
    require(mode !is FcRowMode.Selection)
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.hub).semantics(mergeDescendants = true) { }.rowInteraction(mode),
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space4), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(FcComponentMetrics.icon)) { icon?.let { FcSymbol(it, tint = if (mode is FcRowMode.Unavailable) FcColors.textDisabled else FcColors.actionPrimary) } }
        Column(Modifier.weight(1f)) {
            Text(title, style = FcTypography.headline, color = if (mode is FcRowMode.Unavailable) FcColors.textDisabled else FcColors.textPrimary)
            subtitle?.let { Text(it, style = FcTypography.caption, color = FcColors.textSecondary) }
        }
        (if (mode is FcRowMode.Unavailable) mode.reason else detail)?.let { Text(it, style = FcTypography.caption, color = FcColors.textSecondary) }
        if (mode is FcRowMode.Action) FcSymbol(FcGlyph.Forward)
    }
}

@Composable
fun FcActionRow(title: String, modifier: Modifier = Modifier, subtitle: String? = null, detail: String? = null,
    destructive: Boolean = false, enabled: Boolean = true, trash: Painter? = null, onClick: () -> Unit) {
    val color = if (!enabled) FcColors.textDisabled else if (destructive) FcColors.statusDestructive else FcColors.textPrimary
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row).semantics(mergeDescendants = true) { }
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
        .padding(vertical = if (subtitle != null) FcSpacing.space3 else FcSpacing.space2),
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space3), verticalAlignment = Alignment.CenterVertically) {
        if (destructive && trash != null) FcSymbol(trash, tint = color)
        Column(Modifier.weight(1f)) {
            Text(title, style = if (subtitle == null) FcTypography.body else FcTypography.headline, color = color)
            subtitle?.let { Text(it, style = FcTypography.caption, color = FcColors.textSecondary) }
        }
        detail?.let { Text(it, style = FcTypography.caption, color = FcColors.textSecondary) }
        if (!destructive) FcSymbol(FcGlyph.Forward, tint = if (enabled) FcColors.textSecondary else FcColors.textDisabled)
    }
}

@Composable
fun FcUndoRow(description: String, modifier: Modifier = Modifier, tag: String = "undo", onUndo: () -> Unit) {
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row).semantics(mergeDescendants = true) {
        customActions = listOf(CustomAccessibilityAction("撤销") { onUndo(); true })
    }, verticalAlignment = Alignment.CenterVertically) {
        Text(description, Modifier.weight(1f), style = FcTypography.body, color = FcColors.textSecondary)
        FcLinkButton("撤销", Modifier.testTag("$tag-action"), onClick = onUndo)
    }
}
