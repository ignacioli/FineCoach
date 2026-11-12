package com.ignacioli.finecoach

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner::class)
@org.robolectric.annotation.Config(sdk = [36])
class ConformanceRelativeGeometryTests {
    private fun row(path: String, x: Double, y: Double, w: Double = 10.0, h: Double = 10.0, dx: Double = 0.0, dy: Double = 0.0, dw: Double = 0.0): JSONObject {
        fun box(x: Double,y: Double,w: Double,h: Double) = JSONObject().put("x",x).put("y",y).put("w",w).put("h",h)
        val design = box(x,y,w,h)
        val actual = box(x+dx,y+dy,w+dw,h)
        return JSONObject().put("path",path).put("selector",JSONObject()).put("category","PASS").put("textMatches",true).put("tokenMatches",true)
            .put("delta",box(dx,dy,dw,0.0)).put("geometry",JSONObject().put("expectedBounds",design).put("actualBounds",actual))
    }
    private fun count(rows: List<JSONObject>, check: String) = ConformanceRelativeGeometry.evaluate(rows).getJSONObject("counts").getInt(check)
    @Test fun wholePageFivePassesTenFailsGrossOnly() {
        for (shift in listOf(0.0,5.0,8.0,10.0)) {
            val result = ConformanceRelativeGeometry.evaluate(listOf(row("a",0.0,0.0,dx=shift,dy=shift),row("b",0.0,20.0,dx=shift,dy=shift)))
            val counts = result.getJSONObject("counts")
            assertEquals(if (shift>8) 2 else 0,counts.getInt("ABSOLUTE_GROSS"))
            listOf("SIZE","GAP","INSET","ALIGN","COLOR").forEach { assertEquals(it,0,counts.getInt(it)) }
        }
    }
    @Test fun oneGapDoesNotCascadeAndBothBoundariesPass() {
        for (shift in listOf(-2.0,0.0,2.0,3.0)) {
            val rows = listOf(row("a",0.0,0.0),row("b",0.0,20.0,dy=shift),row("c",0.0,40.0,dy=shift))
            val result = ConformanceRelativeGeometry.evaluate(rows)
            assertEquals(if (shift==3.0) 1 else 0,result.getJSONObject("counts").getInt("GAP"))
            val gaps = result.getJSONArray("gaps")
            assertEquals(2,gaps.length())
            assertEquals("a",gaps.getJSONObject(0).getString("a"))
        }
    }
    @Test fun childInsetChoosesSmallestParent() {
        for (shift in listOf(0.0,2.0,3.0)) {
            assertEquals(if (shift>2) 1 else 0,count(listOf(row("outer",0.0,0.0,100.0,100.0),
                row("parent",10.0,10.0,50.0,50.0),row("child",20.0,20.0,dx=shift)),"INSET"))
        }
    }
    @Test fun alignmentIsOneFailurePerEdgeGroup() {
        for (shift in listOf(0.0,2.0,3.0)) {
            // Different widths ensure only the left edges form a group.
            assertEquals(if (shift>2) 1 else 0,count(listOf(row("a",0.0,0.0),row("b",0.0,20.0,w=20.0,dx=shift)),"ALIGN"))
        }
    }
    @Test fun sizeAndExactColorHavePositiveAndNegativeCases() {
        for (delta in listOf(-2.0,0.0,2.0,3.0)) assertEquals(if (delta>2) 1 else 0,count(listOf(row("a",0.0,0.0,dw=delta)),"SIZE"))
        assertEquals(0,count(listOf(row("a",0.0,0.0)),"COLOR"))
        assertEquals(1,count(listOf(row("a",0.0,0.0).put("tokenMatches",false)),"COLOR"))
    }
    @Test fun horizontalGapAndVerticalInsetRejectThreeDp() {
        for (shift in listOf(-2.0,2.0,3.0)) {
            assertEquals(if (shift>2) 1 else 0,count(listOf(row("a",0.0,0.0),row("b",20.0,0.0,dx=shift)),"GAP"))
            assertEquals(if (shift>2) 1 else 0,count(listOf(row("p",0.0,0.0,100.0,100.0),row("c",20.0,20.0,dy=shift)),"INSET"))
        }
    }
    @Test fun alignmentMembershipUsesDesignHalfDpBoundary() {
        assertEquals(1,count(listOf(row("a",0.0,0.0),row("b",0.5,20.0,w=20.0,dx=3.0)),"ALIGN"))
        assertEquals(0,count(listOf(row("a",0.0,0.0),row("b",0.501,20.0,w=20.0,dx=3.0)),"ALIGN"))
    }
}
