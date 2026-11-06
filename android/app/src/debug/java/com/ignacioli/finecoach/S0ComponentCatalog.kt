package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.testTag
import com.ignacioli.finecoach.designsystem.*
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

// fictional-data: UI contract samples only; never persists or loads product records.
data class S0CatalogEntry(val id: String, val states: List<String>)
val S0CatalogEntries = listOf(
    S0CatalogEntry("DS-BASE", listOf("tokens")),
    S0CatalogEntry("DS-BUTTON", listOf("default", "disabled", "secondary", "link")),
    S0CatalogEntry("DS-TITLE-ACTION", listOf("icon", "add")),
    S0CatalogEntry("DS-SEGMENTED", listOf("first", "last")),
    S0CatalogEntry("DS-CHIP", listOf("off", "on", "body")),
    S0CatalogEntry("DS-TOGGLE", listOf("off", "on", "disabled")),
    S0CatalogEntry("DS-STEPPER", listOf("lower", "upper", "field")),
    S0CatalogEntry("DS-TEXT-FIELD", listOf("empty", "secure", "search")),
    S0CatalogEntry("DS-LIST-ROW", listOf("plain", "action", "selected", "unavailable", "group")),
    S0CatalogEntry("DS-SECTION", listOf("label", "entry")),
    S0CatalogEntry("DS-LABEL-VALUE-ROW", listOf("text", "slot", "action")),
    S0CatalogEntry("DS-PAGE-HEADER", listOf("back", "trailing")),
    S0CatalogEntry("DS-HUB-ROW", listOf("action", "info", "unavailable")),
    S0CatalogEntry("DS-INLINE-RESULT", listOf("failure", "success", "info")),
    S0CatalogEntry("DS-ACTION-ROW", listOf("normal", "destructive", "disabled")),
    S0CatalogEntry("DS-UNDO-ROW", listOf("visible")),
    S0CatalogEntry("DS-BOTTOM-SHEET", listOf("open")),
    S0CatalogEntry("DS-CONFIRM-DIALOG", listOf("open", "long")),
    S0CatalogEntry("DS-STATUS", listOf("overdue", "conflict", "coursePackageInvalid", "notComparable", "permissionDenied")),
    S0CatalogEntry("DS-SAVE-STATUS", listOf("saving", "saved", "failed")),
    S0CatalogEntry("DS-AVATAR", listOf("initial")),
    S0CatalogEntry("DS-SYMBOL", listOf("pageBack", "back", "forward", "check", "checkOnFill", "minus", "plus", "collapse")),
)

@Composable
internal fun S0ComponentCatalog(onBack: () -> Unit) {
    var selectedId by remember { mutableStateOf<String?>(null) }
    val back = { if (selectedId != null) selectedId = null else onBack() }
    FcPlatformShell(onBack = back) {
        FcPageHeader(selectedId ?: "基础组件样例", onBack = back, tag = "catalog")
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).testTag("catalog-content"),
            verticalArrangement = Arrangement.spacedBy(FcSpacing.space3)) {
            if (selectedId == null) S0CatalogEntries.forEach { entry ->
                FcGroupEntryRow(entry.id, entry.states.size, Modifier.testTag("catalog-${entry.id}")) { selectedId = entry.id }
            } else {
                val entry = S0CatalogEntries.single { it.id == selectedId }
                Text("虚构样例 · 无持久化", style = FcTypography.caption, color = FcColors.textSecondary)
                entry.states.forEach { state ->
                    FcSectionLabel(state)
                    S0ComponentState(entry.id, state)
                }
            }
        }
    }
}

