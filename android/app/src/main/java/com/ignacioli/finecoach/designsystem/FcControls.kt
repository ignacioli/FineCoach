package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

// Geometry in components.md §4 / README §6/§8, expressed using generated tokens.
// These are aliases for existing component dimensions, not independent token values.
object FcComponentMetrics {
    val addExerciseSheetHeight = FcSpacing.space8 * 17 // 544, S1-D63; capped by the available height.
    val illustration = FcSpacing.space8 * 6 + FcSpacing.space4 + FcSpacing.space3 // 220, README §9
    val calendarIllustration = FcSpacing.space8 * 5 // 160, §4.9
    val touch = FcSpacing.space8 + FcSpacing.space3 // 44
    val row = FcSpacing.space8 + FcSpacing.space4 + FcSpacing.space1 // 52
    val field = FcSpacing.space8 + FcSpacing.space4 // 48
    val hub = FcSpacing.space8 * 2 // 64
    val label = FcSpacing.space8 * 3 // 96
    val icon = FcSpacing.space6 // 24
    val badge = FcSpacing.space4 + FcSpacing.space3 / 2 // 22
    val hairline = FcSpacing.space1 / 4 // 1
    val stroke = FcSpacing.space3 / 8 // 1.5
    val dialogWidth = FcSpacing.space8 * 9 + FcSpacing.space3 // 300
}

private fun Modifier.touch() = sizeIn(minWidth = FcComponentMetrics.touch, minHeight = FcComponentMetrics.touch)

@Composable
fun FcButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, labelModifier: Modifier = Modifier, onClick: () -> Unit) =
    FcButtonContent(title, modifier, enabled, false, labelModifier, onClick)

@Composable
fun FcSecondaryButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) =
    FcButtonContent(title, modifier, enabled, true, Modifier, onClick)

@Composable
private fun FcButtonContent(title: String, modifier: Modifier, enabled: Boolean, secondary: Boolean, labelModifier: Modifier, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val foreground = if (!enabled) FcColors.textSecondary else if (secondary) FcColors.actionPrimary else FcColors.actionOn
    val background = when {
        secondary -> FcColors.surfacePage
        !enabled -> FcColors.surfaceDivider
        pressed -> FcColors.actionPressed
        else -> FcColors.actionPrimary
    }
    val shape = RoundedCornerShape(FcShapes.md)
    Box(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row).clip(shape)
        .background(background).then(if (secondary) Modifier.border(BorderStroke(FcComponentMetrics.stroke, foreground), shape) else Modifier)
        .clickable(enabled = enabled, role = Role.Button, interactionSource = interaction, indication = null, onClick = onClick)
        .padding(horizontal = FcSpacing.space4, vertical = FcSpacing.space2), contentAlignment = Alignment.Center) {
        FcText(title, labelModifier, style = FcTypography.headline, color = foreground, textAlign = TextAlign.Center)
    }
}

@Composable
fun FcLinkButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true,
    contentAlignment: Alignment = Alignment.Center, compactLayout: Boolean = false, onClick: () -> Unit) {
    Box(modifier.then(if (compactLayout) Modifier else Modifier.touch()).clickable(enabled = enabled, role = Role.Button, onClick = onClick), contentAlignment = contentAlignment) {
        FcText(title, style = FcTypography.style("callout", 600), color = if (enabled) FcColors.actionPrimary else FcColors.textSecondary)
    }
}

enum class FcGlyph(val glyph: String) { PageBack("‹"), Back("‹"), Forward("›"), Check("✓"), CheckOnFill("✓") }

@Composable
fun FcSymbol(kind: FcGlyph, modifier: Modifier = Modifier, tint: Color? = null, visualTag: String? = null) {
    val style = when (kind) {
        FcGlyph.PageBack -> FcTypography.title.copy(fontWeight = FcTypography.body.fontWeight)
        FcGlyph.Back, FcGlyph.Forward -> FcTypography.exerciseTitle.copy(fontWeight = FcTypography.body.fontWeight)
        FcGlyph.Check -> FcTypography.style("callout", 600)
        FcGlyph.CheckOnFill -> FcTypography.sectionLabel
    }
    // A merge boundary keeps decorative text out of ancestors while preserving layout observation.
    val observation = (if (visualTag == null) modifier else modifier.testTag(visualTag))
        .semantics(mergeDescendants = true) { hideFromAccessibility() }
    FcText(kind.glyph, observation, style = style,
        color = tint ?: when (kind) {
            FcGlyph.Check -> FcColors.actionPrimary
            FcGlyph.CheckOnFill -> FcColors.actionOn
            else -> FcColors.textSecondary
        })
}

