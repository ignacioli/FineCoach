// fictional-data: generic resource labels only; no personal data or seed records.
package com.ignacioli.finecoach.features.resources

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.designsystem.*
import com.ignacioli.finecoach.navigation.S1Routes
import com.ignacioli.finecoach.storage.repository.ExerciseRepository

/** Coach-owned resources; neither row mutates student or training data. */
@Composable
fun ResourceHubScreen(exercises: ExerciseRepository, templates: TemplateUseCases,
    onNavigate: (String) -> Unit, onBack: () -> Unit) {
    var exerciseSummary by remember { mutableStateOf<String?>(null) }
    var templateSummary by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(exercises, templates) {
        exerciseSummary = when (val result = exercises.listCatalog()) {
            is ApplicationResult.Failure -> "动作数量加载失败"
            is ApplicationResult.Success -> if (exercises.catalogUnavailable) "动作库暂不可用" else {
                val active = result.value.filter { it.lifecycle == ExerciseLifecycle.active && !it.isRetired }
                "内置 ${active.count { it.kind == ExerciseKind.builtIn }} 个 · 自定义 ${active.count { it.kind == ExerciseKind.custom }} 个"
            }
        }
        templateSummary = when (val result = templates.list()) {
            is ApplicationResult.Failure -> "模板数量加载失败"
            is ApplicationResult.Success -> "${result.value.size} 个模板"
        }
    }
    FcPageSecondary("资料库", onBack, tag = "resource-hub") {
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).testTag("resource-hub-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space4)) {
            Column(Modifier.fillMaxWidth()) {
                FcListRowDivider()
                FcHubRow("动作库", painterResource(R.drawable.ic_ms_grid_view), Modifier.testTag("resource-hub-exercises"), subtitle = exerciseSummary,
                    mode = FcRowMode.Action { onNavigate(S1Routes.EXERCISES) })
                FcListRowDivider()
                FcHubRow("训练模板", painterResource(R.drawable.ic_ms_list_alt), Modifier.testTag("resource-hub-templates"), subtitle = templateSummary,
                    mode = FcRowMode.Action { onNavigate(S1Routes.TEMPLATES) })
                FcListRowDivider()
            }
            FcText("资料库存放教练自己的动作与模板，不属于某一名学员。", style = FcTypography.caption, color = FcColors.textSecondary)
        }
    }
}
