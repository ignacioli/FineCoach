// fictional-data: debug-only parser for explicitly declared synthetic walkthrough records.
package com.ignacioli.finecoach.seed

import android.content.Context
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

/** JSON is the data authority. Unknown fields fail closed instead of silently ignoring fixture edits. */
internal class S1SeedFixture private constructor(val json: JSONObject) {
    val version get() = json.getInt("seedVersion")
    val dataset get() = json.getString("dataset")
    val now: Instant get() = Instant.parse(json.getString("clockUTC"))
    fun uuid(number: Int): String = json.getString("uuidPrefix") + number.toString().padStart(12, '0')
    fun records(key: String) = json.objects(key)
    fun selected(key: String, variant: String) = records(key).filter { variant in it.strings("variants") }
    fun at(offset: Long) = now.plusSeconds(offset)

    companion object {
        const val PATH = "seed/s1-seed.json"
        fun read(context: Context) = decode(context.assets.open(PATH).bufferedReader().use { it.readText() })
        fun decode(text: String): S1SeedFixture {
            val root = JSONObject(text)
            root.keysOnly("declaration source seedVersion dataset clockUTC uuidPrefix generatedIDStart catalogCount expectedRows scenarios students packages sessions ledger templates")
            require(root.getString("declaration").contains("fictional-data"))
            val fixture = S1SeedFixture(root)
            require(fixture.version > 0 && fixture.dataset == "fictional-s1-coach-core-v${fixture.version}")
            fixture.now
            UUID.fromString(fixture.uuid(1))
            require(root.getInt("generatedIDStart") > 0 && root.getInt("catalogCount") > 0)
            require(fixture.records("scenarios").map { it.getString("key") }.toSet() == setOf("empty", "single", "multi"))
            root.getJSONObject("expectedRows").keysOnly("empty single multi")
            for (variant in listOf("empty", "single", "multi")) require(root.getJSONObject("expectedRows").getInt(variant) > 0)
            fixture.records("scenarios").forEach { it.recordKeys("key") }
            for (group in listOf("students", "packages", "sessions", "ledger", "templates")) {
                val rows = fixture.records(group)
                val identity = if (group == "students") "id" else "key"
                require(rows.map { it.get(identity).toString() }.distinct().size == rows.size)
                rows.forEach { row ->
                    require(row.strings("variants").isNotEmpty() && row.strings("variants").all { it in setOf("single", "multi") })
                    when (group) {
                        "students" -> row.recordKeys("variants id name sex trainingGoal injuryNotes privateCoachNote phone wechatID lifecycle offsetSeconds")
                        "packages" -> row.recordKeys("variants key studentID name totalCredits startDate endDate state confirmedReplacement offsetSeconds")
                        "ledger" -> row.recordKeys("variants key kind packageKey sessionKey direction amount note offsetSeconds")
                        else -> {
                            row.recordKeys(if (group == "sessions") "variants key studentID state startOffsetSeconds finishOffsetSeconds trainingFocus sections exercises summary" else "variants key name trainingFocus offsetSeconds sections exercises")
                            row.objects("sections").forEach { it.recordKeys("id name orderIndex") }
                            row.objects("exercises").forEach { exercise ->
                                exercise.recordKeys("id sectionID orderIndex sourceKind stableID canonicalName recordMode sets")
                                require(exercise.getString("sourceKind") in setOf("builtIn", "sessionOnly"))
                                exercise.objects("sets").forEach { it.recordKeys("id orderIndex state offsetSeconds unit weightValue repetitionCount durationSeconds distanceValue speedValue resistanceValue") }
                            }
                            row.optJSONObject("summary")?.recordKeys("publicSummary privateCoachNote offsetSeconds")
                        }
                    }
                }
            }
            return fixture
        }
    }
}

internal fun JSONObject.objects(key: String): List<JSONObject> = getJSONArray(key).let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
internal fun JSONObject.strings(key: String): List<String> = getJSONArray(key).let { a -> (0 until a.length()).map { a.getString(it) } }
internal fun JSONObject.optional(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null
private fun JSONObject.keysOnly(fields: String) {
    require(keys().asSequence().all { it in fields.split(' ') }) { "Unknown seed fixture field" }
}
private fun JSONObject.recordKeys(fields: String) {
    keysOnly("scenario $fields")
    require(getString("scenario").isNotBlank()) { "Missing seed scenario" }
}
