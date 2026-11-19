package com.ignacioli.finecoach

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.designsystem.*

// fictional-data: S1 additions stay separate so the frozen S0/G2 66-state matrix does not change.
val S1CatalogEntries = listOf(
    S0CatalogEntry("DS-CALENDAR-DAY", listOf("plain", "selected", "scheduled")),
    S0CatalogEntry("DS-AMBIENT-SCENE", listOf("today", "calendar")),
    S0CatalogEntry("DS-SET-ROW", listOf("draft", "pending", "completed", "disabled", "undo")),
    S0CatalogEntry("DS-EQUIPMENT-ICON", FcEquipmentIcon.entries.map { it.name }),
    S0CatalogEntry("DS-PAGE-PRIMARY", listOf("coach", "viewer")),
    S0CatalogEntry("DS-PAGE-SECONDARY", listOf("back", "bottom")),
    S0CatalogEntry("DS-EMPTY-STATE", listOf("static", "ambient")),
    S0CatalogEntry("DS-LAUNCH", listOf("white")),
)

@Composable
internal fun S1ComponentState(id: String, state: String) {
    val modifier = Modifier.testTag("$id-$state")
    when (id) {
        "DS-CALENDAR-DAY" -> FcCalendarDayCell(8,state == "selected",state == "scheduled",modifier) {}
        "DS-AMBIENT-SCENE" -> Box(modifier) { FcAmbientScene(size = if (state == "calendar") FcComponentMetrics.calendarIllustration else FcComponentMetrics.illustration) }
        "DS-SET-ROW" -> FcSetRow(1, "20 kg × 8", state == "completed" || state == "undo", state == "pending", {}, {}, modifier,
            enabled = state != "disabled", tag = "$id-$state", onUndo = if (state == "undo") ({}) else null)
        "DS-EQUIPMENT-ICON" -> FcEquipmentIconView(FcEquipmentIcon.valueOf(state), modifier)
        "DS-PAGE-PRIMARY" -> FcPagePrimary("虚构首页", modifier, segments = if (state == "coach") ({ FcSegmentedSwitch(listOf("今日", "学员"), 0, {}) }) else null) { }
        "DS-PAGE-SECONDARY" -> Box(Modifier.height(FcComponentMetrics.row * 6)) {
            FcPageSecondary("虚构详情", {}, modifier, bottom = if (state == "bottom") ({ FcButton("样例保存", onClick = {}) }) else null) { }
        }
        "DS-EMPTY-STATE" -> Box(Modifier.height(FcComponentMetrics.row * 9)) {
            FcEmptyState("虚构空态", "样例说明", modifier.fillMaxSize(), ambient = state == "ambient",
                actionTitle = if (state == "static") "样例创建" else null)
        }
        "DS-LAUNCH" -> Box(Modifier.height(FcComponentMetrics.row * 4)) { FcLaunch(modifier) }
        else -> error("Unknown S1 catalog ID: $id")
    }
}
