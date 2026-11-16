package com.ignacioli.finecoach.features.students

import com.ignacioli.finecoach.designsystem.FcText
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.ignacioli.finecoach.designsystem.FcAvatar
import com.ignacioli.finecoach.designsystem.FcColors
import com.ignacioli.finecoach.designsystem.FcComponentMetrics
import com.ignacioli.finecoach.designsystem.FcGlyph
import com.ignacioli.finecoach.designsystem.FcLabelValueRow
import com.ignacioli.finecoach.designsystem.FcLinkButton
import com.ignacioli.finecoach.designsystem.FcSpacing
import com.ignacioli.finecoach.designsystem.FcSymbol
import com.ignacioli.finecoach.designsystem.FcTypography

@Composable
internal fun StudentActiveRow(
    displayName: String,
    focusSubtitle: String,
    trailingDetail: String?,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = FcComponentMetrics.row)
            .semantics(mergeDescendants = true) { }
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = FcSpacing.space3),
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FcAvatar(name = displayName, modifier = Modifier.testTag("conformance:DS-AVATAR · circle"))
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space1),
        ) {
            FcText(
                text = displayName,
                style = FcTypography.headline,
                color = FcColors.textPrimary,
            )
            FcText(
                text = focusSubtitle,
                style = FcTypography.caption,
                color = FcColors.textSecondary,
            )
        }
        if (trailingDetail != null) {
            FcText(
                text = trailingDetail,
                style = FcTypography.caption,
                color = FcColors.textSecondary,
            )
        }
        FcSymbol(FcGlyph.Forward)
    }
}

@Composable
internal fun StudentArchivedRow(
    displayName: String,
    archivedOnSubtitle: String,
    rowTag: String,
    restoreTag: String,
    restoreEnabled: Boolean = true,
    onOpenDetail: () -> Unit,
    onRestore: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = FcComponentMetrics.row)
            .padding(vertical = FcSpacing.space3),
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .heightIn(min = FcComponentMetrics.touch)
                .testTag(rowTag)
                .semantics(mergeDescendants = true) { }
                .clickable(role = Role.Button, onClick = onOpenDetail),
            horizontalArrangement = Arrangement.spacedBy(FcSpacing.space4),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FcAvatar(name = displayName)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(FcSpacing.space1),
            ) {
                FcText(
                    text = displayName,
                    style = FcTypography.headline,
                    color = FcColors.textPrimary,
                )
                FcText(
                    text = archivedOnSubtitle,
                    style = FcTypography.caption,
                    color = FcColors.textSecondary,
                )
            }
            Spacer(modifier = Modifier.width(FcSpacing.space2))
        }
        FcLinkButton(
            title = "恢复",
            modifier = Modifier
                .testTag(restoreTag)
                .semantics { contentDescription = "恢复 $displayName" },
            enabled = restoreEnabled,
            onClick = onRestore,
        )
    }
}

@Composable
internal fun StudentOverviewRow(
    kicker: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    value: @Composable () -> Unit,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = FcComponentMetrics.row)
            .semantics(mergeDescendants = true) { }
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = FcSpacing.space3),
        horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space1),
        ) {
            FcText(
                text = kicker,
                style = FcTypography.caption,
                color = FcColors.textSecondary,
            )
            value()
        }
        FcSymbol(FcGlyph.Forward)
    }
}

@Composable
internal fun StudentInlineFieldRow(
    label: String,
    placeholder: String,
    value: String,
    onValueChange: (String) -> Unit,
    rowTag: String,
    inputTag: String,
    enabled: Boolean = true,
    singleLine: Boolean = true,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
) {
    FcLabelValueRow(
        label = label,
        modifier = Modifier.testTag(rowTag),
    ) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = FcComponentMetrics.touch)
                .testTag(inputTag)
                .semantics { contentDescription = label },
            enabled = enabled,
            singleLine = singleLine,
            maxLines = if (singleLine) 1 else 5,
            textStyle = FcTypography.body.copy(color = FcColors.textPrimary),
            keyboardOptions = keyboardOptions,
            cursorBrush = SolidColor(FcColors.actionPrimary),
            decorationBox = { innerField ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = FcComponentMetrics.touch),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    if (value.isEmpty()) {
                        FcText(
                            text = placeholder,
                            style = FcTypography.body,
                            color = FcColors.textSecondary,
                        )
                    }
                    innerField()
                }
            },
        )
    }
}
