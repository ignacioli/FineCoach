package com.ignacioli.finecoach.core.application

import android.content.res.AssetManager
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.parseDomainName
import org.json.JSONObject
import java.time.Instant
import java.util.WeakHashMap

/** All attribution and license text is bundled; these identifiers are never fetched. */
data class ExerciseProvenance(
    val recordID: String,
    val sourceIdentifier: String,
    val authorOrOwner: String,
    val licenseIdentifier: String,
    val licenseText: String,
    val attributionRequirement: String,
    val contentVersion: String,
    val reviewDate: String,
    val reviewerEvidence: String,
)

data class ExerciseCatalogMetadata(
    val primaryMuscleGroup: String,
    val equipmentClass: String,
    val secondaryMuscleGroups: List<String>,
    val isUnilateralByDefault: Boolean,
)

data class LoadedExerciseCatalog internal constructor(
    val records: List<ExerciseRecord>,
    val provenance: Map<String, ExerciseProvenance>,
    val metadata: Map<StableExerciseID, ExerciseCatalogMetadata>,
)

class ExerciseCatalogLoader internal constructor(
    private val assets: AssetManager,
    private val cache: ExerciseCatalogCache,
    private val readText: () -> String,
) {
    constructor(assets: AssetManager) : this(assets, processCache,
        { assets.open(CATALOG_PATH).bufferedReader().use { it.readText() } })

    fun load(now: Instant): LoadedExerciseCatalog = cache.load(assets, now) {
        decode(readText(), now).also {
            require(assets.open(LICENSE_PATH).use { stream -> stream.read() } != -1)
        }
    }

    fun cachedMetadata(): Map<StableExerciseID, ExerciseCatalogMetadata> = cache.metadata(assets)

    companion object {
        private val processCache = ExerciseCatalogCache()
        const val CATALOG_PATH = "exercises/provenance.json"
        const val LICENSE_PATH = "exercises/licenses/SOURCES.md"
        private val muscles = setOf("胸", "肩", "背", "大腿", "小腿", "臂", "臀", "核心")
        private val equipment = setOf("杠铃", "哑铃", "固定器械", "史密斯机", "绳索", "哈克机", "壶铃", "徒手", "悍马机", "弹力带", "悬挂带", "单杠", "其他")

        internal fun decode(text: String, now: Instant): LoadedExerciseCatalog {
            val root = JSONObject(text)
            fun required(objectValue: JSONObject, key: String): String = objectValue.getString(key).also {
                require(it.isNotBlank())
            }
            val version = required(root, "metadataVersion")
            val manifest = root.getJSONObject("provenance")
            required(manifest, "catalogID")
            require(required(manifest, "contentVersion") == version)
            require(!manifest.getBoolean("isFictionalPlaceholder"))
            val sources = manifest.getJSONArray("records")
            val provenance = linkedMapOf<String, ExerciseProvenance>()
            for (index in 0 until sources.length()) {
                val source = sources.getJSONObject(index)
                require(source.getBoolean("redistributionAllowed"))
                val id = required(source, "recordID")
                val record = ExerciseProvenance(id, required(source, "sourceIdentifier"),
                    required(source, "authorOrOwner"), required(source, "licenseIdentifier"),
                    required(source, "licenseText"), required(source, "attributionRequirement"),
                    required(source, "contentVersion"), required(source, "reviewDate"), required(source, "reviewerEvidence"))
                require(record.contentVersion == version && provenance.put(id, record) == null)
            }
            val rows = root.getJSONArray("exercises")
            require(rows.length() > 0 && rows.length() == provenance.size)
            val metadata = linkedMapOf<StableExerciseID, ExerciseCatalogMetadata>()
            val names = mutableSetOf<String>()
            val refs = mutableSetOf<String>()
            val records = (0 until rows.length()).map { index ->
                val row = rows.getJSONObject(index)
                val id = StableExerciseID.parse(row.getString("id"))
                val name = parseDomainName(row.getString("canonicalName"), "canonicalName").value
                val ref = row.getString("provenanceRef")
                require(names.add(name) && refs.add(ref) && ref in provenance)
                val secondary = row.optJSONArray("secondaryMuscleGroups")
                val parts = if (secondary == null) emptyList() else (0 until secondary.length()).map { secondary.getString(it) }
                val facet = ExerciseCatalogMetadata(row.getString("primaryMuscleGroup"), row.getString("equipmentClass"),
                    parts, row.optBoolean("unilateral", false))
                require(facet.primaryMuscleGroup in muscles && facet.equipmentClass in equipment && parts.all { it in muscles })
                require(metadata.put(id, facet) == null)
                ExerciseRecord(id, ExerciseKind.builtIn, name, RecordMode.parse(row.getString("recordMode")), version,
                    ExerciseLifecycle.active, row.optBoolean("retired", false), ref, now, now)
            }
            return LoadedExerciseCatalog(records, provenance.toMap(), metadata.toMap())
        }
    }
}

/** AssetManager identifies an immutable packaged asset set; failed reads never populate the cache. */
internal class ExerciseCatalogCache {
    private val catalogs = WeakHashMap<AssetManager, LoadedExerciseCatalog>()

    @Synchronized
    fun load(assets: AssetManager, now: Instant, read: () -> LoadedExerciseCatalog): LoadedExerciseCatalog {
        val catalog = synchronized(catalogs) { catalogs[assets] }
            ?: read().also { synchronized(catalogs) { catalogs[assets] = it } }
        // Timestamps belong to the caller's synchronization, not the first process cache fill.
        return catalog.copy(records = catalog.records.map { it.copy(createdAtUTC = now, updatedAtUTC = now) })
    }

    fun metadata(assets: AssetManager): Map<StableExerciseID, ExerciseCatalogMetadata> =
        synchronized(catalogs) { catalogs[assets]?.metadata ?: emptyMap() }
}