enum class FcAssetSymbol { Minus, Plus, Collapse }

@Composable
fun FcSymbol(kind: FcAssetSymbol, painter: Painter, modifier: Modifier = Modifier) {
    FcSymbol(painter, modifier.size(if (kind == FcAssetSymbol.Collapse) FcSpacing.space4 - FcComponentMetrics.hairline else FcShapes.xl),
        tint = if (kind == FcAssetSymbol.Collapse) FcColors.actionPrimary else FcColors.textPrimary)
}

@Composable
fun FcSymbol(painter: Painter, modifier: Modifier = Modifier, tint: Color = FcColors.textPrimary) {
    Icon(painter, contentDescription = null, modifier = modifier.size(FcComponentMetrics.icon), tint = tint)
}

@Composable
fun FcTitleIconButton(label: String, painter: Painter, modifier: Modifier = Modifier, onClick: () -> Unit) =
    FcTitleIconButton(label, painter, modifier, Modifier, onClick)

@Composable
fun FcTitleIconButton(label: String, painter: Painter, modifier: Modifier = Modifier, visualModifier: Modifier, onClick: () -> Unit) {
    require(label.isNotBlank())
    Box(modifier.touch().semantics { contentDescription = label }
        .clickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(painter, null, visualModifier.size(FcComponentMetrics.badge, FcShapes.xl), tint = FcColors.textSecondary)
    }
}

@Composable
fun FcTitleAddButton(label: String, painter: Painter, modifier: Modifier = Modifier, onClick: () -> Unit) {
    require(label.isNotBlank())
    Box(modifier.touch().semantics { contentDescription = label }
        .clickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(painter, null, Modifier.size(FcComponentMetrics.badge), tint = FcColors.actionPrimary)
    }
}

@Composable
fun FcSegmentedSwitch(options: List<String>, selection: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, tag: String = "segmented") {
    require(options.size in 2..4 && selection in options.indices)
    Row(modifier.selectableGroup(), horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
        options.forEachIndexed { index, title ->
            val selected = index == selection
            // DS-SEGMENTED: the option owns its visual size; Compose expands the touch target outward.
            Box(Modifier.widthIn(min = FcSpacing.space8 + FcSpacing.space4 + FcSpacing.space1 / 2)
                .heightIn(min = FcSpacing.space8).testTag("$tag-$index")
                .selectable(selected = selected, role = Role.Tab, onClick = { onSelect(index) }), contentAlignment = Alignment.Center) {
                Box(Modifier.clip(FcShapes.capsule)
                    .then(if (selected) Modifier.background(FcColors.actionPrimary) else Modifier)
                    .testTag(if (selected) "conformance:DS-SEGMENTED · selected" else "$tag-unselected-$index")
                    .padding(horizontal = FcSpacing.space2, vertical = FcSpacing.space1)) {
                FcText(title,
                    style = if (selected) FcTypography.headline else FcTypography.body,
                    color = if (selected) FcColors.actionOn else FcColors.textSecondary)
                }
            }
        }
    }
}

@Composable
fun FcFilterChip(title: String, selected: Boolean, modifier: Modifier = Modifier, visualModifier: Modifier = Modifier, onClick: () -> Unit) =
    FcChip(title, selected, false, modifier, onClick, visualModifier)

@Composable
fun FcBodyPartChip(title: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) =
    FcChip(title, selected, true, modifier, onClick)

@Composable
private fun FcChip(title: String, selected: Boolean, body: Boolean, modifier: Modifier, onClick: () -> Unit, visualModifier: Modifier = Modifier) {
    Box(modifier.then(if (body) Modifier.touch() else Modifier).semantics { this.selected = selected }.clickable(role = Role.Checkbox, onClick = onClick), contentAlignment = Alignment.Center) {
        Box(visualModifier.heightIn(min = if (body) FcSpacing.space6 + FcSpacing.space1 else FcSpacing.space8 - FcSpacing.space1 / 2)
            .widthIn(min = if (body) FcComponentMetrics.field else 0.dp).clip(FcShapes.capsule)
            .background(if (selected) FcColors.actionPrimary else FcColors.surfaceSelected)
            .padding(horizontal = if (body) FcSpacing.space4 else FcSpacing.space3), contentAlignment = Alignment.Center) {
            FcText(title, style = FcTypography.chipLabel, color = if (selected) FcColors.actionOn else FcColors.textPrimary)
        }
    }
}

