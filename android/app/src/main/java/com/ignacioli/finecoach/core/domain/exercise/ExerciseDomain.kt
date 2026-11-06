package com.ignacioli.finecoach.core.domain.exercise

import com.ignacioli.finecoach.core.domain.common.ExerciseClaimScope
import com.ignacioli.finecoach.core.domain.common.ExerciseKind
import com.ignacioli.finecoach.core.domain.common.ExerciseLifecycle
import com.ignacioli.finecoach.core.domain.common.ExerciseSourceKind
import com.ignacioli.finecoach.core.domain.common.RecordMode
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.training.DomainError
import com.ignacioli.finecoach.core.domain.training.fail
import com.ignacioli.finecoach.core.domain.training.optionalText
import com.ignacioli.finecoach.core.domain.training.requiredText
import java.time.Instant

object ExerciseNameNormalizer {
    fun normalized(rawValue: String): String = requiredText(rawValue, "normalizedName")
}

data class ExerciseCatalogItem(
    val exerciseID: StableExerciseID,
    val kind: ExerciseKind,
    val canonicalName: String,
    val normalizedName: String,
    val recordMode: RecordMode,
    val metadataVersion: String,
    val lifecycle: ExerciseLifecycle,
    val isRetired: Boolean,
    val provenanceRef: String?,
    val createdAtUTC: Instant,
    val updatedAtUTC: Instant,
) {
    init {
        requiredText(canonicalName, "canonicalName")
        requiredText(metadataVersion, "metadataVersion")
        if (kind == ExerciseKind.builtIn && provenanceRef == null) {
            fail(DomainError.incompatibleInput, "provenanceRef")
        }
        if (kind == ExerciseKind.custom && provenanceRef != null) {
            fail(DomainError.incompatibleInput, "provenanceRef")
        }
    }

    fun updatingCustom(canonicalName: String, recordMode: RecordMode, nowUTC: Instant): ExerciseCatalogItem {
        if (kind != ExerciseKind.custom || lifecycle != ExerciseLifecycle.active) {
            fail(DomainError.invalidState)
        }
        val normalizedName = ExerciseNameNormalizer.normalized(canonicalName)
        return copy(
            canonicalName = normalizedName,
            normalizedName = normalizedName,
            recordMode = recordMode,
            updatedAtUTC = nowUTC,
            isRetired = false,
        )
    }

    fun archived(nowUTC: Instant): ExerciseCatalogItem {
        if (kind != ExerciseKind.custom || lifecycle != ExerciseLifecycle.active) {
            fail(DomainError.invalidState)
        }
        return copy(lifecycle = ExerciseLifecycle.archived, updatedAtUTC = nowUTC, isRetired = false)
    }

    fun restored(nowUTC: Instant): ExerciseCatalogItem {
        if (kind != ExerciseKind.custom || lifecycle != ExerciseLifecycle.archived) {
            fail(DomainError.invalidState)
        }
        return copy(lifecycle = ExerciseLifecycle.active, updatedAtUTC = nowUTC, isRetired = false)
    }

    companion object {
        fun makeBuiltIn(
            id: StableExerciseID,
            canonicalName: String,
            recordMode: RecordMode,
            metadataVersion: String,
            provenanceRef: String,
            nowUTC: Instant,
            isRetired: Boolean = false,
        ): ExerciseCatalogItem {
            val normalizedName = ExerciseNameNormalizer.normalized(canonicalName)
            return ExerciseCatalogItem(
                exerciseID = id,
                kind = ExerciseKind.builtIn,
                canonicalName = normalizedName,
                normalizedName = normalizedName,
                recordMode = recordMode,
                metadataVersion = requiredText(metadataVersion, "metadataVersion"),
                lifecycle = ExerciseLifecycle.active,
                provenanceRef = requiredText(provenanceRef, "provenanceRef"),
                createdAtUTC = nowUTC,
                updatedAtUTC = nowUTC,
                isRetired = isRetired,
            )
        }

        fun makeCustom(
            id: StableExerciseID,
            canonicalName: String,
            recordMode: RecordMode,
            nowUTC: Instant,
        ): ExerciseCatalogItem {
            val normalizedName = ExerciseNameNormalizer.normalized(canonicalName)
            return ExerciseCatalogItem(
                exerciseID = id,
                kind = ExerciseKind.custom,
                canonicalName = normalizedName,
                normalizedName = normalizedName,
                recordMode = recordMode,
                metadataVersion = "custom.1",
                lifecycle = ExerciseLifecycle.active,
                provenanceRef = null,
                createdAtUTC = nowUTC,
                updatedAtUTC = nowUTC,
                isRetired = false,
            )
        }
    }
}

data class ExerciseNameClaim(
    val normalizedName: String,
    val ownerKind: ExerciseSourceKind,
    val ownerID: StableExerciseID,
    val scope: ExerciseClaimScope,
) {
    constructor(
        normalizedName: String,
        ownerKind: ExerciseSourceKind,
        ownerID: StableExerciseID,
        scope: ExerciseClaimScope,
        normalize: Boolean = true,
    ) : this(
        normalizedName = if (normalize) ExerciseNameNormalizer.normalized(normalizedName) else normalizedName,
        ownerKind = ownerKind,
        ownerID = ownerID,
        scope = scope,
    )
}

