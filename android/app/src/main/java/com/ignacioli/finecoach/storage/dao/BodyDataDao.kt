package com.ignacioli.finecoach.storage.dao
import androidx.room.*
import com.ignacioli.finecoach.storage.entity.*
@Dao
interface BodyDataDao {
    @Query("SELECT * FROM body_metric_definitions WHERE studentID IS NULL OR studentID = :student ORDER BY createdAtUTC, id") fun metrics(student: String): List<BodyMetricDefinitionEntity>
    @Query("SELECT * FROM body_metric_definitions WHERE id = :id") fun metric(id: String): BodyMetricDefinitionEntity?
    @Insert fun insert(row: BodyMetricDefinitionEntity)
    @Update fun update(row: BodyMetricDefinitionEntity): Int
    @Query("SELECT * FROM body_measurements WHERE studentID = :student AND metricID = :metric ORDER BY localCalendarDay, id") fun history(student: String, metric: String): List<BodyMeasurementEntity>
    @Query("SELECT * FROM body_measurements WHERE studentID = :student ORDER BY localCalendarDay DESC, id") fun allMeasurements(student: String): List<BodyMeasurementEntity>
    @Query("SELECT * FROM body_measurements WHERE studentID = :student AND metricID = :metric AND localCalendarDay = :day") fun onDay(student: String, metric: String, day: String): BodyMeasurementEntity?
    @Insert fun insert(row: BodyMeasurementEntity)
    @Update fun update(row: BodyMeasurementEntity): Int
    @Query("DELETE FROM body_measurements WHERE id = :id") fun deleteMeasurement(id: String): Int
    @Query("DELETE FROM body_measurements WHERE studentID = :student AND metricID = :metric") fun deleteAll(student: String, metric: String)
    @Query("SELECT count(*) FROM body_measurements WHERE metricID = :metric") fun measurementCount(metric: String): Int
    @Query("DELETE FROM body_metric_definitions WHERE id = :id") fun deleteMetric(id: String): Int
}
