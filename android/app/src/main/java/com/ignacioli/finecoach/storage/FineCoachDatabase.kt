package com.ignacioli.finecoach.storage

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(entities = [StoreMetadata::class], version = 1, exportSchema = true)
abstract class FineCoachDatabase : RoomDatabase() {
    abstract fun storeMetadataDao(): StoreMetadataDao
}