// Matches BodyPart.allCases; labels come from the iOS Localizable catalog.
val FcBodyParts = listOf("胸", "肩", "背", "大腿", "小腿", "臂", "臀", "核心")

@Composable
fun FcBodyPartPicker(selected: Set<Int>, onToggle: (Int) -> Unit, modifier: Modifier = Modifier, tag: String = "body") {
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2),
        verticalArrangement = Arrangement.spacedBy(-FcSpacing.space2)) {
        FcBodyParts.forEachIndexed { index, title ->
            FcBodyPartChip(title, index in selected, Modifier.testTag("$tag-$index")) { onToggle(index) }
        }
    }
}

@Composable
fun FcToggle(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    require(label.isNotBlank())
    Box(modifier.touch().semantics { contentDescription = label }
        .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange), contentAlignment = Alignment.Center) {
        Box(Modifier.size(FcComponentMetrics.touch, FcSpacing.space6 + FcSpacing.space1 / 2)
            .clip(FcShapes.capsule).background(if (checked) FcColors.actionPrimary else FcColors.surfaceDivider)
            .then(if (!checked) Modifier.border(FcComponentMetrics.stroke, FcColors.borderControl, FcShapes.capsule) else Modifier)
            .padding(FcSpacing.space1), contentAlignment = if (checked) Alignment.CenterEnd else Alignment.CenterStart) {
            Box(Modifier.size(FcSpacing.space4 + FcSpacing.space1 / 2).background(FcColors.actionOn, CircleShape))
        }
    }
}

@Composable
fun FcTextField(title: String, value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
    secure: Boolean = false, enabled: Boolean = true, search: Boolean = false,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default, visualModifier: Modifier = Modifier,
    singleLine: Boolean = true, placeholder: String = title) {
    BasicTextField(value, onValueChange, modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.touch)
        .semantics { contentDescription = title }, enabled = enabled, singleLine = singleLine, keyboardOptions = keyboardOptions, keyboardActions = keyboardActions,
        textStyle = (if (search) FcTypography.style("callout", 400) else FcTypography.body).copy(color = FcColors.textPrimary),
        visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
        cursorBrush = SolidColor(FcColors.actionPrimary), decorationBox = { field ->
            Box(Modifier.fillMaxWidth().wrapContentHeight(unbounded = true).then(visualModifier).then(if (search) Modifier.height(FcSpacing.space8 + FcSpacing.space2) else Modifier.heightIn(min = FcComponentMetrics.field))
                .background(FcColors.surfaceCanvas, RoundedCornerShape(FcShapes.sm)).padding(horizontal = FcSpacing.space4, vertical = FcSpacing.space2),
                contentAlignment = if (singleLine) Alignment.CenterStart else Alignment.TopStart) {
                if (value.isEmpty() && placeholder.isNotEmpty()) FcText(placeholder, style = FcTypography.style("callout", 400), color = FcColors.textSecondary)
                field()
            }
        })
}

@Composable
fun FcSearchField(title: String, value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, visualModifier: Modifier = Modifier) =
    FcTextField(title, value, onValueChange, modifier, search = true, visualModifier = visualModifier)

fun fcStepped(value: Int, delta: Int, range: IntRange): Int {
    require(!range.isEmpty() && delta in listOf(-1, 1))
    return (value.toLong() + delta).coerceIn(range.first.toLong(), range.last.toLong()).toInt()
}

