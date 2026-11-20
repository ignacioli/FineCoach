package com.ignacioli.finecoach.storage.local

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.insight.Insight
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.*
import java.util.UUID
import org.json.JSONObject
import org.json.JSONArray

/** This private device state is deliberately outside Room/FCBK generations. */
class InsightLocalStateStore(filesDir: File) {
    private val file = File(filesDir, "Insights/local-state.json")
    private data class State(val entries: Map<String, LocalDate> = emptyMap(), val firstNudgePlayed: Boolean = false)
    @Synchronized fun activeKeys(now: Instant, zone: ZoneId): Set<String> {
        val raw = read(); val active = prune(raw, now, zone)
        if (active != raw) try { write(active) } catch (_: Exception) { /* Read failure policy: no UI error. */ }
        return active.entries.keys.toSet()
    }
    @Synchronized fun firstNudgePlayed(): Boolean = read().firstNudgePlayed
    @Synchronized fun markFirstNudgePlayed(): ApplicationResult<Unit> = mutation { write(read().copy(firstNudgePlayed = true)) }
    @Synchronized fun snooze(insight: Insight, now: Instant, zone: ZoneId): ApplicationResult<Unit> = mutation {
        require(opaque(insight.snoozeKey))
        val state = prune(read(), now, zone)
        write(state.copy(entries = state.entries + (insight.snoozeKey to now.atZone(zone).toLocalDate().plusDays(14))))
    }
    @Synchronized fun unsnooze(insight: Insight): ApplicationResult<Unit> = mutation {
        require(opaque(insight.snoozeKey))
        val state = read(); write(state.copy(entries = state.entries - insight.snoozeKey))
    }
    private fun prune(state: State, now: Instant, zone: ZoneId) = state.copy(entries = state.entries.filterValues { now.atZone(zone).toLocalDate() < it })
    private fun read(): State = try {
        val root = JSONObject(file.readText())
        require(root.get("version") == 1 && root.get("firstNudgePlayed") is Boolean && root.keys().asSequence().toSet() == setOf("version", "entries", "firstNudgePlayed"))
        val entries = root.getJSONArray("entries"); val values = linkedMapOf<String, LocalDate>()
        for (i in 0 until entries.length()) {
            val item = entries.getJSONObject(i); val key = item.getString("key"); val date = item.getString("until")
            require(item.keys().asSequence().toSet() == setOf("key", "until") && opaque(key))
            val parsed = LocalDate.parse(date); require(parsed.toString() == date && !values.containsKey(key))
            values[key] = parsed
        }
        State(values, root.getBoolean("firstNudgePlayed"))
    } catch (_: Exception) { State() }
    private fun write(state: State) {
        val root = JSONObject().put("version", 1).put("firstNudgePlayed", state.firstNudgePlayed)
        val entries = JSONArray()
        for ((key, until) in state.entries.toSortedMap()) entries.put(JSONObject().put("key", key).put("until", until.toString()))
        root.put("entries", entries)
        check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
        val temp = File.createTempFile(".local-state-", ".tmp", file.parentFile)
        try {
            FileOutputStream(temp).use { stream -> stream.write(root.toString().toByteArray(Charsets.UTF_8)); stream.fd.sync() }
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally { temp.delete() }
    }
    private fun mutation(action: () -> Unit): ApplicationResult<Unit> = try { action(); ApplicationResult.Success(Unit) }
        catch (_: Exception) { ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed)) }
    private fun opaque(key: String): Boolean {
        val parts = key.split(':')
        val shape = when(parts.firstOrNull()) { "package", "inactive" -> parts.size == 2; "stagnant" -> parts.size == 3; else -> false }
        return shape && parts.drop(1).all { id -> Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(id) && runCatching { UUID.fromString(id) }.isSuccess }
    }
}
