package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.core.domain.training.*
import com.ignacioli.finecoach.core.domain.progress.*
import com.ignacioli.finecoach.core.domain.insight.*
import com.ignacioli.finecoach.core.domain.body.*
import com.ignacioli.finecoach.core.domain.student.*
import com.ignacioli.finecoach.core.domain.appointment.*
import com.ignacioli.finecoach.domain.CreditLedger
import java.io.File
import java.math.BigDecimal
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId

// fictional-data: infrastructure fixtures never represent real people.
internal class VectorFailure(val kind: String, val field: String, id: String) :
    RuntimeException("vector=$id path=$field kind=$kind")

/** Strict JSON, independent of Android's permissive JSONObject parser and platform mocks. */
internal class VectorJSON(private val text: String) {
    private var i = 0
    fun parse(): Any? { val result = value(); space(); require(i == text.length); return result }
    private fun space() { while (i < text.length && text[i] in " \r\n\t") i++ }
    private fun take(c: Char): Boolean { space(); return if (i < text.length && text[i] == c) { i++; true } else false }
    private fun value(): Any? {
        space(); require(i < text.length)
        return when (text[i]) {
            '{' -> { i++; val map = linkedMapOf<String, Any?>(); if (!take('}')) { do {
                space(); val key = string(); require(!map.containsKey(key)); require(take(':')); map[key] = value()
            } while (take(',')); require(take('}')) }; map }
            '[' -> { i++; val list = mutableListOf<Any?>(); if (!take(']')) { do { list.add(value()) } while (take(',')); require(take(']')) }; list }
            '"' -> string()
            't' -> literal("true", true)
            'f' -> literal("false", false)
            'n' -> literal("null", null)
            else -> { val match = Regex("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?").find(text, i)
                require(match != null && match.range.first == i); i += match.value.length
                if (match.value.any { it in ".eE" }) BigDecimal(match.value) else match.value.toLong() }
        }
    }
    private fun literal(word: String, result: Any?): Any? { require(text.startsWith(word, i)); i += word.length; return result }
    private fun string(): String {
        require(i < text.length && text[i++] == '"'); val out = StringBuilder()
        while (i < text.length) {
            val c = text[i++]; if (c == '"') return out.toString()
            require(c >= ' ')
            if (c != '\\') out.append(c) else {
                require(i < text.length)
                when (val escape = text[i++]) {
                    '"', '\\', '/' -> out.append(escape)
                    'b' -> out.append('\b'); 'f' -> out.append('\u000c'); 'n' -> out.append('\n'); 'r' -> out.append('\r'); 't' -> out.append('\t')
                    'u' -> { require(i + 4 <= text.length); val hex = text.substring(i, i + 4); require(Regex("[0-9a-fA-F]{4}").matches(hex)); out.append(hex.toInt(16).toChar()); i += 4 }
                    else -> error("Invalid JSON escape")
                }
            }
        }
        error("Unterminated JSON string")
    }
}