@Composable
internal fun S0ComponentState(id: String, state: String) {
    val tag = "$id-$state"
    var count by remember { mutableIntStateOf(0) }
    var text by remember { mutableStateOf("") }
    var checked by remember { mutableStateOf(state == "on" || state == "selected") }
    var open by remember { mutableStateOf(false) }
    var expanded by remember { mutableStateOf(false) }
    var date by remember { mutableStateOf<Long?>(null) }
    val tap = { count++; Unit }
    val modifier = Modifier.testTag(tag)
    Column(Modifier.fillMaxWidth().testTag("$tag-parent")) {
        when (id) {
            "DS-BASE" -> Text("虚构教练 · 字体与主题", modifier, style = FcTypography.body, color = FcColors.textPrimary)
            "DS-BUTTON" -> when (state) {
                "secondary" -> FcSecondaryButton("次按钮样例", modifier, onClick = tap)
                "link" -> FcLinkButton("链接样例", modifier, onClick = tap)
                else -> FcButton("主按钮样例", modifier, enabled = state != "disabled", onClick = tap)
            }
            "DS-TITLE-ACTION" -> if (state == "add") FcTitleAddButton("新建预约样例", painterResource(R.drawable.ic_ms_add), modifier, tap)
                else Row(horizontalArrangement = Arrangement.spacedBy(FcSpacing.space2)) {
                    FcTitleIconButton("设置样例", painterResource(R.drawable.ic_ms_settings), modifier, tap)
                    FcTitleIconButton("日历样例", painterResource(R.drawable.ic_ms_calendar_month), Modifier.testTag("$tag-calendar"), tap)
                    FcTitleIconButton("资料库样例", painterResource(R.drawable.ic_ms_grid_view), Modifier.testTag("$tag-library"), tap)
                    FcTitleIconButton("筛选样例", painterResource(R.drawable.ic_ms_filter_list), Modifier.testTag("$tag-filter"), tap)
                }
            "DS-SEGMENTED" -> {
                var selected by remember { mutableIntStateOf(if (state == "first") 0 else 1) }
                FcSegmentedSwitch(listOf("选项甲", "选项乙"), selected, { selected = it }, modifier, tag)
            }
            "DS-CHIP" -> if (state == "body") {
                var parts by remember { mutableStateOf(setOf<Int>()) }
                FcBodyPartPicker(parts, { parts = if (it in parts) parts - it else parts + it }, modifier, tag)
            } else FcFilterChip("虚构筛选", checked, modifier) { checked = !checked }
            "DS-TOGGLE" -> FcToggle("样例开关", checked, { checked = it }, modifier, enabled = state != "disabled")
            "DS-STEPPER" -> if (state == "field") FcStepperField("样例数值", text, { text = it }, text != "0",
                painterResource(R.drawable.ic_ms_remove), painterResource(R.drawable.ic_ms_add), { text = "0" }, { text = "1" }, modifier, tag)
                else {
                    var number by remember { mutableIntStateOf(if (state == "lower") 0 else 2) }
                    FcStepper("样例次数", number, 0..2, { number = it }, painterResource(R.drawable.ic_ms_remove), painterResource(R.drawable.ic_ms_add), modifier, tag)
                }
            "DS-TEXT-FIELD" -> if (state == "search") FcSearchField("搜索虚构内容", text, { text = it }, modifier)
                else FcTextField("虚构输入", text, { text = it }, modifier, secure = state == "secure")
            "DS-LIST-ROW" -> if (state == "group") FcListGroupRow("虚构分组", listOf(checked, false), expanded,
                { expanded = !expanded }, { checked = !checked }, painterResource(R.drawable.ic_ms_expand_more), painterResource(R.drawable.ic_ms_remove), modifier, tag)
                else FcListRow("虚构项目", modifier, subtitle = "虚构说明", mode = when (state) {
                    "action" -> FcRowMode.Action(tap)
                    "selected" -> FcRowMode.Selection(checked) { checked = !checked }
                    "unavailable" -> FcRowMode.Unavailable("样例不可用")
                    else -> FcRowMode.Informational
                })
            "DS-SECTION" -> if (state == "label") FcSectionLabel("虚构区段", modifier)
                else FcGroupEntryRow("虚构分组", 2, modifier, tap)
            "DS-LABEL-VALUE-ROW" -> when (state) {
                "text" -> FcLabelValueText("虚构标签", "虚构值", modifier)
                "slot" -> FcLabelValueRow("虚构开关", modifier) { FcToggle("值开关", checked, { checked = it }, Modifier.testTag("$tag-toggle")) }
                else -> {
                    FcLabelValueRow("虚构日期", modifier, onClick = { open = true }) { Text(date?.let { DateTimeFormatter.ofPattern("yyyy年M月d日").withZone(ZoneOffset.UTC).format(Instant.ofEpochMilli(it)) } ?: "选择日期", style = FcTypography.body, color = FcColors.textPrimary) }
                    if (open) FcDatePickerDialog(date, { date = it; open = false }, { open = false })
                }
            }
            "DS-PAGE-HEADER" -> FcPageHeader("虚构标题", modifier, "虚构副标题", onBack = tap, tag = tag,
                trailingTitle = if (state == "trailing") "编辑样例" else null, onTrailing = tap)
            "DS-HUB-ROW" -> FcHubRow("虚构入口", painterResource(R.drawable.ic_ms_grid_view), modifier, subtitle = "虚构说明", mode = when (state) {
                "action" -> FcRowMode.Action(tap); "unavailable" -> FcRowMode.Unavailable("档案未包含"); else -> FcRowMode.Informational
            })
            "DS-INLINE-RESULT" -> FcInlineResult(when (state) { "failure" -> FcResultVariant.Failure; "success" -> FcResultVariant.Success; else -> FcResultVariant.Info },
                "虚构结果", "仅演示，不代表保存或交付", painterResource(if (state == "failure") R.drawable.ic_ms_priority_high else R.drawable.ic_ms_info), modifier, onRetry = tap, tag = tag)
            "DS-ACTION-ROW" -> {
                FcActionRow(if (state == "destructive") "删除虚构样例" else "普通操作样例", modifier,
                    destructive = state == "destructive", enabled = state != "disabled",
                    trash = if (state == "destructive") painterResource(R.drawable.ic_ms_delete) else null, onClick = { if (state == "destructive") open = true else tap() })
                if (open) FcConfirmationDialog("确认删除虚构样例？", "只更新内存计数", "删除样例", { tap(); open = false }, { open = false }, tag = tag)
            }
            "DS-UNDO-ROW" -> FcUndoRow("虚构对象已删除", modifier, tag, tap)
            "DS-BOTTOM-SHEET" -> {
                FcButton("打开样例面板", modifier) { open = true }
                if (open) FcBottomSheet("虚构操作面板", { open = false }) {
                    FcActionRow("关闭样例面板", Modifier.testTag("$tag-close")) { open = false }
                }
            }
            "DS-CONFIRM-DIALOG" -> {
                FcButton("打开样例确认", modifier) { open = true }
                if (open) FcConfirmationDialog("确认虚构操作？", if (state == "long") "虚构长说明。".repeat(100) else "无数据写入", "确认样例",
                    { tap(); open = false }, { open = false }, tag = tag)
            }
            "DS-STATUS" -> {
                val status = FcStatus.entries.single { it.name.replaceFirstChar(Char::lowercase) == state }
                FcStatusLabel(status, painterResource(if (status.warning) R.drawable.ic_ms_priority_high else R.drawable.ic_ms_info), modifier)
            }
            "DS-SAVE-STATUS" -> FcSaveStatusView(FcSaveState.entries.single { it.name.lowercase() == state },
                painterResource(when (state) { "saving" -> R.drawable.ic_ms_sync; "saved" -> R.drawable.ic_ms_check_circle; else -> R.drawable.ic_ms_warning }), modifier)
            "DS-AVATAR" -> FcAvatar("虚构", modifier)
            "DS-SYMBOL" -> if (state in listOf("minus", "plus", "collapse")) {
                FcSymbol(FcAssetSymbol.entries.single { it.name.lowercase() == state },
                    painterResource(when (state) { "minus" -> R.drawable.ic_ms_remove; "plus" -> R.drawable.ic_ms_add; else -> R.drawable.ic_ms_expand_more }), modifier)
            } else FcSymbol(FcGlyph.entries.single { it.name.replaceFirstChar(Char::lowercase) == state }, modifier)
            else -> error("Unknown catalog ID: $id")
        }
        Text("样例交互计数：$count", Modifier.testTag("$tag-count"), style = FcTypography.caption, color = FcColors.textSecondary)
    }
}
