package com.ignacioli.finecoach.storage.repository

import android.database.sqlite.SQLiteException
import android.icu.text.Transliterator
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.DomainException
import com.ignacioli.finecoach.core.domain.training.parseDomainName
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.entity.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withContext
import java.text.Normalizer
import java.util.Locale
import java.util.concurrent.Callable
import java.util.concurrent.ConcurrentHashMap

class ExerciseRepository(
    private val database: FineCoachDatabase,
    loader: ExerciseCatalogLoader,
    private val clock: AppClock,
    private val readCatalog: () -> LoadedExerciseCatalog = { loader.load(clock.now()) },
) : ExerciseRepositoryPort {
    private val dao get() = database.t006bExerciseDao()
    private val base get() = database.s1Dao()
    private val pinyin = ConcurrentHashMap<String, Pair<String, String>>()

    /** Launch preparation is separate from Room construction and never blocks app availability on failure. */
    var catalogUnavailable: Boolean = false
        private set

    suspend fun prepareCatalog() {
        val result = synchronizeCatalog()
        catalogUnavailable = result is ApplicationResult.Failure &&
            (listCatalog() as? ApplicationResult.Success)?.value?.any { it.kind == ExerciseKind.builtIn } != true
    }

    /** Keeps historical rows addressable, including retired/archived/hidden items. */
    override suspend fun listCatalog(): ApplicationResult<List<ExerciseRecord>> = transaction {
        dao.catalog().map { it.record() }
    }

    private data class BrowseMetadataSnapshot(
        val entries: Map<StableExerciseID, ExerciseCatalogMetadata> = emptyMap(),
        val unavailable: Boolean = false,
    )
    @Volatile private var browseSnapshot = BrowseMetadataSnapshot()
    val browseMetadata: Map<StableExerciseID, ExerciseCatalogMetadata> get() = browseSnapshot.entries
    val browseMetadataUnavailable: Boolean get() = browseSnapshot.unavailable

    private fun loadCatalog(): LoadedExerciseCatalog = try {
        readCatalog().also { browseSnapshot = BrowseMetadataSnapshot(it.metadata.toMap()) }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        browseSnapshot = browseSnapshot.copy(unavailable = true)
        throw failure
    }

    override suspend fun search(query: String) = search(query, includeHidden = false)

    suspend fun search(query: String, includeHidden: Boolean): ApplicationResult<List<ExerciseRecord>> = transaction {
        val metadata = try { loadCatalog().metadata }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) {
            // Existing durable catalog and last successful facets remain usable on bundle read failure.
            if (dao.catalog().none { it.kind == ExerciseKind.builtIn }) throw failure
            browseSnapshot.entries
        }
        val preferences = dao.preferences().associateBy { it.exerciseID }
        val occupied = dao.claims().filter { it.ownerKind != ExerciseSourceKind.builtIn }.map { it.normalizedName }.toSet()
        val normalizedQuery = fold(query.trim())
        val pinyinQuery = compact(normalizedQuery)
        dao.catalog().filter { item ->
            val preference = preferences[item.id]
            val facet = metadata[StableExerciseID.parse(item.id)]
            // Keep the existing library path to restore archived custom exercises.
            (item.lifecycle == ExerciseLifecycle.active || (includeHidden && item.kind == ExerciseKind.custom)) &&
                !item.isRetired && (includeHidden || preference?.isHidden != true) &&

                !(item.kind == ExerciseKind.builtIn && item.normalizedName in occupied) &&
                (normalizedQuery.isEmpty() || listOfNotNull(item.canonicalName, preference?.alias,
                    facet?.primaryMuscleGroup, facet?.equipmentClass).any { fold(it).contains(normalizedQuery) } ||
                    listOfNotNull(item.canonicalName, preference?.alias).any { pinyinMatches(it, pinyinQuery) })
        }.map { it.record() }
    }

    suspend fun synchronizeCatalog(): ApplicationResult<Unit> = transaction {
        val catalog = loadCatalog()
        val existing = dao.catalog().associateBy { it.id }
        val incomingIDs = catalog.records.map { it.exerciseID.value }.toSet()
        for (record in catalog.records) {
            val current = existing[record.exerciseID.value]
            if (current != null && current.kind != ExerciseKind.builtIn) reject(ApplicationErrorCode.conflict)
            var updated = record.entity()
            if (current != null) {
                updated = updated.copy(createdAtUTC = current.createdAtUTC, updatedAtUTC = current.updatedAtUTC)
                if (updated != current) updated = updated.copy(updatedAtUTC = clock.now())
                dao.update(updated)
            } else base.insert(updated)
        }
        for (current in existing.values) {
            if (current.kind == ExerciseKind.builtIn && current.id !in incomingIDs && !current.isRetired) {
                dao.update(current.copy(isRetired = true, updatedAtUTC = clock.now()))
            }
        }
        reconcileBuiltInClaims()
    }

    override suspend fun saveCustom(record: ExerciseRecord): ApplicationResult<ExerciseRecord> = transaction {
        if (record.kind != ExerciseKind.custom || record.provenanceRef != null || record.isRetired) {
            reject(ApplicationErrorCode.incompatibleInput)
        }
        val name = parseDomainName(record.canonicalName, "canonicalName").value
        val current = base.findExerciseCatalog(record.exerciseID.value)
        if (current != null && current.kind != ExerciseKind.custom) reject(ApplicationErrorCode.invalidState)
        // An archived row can only be restored as-is, not edited at the same time.
        if (current?.lifecycle == ExerciseLifecycle.archived &&
            (record.lifecycle != ExerciseLifecycle.active || name != current.canonicalName || record.recordMode != current.recordMode)) {
            reject(ApplicationErrorCode.invalidState)
        }
        if (current != null && record.lifecycle == ExerciseLifecycle.archived &&
            (name != current.canonicalName || record.recordMode != current.recordMode)) {
            reject(ApplicationErrorCode.invalidState)
        }
        if (current == null && record.lifecycle != ExerciseLifecycle.active) reject(ApplicationErrorCode.invalidState)
        val updated = record.copy(canonicalName = name, metadataVersion = current?.metadataVersion ?: "custom.1",
            createdAtUTC = current?.createdAtUTC ?: clock.now(), updatedAtUTC = clock.now())
        if (updated.lifecycle == ExerciseLifecycle.active) {
            acquire(ExerciseNameClaimEntity(name, ExerciseSourceKind.custom, record.exerciseID.value, ExerciseClaimScope.activeCatalog))
        }
        // Acquire first: a conflicting rename leaves both the old row and claim unchanged.
        if (current != null) dao.update(updated.entity()) else base.insert(updated.entity())
        dao.claims().filter { it.ownerID == record.exerciseID.value &&
            (updated.lifecycle == ExerciseLifecycle.archived || it.normalizedName != name) }.forEach {
            dao.releaseName(it.ownerID, it.normalizedName)
        }
        reconcileBuiltInClaims()
        requireNotNull(base.findExerciseCatalog(record.exerciseID.value)).record()
    }

    /** Claim operation only; currentSession never creates a global catalog row. */
    override suspend fun renameClaim(
        exerciseID: StableExerciseID, normalizedName: String, scope: ExerciseClaimScope,
    ): ApplicationResult<Unit> = transaction {
        val name = parseDomainName(normalizedName, "canonicalName").value
        val current = base.findExerciseCatalog(exerciseID.value)
        val kind = when (scope) {
            ExerciseClaimScope.activeCatalog -> {
                if (current == null) reject(ApplicationErrorCode.notFound)
                if (current.lifecycle != ExerciseLifecycle.active || current.isRetired || current.normalizedName != name) {
                    reject(ApplicationErrorCode.invalidState)
                }
                if (current.kind == ExerciseKind.builtIn) ExerciseSourceKind.builtIn else ExerciseSourceKind.custom
            }
            ExerciseClaimScope.currentSession -> {
                if (current != null) reject(ApplicationErrorCode.invalidState)
                ExerciseSourceKind.sessionOnly
            }
        }
        val claim = ExerciseNameClaimEntity(name, kind, exerciseID.value, scope)
        acquire(claim)
        dao.release(exerciseID.value, scope)
        acquire(claim)
        reconcileBuiltInClaims()
    }

    /** T008 can release alongside session completion/deletion in its existing Room transaction. */
    fun releaseSessionClaimsInTransaction(ownerIDs: Set<StableExerciseID>) {
        check(database.inTransaction())
        ownerIDs.forEach { dao.release(it.value, ExerciseClaimScope.currentSession) }
        reconcileBuiltInClaims()
    }

    suspend fun preference(id: StableExerciseID): ApplicationResult<ExercisePreferenceRecord?> = transaction {
        base.findExercisePreference(id.value)?.record()
    }

    override suspend fun updatePreference(command: UpdateExercisePreferenceCommand): ApplicationResult<ExercisePreferenceRecord> = transaction {
        if (base.findExerciseCatalog(command.exerciseID.value) == null) reject(ApplicationErrorCode.notFound)
        // The frozen Android command supplies a complete preference; null alias clears it.
        val alias = command.alias?.takeIf { it.isNotBlank() }?.let { parseDomainName(it, "alias").value }
        val row = ExercisePreferenceEntity(command.exerciseID.value, alias, command.isFavorite, command.isHidden,
            command.isAssisted, command.isUnilateral)
        dao.save(row)
        requireNotNull(base.findExercisePreference(row.exerciseID)).record()
    }

    private fun acquire(claim: ExerciseNameClaimEntity) {
        val existing = base.findExerciseNameClaim(claim.normalizedName)
        if (existing != null) {
            if (existing.ownerID == claim.ownerID && existing.scope == claim.scope) return
            reject(ApplicationErrorCode.conflict)
        }
        base.insert(claim)
    }

    private fun reconcileBuiltInClaims() {
        val claims = dao.claims()
        val occupied = claims.filter { it.ownerKind != ExerciseSourceKind.builtIn }.map { it.normalizedName }.toSet()
        claims.filter { it.ownerKind == ExerciseSourceKind.builtIn && it.scope == ExerciseClaimScope.activeCatalog }
            .forEach { dao.release(it.ownerID, it.scope) }
        dao.catalog().filter { it.kind == ExerciseKind.builtIn && it.lifecycle == ExerciseLifecycle.active &&
            !it.isRetired && it.normalizedName !in occupied }.forEach {
            acquire(ExerciseNameClaimEntity(it.normalizedName, ExerciseSourceKind.builtIn, it.id, ExerciseClaimScope.activeCatalog))
        }
    }

    private suspend fun <T> transaction(action: () -> T): ApplicationResult<T> = withContext(Dispatchers.IO) {
        try {
            ApplicationResult.Success(database.runInTransaction(Callable { action() }))
        } catch (failure: CancellationException) {
            throw failure
        } catch (failure: ExerciseFailure) {
            ApplicationResult.Failure(ApplicationError(failure.code))
        } catch (failure: DomainException) {
            ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.valueOf(failure.error.name), failure.field))
        } catch (_: IllegalArgumentException) {
            ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput))
        } catch (_: org.json.JSONException) {
            ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput))
        } catch (_: java.io.IOException) {
            ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
        } catch (_: SQLiteException) {
            ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
        } catch (_: IllegalStateException) {
            ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed))
        }
    }

    private class ExerciseFailure(val code: ApplicationErrorCode) : RuntimeException(code.name)
    private fun reject(code: ApplicationErrorCode): Nothing = throw ExerciseFailure(code)

    private fun ExerciseRecord.entity() = ExerciseCatalogEntity(exerciseID.value, kind, canonicalName, canonicalName,
        recordMode, metadataVersion, lifecycle, isRetired, provenanceRef, createdAtUTC, updatedAtUTC)
    private fun ExerciseCatalogEntity.record() = ExerciseRecord(StableExerciseID.parse(id), kind, canonicalName,
        recordMode, metadataVersion, lifecycle, isRetired, provenanceRef, createdAtUTC, updatedAtUTC)
    private fun ExercisePreferenceEntity.record() = ExercisePreferenceRecord(StableExerciseID.parse(exerciseID), alias,
        isFavorite, isHidden, isAssisted, isUnilateral)

    private fun fold(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT)
    private fun compact(value: String) = value.filter { it.isLetterOrDigit() }
    private fun pinyinMatches(value: String, query: String): Boolean {
        if (query.isEmpty()) return false
        val tokens = pinyin.getOrPut(value) {
            val syllables = fold(Transliterator.getInstance("Han-Latin").transliterate(value))
                .split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
            syllables.joinToString("") to syllables.map { it.first() }.joinToString("")
        }
        return tokens.first.contains(query) || tokens.second.contains(query)
    }
}
