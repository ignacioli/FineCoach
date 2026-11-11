package com.ignacioli.finecoach.designsystem

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.isSpecified
import kotlin.math.roundToInt

/**
 * S1-D40 R1 text line box. On this stack a single-line Text always measures at the bundled
 * font's natural extent (~1.45em for Noto Sans SC); `lineHeight` cannot shrink it. Designs use
 * the CSS model: box = fontSize × line-height token, glyphs centered. This modifier lays out a
 * single line at exactly the style's token line height and centers the natural box inside it;
 * the natural box overflows equally above and below and is not clipped. As in CSS, ink can extend
 * beyond the token box (especially descenders and large numerals), but stays within the natural box.
 * Clipping containers must leave room outside the token line box for this ink (S1-D42).
 * Multi-line text keeps its natural layout. Constraints from outer modifiers still apply.
 * The empty semantics in front of the line box makes the node report the line box as its bounds
 * (a SemanticsNode takes the bounds of its outermost semantics modifier).
 */
internal class FcLineCount { var lines = 1 }

internal fun Modifier.fcLineBox(style: TextStyle, lineCount: FcLineCount): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minHeight = 0))
    fun baselines(y: Int) = buildMap<AlignmentLine, Int> {
        for (line in listOf(FirstBaseline, LastBaseline)) {
            val value = placeable[line]
            if (value != AlignmentLine.Unspecified) put(line, value + y)
        }
    }
    if (!style.lineHeight.isSpecified || lineCount.lines != 1) {
        val height = placeable.height.coerceIn(constraints.minHeight, constraints.maxHeight)
        return@layout layout(placeable.width, height, alignmentLines = baselines(0)) { placeable.place(0, 0) }
    }
    val box = style.lineHeight.toPx().roundToInt()
    val height = box.coerceIn(constraints.minHeight, constraints.maxHeight)
    // A taller outer minimum keeps the line box at the top, like a plain Text would.
    val y = ((box - placeable.height) / 2f).roundToInt()
    layout(placeable.width, height, alignmentLines = baselines(y)) { placeable.place(0, y) }
}

/** The only text primitive for design-system and feature code (S1-D40, enforced by G3 `rawText`). */
@Composable
fun FcText(text: String, modifier: Modifier = Modifier, color: Color = Color.Unspecified,
    textAlign: TextAlign? = null, overflow: TextOverflow = TextOverflow.Clip, softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE, minLines: Int = 1, onTextLayout: ((TextLayoutResult) -> Unit)? = null,
    style: TextStyle = FcTypography.body) {
    val lineCount = remember { FcLineCount() }
    Text(text, modifier.semantics { }.fcLineBox(style, lineCount), color = color, textAlign = textAlign, overflow = overflow,
        softWrap = softWrap, maxLines = maxLines, minLines = minLines,
        onTextLayout = { lineCount.lines = it.lineCount; onTextLayout?.invoke(it) }, style = style)
}

@Composable
fun FcText(text: AnnotatedString, modifier: Modifier = Modifier, color: Color = Color.Unspecified,
    textAlign: TextAlign? = null, overflow: TextOverflow = TextOverflow.Clip, softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE, minLines: Int = 1, onTextLayout: ((TextLayoutResult) -> Unit)? = null,
    style: TextStyle = FcTypography.body) {
    val lineCount = remember { FcLineCount() }
    Text(text, modifier.semantics { }.fcLineBox(style, lineCount), color = color, textAlign = textAlign, overflow = overflow,
        softWrap = softWrap, maxLines = maxLines, minLines = minLines,
        onTextLayout = { lineCount.lines = it.lineCount; onTextLayout?.invoke(it) }, style = style)
}
