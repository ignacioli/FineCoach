package com.ignacioli.finecoach.core.domain.body

import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.core.domain.progress.FoundationDecimal
import java.math.RoundingMode
import java.time.*
import java.util.UUID

class BodyMeasurement(val id: UUID, val studentID: StudentID, val metricID: UUID, val localCalendarDay: LocalDate,
    val value: DecimalValue, enteredUnit: String, val createdAtUTC: Instant, val updatedAtUTC: Instant) {
    val enteredUnit = enteredUnit.trim()
    init { require(this.enteredUnit.isNotEmpty()) { "Invalid body unit" } }
    fun editingSameDay(value: DecimalValue, enteredUnit: String, now: Instant) = BodyMeasurement(id, studentID, metricID, localCalendarDay, value, enteredUnit, createdAtUTC, now)
    override fun toString() = "BodyMeasurement(redacted)"
    companion object {
        fun recordedNow(id: UUID, studentID: StudentID, metricID: UUID, instant: Instant, zone: ZoneId, value: DecimalValue, enteredUnit: String) =
            BodyMeasurement(id, studentID, metricID, instant.atZone(zone).toLocalDate(), value, enteredUnit, instant, instant)
    }
}
class BodyMeasurementDayIndex(measurements: List<BodyMeasurement> = emptyList()) {
    private val rows = measurements.toMutableList()
    val measurements: List<BodyMeasurement> get() = rows.toList()
    fun upsert(candidate: BodyMeasurement): BodyMeasurement {
        val old = rows.firstOrNull { it.studentID == candidate.studentID && it.metricID == candidate.metricID && it.localCalendarDay == candidate.localCalendarDay }
        val saved = old?.editingSameDay(candidate.value, candidate.enteredUnit, candidate.updatedAtUTC) ?: candidate
        rows.removeAll { it.id == saved.id }; rows += saved
        return saved
    }
    fun delete(id: UUID) { rows.removeAll { it.id == id } }
    fun history(student: StudentID, metric: UUID) = rows.filter { it.studentID == student && it.metricID == metric }.sortedBy { it.localCalendarDay }
}
object BuiltInUnitConversion {
    private val pounds = "2.2046226218".toBigDecimal(); private val inches = "0.3937007874".toBigDecimal()
    fun weight(value: DecimalValue, unit: String): DecimalValue = when(unit) {
        "kg" -> value; "lb" -> rounded(value.decimal * pounds); else -> throw IllegalArgumentException("Invalid body unit")
    }
    fun length(value: DecimalValue, unit: String): DecimalValue = when(unit) {
        "cm" -> value; "in" -> rounded(value.decimal * inches); else -> throw IllegalArgumentException("Invalid body unit")
    }
    fun canonicalKilograms(value: DecimalValue, unit: String): DecimalValue = when(unit) {
        "kg" -> value; "lb" -> DecimalValue.fromBigDecimal(FoundationDecimal.divide(value.decimal, pounds)); else -> throw IllegalArgumentException("Invalid body unit")
    }
    fun canonicalCentimeters(value: DecimalValue, unit: String): DecimalValue = when(unit) {
        "cm" -> value; "in" -> DecimalValue.fromBigDecimal(FoundationDecimal.divide(value.decimal, inches)); else -> throw IllegalArgumentException("Invalid body unit")
    }
    private fun rounded(value: java.math.BigDecimal) = DecimalValue.fromBigDecimal(value.setScale(2, RoundingMode.HALF_UP))
}