internal class SharedVectorRunner(private val conformance: Boolean, private val extraOps: Set<String> = emptySet(),
    private val dispatch: ((String, Map<String, Any?>) -> Any?)? = null) {
    private var id = "<unread>"
    private val seen = mutableSetOf<String>()
    private fun fail(path: String, kind: String = "format"): Nothing = throw VectorFailure(kind, path, id)
    @Suppress("UNCHECKED_CAST")
    private fun obj(value: Any?, path: String): Map<String, Any?> = value as? Map<String, Any?> ?: fail(path)
    private fun str(value: Any?, path: String): String = value as? String ?: fail(path)
    private fun keys(map: Map<String, Any?>, required: Set<String>, optional: Set<String>, path: String) {
        required.forEach { if (!map.containsKey(it)) fail("$path/$it") }
        map.keys.forEach { if (it !in required + optional) fail("$path/$it") }
    }
    fun run(bytes: ByteArray, filename: String) {
        id = filename.substringAfter("__").removeSuffix(".json")
        val root = try {
            val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
            obj(VectorJSON(text).parse(), "/")
        } catch (e: VectorFailure) { throw e } catch (_: Exception) { fail("/") }
        keys(root, setOf("id", "rule", "given", "when", "then"), setOf("meta"), "")
        id = str(root["id"], "/id")
        if (!Regex("[a-z][a-z0-9-]*").matches(id) || !filename.matches(Regex("m1[ab]-fr-[0-9]{3}__${Regex.escape(id)}\\.json"))) fail("/id")
        if (!seen.add(id)) fail("/id")
        if (root.containsKey("meta")) obj(root["meta"], "/meta")
        val rules = if (root["rule"] is List<*>) root["rule"] as List<*> else listOf(root["rule"])
        if (rules.isEmpty()) fail("/rule")
        rules.forEach { if (it !in knownRules) fail("/rule") }
        val given = obj(root["given"], "/given")
        val clock = obj(given["clock"], "/given/clock")
        val now = str(clock["now"], "/given/clock/now")
        if (!now.endsWith("Z") || runCatching { Instant.parse(now) }.isFailure) fail("/given/clock/now")
        val then = obj(root["then"], "/then")
        keys(then, emptySet(), setOf("state", "error"), "/then")
        if (then.isEmpty()) fail("/then")
        if (then.containsKey("error") && then["error"] !in errors) fail("/then/error")
        val operations = when (val w = root["when"]) { is Map<*, *> -> listOf(w); is List<*> -> w; else -> fail("/when") }
        if (operations.isEmpty()) fail("/when")
        // Validate every action before dispatch; unknown ops never become DomainError.
        val actions = operations.mapIndexed { index, raw ->
            val path = "/when/$index"; val action = obj(raw, path)
            keys(action, setOf("op", "args"), emptySet(), path)
            val op = str(action["op"], "$path/op")
            if (op !in extraOps && op != "credit-ledger.balance" && !(conformance && op in setOf("fixture.value", "fixture.fail", "fixture.calendar"))) fail("$path/op")
            obj(action["args"], "$path/args")
            if (op == "fixture.calendar") {
                val zone = str(given["timeZone"], "/given/timeZone")
                if (zone !in ZoneId.getAvailableZoneIds()) fail("/given/timeZone")
            }
            action
        }
        val results = mutableListOf<Any?>(); var state: Any? = null; var error: String? = null
        for ((index, action) in actions.withIndex()) {
            val args = obj(resolve(action["args"], root, results, "/when/$index/args"), "/when/$index/args")
            try {
                state = when (action["op"]) {
                    "fixture.value", "fixture.calendar" -> { keys(args, setOf("value"), emptySet(), "/when/$index/args"); args["value"] }
                    "fixture.fail" -> { keys(args, setOf("error"), emptySet(), "/when/$index/args"); val token = str(args["error"], "/when/$index/args/error"); if (token !in errors) fail("/when/$index/args/error"); throw DomainFailure(token) }
                    "credit-ledger.balance" -> balance(args, "/when/$index/args")
                    else -> requireNotNull(dispatch).invoke(action["op"] as String, args)
                }
                results.add(state)
            } catch (e: DomainFailure) { error = e.token; break }
        }
        if (error != then["error"]) fail("/then/error", "compare")
        if (then.containsKey("state")) compare(then["state"], state, "/then/state")
    }
    private fun resolve(value: Any?, root: Map<String, Any?>, results: List<Any?>, path: String): Any? = when (value) {
        is Map<*, *> -> if (value.containsKey("\$ref")) {
            if (value.keys != setOf("\$ref")) fail(path)
            val pointer = str(value["\$ref"], path)
            if (!pointer.startsWith("/") || Regex("~(?![01])").containsMatchIn(pointer)) fail(path)
            val tokens = pointer.drop(1).split('/').map { it.replace("~1", "/").replace("~0", "~") }
            var current: Any? = root + ("results" to results)
            for (token in tokens) current = when (val node = current) {
                is Map<*, *> -> if (node.containsKey(token)) node[token] else fail(path)
                is List<*> -> { if (!Regex("0|[1-9][0-9]*").matches(token)) fail(path); val n = token.toIntOrNull() ?: fail(path); if (n !in node.indices) fail(path); node[n] }
                else -> fail(path)
            }
            current
        } else value.entries.associate { it.key as String to resolve(it.value, root, results, "$path/${it.key}") }
        is List<*> -> value.mapIndexed { n, child -> resolve(child, root, results, "$path/$n") }
        else -> value
    }
    private class DomainFailure(val token: String) : RuntimeException()
    private fun balance(args: Map<String, Any?>, path: String): Any {
        keys(args, setOf("totalCredits", "adjustments"), emptySet(), path)
        val total = args["totalCredits"] as? Long ?: fail("$path/totalCredits")
        val list = args["adjustments"] as? List<*> ?: fail("$path/adjustments")
        val adjustments = list.mapIndexed { n, raw ->
            val p = "$path/adjustments/$n"; val a = obj(raw, p)
            keys(a, setOf("id", "packageID", "direction", "amount", "reasonKind", "sourceEventKey", "createdAtUTC"), emptySet(), p)
            for (key in listOf("id", "packageID")) { val uuid = str(a[key], "$p/$key"); if (!Regex("[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}").matches(uuid)) fail("$p/$key") }
            val direction = when (a["direction"]) { "debit" -> CreditLedger.Direction.debit; "credit" -> CreditLedger.Direction.credit; else -> fail("$p/direction") }
            val amount = a["amount"] as? Long ?: fail("$p/amount")
            if (a["reasonKind"] !in setOf("sessionComplete", "sessionReopen", "appointmentAbsent", "adhocSession")) fail("$p/reasonKind")
            if (runCatching { Instant.parse(str(a["createdAtUTC"], "$p/createdAtUTC")) }.isFailure) fail("$p/createdAtUTC")
            val key = str(a["sourceEventKey"], "$p/sourceEventKey")
            if (amount <= 0) throw DomainFailure("invalidNumber")
            if (key.isBlank()) throw DomainFailure("invalidIdentifier")
            CreditLedger.Adjustment(direction, amount)
        }
        return mapOf("balance" to CreditLedger.balance(total, adjustments))
    }
    private fun compare(expected: Any?, actual: Any?, path: String) {
        if (expected is Map<*, *>) {
            if (actual !is Map<*, *>) fail(path, "compare")
            for ((key, v) in expected) { if (!actual.containsKey(key)) fail("$path/$key", "compare"); compare(v, actual[key], "$path/$key") }
        } else if (expected is List<*>) {
            if (actual !is List<*>) fail(path, "compare")
            if (path.endsWith("/trainingFocus")) {
                if (expected.any { it !is String } || actual.any { it !is String } || expected.toSet() != actual.toSet()) fail(path, "compare")
            } else { if (expected.size != actual.size) fail(path, "compare"); expected.indices.forEach { compare(expected[it], actual[it], "$path/$it") } }
        } else if (path.endsWith("AtUTC") && expected is String && actual is String) {
            if (runCatching { Instant.parse(expected) == Instant.parse(actual) }.getOrDefault(false).not()) fail(path, "compare")
        } else if (expected != actual || (expected != null && actual != null && expected.javaClass != actual.javaClass)) fail(path, "compare")
    }
    companion object {
        // Existing normative rule IDs, not a regex accepting nonexistent requirements.
        val knownRules = (1..45).map { "M1A-FR-" + it.toString().padStart(3, '0') }.toSet() + (1..34).map { "M1B-FR-" + it.toString().padStart(3, '0') }
        val errors = setOf("emptyText", "textTooLong", "invalidDecimal", "invalidNumber", "invalidUnit", "invalidMode", "invalidState", "invalidIdentifier", "conflict", "notFound", "staleRevision", "protectedDataUnavailable", "persistenceFailed", "randomSourceFailed", "invalidFileOperation", "incompatibleInput", "recurrenceLimitExceeded", "overlapConflict")
    }
}

