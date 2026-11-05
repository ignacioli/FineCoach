package com.ignacioli.finecoach.storage

import android.content.Context
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import com.ignacioli.finecoach.storage.value.StorageValueConverters
import java.time.Instant

object FineCoachDatabaseFactory {
    const val DATABASE_NAME = "finecoach.db"
    const val CREATED_AT_KEY = "created_at"

    // Blocking DAO operations must be called off the main thread. The caller
    // owns the database lifetime; no automatic open occurs in the app shell.
    fun create(context: Context): FineCoachDatabase {
        require(!context.isDeviceProtectedStorage) { "Credential-protected storage required" }
        val application = context.applicationContext
        require(!application.isDeviceProtectedStorage) { "Credential-protected storage required" }
        val path = application.getDatabasePath(DATABASE_NAME)
        return Room.databaseBuilder(application, FineCoachDatabase::class.java, path.absolutePath)
            .addCallback(object : RoomDatabase.Callback() {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL(
                        "INSERT INTO store_metadata (`key`, value) VALUES (?, ?)",
                        arrayOf(CREATED_AT_KEY, StorageValueConverters().instantToString(Instant.now())),
                    )
                }
            })
            .build()
    }
}
