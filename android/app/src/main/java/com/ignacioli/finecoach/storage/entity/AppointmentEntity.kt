package com.ignacioli.finecoach.storage.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(tableName = "recurrence_series", primaryKeys = ["id"], indices = [Index("studentID")],
    foreignKeys = [ForeignKey(entity = StudentEntity::class, parentColumns = ["id"], childColumns = ["studentID"])])
data class RecurrenceSeriesEntity(
    val id: String, val studentID: String, val intervalDays: Int,
    val endDate: String?, val repeatCount: Int?, val defaultStartTime: String,
    val defaultDurationMinutes: Int, val defaultReminderEnabled: Boolean,
    val defaultReminderLeadMinutes: Int?, val status: String, val createdAtUTC: String, val updatedAtUTC: String,
)

@Entity(tableName = "appointments", primaryKeys = ["id"],
    indices = [Index("studentID"), Index("seriesID"), Index("date"), Index("linkedSessionID")],
    foreignKeys = [
        ForeignKey(entity = StudentEntity::class, parentColumns = ["id"], childColumns = ["studentID"]),
        ForeignKey(entity = RecurrenceSeriesEntity::class, parentColumns = ["id"], childColumns = ["seriesID"]),
        ForeignKey(entity = SessionEntity::class, parentColumns = ["id"], childColumns = ["linkedSessionID"], onDelete = ForeignKey.SET_NULL),
    ])
data class AppointmentEntity(
    val id: String, val studentID: String, val seriesID: String?, val date: String, val startTime: String,
    val durationMinutes: Int, val status: String, val absentCreditChoice: String?, val cancellationReason: String?,
    val isDetachedException: Boolean, val reminderEnabled: Boolean, val reminderLeadMinutes: Int?,
    val linkedSessionID: String?, val trainingFocus: String, val createdAtUTC: String, val updatedAtUTC: String,
)
