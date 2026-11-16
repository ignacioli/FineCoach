package com.ignacioli.finecoach.designsystem

import android.view.Window
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

// Debug's T009 registry is injected at the shell, including independent windows.
class FcWindowRegistry(val register: (Window) -> Unit, val unregister: (Window) -> Unit)
val LocalFcWindowRegistry = staticCompositionLocalOf<FcWindowRegistry?> { null }

@Composable
private fun RegisterOverlayWindow(clearDim: Boolean = false) {
    val view = LocalView.current
    val registry = LocalFcWindowRegistry.current
    val window = (view.parent as? DialogWindowProvider)?.window
    DisposableEffect(window, registry) {
        if (window != null) {
            if (clearDim) window.setDimAmount(0f)
            registry?.register?.invoke(window)
        }
        onDispose { if (window != null) registry?.unregister?.invoke(window) }
    }
}

enum class FcStatus(val text: String, val glyph: String, val warning: Boolean) {
    Overdue("逾期", "!", true), Conflict("冲突", "!", true), CoursePackageInvalid("课包异常", "!", true),
    NotComparable("不可比较", "i", false), PermissionDenied("权限拒绝", "i", false)
}

@Composable
fun FcStatusBadge(glyph: String, color: Color, modifier: Modifier = Modifier, icon: Painter? = null) {
    require(glyph.isNotBlank() && (glyph == "✓" || icon != null))
    Box(modifier.size(FcComponentMetrics.badge).background(color, CircleShape).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (glyph == "✓") FcSymbol(FcGlyph.CheckOnFill)
        else Icon(requireNotNull(icon), null, Modifier.size(FcSpacing.space3), tint = FcColors.actionOn)
    }
}

@Composable
fun FcStatusLabel(status: FcStatus, icon: Painter, modifier: Modifier = Modifier) = FcStatusLabel(status.text, status.glyph,
    if (status.warning) FcColors.statusWarning else FcColors.actionPrimary, icon, modifier)

@Composable
fun FcStatusLabel(text: String, glyph: String, color: Color, icon: Painter, modifier: Modifier = Modifier) {
    require(text.isNotBlank() && glyph.isNotBlank())
    Row(modifier.clearAndSetSemantics { contentDescription = text }, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcStatusBadge(glyph, color, icon = icon)
        FcText(text, style = FcTypography.caption, color = FcColors.textSecondary)
    }
}

enum class FcSaveState(val text: String) { Saving("保存中"), Saved("已保存"), Failed("保存失败") }

@Composable
fun FcSaveStatusView(state: FcSaveState, icon: Painter, modifier: Modifier = Modifier) {
    val color = if (state == FcSaveState.Failed) FcColors.statusDestructive else FcColors.textSecondary
    Row(modifier.heightIn(min = FcComponentMetrics.touch).clearAndSetSemantics { contentDescription = state.text },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        FcSymbol(icon, tint = color)
        FcText(state.text, style = FcTypography.body, color = color)
    }
}

enum class FcResultVariant(val glyph: String) { Failure("!"), Success("✓"), Info("i") }

@Composable
fun FcInlineResult(variant: FcResultVariant, title: String, description: String, icon: Painter, modifier: Modifier = Modifier,
    retryTitle: String = "重试", onRetry: (() -> Unit)? = null, tag: String = "result") {
    require(title.isNotBlank())
    val failure = variant == FcResultVariant.Failure
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                FcStatusBadge(variant.glyph, if (failure) FcColors.statusDestructive else FcColors.actionPrimary, icon = icon)
                FcText(title, style = FcTypography.style("callout", 600), color = if (failure) FcColors.statusDestructive else FcColors.textPrimary)
            }
            FcText(description, style = FcTypography.caption, color = FcColors.textSecondary)
        }
        onRetry?.let { FcLinkButton(retryTitle, Modifier.align(Alignment.CenterHorizontally).testTag("$tag-retry"), onClick = it) }
    }
}

@Composable
fun FcAvatar(name: String, modifier: Modifier = Modifier) {
    Box(modifier.size(FcComponentMetrics.touch).background(FcColors.surfaceSelected, CircleShape).semantics(mergeDescendants = true) { hideFromAccessibility() },
        contentAlignment = Alignment.Center) {
        FcText(name.take(1), style = FcTypography.headline, color = FcColors.actionPrimary)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FcBottomSheet(title: String, onDismiss: () -> Unit, modifier: Modifier = Modifier, subtitle: String? = null,
    skipPartiallyExpanded: Boolean = false, panelFlow: Boolean = false,
    content: @Composable ColumnScope.() -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartiallyExpanded)
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = FcColors.surfacePage,
        sheetState = sheetState,
        tonalElevation = 0.dp, contentColor = FcColors.textPrimary, scrimColor = FcColors.overlayScrim,
        shape = RoundedCornerShape(topStart = FcShapes.lg, topEnd = FcShapes.lg),
        dragHandle = null) {
        RegisterOverlayWindow()
        // Apply caller semantics inside the anchored M3 surface, after placement.
        Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.padding(top = FcSpacing.space2)) { Box(Modifier.size(FcSpacing.space8 + FcSpacing.space1,
                FcSpacing.space1 + FcComponentMetrics.hairline).background(FcColors.surfaceDivider, FcShapes.capsule).clearAndSetSemantics { if (panelFlow) testTag = "conformance:Grabber" }) }
            // Constrain content, not ModalBottomSheet's draggable viewport/anchor calculation.
            // The custom drag handle above contributes space.2 + space.1 + hairline.
            Column(Modifier.fillMaxWidth().then(if (panelFlow) Modifier.heightIn(max = FcComponentMetrics.addExerciseSheetHeight -
                FcSpacing.space2 - FcSpacing.space1 - FcComponentMetrics.hairline) else Modifier)
                .then(if (panelFlow) Modifier.padding(top = FcSpacing.space4) else Modifier.padding(horizontal = FcSpacing.space4)).padding(bottom = FcSpacing.space6)
                .testTag("sheet-content"), verticalArrangement = Arrangement.spacedBy(if (panelFlow) FcSpacing.space4 else FcSpacing.space2)) {
                Box(Modifier.then(if (panelFlow) Modifier.padding(horizontal = FcSpacing.space4) else Modifier)) {
                    FcText(title, Modifier.semantics { heading() }, style = FcTypography.headline, color = FcColors.textPrimary)
                }
                subtitle?.let { FcText(it, style = FcTypography.style("callout", 400), color = FcColors.textSecondary) }
                content()
            }
        }
    }
}

