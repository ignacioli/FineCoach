package com.ignacioli.finecoach

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class StoragePrivacyTests {
    @Test fun productionSourcesAndBuildScriptsHaveNoStorageRelaxations() {
        val project = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))
        require(project.isDirectory)
        val sources = listOf("main", "debug", "release").flatMap { variant ->
            File(project, "src/$variant").walkTopDown()
                .filter { it.isFile && it.extension in setOf("kt", "java") }.toList()
        }
        require(sources.isNotEmpty())
        val builds = listOf(File(project, "build.gradle.kts"), File(project.parentFile, "build.gradle.kts"),
            File(project.parentFile, "settings.gradle.kts"))
        require(builds.all { it.isFile })
        val forbidden = listOf(
            "fallbackToDestructiveMigration", "allowMainThreadQueries", "openHelperFactory",
            "createFromAsset", "createFromFile", "createFromInputStream", "setQueryCallback",
        )
        (sources + builds).forEach { file ->
            val source = file.readText()
            forbidden.forEach { assertFalse("Storage relaxation in ${file.name}: $it", source.contains(it)) }
        }
        val storage = sources.filter { it.invariantSeparatorsPath.contains("/storage/") }
        require(storage.isNotEmpty())
        storage.forEach { file ->
            assertFalse("Binary floating point in storage: ${file.name}", Regex("\\b(Double|Float)\\b").containsMatchIn(file.readText()))
        }
    }

    @Test fun databaseFileIsCredentialPrivateAndOutsideCacheAndExternalStorage() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val worker = Executors.newSingleThreadExecutor()
        try {
            worker.submit(Callable {
                val database = FineCoachDatabaseFactory.create(context)
                try {
                    database.openHelper.writableDatabase
                    val path = context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME).canonicalFile
                    assertTrue(path.isFile)
                    assertEquals(path.path, File(requireNotNull(database.openHelper.databaseName)).canonicalPath)
                    assertEquals(File(context.dataDir, "databases").canonicalFile, path.parentFile)
                    assertFalse(context.isDeviceProtectedStorage)
                    val forbiddenRoots = listOfNotNull(context.cacheDir, context.codeCacheDir,
                        context.externalCacheDir, context.getExternalFilesDir(null),
                        context.createDeviceProtectedStorageContext().dataDir)
                    forbiddenRoots.forEach { root ->
                        val forbidden = root.canonicalPath
                        assertFalse(path.path == forbidden || path.path.startsWith(forbidden + File.separator))
                    }
                } finally {
                    database.close()
                }
            }).get(30, TimeUnit.SECONDS)
        } finally {
            worker.shutdownNow()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    @Test fun deviceProtectedContextIsRejectedBeforeDatabaseCreation() {
        val context = ApplicationProvider.getApplicationContext<Context>().createDeviceProtectedStorageContext()
        assertTrue(context.isDeviceProtectedStorage)
        val path = context.getDatabasePath(FineCoachDatabaseFactory.DATABASE_NAME)
        assertFalse(path.exists())
        assertThrows(IllegalArgumentException::class.java) { FineCoachDatabaseFactory.create(context) }
        assertFalse(path.exists())
    }
}
