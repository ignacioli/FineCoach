package com.ignacioli.finecoach.storage

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "store_metadata")
data class StoreMetadata(
    @PrimaryKey val key: String,
    val value: String,
)