@Composable
fun FcStepper(label: String, value: Int, range: IntRange, onValueChange: (Int) -> Unit,
    minus: Painter, plus: Painter, modifier: Modifier = Modifier, tag: String = "stepper") {
    require(value in range)
    Row(modifier.heightIn(min = FcComponentMetrics.touch).drawBehind {
        val height = (FcSpacing.space8 + FcSpacing.space1).toPx()
        drawRoundRect(FcColors.surfaceCanvas, topLeft = Offset(0f, (size.height - height) / 2),
            size = Size(size.width, height), cornerRadius = CornerRadius(height / 2))
    }
        .semantics(mergeDescendants = true) {
            contentDescription = label; stateDescription = value.toString()
            progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), range.first.toFloat()..range.last.toFloat())
            setProgress { target ->
                val delta = target.compareTo(value.toFloat())
                if (delta == 0) false else {
                    val next = fcStepped(value, delta, range)
                    if (next == value) false else { onValueChange(next); true }
                }
            }
            customActions = listOf(
                CustomAccessibilityAction("减少$label") { if (value > range.first) { onValueChange(fcStepped(value, -1, range)); true } else false },
                CustomAccessibilityAction("增加$label") { if (value < range.last) { onValueChange(fcStepped(value, 1, range)); true } else false })
        }, verticalAlignment = Alignment.CenterVertically) {
        FcStepButton("减少$label", minus, value > range.first, Modifier.testTag("$tag-minus").semantics { hideFromAccessibility() }) { onValueChange(fcStepped(value, -1, range)) }
        FcText(value.toString(), Modifier.widthIn(min = FcSpacing.space8 + FcSpacing.space2), style = FcTypography.numeralLarge,
            color = FcColors.textPrimary, textAlign = TextAlign.Center)
        FcStepButton("增加$label", plus, value < range.last, Modifier.testTag("$tag-plus").semantics { hideFromAccessibility() }) { onValueChange(fcStepped(value, 1, range)) }
    }
}

@Composable
internal fun FcStepButton(label: String, painter: Painter, enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier.touch().semantics { contentDescription = label }.clickable(enabled = enabled, role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        FcSymbol(painter, Modifier.size(FcShapes.xl), tint = if (enabled) FcColors.textPrimary else FcColors.textDisabled)
    }
}

@Composable
fun FcStepperField(label: String, value: String, onValueChange: (String) -> Unit, canDecrement: Boolean,
    minus: Painter, plus: Painter, onDecrement: () -> Unit, onIncrement: () -> Unit,
    modifier: Modifier = Modifier, tag: String = "stepper-field", keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default) {
    var focused by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    @Composable fun step(increment: Boolean, inset: Modifier) {
        val suffix = if (increment) "plus" else "minus"
        val enabled = increment || canDecrement
        Box(inset.size(FcComponentMetrics.touch).testTag("$tag-$suffix")
            .semantics { contentDescription = (if (increment) "增加" else "减少") + label }
            .clickable(enabled = enabled, role = Role.Button, onClick = if (increment) onIncrement else onDecrement), contentAlignment = Alignment.Center) {
            val painter = if (increment) plus else minus
            val tint = if (enabled) FcColors.textPrimary else FcColors.textDisabled
            // S1-D40 R4: the AD-01 Material symbol at its natural 20dp bounds, centered in the touch box.
            FcSymbol(painter, Modifier.size(FcShapes.xl).testTag("$tag-$suffix-glyph").semantics {
                text = AnnotatedString(if (increment) "+" else "−"); hideFromAccessibility()
            }, tint = tint)
        }
    }
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.field).background(FcColors.surfaceCanvas, FcShapes.capsule)
        .then(if (focused) Modifier.border(FcComponentMetrics.stroke, FcColors.actionPrimary, FcShapes.capsule) else Modifier),
        verticalAlignment = Alignment.CenterVertically) {
        step(false, Modifier.padding(start = FcSpacing.space1)) // S1-D42: symbols sit space.1 inside the capsule (P0-a2)
        Box(Modifier.weight(1f).heightIn(min = FcComponentMetrics.touch).testTag("$tag-input-touch")
            .clickable { focus.requestFocus(); keyboard?.show() }, contentAlignment = Alignment.Center) {
        BasicTextField(value, onValueChange, Modifier.widthIn(min = FcSpacing.space4).width(IntrinsicSize.Min).focusRequester(focus)
            .testTag("$tag-input").onFocusChanged { focused = it.isFocused }.semantics { contentDescription = label },
            // S1-D42: the platform text field keeps its natural single-line minimum height outside the caller's
            // modifiers, so the editor is centered on the token line box and compared by center (EDITABLE_TEXT_FIELD).
            // The outer value slot centers the intrinsic-width editor. CoreTextField's
            // horizontally scrolling paragraph can be wider than that editor: center
            // alignment inside that paragraph moves glyphs outside the visible field.
            textStyle = FcTypography.numeralLarge.copy(color = FcColors.textPrimary, textAlign = TextAlign.Start),
            singleLine = true, keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, cursorBrush = SolidColor(FcColors.actionPrimary))
        }
        step(true, Modifier.padding(end = FcSpacing.space1))
    }
}
