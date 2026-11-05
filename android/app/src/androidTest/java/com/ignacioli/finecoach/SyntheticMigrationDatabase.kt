package com.ignacioli.finecoach

import androidx.room.ColumnInfo
import androidx.room.Database
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Entity(tableName = "synthetic_probe")
internal data class SyntheticProbeV1(@PrimaryKey val id: Long, val label: String)

@Entity(tableName = "synthetic_probe")
internal data class SyntheticProbeV2(
    @PrimaryKey val id: Long,
    val label: String,
    @ColumnInfo(name = "fictional_rank", defaultValue = "7") val fictionalRank: Int = 7,
)

@Database(entities = [SyntheticProbeV1::class], version = 1, exportSchema = true)
internal abstract class SyntheticMigrationDatabaseV1 : RoomDatabase()

/** Test-only compiler exports, unrelated to the app storage schema. */
@Database(entities = [SyntheticProbeV2::class], version = 2, exportSchema = true)
internal abstract class SyntheticMigrationDatabase : RoomDatabase() {
    companion object {
        const val V1_SCHEMA_FOLDER = "com.ignacioli.finecoach.SyntheticMigrationDatabaseV1"
        const val SCHEMA_FOLDER = "com.ignacioli.finecoach.SyntheticMigrationDatabase"
        const val V1 = 1
        const val V2 = 2

        // No generated implementation is instantiated by the schema-backed helper.
        val migration1To2 = object : Migration(V1, V2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `synthetic_probe` ADD COLUMN `fictional_rank` INTEGER NOT NULL DEFAULT 7")
            }
        }
    }
}
