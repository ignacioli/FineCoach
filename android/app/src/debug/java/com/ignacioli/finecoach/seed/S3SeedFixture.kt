// fictional-data: invented, page-specific walkthrough students, histories and measurements only.
package com.ignacioli.finecoach.seed

import com.ignacioli.finecoach.S1AppGraph
import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import com.ignacioli.finecoach.storage.repository.BodyDataRepository
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Debug-only extension; base S1/S2 business records are never changed. */
internal object S3SeedFixture {
    enum class Role(val number: Int, val displayName: String) {
        trends(101, "虚构趋势松鼠"), gains(102, "虚构收获海星"), stagnant(103, "虚构停滞云雀"),
        inactive(104, "虚构久别鲸鱼"), coursePackage(105, "虚构课包青蛙"),
    }
    fun studentID(fixture: S1SeedFixture, role: Role) = StudentID.parse(fixture.uuid(role.number))

    fun extend(base: String): String {
        val root = JSONObject(base)
        check(root.getInt("seedVersion") == 6) { "Unsupported seed base" }
        // The asset remains the shared metadata authority for the installer and host task.
        val original = root.objects("sessions")
        val history = original.first()
        for (role in Role.entries) {
            val student = JSONObject(root.getJSONArray("students").getJSONObject(0).toString())
                .put("id", role.number).put("name", role.displayName).put("variants", JSONArray(listOf("multi")))
                .put("trainingGoal", "S3 页面走查专用虚构记录").put("phone", "000-0${role.number}")
                .put("wechatID", "fictional-s3-${role.name}").put("offsetSeconds", -180L * 86400)
                .put("scenario", "T050 页面专人 ${role.name}")
            root.getJSONArray("students").put(student)
        }
        var next = 60000
        var index = 0
        fun session(role: Role, offset: Long, weight: String, reps: String?, weightReps: String = "8", focus: String = "chest"): JSONObject {
            val row = JSONObject(history.toString())
                .put("key", "s3-history-${index++}").put("scenario", "T050 页面专人历史")
                .put("variants", JSONArray(listOf("multi"))).put("studentID", role.number)
                .put("startOffsetSeconds", offset - 1800).put("finishOffsetSeconds", offset)
                .put("trainingFocus", JSONArray(listOf(focus)))
            row.remove("summary")
            val sectionID = next++
            row.put("sections", JSONArray().put(JSONObject(history.objects("sections").first().toString()).put("id", sectionID)))
            val exercises = JSONArray()
            for ((i, value) in listOfNotNull(weight, reps).withIndex()) {
                val exercise = JSONObject(history.objects("exercises")[i].toString()).put("id", next++).put("sectionID", sectionID)
                val set = JSONObject(exercise.objects("sets").first().toString()).put("id", next++).put("offsetSeconds", offset - 60)
                set.put(if (i == 0) "weightValue" else "repetitionCount", value)
                if (i == 0) set.put("repetitionCount", weightReps)
                exercise.put("sets", JSONArray().put(set)); exercises.put(exercise)
            }
            return row.put("exercises", exercises)
        }
        val added = mutableListOf<JSONObject>()
        repeat(24) { i ->
            added += session(Role.trends, -(120L - i * 5) * 86400, (20 + i * 2).toString(), (10 + i).toString(),
                (8 + i / 8).toString(), if (i == 0) "back" else "chest")
        }
        // Exactly ten sessions; the last is the second attendance of the fourth week.
        listOf(39L, 37L, 27L, 25L, 20L, 18L, 13L, 11L, 6L, 1L).forEachIndexed { i, day ->
            added += session(Role.gains, -day * 86400 + 3600, if (i == 9) "22" else "18",
                when (i) { 0 -> "20"; 9 -> "10"; else -> "8" })
        }
        listOf(6L, 4L, 2L, 0L).forEach { day -> added += session(Role.stagnant, -day * 86400 - 3600, "20", null) }
        added += session(Role.inactive, -90L * 86400, "18", null)
        root.put("sessions", JSONArray(added + original))
        val packageKey = "s3-package-warning"
        root.getJSONArray("packages").put(JSONObject(root.objects("packages").first { it.getString("key") == "available" }.toString())
            .put("key", packageKey).put("studentID", Role.coursePackage.number).put("name", "虚构走查课包")
            .put("variants", JSONArray(listOf("multi"))).put("scenario", "T050 课包专人预警"))
        root.getJSONArray("ledger").put(JSONObject().put("key", "s3-package-adjustment").put("scenario", "T050 课包专人余额")
            .put("variants", JSONArray(listOf("multi"))).put("kind", "manualCorrection").put("packageKey", packageKey)
            .put("direction", "debit").put("amount", 7).put("note", "虚构走查调整").put("offsetSeconds", 0))
        return root.toString()
    }

    class BodyInput(val metric: BuiltInBodyMetric?, val daysAgo: Long, val value: String, val unit: String)
    fun bodyInputs(): List<BodyInput> = buildList {
        repeat(8) { i ->
            val day = (7L - i) * 14
            // One imperial entry remains; all other inputs are direct canonical values.
            add(BodyInput(BuiltInBodyMetric.weight, day, if (i == 1) "140" else (70 - i).toString(), if (i == 1) "lb" else "kg"))
            add(BodyInput(BuiltInBodyMetric.waist, day, if (i == 1) "30" else (80 - i).toString(), if (i == 1) "in" else "cm"))
            add(BodyInput(BuiltInBodyMetric.bodyFatPercent, day, (20 - i).toString(), "%"))
            add(BodyInput(null, day, (3 + i).toString(), "格"))
        }
    }

    suspend fun installBody(graph: S1AppGraph, fixture: S1SeedFixture) {
        var next = 90000
        val cases = BodyDataUseCases(BodyDataRepository(graph.database, graph.clock), graph.clock, graph.zone) { UUID.fromString(fixture.uuid(next++)) }
        val student = studentID(fixture, Role.trends)
        val custom = success(cases.createCustomMetric(student, "虚构恢复指标", "格"))
        for (input in bodyInputs()) {
            val value = DecimalValue.parse(input.value)
            val stored = when (input.metric?.rule) {
                BodyMetricUnitRuleKind.weight -> BuiltInUnitConversion.canonicalKilograms(value, input.unit)
                BodyMetricUnitRuleKind.length -> BuiltInUnitConversion.canonicalCentimeters(value, input.unit)
                else -> value
            }
            val unit = input.metric?.canonicalUnit ?: input.unit
            success(cases.recordMeasurement(student, input.metric?.id ?: custom.id, stored.canonicalString, unit, fixture.at(-input.daysAgo * 86400)))
        }
    }

    private fun <T> success(result: ApplicationResult<T>): T = when (result) {
        is ApplicationResult.Success -> result.value
        is ApplicationResult.Failure -> error("Seed repository operation failed")
    }
}
