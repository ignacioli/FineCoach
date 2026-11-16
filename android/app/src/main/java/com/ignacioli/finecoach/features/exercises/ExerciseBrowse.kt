package com.ignacioli.finecoach.features.exercises

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*

/** Mirrors iOS ExerciseCatalogBrowse; the repository owns search and canonicalName/id ordering. */
object ExerciseBrowse {
    val muscles = listOf("胸", "肩", "背", "大腿", "小腿", "臂", "臀", "核心")
    val equipment = listOf("杠铃", "哑铃", "固定器械", "史密斯机", "绳索", "哈克机", "壶铃", "徒手", "悍马机", "弹力带", "悬挂带", "单杠", "其他")
    data class Section(val id: String, val entries: List<ExerciseRecord>) {
        val title get() = when (id) { "custom" -> "自定义"; "uncategorized" -> "未分类"; else -> id }
    }

    fun sections(entries: List<ExerciseRecord>, metadata: Map<StableExerciseID, ExerciseCatalogMetadata>,
        muscle: String?, equipment: String?): List<Section> = buildList {
        if (muscle == null && equipment == null) {
            val custom = entries.filter { it.kind == ExerciseKind.custom }
            if (custom.isNotEmpty()) add(Section("custom", custom))
        }
        val grouped = entries.filter { it.kind == ExerciseKind.builtIn }
            .filter { muscle == null || metadata[it.exerciseID]?.primaryMuscleGroup == muscle }
            .filter { equipment == null || metadata[it.exerciseID]?.equipmentClass == equipment }
            .groupBy { metadata[it.exerciseID]?.primaryMuscleGroup ?: "uncategorized" }
        (muscles + "uncategorized").forEach { key ->
            if (muscle == null || key == muscle) grouped[key]?.let { add(Section(key, it)) }
        }
    }

    fun recent(sessions: List<SessionContentRecord>, entries: List<ExerciseRecord>,
        preferences: Map<StableExerciseID, ExercisePreferenceRecord>, studentID: StudentID? = null,
        limit: Int = 5): List<ExerciseRecord> {
        if (limit <= 0) return emptyList()
        val available = availableRecent(entries, preferences)
        if (available.isEmpty()) return emptyList()
        val seen = mutableSetOf<StableExerciseID>()
        val result = mutableListOf<ExerciseRecord>()
        for (session in sessions.sortedByDescending { it.session.completedAtUTC }) {
            collectRecent(session, available, seen, result, studentID, limit)
            if (result.size == limit) break
        }
        return result
    }

    internal fun availableRecent(entries: List<ExerciseRecord>, preferences: Map<StableExerciseID, ExercisePreferenceRecord>) =
        entries.filter { it.lifecycle == ExerciseLifecycle.active && !it.isRetired &&
            preferences[it.exerciseID]?.isHidden != true }.associateBy { it.exerciseID }

    internal fun collectRecent(content: SessionContentRecord, available: Map<StableExerciseID, ExerciseRecord>,
        seen: MutableSet<StableExerciseID>, result: MutableList<ExerciseRecord>, studentID: StudentID?, limit: Int = 5) {
        val session = content.session
        if (result.size >= limit || session.state != SessionState.completed || session.completedAtUTC == null ||
            (studentID != null && session.studentID != studentID)) return
        for (exercise in content.exercises.sortedBy { it.orderIndex }) {
            val id = exercise.sourceID
            if (exercise.sourceKind == ExerciseSourceKind.sessionOnly || id == null) continue
            val entry = available[id] ?: continue
            if (!seen.add(id)) continue
            result.add(entry)
            if (result.size == limit) return
        }
    }

    fun showsRecent(query: String, muscle: String?, equipment: String?, recent: List<ExerciseRecord>) =
        query.isBlank() && muscle == null && equipment == null && recent.isNotEmpty()
}
