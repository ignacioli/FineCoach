package com.ignacioli.finecoach.features.session

import androidx.compose.runtime.Composable

@Composable
fun DurationReviewScreen(state: ActiveSessionUiState, onCancel: () -> Unit, onSaved: () -> Unit) =
    SessionRecoveryReview(state, onCancel, onSaved)