data class ExerciseNameClaimTable(
    val claims: List<ExerciseNameClaim> = emptyList(),
) {
    fun claim(matchingNormalizedName: String): ExerciseNameClaim? {
        val key = ExerciseNameNormalizer.normalized(matchingNormalizedName)
        return claims.firstOrNull { it.normalizedName == key }
    }

    fun acquire(incoming: ExerciseNameClaim): ExerciseNameClaimTable {
        val existing = claim(incoming.normalizedName)
        if (existing != null) {
            if (existing.ownerID == incoming.ownerID && existing.scope == incoming.scope) {
                return this
            }
            fail(DomainError.conflict)
        }
        return copy(claims = claims + incoming)
    }

    fun release(ownerID: StableExerciseID, scope: ExerciseClaimScope? = null): ExerciseNameClaimTable {
        return copy(
            claims = claims.filterNot { claim ->
                claim.ownerID == ownerID && (scope == null || claim.scope == scope)
            },
        )
    }

    fun release(scope: ExerciseClaimScope): ExerciseNameClaimTable =
        copy(claims = claims.filterNot { it.scope == scope })
}

data class ExercisePreference(
    val exerciseID: StableExerciseID,
    val alias: String? = null,
    val isFavorite: Boolean = false,
    val isHidden: Boolean = false,
    val isAssisted: Boolean = false,
    val isUnilateral: Boolean? = null,
) {
    fun updating(
        alias: String? = this.alias,
        isFavorite: Boolean = this.isFavorite,
        isHidden: Boolean = this.isHidden,
        isAssisted: Boolean = this.isAssisted,
        isUnilateral: Boolean? = this.isUnilateral,
    ): ExercisePreference {
        return ExercisePreference(
            exerciseID = exerciseID,
            alias = optionalText(alias),
            isFavorite = isFavorite,
            isHidden = isHidden,
            isAssisted = isAssisted,
            isUnilateral = isUnilateral,
        )
    }
}

data class ExerciseLibraryEntry(
    val item: ExerciseCatalogItem,
    val preference: ExercisePreference?,
    val primaryMuscleGroup: String? = null,
    val equipmentClass: String? = null,
    val secondaryMuscleGroups: List<String> = emptyList(),
    val isUnilateralByDefault: Boolean = false,
) {
    val exerciseID: StableExerciseID
        get() = item.exerciseID

    val isUnilateral: Boolean
        get() = preference?.isUnilateral ?: isUnilateralByDefault

    val displayedName: String
        get() = preference?.alias?.takeIf { it.isNotEmpty() } ?: item.canonicalName
}

data class ExerciseCatalogBrowseFacet(
    val primaryMuscleGroup: String,
    val equipmentClass: String,
    val secondaryMuscleGroups: List<String> = emptyList(),
    val isUnilateral: Boolean = false,
)

object ExerciseCatalogBrowse {
    val muscleGroupOrder = listOf("胸", "肩", "背", "大腿", "小腿", "臂", "臀", "核心")
    val equipmentClassOrder = listOf(
        "杠铃",
        "哑铃",
        "固定器械",
        "史密斯机",
        "绳索",
        "哈克机",
        "壶铃",
        "徒手",
        "悍马机",
        "弹力带",
        "悬挂带",
        "单杠",
        "其他",
    )
    const val customSectionID: String = "custom"
    const val uncategorizedSectionID: String = "uncategorized"

    data class Section(
        val id: String,
        val entries: List<ExerciseLibraryEntry>,
    )

    fun sections(
        entries: List<ExerciseLibraryEntry>,
        muscleFilter: String?,
        equipmentFilter: String?,
    ): List<Section> {
        val filtersActive = muscleFilter != null || equipmentFilter != null
        val result = mutableListOf<Section>()
        if (!filtersActive) {
            val custom = entries.filter { it.item.kind == ExerciseKind.custom }
            if (custom.isNotEmpty()) {
                result += Section(customSectionID, custom)
            }
        }

        val grouped = linkedMapOf<String, MutableList<ExerciseLibraryEntry>>()
        for (entry in entries) {
            if (entry.item.kind != ExerciseKind.builtIn) {
                continue
            }
            if (muscleFilter != null && entry.primaryMuscleGroup != muscleFilter) {
                continue
            }
            if (equipmentFilter != null && entry.equipmentClass != equipmentFilter) {
                continue
            }
            val key = entry.primaryMuscleGroup ?: uncategorizedSectionID
            grouped.getOrPut(key) { mutableListOf() }.add(entry)
        }

        for (muscle in muscleGroupOrder) {
            if (muscleFilter != null && muscle != muscleFilter) {
                continue
            }
            val rows = grouped[muscle]
            if (!rows.isNullOrEmpty()) {
                result += Section(muscle, rows)
            }
        }

        if (muscleFilter == null) {
            val uncategorized = grouped[uncategorizedSectionID]
            if (!uncategorized.isNullOrEmpty()) {
                result += Section(uncategorizedSectionID, uncategorized)
            }
        }

        return result
    }
}
