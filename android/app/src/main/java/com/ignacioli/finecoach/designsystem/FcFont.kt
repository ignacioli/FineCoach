package com.ignacioli.finecoach.designsystem

import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontLoadingStrategy
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import com.ignacioli.finecoach.R

// D05: one complete bundled variable font; each request explicitly drives wght.
@OptIn(ExperimentalTextApi::class)
val FcFontFamily = FontFamily(
    listOf(400, 500, 600, 700).map { weight ->
        Font(
            resId = R.font.noto_sans_sc_variable,
            weight = FontWeight(weight),
            loadingStrategy = FontLoadingStrategy.Blocking,
            variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
        )
    },
)
