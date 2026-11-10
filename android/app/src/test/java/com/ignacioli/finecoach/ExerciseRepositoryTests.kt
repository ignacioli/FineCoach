package com.ignacioli.finecoach

import android.content.Context
import com.ignacioli.finecoach.features.exercises.*
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.*
import com.ignacioli.finecoach.storage.entity.*
import com.ignacioli.finecoach.storage.repository.ExerciseRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

/** fictional-data: all custom exercises, session and template owners are invented. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ExerciseRepositoryTests {
    private lateinit var context: Context
    private lateinit var database: FineCoachDatabase
    private lateinit var repository: ExerciseRepository
    private lateinit var loader: ExerciseCatalogLoader
    private val now = Instant.parse("2026-11-06T08:09:10Z")
    private val clock = AppClock { now }
    private fun id(value: String) = StableExerciseID.parse(value)
    private fun uuid(n: Int) = UUID.fromString("00000000-0000-4000-8000-${n.toString().padStart(12, '0')}")
    private fun custom(value: String = "fictional-one", name: String = "虚构动作") = ExerciseRecord(id(value),
        ExerciseKind.custom, name, RecordMode.weightReps, "custom.1", ExerciseLifecycle.active, false, null, now, now)
    private fun <T> ok(result: ApplicationResult<T>): T {
        assertTrue("Expected success, got $result", result is ApplicationResult.Success)
        return (result as ApplicationResult.Success).value
    }
    private fun failure(code: ApplicationErrorCode, result: ApplicationResult<*>) {
        assertEquals(code, (result as ApplicationResult.Failure).error.code)
    }
    private fun reopen() {
        database.close()
        database = FineCoachDatabaseFactory.create(context)
        repository = ExerciseRepository(database, loader, clock)
    }
    private fun preference(item: ExerciseRecord, alias: String? = null, hidden: Boolean = false) =
        UpdateExercisePreferenceCommand(item.exerciseID, alias, true, hidden, true, false)

    @Before fun prepare() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        loader = ExerciseCatalogLoader(context.assets)
        database = FineCoachDatabaseFactory.create(context)
        repository = ExerciseRepository(database, loader, clock)
    }
    @After fun cleanUp() = runBlocking {
        withContext(Dispatchers.IO) { database.close() }
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        Unit
    }

    @Test fun metadataReadFailureKeepsLastSuccessfulFacetsAndReportsUnavailableUntilRecovery() = runBlocking {
        var failRead = false
        repository = ExerciseRepository(database, loader, clock) {
            if (failRead) throw java.io.IOException("fictional catalog read failure")
            loader.load(now)
        }
        ok(repository.synchronizeCatalog())
        val initial = ok(repository.search("胸"))
        val metadata = repository.browseMetadata
        assertTrue(metadata.isNotEmpty()); assertFalse(repository.browseMetadataUnavailable)
        failRead = true
        assertEquals(initial, ok(repository.search("胸")))
        assertEquals(metadata, repository.browseMetadata)
        assertTrue(repository.browseMetadataUnavailable)
        failRead = false
        assertEquals(initial, ok(repository.search("胸")))
        assertFalse(repository.browseMetadataUnavailable)
    }

    @Test fun browseCombinesSearchMuscleEquipmentAndPreservesCanonicalOrderingAndCounts() = runBlocking {
        ok(repository.synchronizeCatalog())
        val all = ok(repository.search(""))
        val metadata = repository.browseMetadata
        val custom = ok(repository.saveCustom(custom()))
        val entries = ok(repository.search(""))
        val sections = ExerciseBrowse.sections(entries, metadata, null, null)
        assertEquals("custom", sections.first().id)
        assertEquals(listOf(custom), sections.first().entries)
        assertEquals(ExerciseBrowse.muscles, sections.drop(1).map { it.id })
        assertEquals(all.size + 1, sections.sumOf { it.entries.size })
        for (muscle in ExerciseBrowse.muscles) {
            val expected = all.filter { metadata[it.exerciseID]?.primaryMuscleGroup == muscle }
            assertEquals(listOf(ExerciseBrowse.Section(muscle, expected)), ExerciseBrowse.sections(entries, metadata, muscle, null))
        }
        for (equipment in ExerciseBrowse.equipment) {
            val filtered = ExerciseBrowse.sections(entries, metadata, null, equipment).flatMap { it.entries }
            assertEquals(all.filter { metadata[it.exerciseID]?.equipmentClass == equipment }.map { it.exerciseID }.toSet(), filtered.map { it.exerciseID }.toSet())
        }
        val searched = ok(repository.search("wo tui"))
        val combined = ExerciseBrowse.sections(searched, metadata, "胸", "杠铃").single().entries
        val expected = all.filter { it.canonicalName.contains("卧推") && metadata[it.exerciseID]?.primaryMuscleGroup == "胸" && metadata[it.exerciseID]?.equipmentClass == "杠铃" }
        assertTrue(expected.isNotEmpty()); assertEquals(expected, combined)
        assertEquals(listOf(ExerciseBrowse.Section("uncategorized", listOf(all.first()))), ExerciseBrowse.sections(listOf(all.first()), emptyMap(), null, null))
    }

    @Test fun includeHiddenKeepsPinyinAliasEquipmentAndRetirementSearchRules() = runBlocking {
        ok(repository.synchronizeCatalog())
        val item = ok(repository.search("杠铃平板卧推")).single()
        ok(repository.updatePreference(preference(item, alias = "虚构卧推别名", hidden = true)))
        assertTrue(ok(repository.search("杠铃平板卧推")).isEmpty())
        for (query in listOf("gang ling ping ban wo tui", "虚构卧推别名", "杠铃", "胸", "  杠铃平板卧推  ")) {
            assertTrue("Hidden result must match $query", item in ok(repository.search(query, true)))
        }
        assertFalse(ok(repository.search("不存在的虚构词", true)).contains(item))
        assertTrue(ok(repository.search("", true)).none { it.isRetired || it.lifecycle != ExerciseLifecycle.active })
        val archived = ok(repository.saveCustom(custom("fictional-archived", "虚构深蹲")))
        ok(repository.saveCustom(archived.copy(lifecycle = ExerciseLifecycle.archived)))
        assertTrue(ok(repository.search("xu gou shen dun")).isEmpty())
        assertEquals(archived.exerciseID, ok(repository.search("xu gou shen dun", true)).single().exerciseID)
        ok(repository.saveCustom(archived))
        // A displayed alias does not reorder canonical catalog rows.

        assertEquals(ok(repository.search("", true)).map { it.exerciseID }, ok(repository.listCatalog()).filter { !it.isRetired }.map { it.exerciseID })
    }

    @Test fun recentSelectionOrdersCompletedSessionsDeduplicatesScopesAndExcludesUnavailableSources() {
        val items = (1..9).map { custom("fictional-$it", "虚构动作$it") }
        fun content(n: Int, student: Int, ids: List<Int>, completed: Boolean = true): SessionContentRecord {
            val time = now.plusSeconds(n.toLong())
            val sessionID = SessionID.fromUUID(uuid(n))
            val record = SessionRecord(sessionID, StudentID.fromUUID(uuid(student)), if (completed) SessionState.completed else SessionState.inProgress,
                now, time, BigDecimal.TEN, null, false, null, emptySet(), null, null, Revision(1u), now, time, if (completed) time else null)
            return SessionContentRecord(record, emptyList(), ids.mapIndexed { index, id ->
                SessionExerciseRecord(SessionExerciseID.fromUUID(uuid(n * 100 + index)), sessionID, index.toUInt(),
                    if (id == 9) ExerciseSourceKind.sessionOnly else ExerciseSourceKind.custom, items[id - 1].exerciseID,
                    "虚构历史显示名", RecordMode.weightReps, null, null, emptyList())
            })
        }
        val available = items.mapIndexed { index, item -> when (index) {
            5 -> item.copy(lifecycle = ExerciseLifecycle.archived)
            6 -> item.copy(isRetired = true)
            else -> item
        } }
        val prefs = mapOf(items[7].exerciseID to ExercisePreferenceRecord(items[7].exerciseID, null, false, true, false, null))
        val history = listOf(content(1, 20, listOf(1, 2, 3, 4, 5)), content(2, 21, listOf(6, 7, 8, 9, 2, 1)), content(3, 20, listOf(4), false))
        assertEquals(listOf(items[1], items[0], items[2], items[3], items[4]), ExerciseBrowse.recent(history, available, prefs))
        assertEquals(items.take(5), ExerciseBrowse.recent(history, available, prefs, StudentID.fromUUID(uuid(20))))
        assertEquals(listOf(items[1], items[0]), ExerciseBrowse.recent(history, available, prefs, StudentID.fromUUID(uuid(21))))
        assertTrue(ExerciseBrowse.recent(history, available, prefs, limit = 0).isEmpty())
        assertTrue(ExerciseBrowse.recent(history, emptyList(), prefs).isEmpty())
        val recent = ExerciseBrowse.recent(history, available, prefs)
        val unreadOlder = content(0, 20, listOf(1)).copy(exercises = object : AbstractList<SessionExerciseRecord>() {
            override val size: Int get() = throw AssertionError("Older session content must not be expanded after reaching the limit")
            override fun get(index: Int): SessionExerciseRecord = throw AssertionError("Older session must remain unread")
        })
        assertEquals(listOf(items[1]), ExerciseBrowse.recent(history + unreadOlder, available, prefs, limit = 1))
        assertTrue(ExerciseBrowse.showsRecent(" \n", null, null, recent))
        assertFalse(ExerciseBrowse.showsRecent("卧推", null, null, recent))
        assertFalse(ExerciseBrowse.showsRecent("", "胸", null, recent))
        assertFalse(ExerciseBrowse.showsRecent("", null, "杠铃", recent))
        assertFalse(ExerciseBrowse.showsRecent("", null, null, emptyList()))
    }

    @Test fun customAndAllPreferencesSurviveRealFileDatabaseReopen() = runBlocking {
        val saved = ok(repository.saveCustom(custom(name = "  虚构动作  ")))
        assertEquals("虚构动作", saved.canonicalName)
        val expected = ok(repository.updatePreference(preference(saved, "虚构别名")))
        reopen()
        assertEquals(listOf(saved), ok(repository.listCatalog()))
        assertEquals(expected, ok(repository.preference(saved.exerciseID)))
        assertEquals(listOf(saved), ok(repository.search("虚构别名")))
    }

    @Test fun duplicateNamesConflictAcrossOwnersAndScopesWithoutPartialWrites() = runBlocking {
        val first = ok(repository.saveCustom(custom()))
        failure(ApplicationErrorCode.conflict, repository.saveCustom(custom("fictional-two")))
        failure(ApplicationErrorCode.conflict, repository.renameClaim(id("fictional-local"), first.canonicalName,
            ExerciseClaimScope.currentSession))
        assertEquals(listOf(first), ok(repository.listCatalog()))
        assertEquals(first.exerciseID.value, database.s1Dao().let { dao ->
            withContext(Dispatchers.IO) { dao.findExerciseNameClaim(first.canonicalName)?.ownerID }
        })
    }

    @Test fun sessionOnlyClaimIsIdempotentRenamableAndNeverCreatesCatalogRow() = runBlocking {
        val owner = id("fictional-local")
        repeat(2) { ok(repository.renameClaim(owner, "虚构临时动作", ExerciseClaimScope.currentSession)) }
        ok(repository.renameClaim(owner, "虚构临时新名", ExerciseClaimScope.currentSession))
        assertTrue(ok(repository.listCatalog()).isEmpty())
        withContext(Dispatchers.IO) {
            assertNull(database.s1Dao().findExerciseNameClaim("虚构临时动作"))
            assertEquals(ExerciseSourceKind.sessionOnly, database.s1Dao().findExerciseNameClaim("虚构临时新名")?.ownerKind)
        }
        failure(ApplicationErrorCode.conflict, repository.saveCustom(custom(name = "虚构临时新名")))
        failure(ApplicationErrorCode.notFound, repository.renameClaim(owner, "虚构临时新名", ExerciseClaimScope.activeCatalog))
    }

    @Test fun conflictingRenameRollsBackOldRowAndClaim() = runBlocking {
        val first = ok(repository.saveCustom(custom()))
        ok(repository.saveCustom(custom("fictional-two", "虚构其他动作")))
        failure(ApplicationErrorCode.conflict, repository.saveCustom(first.copy(canonicalName = "虚构其他动作")))
        reopen()
        assertEquals(first, ok(repository.listCatalog()).first { it.exerciseID == first.exerciseID })
        withContext(Dispatchers.IO) {
            assertEquals(first.exerciseID.value, database.s1Dao().findExerciseNameClaim(first.canonicalName)?.ownerID)
        }
    }

    @Test fun archiveReleasesNameRestoreChecksConflictAndHiddenDoesNotRelease() = runBlocking {
        val first = ok(repository.saveCustom(custom()))
        ok(repository.updatePreference(preference(first, hidden = true)))
        assertTrue(ok(repository.search("")).isEmpty())
        failure(ApplicationErrorCode.conflict, repository.saveCustom(custom("fictional-two")))
        val archived = ok(repository.saveCustom(first.copy(lifecycle = ExerciseLifecycle.archived)))
        val second = ok(repository.saveCustom(custom("fictional-two")))
        failure(ApplicationErrorCode.conflict, repository.saveCustom(archived.copy(lifecycle = ExerciseLifecycle.active)))
        ok(repository.saveCustom(second.copy(lifecycle = ExerciseLifecycle.archived)))
        ok(repository.saveCustom(archived.copy(lifecycle = ExerciseLifecycle.active)))
        ok(repository.updatePreference(preference(first, hidden = false)))
        assertEquals(first.exerciseID, ok(repository.search("")).single().exerciseID)
    }

    @Test fun aliasNormalizationClearingAndUnknownPreference() = runBlocking {
        val item = ok(repository.saveCustom(custom()))
        assertEquals("虚构别名", ok(repository.updatePreference(preference(item, "  虚构别名  "))).alias)
        assertNull(ok(repository.updatePreference(preference(item, "  "))).alias)
        assertNull(ok(repository.updatePreference(preference(item, null))).alias)
        failure(ApplicationErrorCode.notFound, repository.updatePreference(preference(custom("fictional-missing"))))
    }

    @Test fun invalidNamesAndBuiltInEditsAreRejected() = runBlocking {
        failure(ApplicationErrorCode.emptyText, repository.saveCustom(custom(name = "  ")))
        failure(ApplicationErrorCode.textTooLong, repository.saveCustom(custom(name = "字".repeat(100000))))
        ok(repository.synchronizeCatalog())
        val builtIn = ok(repository.listCatalog()).first()
        failure(ApplicationErrorCode.incompatibleInput, repository.saveCustom(builtIn))
        failure(ApplicationErrorCode.invalidState, repository.saveCustom(custom(builtIn.exerciseID.value)))
    }

    @Test fun assetCatalogAndPerItemLicenseAreCompleteAndByteIdentical() = runBlocking {
        val catalog = loader.load(now)
        assertEquals(542, catalog.records.size)
        assertEquals(catalog.records.size, catalog.provenance.size)
        assertEquals(catalog.records.size, catalog.metadata.size)
        catalog.records.forEach {
            val source = requireNotNull(catalog.provenance[it.provenanceRef])
            assertTrue(source.licenseText.isNotBlank() && source.attributionRequirement.isNotBlank())
        }
        val app = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))
        val copies = mapOf(ExerciseCatalogLoader.CATALOG_PATH to "ios/FineCoachApp/Resources/ExerciseCatalog/provenance.json",
            ExerciseCatalogLoader.LICENSE_PATH to "design/catalog-expansion/source/2026-10-17/out/SOURCES.md")
        copies.forEach { (asset, source) ->
            val bytes = context.assets.open(asset).use { it.readBytes() }
            assertArrayEquals(File(app, "../../$source").readBytes(), bytes)
            val relative = asset.removePrefix("exercises/")
            listOf("main/assets/exercises/", "assets/exercises/").forEach { prefix ->
                FictionalDataPolicy.validateFixture(prefix + relative, bytes)
                assertThrows(IllegalArgumentException::class.java) {
                    FictionalDataPolicy.validateFixture(prefix + relative, bytes + "changed".toByteArray())
                }
            }
            assertThrows(IllegalArgumentException::class.java) {
                FictionalDataPolicy.validateFixture("assets/exercises/unregistered.txt", bytes)
            }
        }
    }

    @Test fun failedLaunchWithoutCatalogIsUnavailableAndKeepsDatabaseUsable() = runBlocking {
        withContext(Dispatchers.IO) {
            database.openHelper.writableDatabase.execSQL("CREATE TRIGGER fictional_catalog_failure BEFORE INSERT ON exercise_catalog BEGIN SELECT RAISE(ABORT, 'fictional failure'); END")
        }
        repository.prepareCatalog()
        assertTrue(repository.catalogUnavailable)
        assertTrue(ok(repository.listCatalog()).isEmpty())
        withContext(Dispatchers.IO) { database.openHelper.writableDatabase.execSQL("DROP TRIGGER fictional_catalog_failure") }
        repository.prepareCatalog()
        assertFalse(repository.catalogUnavailable)
        assertEquals(542, ok(repository.listCatalog()).size)
    }

    @Test fun failedLaunchWithExistingCatalogSilentlyPreservesSearchAndStableRows() = runBlocking {
        repository.prepareCatalog()
        val before = ok(repository.listCatalog())
        withContext(Dispatchers.IO) {
            database.openHelper.writableDatabase.execSQL("CREATE TRIGGER fictional_catalog_failure BEFORE UPDATE ON exercise_catalog BEGIN SELECT RAISE(ABORT, 'fictional failure'); END")
        }
        repository.prepareCatalog()
        assertFalse(repository.catalogUnavailable)
        assertEquals(before, ok(repository.listCatalog()))
        assertTrue(ok(repository.search("杠铃平板卧推")).isNotEmpty())
    }

    @Test fun syncIsIdempotentPreservesPreferencesAndReopensWithSameStableIDs() = runBlocking {
        ok(repository.synchronizeCatalog())
        val original = ok(repository.listCatalog())
        val item = original.first { !it.isRetired }
        val pref = ok(repository.updatePreference(preference(item, "虚构目录别名")))
        ok(repository.synchronizeCatalog())
        reopen()
        assertEquals(original, ok(repository.listCatalog()))
        assertEquals(pref, ok(repository.preference(item.exerciseID)))
        assertEquals(item.exerciseID, ok(repository.search("虚构目录别名")).single().exerciseID)
    }

    @Test fun builtInNamesRejectNewCustomAndSessionClaims() = runBlocking {
        ok(repository.synchronizeCatalog())
        val builtIn = ok(repository.search("")).first()
        failure(ApplicationErrorCode.conflict, repository.saveCustom(custom(name = builtIn.canonicalName)))
        failure(ApplicationErrorCode.conflict, repository.renameClaim(id("fictional-local"), builtIn.canonicalName,
            ExerciseClaimScope.currentSession))
        failure(ApplicationErrorCode.invalidState, repository.renameClaim(builtIn.exerciseID, "虚构篡改",
            ExerciseClaimScope.activeCatalog))
    }

    @Test fun existingCustomClaimWinsSyncAndRenameImmediatelyRevealsBuiltIn() = runBlocking {
        val incoming = loader.load(now).records.first { !it.isRetired }
        val local = ok(repository.saveCustom(custom(name = incoming.canonicalName)))
        ok(repository.synchronizeCatalog())
        assertFalse(ok(repository.search("")).any { it.exerciseID == incoming.exerciseID })
        ok(repository.saveCustom(local.copy(canonicalName = "虚构改名动作")))
        assertTrue(ok(repository.search("")).any { it.exerciseID == incoming.exerciseID })
        withContext(Dispatchers.IO) {
            assertEquals(incoming.exerciseID.value, database.s1Dao().findExerciseNameClaim(incoming.canonicalName)?.ownerID)
        }
    }

    @Test fun sessionClaimWinsSyncUntilAtomicRelease() = runBlocking {
        val incoming = loader.load(now).records.first { !it.isRetired }
        val local = id("fictional-session-owner")
        ok(repository.renameClaim(local, incoming.canonicalName, ExerciseClaimScope.currentSession))
        ok(repository.synchronizeCatalog())
        assertFalse(ok(repository.search("")).any { it.exerciseID == incoming.exerciseID })
        withContext(Dispatchers.IO) {
            database.runInTransaction { repository.releaseSessionClaimsInTransaction(setOf(local)) }
        }
        assertTrue(ok(repository.search("")).any { it.exerciseID == incoming.exerciseID })
    }

    @Test fun offlineSearchMatchesChinesePinyinInitialsAliasAndFacets() = runBlocking {
        ok(repository.synchronizeCatalog())
        val rows = ok(repository.search("杠铃上斜卧推"))
        assertEquals(1, rows.size)
        val item = rows.single()
        for (query in listOf("gang ling shang xie wo tui", "GLSXWT", "shangxie")) {
            assertTrue("Missing pinyin match", ok(repository.search(query)).any { it.exerciseID == item.exerciseID })
        }
        assertTrue(ok(repository.search("胸")).any { it.exerciseID == item.exerciseID })
        assertTrue(ok(repository.search("杠铃")).any { it.exerciseID == item.exerciseID })
        val local = ok(repository.saveCustom(custom(name = "虚构哑铃动作")))
        ok(repository.updatePreference(preference(local, "虚构别名")))
        assertTrue(ok(repository.search("xgbm")).any { it.exerciseID == local.exerciseID })
        assertTrue(ok(repository.search("no-such-fictional-exercise")).isEmpty())
    }

    @Test fun syncRetiresMissingBuiltInAndPreservesHistoricalAndTemplateSnapshots() = runBlocking {
        val item = ok(repository.saveCustom(custom()))
        val incoming = loader.load(now).records.first { !it.isRetired }
        val studentID = uuid(1)
        val sessionID = uuid(2)
        val snapshot = SessionExerciseEntity(uuid(3), sessionID, 0, ExerciseSourceKind.custom,
            item.exerciseID.value, item.canonicalName, item.recordMode, null, null)
        val template = TemplateExerciseEntity(uuid(5), uuid(4), null, 0, ExerciseSourceKind.custom,
            item.exerciseID.value, item.canonicalName, item.recordMode)
        val builtInSnapshot = snapshot.copy(id = uuid(6), orderIndex = 1, sourceKind = ExerciseSourceKind.builtIn,
            sourceID = incoming.exerciseID.value, displayNameSnapshot = "虚构旧目录名称", recordModeSnapshot = RecordMode.duration)
        val builtInTemplate = template.copy(id = uuid(7), orderIndex = 1, sourceKind = ExerciseSourceKind.builtIn,
            sourceID = incoming.exerciseID.value, displayNameSnapshot = "虚构旧目录名称", recordModeSnapshot = RecordMode.duration)
        withContext(Dispatchers.IO) {
            val dao = database.s1Dao()
            dao.insert(StudentEntity(studentID, "虚构学员", StudentSex.undisclosed, null, null, null, null, null,
                StudentLifecycle.active, now, now))
            dao.insert(SessionEntity(sessionID, studentID, SessionState.completed, now, now, BigDecimal.TEN,
                null, false, null, null, null, "1", now, now, now, null, null))
            dao.insert(snapshot)
            dao.insert(builtInSnapshot)
            dao.insert(TrainingTemplateEntity(uuid(4), "虚构模板", "1", now, now))
            dao.insert(template)
            dao.insert(builtInTemplate)
            dao.insert(ExerciseCatalogEntity(incoming.exerciseID.value, ExerciseKind.builtIn, "虚构旧目录名称", "虚构旧目录名称",
                RecordMode.duration, "old", ExerciseLifecycle.active, false, "fictional-old-source", now, now))
            dao.insert(ExerciseCatalogEntity("fictional-old-built-in", ExerciseKind.builtIn, "虚构旧内置", "虚构旧内置",
                RecordMode.reps, "old", ExerciseLifecycle.active, false, "fictional-old-source", now, now))
        }
        ok(repository.saveCustom(item.copy(canonicalName = "虚构新名", recordMode = RecordMode.duration)))
        ok(repository.updatePreference(preference(item, hidden = true)))
        ok(repository.synchronizeCatalog())
        ok(repository.updatePreference(preference(incoming, hidden = true)))
        reopen()
        withContext(Dispatchers.IO) {
            assertEquals(snapshot, database.s1Dao().findSessionExercise(snapshot.id))
            assertEquals(template, database.s1Dao().findTemplateExercise(template.id))
            assertEquals(builtInSnapshot, database.s1Dao().findSessionExercise(builtInSnapshot.id))
            assertEquals(builtInTemplate, database.s1Dao().findTemplateExercise(builtInTemplate.id))
            assertEquals(incoming.canonicalName, database.s1Dao().findExerciseCatalog(incoming.exerciseID.value)?.canonicalName)
            assertTrue(requireNotNull(database.s1Dao().findExerciseCatalog("fictional-old-built-in")).isRetired)
        }
        assertFalse(ok(repository.search("")).any { it.exerciseID == id("fictional-old-built-in") || it.exerciseID == item.exerciseID })
    }

    @Test fun loaderRejectsPlaceholderMissingLicenseAndDuplicateIdentity() {
        val original = context.assets.open(ExerciseCatalogLoader.CATALOG_PATH).bufferedReader().use { it.readText() }
        val bad = listOf<(JSONObject) -> Unit>(
            { it.getJSONObject("provenance").put("isFictionalPlaceholder", true) },
            { it.getJSONObject("provenance").getJSONArray("records").getJSONObject(0).put("redistributionAllowed", false) },
            { it.getJSONObject("provenance").getJSONArray("records").getJSONObject(0).put("licenseText", "") },
            { it.getJSONArray("exercises").getJSONObject(1).put("id", it.getJSONArray("exercises").getJSONObject(0).getString("id")) },
            { it.getJSONArray("exercises").getJSONObject(0).put("provenanceRef", "fictional-missing") },
        )
        bad.forEach { mutate ->
            val root = JSONObject(original)
            mutate(root)
            assertThrows(IllegalArgumentException::class.java) { ExerciseCatalogLoader.decode(root.toString(), now) }
        }
    }

    @Test fun catalogSyncStableIDCollisionRollsBackAllEarlierInserts() = runBlocking {
        val last = loader.load(now).records.last()
        val local = ok(repository.saveCustom(custom(last.exerciseID.value, "虚构保留动作")))
        val pref = ok(repository.updatePreference(preference(local, "虚构保留别名")))
        failure(ApplicationErrorCode.conflict, repository.synchronizeCatalog())
        reopen()
        assertEquals(listOf(local), ok(repository.listCatalog()))
        assertEquals(pref, ok(repository.preference(local.exerciseID)))
        withContext(Dispatchers.IO) {
            assertEquals(1, database.t006bExerciseDao().claims().size)
        }
    }

    @Test fun persistenceFailureDoesNotReportSuccessOrLeaveNewClaim() = runBlocking {
        val item = ok(repository.saveCustom(custom()))
        withContext(Dispatchers.IO) {
            database.openHelper.writableDatabase.execSQL(
                "CREATE TEMP TRIGGER fictional_reject_exercise_update BEFORE UPDATE ON exercise_catalog " +
                    "BEGIN SELECT RAISE(ABORT, 'fictional persistence failure'); END",
            )
        }
        failure(ApplicationErrorCode.persistenceFailed, repository.saveCustom(item.copy(canonicalName = "虚构失败改名")))
        reopen()
        assertEquals(listOf(item), ok(repository.listCatalog()))
        withContext(Dispatchers.IO) {
            assertNull(database.s1Dao().findExerciseNameClaim("虚构失败改名"))
            assertEquals(item.exerciseID.value, database.s1Dao().findExerciseNameClaim(item.canonicalName)?.ownerID)
        }
    }

    @Test fun useCasesCreateEditArchiveRestoreAndSessionOnlyStayExplicit() = runBlocking {
        val ids = object : StableIDGenerator {
            override fun newExerciseID() = id("fictional-usecase")
            override fun newStudentID(): StudentID = error("Unused ID kind")
            override fun newCoursePackageID(): CoursePackageID = error("Unused ID kind")
            override fun newCreditAdjustmentID(): CreditAdjustmentID = error("Unused ID kind")
            override fun newSessionID(): SessionID = error("Unused ID kind")
            override fun newTemplateID(): TemplateID = error("Unused ID kind")
            override fun newSectionID(): SectionID = error("Unused ID kind")
            override fun newSessionExerciseID(): SessionExerciseID = error("Unused ID kind")
            override fun newTemplateExerciseID(): TemplateExerciseID = error("Unused ID kind")
            override fun newTrainingSetID(): TrainingSetID = error("Unused ID kind")
        }
        val useCases = ExerciseUseCases(repository, clock, ids)
        ok(useCases.claimSessionOnly(id("fictional-local"), "虚构仅本课动作"))
        assertTrue(ok(repository.listCatalog()).isEmpty())
        val created = ok(useCases.createCustom("虚构显式入库", RecordMode.reps))
        assertEquals(ids.newExerciseID(), created.exerciseID)
        val edited = ok(useCases.updateCustom(created.exerciseID, "虚构编辑名称", RecordMode.duration))
        assertEquals(created.createdAtUTC, edited.createdAtUTC)
        assertEquals(RecordMode.duration, edited.recordMode)
        ok(useCases.archiveCustom(created.exerciseID))
        assertTrue(ok(useCases.search("")).isEmpty())
        failure(ApplicationErrorCode.invalidState, useCases.archiveCustom(created.exerciseID))
        failure(ApplicationErrorCode.invalidState, useCases.updateCustom(created.exerciseID, "虚构禁止编辑", RecordMode.reps))
        val restored = ok(useCases.restoreCustom(created.exerciseID))
        assertEquals(edited.canonicalName, restored.canonicalName)
        assertEquals(listOf(restored), ok(useCases.search("")))
    }

    @Test fun repositoryProductionSourcesHaveNoBusinessLogsOrNetworkCalls() {
        val app = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))
        listOf("storage/repository/ExerciseRepository.kt", "storage/dao/T006bExerciseDao.kt",
            "core/application/ExerciseUseCases.kt", "core/application/ExerciseCatalogLoader.kt").forEach {
            PrivacySourcePolicy.validate(File(app, "src/main/java/com/ignacioli/finecoach/$it").readText())
        }
    }
}
