package com.ignacioli.finecoach.storage.migration
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
val MIGRATION_3_4 = object : Migration(3, 4) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS `body_metric_definitions` (`id` TEXT NOT NULL, `studentID` TEXT, `kind` TEXT NOT NULL, `name` TEXT NOT NULL, `unitRuleKind` TEXT NOT NULL, `currentUnit` TEXT NOT NULL, `lifecycle` TEXT NOT NULL, `createdAtUTC` TEXT NOT NULL, `updatedAtUTC` TEXT NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`studentID`) REFERENCES `students`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_body_metric_definitions_studentID` ON `body_metric_definitions` (`studentID`)")
        db.execSQL("CREATE TABLE IF NOT EXISTS `body_measurements` (`id` TEXT NOT NULL, `studentID` TEXT NOT NULL, `metricID` TEXT NOT NULL, `localCalendarDay` TEXT NOT NULL, `value` TEXT NOT NULL, `enteredUnit` TEXT NOT NULL, `createdAtUTC` TEXT NOT NULL, `updatedAtUTC` TEXT NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`studentID`) REFERENCES `students`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE, FOREIGN KEY(`metricID`) REFERENCES `body_metric_definitions`(`id`) ON UPDATE NO ACTION ON DELETE RESTRICT)")
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_body_measurements_studentID_metricID_localCalendarDay` ON `body_measurements` (`studentID`, `metricID`, `localCalendarDay`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_body_measurements_metricID` ON `body_measurements` (`metricID`)")
    }
}
