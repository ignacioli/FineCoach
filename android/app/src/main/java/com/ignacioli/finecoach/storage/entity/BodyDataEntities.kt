package com.ignacioli.finecoach.storage.entity

import androidx.room.*

@Entity(tableName = "body_metric_definitions", foreignKeys = [ForeignKey(entity = StudentEntity::class, parentColumns = ["id"], childColumns = ["studentID"], onDelete = ForeignKey.CASCADE)], indices = [Index("studentID")])
data class BodyMetricDefinitionEntity(
    @PrimaryKey val id: String, val studentID: String?, val kind: String, val name: String,
    val unitRuleKind: String, val currentUnit: String, val lifecycle: String,
    val createdAtUTC: String, val updatedAtUTC: String,
) { override fun toString() = "BodyMetricDefinitionEntity(redacted)" }

@Entity(tableName = "body_measurements", foreignKeys = [
    ForeignKey(entity = StudentEntity::class, parentColumns = ["id"], childColumns = ["studentID"], onDelete = ForeignKey.CASCADE),
    ForeignKey(entity = BodyMetricDefinitionEntity::class, parentColumns = ["id"], childColumns = ["metricID"], onDelete = ForeignKey.RESTRICT),
], indices = [Index(value = ["studentID", "metricID", "localCalendarDay"], unique = true), Index("metricID")])
data class BodyMeasurementEntity(
    @PrimaryKey val id: String, val studentID: String, val metricID: String, val localCalendarDay: String,
    val value: String, val enteredUnit: String, val createdAtUTC: String, val updatedAtUTC: String,
) { override fun toString() = "BodyMeasurementEntity(redacted)" }
