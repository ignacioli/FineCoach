package com.ignacioli.finecoach.designsystem

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role

/** DS-LIST-ROW appointment composition: time, identity/focus, status and optional disclosure. */
@Composable
fun FcAppointmentRow(time: String, title: String, status: String, modifier: Modifier = Modifier,
    prominent: Boolean = false, subtitle: String = "", showsDisclosure: Boolean = true, overdue: Boolean = false, onClick: (() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().heightIn(min = FcComponentMetrics.row)
        .then(if (onClick == null) Modifier else Modifier.clickable(role = Role.Button, onClick = onClick))
        .padding(vertical = FcSpacing.space3), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
        if (prominent) Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(FcSpacing.space1)) {
            FcText(time, style = FcTypography.title, color = FcColors.textPrimary)
            FcText(title, style = FcTypography.body, color = FcColors.textPrimary)
            FcText(subtitle, style = FcTypography.caption, color = FcColors.textSecondary)
        } else {
            Box(Modifier.width(FcComponentMetrics.field + FcSpacing.space3)) {
                FcText(time, style = FcTypography.style("callout", 600), color = FcColors.textPrimary)
            }
            Box(Modifier.weight(1f)) {
                FcText(title, style = FcTypography.body, color = FcColors.textPrimary, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
            }
            if (overdue) FcStatusLabel(FcStatus.Overdue, androidx.compose.ui.res.painterResource(com.ignacioli.finecoach.R.drawable.ic_ms_priority_high), Modifier.testTag("appointment-overdue-status"))
            else FcText(status, style = FcTypography.caption, color = FcColors.textSecondary)
        }
        if (onClick != null && showsDisclosure) FcSymbol(FcGlyph.Forward)
        else if (onClick != null) Spacer(Modifier.width(FcComponentMetrics.icon))
    }
}
