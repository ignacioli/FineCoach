package com.ignacioli.finecoach.storage.migration

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory

// v1 contains only store_metadata. Never rebuild it or import Core Data's history.
val MIGRATION_1_2: Migration = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `students` (
                `id` TEXT NOT NULL,
                `displayName` TEXT NOT NULL,
                `sex` TEXT NOT NULL,
                `trainingGoal` TEXT,
                `injuryNotes` TEXT,
                `privateCoachNote` TEXT,
                `phone` TEXT,
                `wechatID` TEXT,
                `lifecycle` TEXT NOT NULL,
                `createdAtUTC` TEXT NOT NULL,
                `updatedAtUTC` TEXT NOT NULL,
                PRIMARY KEY(`id`)
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_students_lifecycle` ON `students` (`lifecycle`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `course_packages` (
                `id` TEXT NOT NULL,
                `studentID` TEXT NOT NULL,
                `name` TEXT,
                `totalCredits` INTEGER NOT NULL,
                `remainingCreditsCache` INTEGER NOT NULL,
                `startDate` TEXT,
                `endDate` TEXT,
                `status` TEXT NOT NULL,
                `createdAtUTC` TEXT NOT NULL,
                `updatedAtUTC` TEXT NOT NULL,
                PRIMARY KEY(`id`)
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_course_packages_studentID` ON `course_packages` (`studentID`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `active_package_claims` (
                `studentID` TEXT NOT NULL,
                `packageID` TEXT NOT NULL,
                PRIMARY KEY(`studentID`)
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_active_package_claims_packageID` ON `active_package_claims` (`packageID`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `credit_adjustments` (
                `id` TEXT NOT NULL,
                `packageID` TEXT NOT NULL,
                `direction` TEXT NOT NULL,
                `amount` INTEGER NOT NULL,
                `reasonKind` TEXT NOT NULL,
                `reasonText` TEXT,
                `linkedSessionID` TEXT,
                `linkedAppointmentID` TEXT,
                `sourceEventKey` TEXT NOT NULL,
                `createdAtUTC` TEXT NOT NULL,
                PRIMARY KEY(`id`),
                FOREIGN KEY(`packageID`) REFERENCES `course_packages`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_credit_adjustments_packageID` ON `credit_adjustments` (`packageID`)")
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_credit_adjustments_sourceEventKey` ON `credit_adjustments` (`sourceEventKey`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `sessions` (
                `id` TEXT NOT NULL,
                `studentID` TEXT NOT NULL,
                `state` TEXT NOT NULL,
                `startedAtUTC` TEXT NOT NULL,
                `lastCheckpointUTC` TEXT NOT NULL,
                `elapsedSeconds` TEXT NOT NULL,
                `interruptionStartedAtUTC` TEXT,
                `durationNeedsReview` INTEGER NOT NULL,
                `coachAdjustedDurationSeconds` TEXT,
                `studentFacingSummary` TEXT,
                `privateCoachNote` TEXT,
                `revision` TEXT NOT NULL,
                `createdAtUTC` TEXT NOT NULL,
                `updatedAtUTC` TEXT NOT NULL,
                `completedAtUTC` TEXT,
                `appointmentID` TEXT,
                `creditSettlementNote` TEXT,
                PRIMARY KEY(`id`),
                FOREIGN KEY(`studentID`) REFERENCES `students`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_sessions_studentID` ON `sessions` (`studentID`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_sessions_state` ON `sessions` (`state`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `active_session_pointers` (
                `key` TEXT NOT NULL,
                `sessionID` TEXT NOT NULL,
                PRIMARY KEY(`key`)
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_active_session_pointers_sessionID` ON `active_session_pointers` (`sessionID`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `session_training_focus` (
                `sessionID` TEXT NOT NULL,
                `bodyPart` TEXT NOT NULL,
                PRIMARY KEY(`sessionID`, `bodyPart`),
                FOREIGN KEY(`sessionID`) REFERENCES `sessions`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `session_exercises` (
                `id` TEXT NOT NULL,
                `sessionID` TEXT NOT NULL,
                `orderIndex` INTEGER NOT NULL,
                `sourceKind` TEXT NOT NULL,
                `sourceID` TEXT,
                `displayNameSnapshot` TEXT NOT NULL,
                `recordModeSnapshot` TEXT NOT NULL,
                `actionPrivateNote` TEXT,
                `sectionID` TEXT,
                PRIMARY KEY(`id`),
                FOREIGN KEY(`sessionID`) REFERENCES `sessions`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_session_exercises_sessionID_orderIndex` ON `session_exercises` (`sessionID`, `orderIndex`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_session_exercises_sectionID` ON `session_exercises` (`sectionID`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `training_sets` (
                `id` TEXT NOT NULL,
                `sessionExerciseID` TEXT NOT NULL,
                `orderIndex` INTEGER NOT NULL,
                `state` TEXT NOT NULL,
                `recordMode` TEXT NOT NULL,
                `weightValue` TEXT,
                `repetitionCount` TEXT,
                `durationSeconds` TEXT,
                `leftValue` TEXT,
                `rightValue` TEXT,
                `distanceValue` TEXT,
                `speedValue` TEXT,
                `resistanceValue` TEXT,
                `unit` TEXT NOT NULL,
                `side` TEXT NOT NULL,
                `createdAtUTC` TEXT NOT NULL,
                `updatedAtUTC` TEXT NOT NULL,
                `completedAtUTC` TEXT,
                PRIMARY KEY(`id`),
                FOREIGN KEY(`sessionExerciseID`) REFERENCES `session_exercises`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_training_sets_sessionExerciseID_orderIndex` ON `training_sets` (`sessionExerciseID`, `orderIndex`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `training_templates` (
                `id` TEXT NOT NULL,
                `name` TEXT NOT NULL,
                `revision` TEXT NOT NULL,
                `createdAtUTC` TEXT NOT NULL,
                `updatedAtUTC` TEXT NOT NULL,
                PRIMARY KEY(`id`)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `template_training_focus` (
                `templateID` TEXT NOT NULL,
                `bodyPart` TEXT NOT NULL,
                PRIMARY KEY(`templateID`, `bodyPart`),
                FOREIGN KEY(`templateID`) REFERENCES `training_templates`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `template_exercises` (
                `id` TEXT NOT NULL,
                `templateID` TEXT NOT NULL,
                `sectionID` TEXT,
                `orderIndex` INTEGER NOT NULL,
                `sourceKind` TEXT NOT NULL,
                `sourceID` TEXT,
                `displayNameSnapshot` TEXT NOT NULL,
                `recordModeSnapshot` TEXT NOT NULL,
                PRIMARY KEY(`id`),
                FOREIGN KEY(`templateID`) REFERENCES `training_templates`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_template_exercises_templateID_orderIndex` ON `template_exercises` (`templateID`, `orderIndex`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_template_exercises_sectionID` ON `template_exercises` (`sectionID`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `template_planned_sets` (
                `templateExerciseID` TEXT NOT NULL,
                `position` INTEGER NOT NULL,
                `recordMode` TEXT NOT NULL,
                `unit` TEXT NOT NULL,
                `side` TEXT NOT NULL,
                `weightValue` TEXT,
                `repetitionCount` TEXT,
                `durationSeconds` TEXT,
                `leftValue` TEXT,
                `rightValue` TEXT,
                `distanceValue` TEXT,
                `speedValue` TEXT,
                `resistanceValue` TEXT,
                PRIMARY KEY(`templateExerciseID`, `position`),
                FOREIGN KEY(`templateExerciseID`) REFERENCES `template_exercises`(`id`) ON UPDATE NO ACTION ON DELETE NO ACTION
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `session_sections` (
                `id` TEXT NOT NULL,
                `ownerKind` TEXT NOT NULL,
                `ownerID` TEXT NOT NULL,
                `name` TEXT NOT NULL,
                `orderIndex` INTEGER NOT NULL,
                PRIMARY KEY(`id`)
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_session_sections_ownerKind_ownerID_orderIndex` ON `session_sections` (`ownerKind`, `ownerID`, `orderIndex`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `exercise_catalog` (
                `id` TEXT NOT NULL,
                `kind` TEXT NOT NULL,
                `canonicalName` TEXT NOT NULL,
                `normalizedName` TEXT NOT NULL,
                `recordMode` TEXT NOT NULL,
                `metadataVersion` TEXT NOT NULL,
                `lifecycle` TEXT NOT NULL,
                `isRetired` INTEGER NOT NULL,
                `provenanceRef` TEXT,
                `createdAtUTC` TEXT NOT NULL,
                `updatedAtUTC` TEXT NOT NULL,
                PRIMARY KEY(`id`)
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_exercise_catalog_normalizedName` ON `exercise_catalog` (`normalizedName`)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `exercise_preferences` (
                `exerciseID` TEXT NOT NULL,
                `alias` TEXT,
                `isFavorite` INTEGER NOT NULL,
                `isHidden` INTEGER NOT NULL,
                `isAssisted` INTEGER NOT NULL,
                `isUnilateral` INTEGER,
                PRIMARY KEY(`exerciseID`)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `exercise_name_claims` (
                `normalizedName` TEXT NOT NULL,
                `ownerKind` TEXT NOT NULL,
                `ownerID` TEXT NOT NULL,
                `scope` TEXT NOT NULL,
                PRIMARY KEY(`normalizedName`)
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_exercise_name_claims_ownerKind_ownerID` ON `exercise_name_claims` (`ownerKind`, `ownerID`)")
        FineCoachDatabaseFactory.initializeGeneration(db)
    }
}