internal object VectorFiles {
    val root: File get() = File(requireNotNull(System.getProperty("finecoach.sharedVectorRoot")))
    fun files(directory: String): List<File> {
        val dir = File(root, directory); check(dir.isDirectory) { "Missing vector directory: $dir" }
        return dir.walkTopDown().filter { it.isFile && it.extension == "json" }.sortedBy { it.relativeTo(root).invariantSeparatorsPath }.toList().also { check(it.isNotEmpty()) }
    }
    fun report(file: File) {
        val bytes = file.readBytes(); val id = (VectorJSON(bytes.toString(Charsets.UTF_8)).parse() as Map<*, *>)["id"] ?: "<missing>"
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        println("VECTOR id=$id path=shared/test-vectors/${file.relativeTo(root).invariantSeparatorsPath} sha256=$digest")
    }
    @Suppress("UNCHECKED_CAST")
    fun checkConformance(file: File) {
        val root = VectorJSON(file.readText()).parse() as Map<String, Any?>
        val meta = root["meta"] as Map<*, *>; val c = meta["conformance"] as Map<*, *>
        val runner = SharedVectorRunner(true)
        var bytes = file.readBytes()
        when (c["mutation"]) {
            "invalid-json" -> bytes = "{fictional-data".toByteArray()
            "invalid-utf8" -> bytes = byteArrayOf(0xc3.toByte(), 0x28)
        }
        // Replace metadata structurally, keeping the ordinary fixture JSON policy-valid.
        if (c["mutation"] == "meta-array") bytes = file.readText().replaceRange(
            file.readText().indexOf("\"meta\""), findMetaEnd(file.readText()), "\"meta\":[]").toByteArray()
        val name = c["filename"] as? String ?: file.name
        if (c["duplicate"] == true) runner.run(bytes, name)
        val failure = try { runner.run(bytes, name); null } catch (e: VectorFailure) { e }
        if (c["outcome"] == "pass") check(failure == null) { failure!! }
        else check(failure != null && failure.kind == c["outcome"] && failure.field == c["path"]) { "${file.name}: expected $c, got $failure" }
        report(file)
    }
    private fun findMetaEnd(text: String): Int {
        val start = text.indexOf('{', text.indexOf("\"meta\"")); var depth = 0; var quoted = false; var escaped = false
        for (i in start until text.length) {
            val c = text[i]
            if (quoted) { if (escaped) escaped = false else if (c == '\\') escaped = true else if (c == '"') quoted = false }
            else if (c == '"') quoted = true else if (c == '{') depth++ else if (c == '}' && --depth == 0) return i + 1
        }
        error("Missing meta end")
    }
}

