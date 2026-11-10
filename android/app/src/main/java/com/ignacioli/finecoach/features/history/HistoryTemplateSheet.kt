package com.ignacioli.finecoach.features.history

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.template.TrainingTemplate
import com.ignacioli.finecoach.designsystem.*
import kotlinx.coroutines.launch

/** The same created ID and content command survive explicit retries; success requires readback. */
class HistoryTemplateState(private val templates: TemplateUseCases, private val clock: AppClock, private val ids: StableIDGenerator) {
    var name by mutableStateOf("")
    var busy by mutableStateOf(false); private set
    var error by mutableStateOf<ApplicationError?>(null); private set
    var created by mutableStateOf<TemplateRecord?>(null); private set
    var saved by mutableStateOf<TemplateContentRecord?>(null); private set
    private var command: SaveTemplateContentCommand? = null
    fun begin() { if (saved != null && error == null) { created = null; saved = null; command = null } }
    suspend fun save(source: SessionContentRecord, onSaved: () -> Unit) {
        if (busy) return
        busy = true
        try {
            if (created == null) when (val result = templates.save(SaveTemplateCommand(null, name, emptySet(), null))) {
                is ApplicationResult.Failure -> { error = result.error; return }
                is ApplicationResult.Success -> created = result.value
            }
            val record = created!!
            if (command == null) {
                val snapshot = TrainingTemplate.snapshotFromSession(source.toDomain(), record.templateID, record.name,
                    newExerciseID = ids::newTemplateExerciseID, newSectionID = ids::newSectionID, nowUTC = clock.now())
                command = SaveTemplateContentCommand(record.templateID, record.revision,
                    snapshot.sections.map { it.toRecord() }, snapshot.exercises.map { it.toRecord() })
            }
            if (saved == null) when (val result = templates.retry(command!!)) {
                is ApplicationResult.Failure -> { error = result.error; return }
                is ApplicationResult.Success -> saved = result.value
            }
            when (val result = templates.load(record.templateID)) {
                is ApplicationResult.Failure -> error = result.error
                is ApplicationResult.Success -> if (result.value != saved) error = ApplicationError(ApplicationErrorCode.staleRevision)
                    else { error = null; onSaved() }
            }
        } catch (error: com.ignacioli.finecoach.core.domain.training.DomainException) {
            this.error = ApplicationError(ApplicationErrorCode.valueOf(error.error.name))
        } finally { busy = false }
    }
}

@Composable
fun HistoryTemplateEntry(state: HistoryTemplateState, source: SessionContentRecord) {
    var open by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    FcActionRow("另存为模板", Modifier.testTag("history-save-template"), detail = if (state.saved != null) "已保存为模板" else null) { state.begin(); open = true }
    if (open) FcBottomSheet("另存为模板", { if (!state.busy) open = false }, subtitle = "只保存动作和组的计划，不含备注与学员信息。", skipPartiallyExpanded = true) {
        Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).testTag("history-template-content")) {
            FcTextField("模板名称", state.name, { state.name = it }, Modifier.testTag("history-template-name"), enabled = !state.busy && state.created == null)
            state.error?.let { FcListRow("保存失败，可重试；已创建的模板会复用", Modifier.testTag("history-template-error")) }
            FcButton("保存模板", Modifier.testTag("history-template-save"), !state.busy && state.name.isNotBlank()) { scope.launch { state.save(source) { open = false } } }
            FcSecondaryButton("取消", Modifier.testTag("history-template-cancel"), !state.busy) { open = false }
        }
    }
}
