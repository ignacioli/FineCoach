package com.ignacioli.finecoach.core.domain.body

import com.ignacioli.finecoach.core.domain.common.*
import java.time.Instant
import java.util.UUID

enum class BodyMetricUnitRuleKind { weight, length, percent, customUnit }
enum class BodyMetricKind { builtIn, custom }
enum class BodyMetricLifecycle { active, archived }
enum class BuiltInBodyMetric(val suffix: String, val displayName: String, val rule: BodyMetricUnitRuleKind) {
    height("b001", "身高", BodyMetricUnitRuleKind.length), weight("b002", "体重", BodyMetricUnitRuleKind.weight),
    bodyFatPercent("b003", "体脂率", BodyMetricUnitRuleKind.percent), chest("b004", "胸围", BodyMetricUnitRuleKind.length),
    waist("b005", "腰围", BodyMetricUnitRuleKind.length), hip("b006", "臀围", BodyMetricUnitRuleKind.length),
    upperArm("b007", "上臂围", BodyMetricUnitRuleKind.length), thigh("b008", "大腿围", BodyMetricUnitRuleKind.length);
    val id: UUID get() = UUID.fromString("00000000-0000-0000-0000-00000000$suffix")
    val canonicalUnit get() = when(rule) { BodyMetricUnitRuleKind.weight -> "kg"; BodyMetricUnitRuleKind.percent -> "%"; else -> "cm" }
    fun definition(now: Instant) = BodyMetricDefinition(id, null, BodyMetricKind.builtIn, NormalizedName.parse(displayName), rule, canonicalUnit, BodyMetricLifecycle.active, now, now)
}

/** Sensitive content must never be included in diagnostic strings. */
class BodyMetricDefinition(
    val id: UUID, val studentID: StudentID?, val kind: BodyMetricKind, val name: NormalizedName,
    val unitRuleKind: BodyMetricUnitRuleKind, currentUnit: String, val lifecycle: BodyMetricLifecycle,
    val createdAtUTC: Instant, val updatedAtUTC: Instant,
) {
    val currentUnit = currentUnit.trim()
    init {
        require(if (kind == BodyMetricKind.builtIn) studentID == null && unitRuleKind != BodyMetricUnitRuleKind.customUnit
            else studentID != null && unitRuleKind == BodyMetricUnitRuleKind.customUnit && this.currentUnit.isNotEmpty()) { "Invalid body metric" }
    }
    private fun changed(name: NormalizedName = this.name, unit: String = currentUnit, lifecycle: BodyMetricLifecycle = this.lifecycle, now: Instant): BodyMetricDefinition =
        BodyMetricDefinition(id, studentID, kind, name, unitRuleKind, unit, lifecycle, createdAtUTC, now)
    fun changingCurrentUnit(unit: String, now: Instant): BodyMetricDefinition { requireCustomActive(); return changed(unit = unit, now = now) }
    fun renamed(name: String, now: Instant): BodyMetricDefinition { requireCustomActive(); return changed(name = NormalizedName.parse(name), now = now) }
    fun archived(now: Instant): BodyMetricDefinition { requireCustomActive(); return changed(lifecycle = BodyMetricLifecycle.archived, now = now) }
    fun restored(now: Instant): BodyMetricDefinition {
        require(kind == BodyMetricKind.custom && lifecycle == BodyMetricLifecycle.archived) { "Invalid body metric state" }
        return changed(lifecycle = BodyMetricLifecycle.active, now = now)
    }
    private fun requireCustomActive() { require(kind == BodyMetricKind.custom && lifecycle == BodyMetricLifecycle.active) { "Invalid body metric state" } }
    override fun toString() = "BodyMetricDefinition(redacted)"
}