@Composable
fun FcConfirmationDialog(title: String, message: String, confirmTitle: String, onConfirm: () -> Unit,
    onDismiss: () -> Unit, cancelTitle: String = "取消", tag: String = "confirm") {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        RegisterOverlayWindow(clearDim = true)
        BoxWithConstraints(Modifier.fillMaxSize().background(FcColors.overlayScrim)
            .clickable(onClick = onDismiss).safeDrawingPadding().padding(FcSpacing.space4), contentAlignment = Alignment.Center) {
            val availableHeight = maxHeight
            Column(Modifier.widthIn(max = FcComponentMetrics.dialogWidth).fillMaxWidth().heightIn(max = availableHeight * 0.8f)
                .background(FcColors.surfaceElevated, RoundedCornerShape(FcShapes.lg))
                .clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { }
                .testTag("$tag-card").padding(FcSpacing.space4), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                FcText(title, Modifier.semantics { heading() }, style = FcTypography.headline, color = FcColors.textPrimary, textAlign = TextAlign.Center)
                FcText(message, Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()),
                    style = FcTypography.caption, color = FcColors.textSecondary, textAlign = TextAlign.Center)
                BoxWithConstraints(Modifier.fillMaxWidth()) {
                    val measurer = rememberTextMeasurer()
                    val density = LocalDensity.current
                    val width = with(density) { ((maxWidth - FcSpacing.space2) / 2).toPx() }
                    val longest = maxOf(measurer.measure(confirmTitle, FcTypography.style("callout", 600)).size.width,
                        measurer.measure(cancelTitle, FcTypography.style("callout", 600)).size.width)
                    if (longest + with(density) { FcSpacing.space4.toPx() } <= width) {
                        Row(horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                            DialogAction(cancelTitle, false, Modifier.weight(1f).testTag("$tag-cancel"), onDismiss)
                            DialogAction(confirmTitle, true, Modifier.weight(1f).testTag("$tag-accept"), onConfirm)
                        }
                    } else Column(verticalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                        DialogAction(confirmTitle, true, Modifier.fillMaxWidth().testTag("$tag-accept"), onConfirm)
                        DialogAction(cancelTitle, false, Modifier.fillMaxWidth().testTag("$tag-cancel"), onDismiss)
                    }
                }
            }
        }
    }
}

@Composable
private fun DialogAction(title: String, primary: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier.heightIn(min = FcComponentMetrics.touch).clickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxWidth().heightIn(min = FcSpacing.space8 + FcSpacing.space1)
            .background(if (primary) FcColors.actionPrimary else FcColors.surfaceSelected, RoundedCornerShape(FcShapes.dialogAction))
            .padding(horizontal = FcSpacing.space2, vertical = FcSpacing.space1), contentAlignment = Alignment.Center) {
            FcText(title, style = FcTypography.style("callout", 600), color = if (primary) FcColors.actionOn else FcColors.actionPrimary, textAlign = TextAlign.Center)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FcDatePickerDialog(initialMillis: Long?, onSelect: (Long?) -> Unit, onDismiss: () -> Unit) {
    val state = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
    DatePickerDialog(onDismissRequest = onDismiss, tonalElevation = 0.dp, colors = DatePickerDefaults.colors(containerColor = FcColors.surfaceElevated),
        confirmButton = { FcLinkButton("确定", Modifier.testTag("date-accept")) { onSelect(state.selectedDateMillis) } },
        dismissButton = { FcLinkButton("取消", Modifier.testTag("date-cancel"), onClick = onDismiss) }) {
        RegisterOverlayWindow()
        DatePicker(state = state, modifier = Modifier.testTag("date-picker"), colors = DatePickerDefaults.colors(containerColor = FcColors.surfaceElevated,
            titleContentColor = FcColors.textSecondary, headlineContentColor = FcColors.textPrimary,
            weekdayContentColor = FcColors.textSecondary, subheadContentColor = FcColors.textPrimary,
            yearContentColor = FcColors.textPrimary, currentYearContentColor = FcColors.actionPrimary,
            selectedYearContentColor = FcColors.actionOn, selectedYearContainerColor = FcColors.actionPrimary,
            disabledYearContentColor = FcColors.textDisabled, dayContentColor = FcColors.textPrimary,
            disabledDayContentColor = FcColors.textDisabled, disabledSelectedDayContentColor = FcColors.textSecondary,
            disabledSelectedDayContainerColor = FcColors.surfaceDivider,
            selectedDayContainerColor = FcColors.actionPrimary, selectedDayContentColor = FcColors.actionOn,
            todayContentColor = FcColors.actionPrimary, todayDateBorderColor = FcColors.actionPrimary))
    }
}
