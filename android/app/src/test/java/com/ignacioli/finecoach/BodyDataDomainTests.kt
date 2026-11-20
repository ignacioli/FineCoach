// fictional-data: synthetic body values. Assertions report boolean outcomes only.
package com.ignacioli.finecoach
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import java.time.*
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
class BodyDataDomainTests {
    @Test fun builtInsHaveStableIDsAndCanonicalUnits() {
        assertTrue(BuiltInBodyMetric.entries.size == 8)
        assertTrue(BuiltInBodyMetric.weight.id.toString() == "00000000-0000-0000-0000-00000000b002")
        assertTrue(BuiltInBodyMetric.entries.map { it.id }.toSet().size == 8)
        assertTrue(BuiltInBodyMetric.entries.all { it.definition(S3Fixtures.now).studentID == null })
    }
    @Test fun localDayUpsertRetainsIdentityAndCreation() {
        val index = BodyMeasurementDayIndex()
        val a = BodyMeasurement.recordedNow(UUID(0, 5), S3Fixtures.student, BuiltInBodyMetric.weight.id, S3Fixtures.now, S3Fixtures.zone, DecimalValue.parse("70"), "kg")
        index.upsert(a)
        val b = index.upsert(BodyMeasurement.recordedNow(UUID(0, 6), a.studentID, a.metricID, S3Fixtures.now.plusSeconds(60), S3Fixtures.zone, DecimalValue.parse("71"), "kg"))
        assertTrue(b.id == a.id && b.createdAtUTC == a.createdAtUTC && index.measurements.size == 1)
        assertTrue(b.value.compareTo(DecimalValue.parse("71")) == 0)
        index.delete(b.id); assertTrue(index.history(a.studentID, a.metricID).isEmpty())
    }
    @Test fun midnightUsesInjectedTimezone() {
        val at = Instant.parse("2026-03-09T06:59:00Z")
        val a = BodyMeasurement.recordedNow(UUID(0, 5), S3Fixtures.student, BuiltInBodyMetric.weight.id, at, S3Fixtures.zone, DecimalValue.parse("70"), "kg")
        val b = BodyMeasurement.recordedNow(UUID(0, 6), a.studentID, a.metricID, at.plusSeconds(60), S3Fixtures.zone, a.value, "kg")
        assertTrue(a.localCalendarDay != b.localCalendarDay)
    }
    @Test fun conversionsNeverMutateAndCustomUnitIsHistorical() {
        val value = DecimalValue.parse("70")
        assertTrue(BuiltInUnitConversion.weight(value, "lb").canonicalString == "154.32")
        assertTrue(value.canonicalString == "70")
        assertTrue(BuiltInUnitConversion.length(DecimalValue.parse("180"), "in").canonicalString == "70.87")
        val custom = BodyMetricDefinition(UUID(0, 5), S3Fixtures.student, BodyMetricKind.custom, com.ignacioli.finecoach.core.domain.common.NormalizedName.parse("虚构指标"), BodyMetricUnitRuleKind.customUnit, "旧单位", BodyMetricLifecycle.active, S3Fixtures.now, S3Fixtures.now)
        val measurement = BodyMeasurement.recordedNow(UUID(0, 6), S3Fixtures.student, custom.id, S3Fixtures.now, S3Fixtures.zone, value, custom.currentUnit)
        assertTrue(custom.changingCurrentUnit("新单位", S3Fixtures.now).currentUnit == "新单位")
        assertTrue(measurement.enteredUnit == "旧单位")
        assertTrue(custom.archived(S3Fixtures.now).restored(S3Fixtures.now).lifecycle == BodyMetricLifecycle.active)
        assertTrue(!measurement.toString().contains(value.canonicalString))
    }
}
