package com.ignacioli.finecoach.storage

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface StoreMetadataDao {
    @Query("SELECT * FROM store_metadata WHERE `key` = :key")
    fun find(key: String): StoreMetadata?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    fun insert(metadata: StoreMetadata)
}
