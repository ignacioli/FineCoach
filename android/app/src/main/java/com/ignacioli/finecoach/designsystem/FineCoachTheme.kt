package com.ignacioli.finecoach.designsystem

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

// DS §2 has one approved palette. System dark mode must not invent new values.
private val colors = lightColorScheme(
    primary = FcColors.actionPrimary,
    onPrimary = FcColors.actionOn,
    primaryContainer = FcColors.surfaceSelected,
    onPrimaryContainer = FcColors.textPrimary,
    inversePrimary = FcColors.actionOn,
    secondary = FcColors.textSecondary,
    onSecondary = FcColors.actionOn,
    secondaryContainer = FcColors.surfaceSelected,
    onSecondaryContainer = FcColors.textPrimary,
    tertiary = FcColors.actionPrimary,
    onTertiary = FcColors.actionOn,
    tertiaryContainer = FcColors.surfaceCanvas,
    onTertiaryContainer = FcColors.textPrimary,
    background = FcColors.surfacePage,
    onBackground = FcColors.textPrimary,
    surface = FcColors.surfacePage,
    onSurface = FcColors.textPrimary,
    surfaceVariant = FcColors.surfaceSubtle,
    onSurfaceVariant = FcColors.textSecondary,
    surfaceTint = FcColors.actionPrimary,
    inverseSurface = FcColors.actionPrimary,
    inverseOnSurface = FcColors.actionOn,
    error = FcColors.statusDestructive,
    onError = FcColors.actionOn,
    errorContainer = FcColors.surfacePage,
    onErrorContainer = FcColors.statusDestructive,
    outline = FcColors.borderControl,
    outlineVariant = FcColors.surfaceDivider,
    scrim = FcColors.overlayScrim,
    surfaceBright = FcColors.surfacePage,
    surfaceDim = FcColors.surfaceCanvas,
    surfaceContainer = FcColors.surfaceElevated,
    surfaceContainerHigh = FcColors.surfaceElevated,
    surfaceContainerHighest = FcColors.surfaceElevated,
    surfaceContainerLow = FcColors.surfacePage,
    surfaceContainerLowest = FcColors.surfacePage,
)

private val typography = Typography(
    displayLarge = FcTypography.display,
    displayMedium = FcTypography.display,
    displaySmall = FcTypography.display,
    headlineLarge = FcTypography.titleLarge,
    headlineMedium = FcTypography.title,
    headlineSmall = FcTypography.title,
    titleLarge = FcTypography.headline,
    titleMedium = FcTypography.callout,
    titleSmall = FcTypography.sectionLabel,
    bodyLarge = FcTypography.body,
    bodyMedium = FcTypography.style("callout", 400),
    bodySmall = FcTypography.caption,
    labelLarge = FcTypography.headline,
    labelMedium = FcTypography.chipLabel,
    labelSmall = FcTypography.compact,
)

@Composable
fun FineCoachTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colors, typography = typography, content = content)
}
