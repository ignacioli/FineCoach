package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*

/** DS-CALENDAR-DAY: the marker slot is reserved even when there is no appointment. */
@Composable
fun FcCalendarDayCell(day: Int, selected: Boolean, hasAppointments: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.touch)
        .semantics(mergeDescendants = true) {
            this.selected = selected
            contentDescription = "${day}日"
            stateDescription = if (hasAppointments) "有课程安排" else "无课程安排"
        }.clickable(role = Role.Button, onClick = onClick), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(FcSpacing.space6 + FcSpacing.space1)
            .then(if (selected) Modifier.background(FcColors.actionPrimary, CircleShape).testTag("conformance:DS-CALENDAR-DAY · selected") else Modifier),
            contentAlignment = Alignment.Center) {
            FcText(day.toString(), style = FcTypography.style("compact", if (selected) 600 else 400),
                color = if (selected) FcColors.actionOn else FcColors.textPrimary)
        }
        Box(Modifier.padding(top = FcSpacing.space1).size(FcSpacing.space1)
            .then(if (hasAppointments && !selected) Modifier.background(FcColors.actionPrimary, CircleShape).testTag("conformance:Has-appointment dot") else Modifier))
    }
}

@Composable
fun FcCalendarMonthButton(previous: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(modifier.size(FcComponentMetrics.touch).semantics { contentDescription = if (previous) "上个月" else "下个月" }
        .clickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        FcSymbol(if (previous) FcGlyph.Back else FcGlyph.Forward)
    }
}
