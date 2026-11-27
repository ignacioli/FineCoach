// fictional-data: structural counts only; never contains identity, exercise names or measurements.
package com.ignacioli.finecoach.seed

import android.content.Context
import com.ignacioli.finecoach.core.application.ExerciseCatalogLoader
import com.ignacioli.finecoach.core.domain.body.BuiltInBodyMetric

/** Derives expected rows from declared inputs, independently of the installed database. */
internal object S1SeedInventory {
    // dataset, version, status, scenario, and the final verified row count.
    const val METADATA_ROWS = 5

    fun expected(context: Context, fixture: S1SeedFixture, scenario: String): Map<String, Int> {
        val catalog = ExerciseCatalogLoader(context.assets).load(fixture.now).records
        val sessions = fixture.selected("sessions", scenario)
        val templates = fixture.selected("templates", scenario)
        val packages = fixture.selected("packages", scenario)
        val appointments = fixture.selected("appointments", scenario)
        val body = scenario == "multi"
        fun instances(row: org.json.JSONObject): Int = when (row.optString("termination")) {
            "RepeatCount" -> row.getInt("count")
            "EndDate" -> ((row.getLong("endDayOffset") - row.getLong("dayOffset")) / 2 + 1).toInt()
            else -> 1
        }
        return sortedMapOf(
            "exercise_catalog" to catalog.size,
            "exercise_name_claims" to catalog.count { !it.isRetired },
            "exercise_preferences" to 0,
            "students" to fixture.selected("students", scenario).size,
            "course_packages" to packages.size,
            "active_package_claims" to packages.groupBy { it.getInt("studentID") }.values.count { it.last().getString("state") == "active" },
            "credit_adjustments" to (fixture.selected("ledger", scenario).size + appointments.count { it.optString("absentCreditChoice") == "charged" }),
            "sessions" to sessions.size,
            "active_session_pointers" to sessions.count { it.getString("state") == "inProgress" },
            "session_training_focus" to sessions.sumOf { it.strings("trainingFocus").distinct().size },
            "session_exercises" to sessions.sumOf { it.objects("exercises").size },
            "training_sets" to sessions.sumOf { it.objects("exercises").sumOf { exercise -> exercise.objects("sets").size } },
            "session_sections" to (sessions + templates).sumOf { it.objects("sections").size },
            "training_templates" to templates.size,
            "template_training_focus" to templates.sumOf { it.strings("trainingFocus").distinct().size },
            "template_exercises" to templates.sumOf { it.objects("exercises").size },
            "template_planned_sets" to templates.sumOf { it.objects("exercises").sumOf { exercise -> exercise.objects("sets").size } },
            "appointments" to appointments.sumOf(::instances),
            "recurrence_series" to appointments.count { it.has("termination") },
            "body_metric_definitions" to if (body) BuiltInBodyMetric.entries.size + 1 else 0,
            "body_measurements" to if (body) S3SeedFixture.bodyInputs().size else 0,
        )
    }
}
