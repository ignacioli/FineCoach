// fictional-data: synthetic loads and public built-in exercise metadata.
package com.ignacioli.finecoach
import com.ignacioli.finecoach.core.domain.progress.EstimatedOneRepMax
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import java.io.File
import org.junit.Assert.*
import org.junit.Test

class EstimatedOneRepMaxTests {
    @Test fun boundaries() {
        fun estimate(w: String, r: String) = EstimatedOneRepMax.value(DecimalValue.parse(w), DecimalValue.parse(r), EstimatedOneRepMax.exerciseIDs.first())?.canonicalString
        assertEquals("90", estimate("90", "1")); assertEquals("120", estimate("90", "10"))
        for (r in listOf("0", "11", "1.5", "-1")) assertNull(estimate("90", r))
        assertNull(estimate("0", "5")); assertNull(estimate("-1", "5"))
        assertNull(EstimatedOneRepMax.value(DecimalValue.parse("90"), DecimalValue.parse("5"), S3Fixtures.exercise))
    }
    @Test fun foundationDecimalExpansion() {
        fun estimate(w: String, r: String) = EstimatedOneRepMax.value(DecimalValue.parse(w), DecimalValue.parse(r), EstimatedOneRepMax.exerciseIDs.first())!!.canonicalString
        assertEquals("53.33333333333333333333333333333333", estimate("50", "2"))
        assertEquals("66.66666666666666666666666666666666", estimate("50", "10"))
        assertEquals("1.066666666666666666666666666666666", estimate("1", "2"))
        assertEquals("2.46666666666666666666666666666666666666", estimate("2", "7"))
        assertEquals("15226337311522633731152263373115226336.2", estimate("12345678901234567890123456789012345678", "7"))
        assertEquals("133333333333333333333333333333333333332", estimate("99999999999999999999999999999999999999", "10"))
    }
    @Test fun allApprovedIDsAreBarbellWeightReps() {
        @Suppress("UNCHECKED_CAST")
        val catalog = VectorJSON(File("src/main/assets/exercises/provenance.json").readText()).parse() as Map<String, Any?>
        val rows = catalog["exercises"] as List<Map<String, Any?>>
        assertEquals(11, EstimatedOneRepMax.exerciseIDs.size)
        for (id in EstimatedOneRepMax.exerciseIDs) {
            val row = rows.single { it["id"] == id.value }
            assertEquals("weightReps", row["recordMode"]); assertEquals("杠铃", row["equipmentClass"])
        }
    }
}
