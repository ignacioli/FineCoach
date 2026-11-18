package com.ignacioli.finecoach.storage.migration

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

val MIGRATION_2_3: Migration = object : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("""CREATE TABLE IF NOT EXISTS `recurrence_series` (
            `id` TEXT NOT NULL, `studentID` TEXT NOT NULL, `intervalDays` INTEGER NOT NULL,
            `endDate` TEXT, `repeatCount` INTEGER, `defaultStartTime` TEXT NOT NULL,
            `defaultDurationMinutes` INTEGER NOT NULL, `defaultReminderEnabled` INTEGER NOT NULL,
            `defaultReminderLeadMinutes` INTEGER, `status` TEXT NOT NULL, `createdAtUTC` TEXT NOT NULL,
            `updatedAtUTC` TEXT NOT NULL, PRIMARY KEY(`id`),
            FOREIGN KEY(`studentID`) REFERENCES `students`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION)""")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_recurrence_series_studentID` ON `recurrence_series` (`studentID`)")
        db.execSQL("""CREATE TABLE IF NOT EXISTS `appointments` (
            `id` TEXT NOT NULL, `studentID` TEXT NOT NULL, `seriesID` TEXT, `date` TEXT NOT NULL,
            `startTime` TEXT NOT NULL, `durationMinutes` INTEGER NOT NULL, `status` TEXT NOT NULL,
            `absentCreditChoice` TEXT, `cancellationReason` TEXT, `isDetachedException` INTEGER NOT NULL,
            `reminderEnabled` INTEGER NOT NULL, `reminderLeadMinutes` INTEGER, `linkedSessionID` TEXT,
            `trainingFocus` TEXT NOT NULL, `createdAtUTC` TEXT NOT NULL, `updatedAtUTC` TEXT NOT NULL,
            PRIMARY KEY(`id`),
            FOREIGN KEY(`studentID`) REFERENCES `students`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION,
            FOREIGN KEY(`seriesID`) REFERENCES `recurrence_series`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION,
            FOREIGN KEY(`linkedSessionID`) REFERENCES `sessions`(`id`) ON UPDATE NO ACTION ON DELETE SET NULL)""")
        for (column in listOf("studentID", "seriesID", "date")) db.execSQL("CREATE INDEX IF NOT EXISTS `index_appointments_${column}` ON `appointments` (`$column`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_appointments_linkedSessionID` ON `appointments` (`linkedSessionID`)")
        installAppointmentIntegrity(db)
    }
}

internal const val STUDENT_DELETION_SCOPE_KEY = "s2.deletingStudent"

/** Triggers add forward-reference semantics without rebuilding any S1 table or dropping legacy rows. */
fun installAppointmentIntegrity(db: SupportSQLiteDatabase) {
    for ((table, column) in listOf("sessions" to "appointmentID", "credit_adjustments" to "linkedAppointmentID")) {
        for (event in listOf("INSERT", "UPDATE OF `$column`")) {
            val suffix = if (event == "INSERT") "insert" else "update"
            db.execSQL("""CREATE TRIGGER IF NOT EXISTS `${table}_appointment_$suffix` BEFORE $event ON `$table`
                WHEN NEW.`$column` IS NOT NULL AND NOT EXISTS (SELECT 1 FROM appointments WHERE id = NEW.`$column`)
                BEGIN SELECT RAISE(ABORT, 'Invalid appointment reference'); END""")
        }
    }
    db.execSQL("""CREATE TRIGGER IF NOT EXISTS appointments_restrict_delete BEFORE DELETE ON appointments
        WHEN (EXISTS (SELECT 1 FROM sessions WHERE appointmentID = OLD.id)
          OR EXISTS (SELECT 1 FROM credit_adjustments WHERE linkedAppointmentID = OLD.id))
          AND NOT EXISTS (SELECT 1 FROM store_metadata WHERE `key` = '$STUDENT_DELETION_SCOPE_KEY' AND value = OLD.studentID)
        BEGIN SELECT RAISE(ABORT, 'Appointment is referenced'); END""")
}