/** S3 projections: explicit context/IDs/times from vectors, no device state or random IDs. */
@Suppress("UNCHECKED_CAST")
internal class S3VectorAdapter(private val now: Instant, private val zone: ZoneId) {
    private fun map(value: Any?) = value as Map<String, Any?>
    private fun rows(value: Any?) = value as List<Map<String, Any?>>
    private fun date(value: Any?): java.time.LocalDate? = value?.let { map(it).let { d -> java.time.LocalDate.of((d.getValue("year") as Long).toInt(), (d.getValue("month") as Long).toInt(), (d.getValue("day") as Long).toInt()) } }
    private fun decimal(value: Any?) = (value as? String)?.let { DecimalValue.parse(it) }
    private fun source(value: Any?) = StableExerciseID.parse(value as String)
    private fun student(value: Any?) = StudentID.parse(value as String)
    private fun session(row: Map<String, Any?>, context: Map<String, Any?>): CompletedSession {
        val id = SessionID.parse(row.getValue("id") as String)
        val eid = SessionExerciseID.parse(row.getValue("exerciseID") as String)
        val at = Instant.parse(row.getValue("completedAtUTC") as String)
        val mode = RecordMode.parse(row.getValue("recordMode") as String)
        val sets = rows(row.getValue("sets")).map { s ->
            val input = map(s.getValue("input"))
            val draft = TrainingSet.makeDraft(
                TrainingSetID.parse(s.getValue("id") as String), eid, (s.getValue("orderIndex") as Long).toUInt(),
                TrainingSetInput(
                    RecordMode.parse(input.getValue("recordMode") as String),
                    weightValue = input["weightValue"] as? String, repetitionCount = input["repetitionCount"] as? String,
                    durationSeconds = input["durationSeconds"] as? String,
                    unit = MeasurementUnit.parse(input.getValue("unit") as String),
                    side = SetSide.parse(input.getValue("side") as String),
                    distanceValue = input["distanceValue"] as? String), at)
            when(s.getValue("state")) { "completed" -> draft.confirmed(at); "pending" -> draft.confirmed(at).undone(at); "draft" -> draft; else -> error("Invalid S3 state") }
        }
        val exercise = SessionExercise(eid, id, (context.getValue("exerciseOrder") as Long).toUInt(),
            ExerciseSourceKind.parse(context.getValue("sourceKind") as String), source(row.getValue("sourceID")),
            NormalizedName.parse(context.getValue("exerciseName") as String), mode,
            ValidatedText.optional(context["actionPrivateNote"] as? String), sets = sets)
        check(context["latestReport"] == null && map(context.getValue("actionPrivateNotes")).isEmpty())
        return CompletedSession(id, student(row.getValue("studentID")),
            NormalizedName.parse(context.getValue("studentName") as String), Instant.parse(row.getValue("startedAtUTC") as String), at,
            (row.getValue("trainingFocus") as List<String>).map { BodyPart.parse(it) }.toSet(),
            SessionNotes(ValidatedText.optional(context["privateCoachNote"] as? String),
                ValidatedText.optional(context["studentFacingSummary"] as? String), emptyMap()), listOf(exercise),
            SessionStatistics(sets.count { it.contributesToStatistics }, decimal(context.getValue("displayedDurationSeconds"))!!, decimal(context["ordinaryTrainingVolume"])),
            (context.getValue("revision") as Long).toULong())
    }
    fun evaluate(op: String, args: Map<String, Any?>): Any {
        val context = map(args.getValue("context"))
        fun history() = rows(args.getValue("history")).map { session(it, context) }
        fun assisted() = (args.getValue("assisted") as List<String>).map(::source).toSet()
        return when(op) {
            "s3.gains" -> {
                val gains = SessionGains.evaluate(session(map(args.getValue("current")), context), history(), zone, assisted())
                mapOf("holderIDs" to gains.recordHolderSetIDs.map { it.value }.sorted(), "strictIDs" to gains.strictRecordHolderSetIDs.map { it.value }.sorted(),
                    "recordCount" to gains.records.size.toLong(), "rowCount" to gains.rows.size.toLong(), "progressCount" to gains.progress.size.toLong(),
                    "milestone" to gains.milestoneSessionNumber?.toLong(), "streak" to gains.attendanceStreakWeeks?.toLong())
            }
            "s3.e1rm" -> mapOf("value" to EstimatedOneRepMax.value(decimal(args.getValue("weight"))!!, decimal(args.getValue("reps"))!!, source(args.getValue("exerciseID")))?.canonicalString)
            "s3.insights" -> {
                val students = rows(args.getValue("students")).map { s ->
                    val at = Instant.parse(s.getValue("createdAtUTC") as String)
                    val value = StudentDraft(s.getValue("name") as String, StudentSex.parse(s.getValue("sex") as String)).makeStudent(student(s.getValue("id")), at)
                    if (s.getValue("archived") as Boolean) value.archived(now) else value
                }
                val packages = rows(args.getValue("packages")).associate { p -> student(p.getValue("studentID")) to InsightEngine.PackageBalance(p.getValue("balance") as Long, date(p["endDate"])) }
                val appointments = rows(args.getValue("appointments")).map { a -> Appointment(
                    java.util.UUID.fromString(a.getValue("id") as String), student(a.getValue("studentID")), date = date(a.getValue("date"))!!,
                    startTime = java.time.LocalTime.of((a.getValue("hour") as Long).toInt(), (a.getValue("minute") as Long).toInt()),
                    status = AppointmentStatus.valueOf(a.getValue("status") as String), createdAtUTC = now, updatedAtUTC = now) }
                val input = InsightEngine.Input(students, packages, appointments, history(), (args.getValue("snoozed") as List<String>).toSet(), assisted())
                mapOf("items" to InsightEngine.evaluate(input, now, zone).map {
                    mapOf("kind" to it.kind.name, "studentID" to it.studentID.value, "exerciseID" to it.exerciseID?.value, "metric" to it.baselineMetric?.name)
                })
            }
            "s3.compare" -> when (val result = Comparison.compareSessions(session(map(args.getValue("a")), context), session(map(args.getValue("b")), context))) {
                is Comparison.SessionComparisonResult.Compatible -> mapOf("compatibility" to "compatible", "setsA" to result.detail.totalSetCountA.toLong(), "setsB" to result.detail.totalSetCountB.toLong())
                Comparison.SessionComparisonResult.DifferentStudent -> mapOf("compatibility" to "differentStudent")
                else -> mapOf("compatibility" to "incompatible")
            }
            "s3.records", "s3.trend" -> {
                val id = source(args.getValue("exerciseID")); val mode = RecordMode.parse(args.getValue("recordMode") as String)
                val direction = if (args.getValue("assisted") as Boolean) Comparison.LoadDirection.decreaseIsImprovement else Comparison.LoadDirection.increaseIsImprovement
                if (op == "s3.records") {
                    val r = Comparison.personalRecords(id, mode, history(), direction)
                    mapOf("weight" to r.highestWeight?.value?.canonicalString, "repsWeight" to r.mostRepsAtWeight?.weight?.canonicalString, "reps" to r.mostRepsAtWeight?.reps?.canonicalString, "repsSession" to r.mostRepsAtWeight?.sessionID?.value)
                } else {
                    val points = Comparison.exerciseTrend(id, mode, history(), direction)
                    mapOf("weights" to points.map { it.maxWeight?.canonicalString }, "deltas" to points.map { it.weightDelta?.canonicalString }, "volumes" to points.map { it.volume?.canonicalString }, "density" to Comparison.TrendSampleDensity.classify(points).name)
                }
            }
            "s3.body-display" -> {
                val v = decimal(args.getValue("value"))!!
                mapOf("weight" to BuiltInUnitConversion.weight(v, args.getValue("weightUnit") as String).canonicalString,
                    "length" to BuiltInUnitConversion.length(decimal(args.getValue("centimeters"))!!, args.getValue("lengthUnit") as String).canonicalString, "original" to v.canonicalString)
            }
            "s3.body-upsert" -> {
                val index = BodyMeasurementDayIndex()
                fun point(prefix: String) = BodyMeasurement.recordedNow(java.util.UUID.fromString(args.getValue(prefix + "ID") as String), student(args.getValue("studentID")), java.util.UUID.fromString(args.getValue("metricID") as String), Instant.parse(args.getValue(prefix + "At") as String), zone, decimal(args.getValue(prefix + "Value"))!!, args.getValue(prefix + "Unit") as String)
                val a = index.upsert(point("first")); val b = index.upsert(point("second"))
                val points = index.history(a.studentID, a.metricID)
                mapOf("count" to points.size.toLong(), "keptFirstID" to (b.id == a.id), "days" to points.map { it.localCalendarDay.toString() }, "units" to points.map { it.enteredUnit })
            }
            else -> error("Unmapped S3 operation")
        }
    }
}
