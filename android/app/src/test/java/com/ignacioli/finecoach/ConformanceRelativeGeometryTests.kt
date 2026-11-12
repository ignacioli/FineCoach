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
    @Test fun quarterDpPrecisionAppliesToEveryRelativeCheck() {
        for ((delta, passes) in listOf(-2.1 to true, -2.3 to false, 2.12 to true, -2.13 to false, 2.125 to false, -2.125 to false)) {
            val expected = if (passes) 0 else 1
            val size = ConformanceRelativeGeometry.evaluate(listOf(row("a",0.0,0.0,dw=delta)))
            assertEquals(expected,size.getJSONObject("counts").getInt("SIZE"))
            val detail = size.getJSONArray("checks").getJSONObject(0).getJSONObject("w")
            assertEquals(delta,detail.getDouble("delta"),0.0)
            assertEquals(if (passes) 2.0 else 2.25,kotlin.math.abs(detail.getDouble("roundedDelta")),0.0)
            assertEquals(expected,count(listOf(row("a",0.0,0.0),row("b",20.0,0.0,dx=delta)),"GAP"))
            assertEquals(expected,count(listOf(row("p",0.0,0.0,100.0,100.0),row("c",20.0,20.0,dx=delta)),"INSET"))
            assertEquals(expected,count(listOf(row("a",0.0,0.0),row("b",0.0,20.0,w=20.0,dx=delta)),"ALIGN"))
        }
    }
    @Test fun wholePageFivePassesTenFailsGrossOnly() {
        for (shift in listOf(0.0,5.0,8.0,10.0)) {
            val result = ConformanceRelativeGeometry.evaluate(listOf(row("container",-10.0,-10.0,100.0,100.0,dx=shift,dy=shift),row("a",0.0,0.0,dx=shift,dy=shift),row("b",0.0,20.0,dx=shift,dy=shift)))
            val counts = result.getJSONObject("counts")
            assertEquals(if (shift>8) 3 else 0,counts.getInt("ABSOLUTE_GROSS"))
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
        val result = ConformanceRelativeGeometry.evaluate(listOf(row("outer",0.0,0.0,100.0,100.0),
            row("parent",10.0,10.0,50.0,50.0,dx=3.0),row("child",20.0,20.0)))
        val checks = result.getJSONArray("checks")
        val inset = (0 until checks.length()).map { checks.getJSONObject(it) }.single {
            it.getString("check") == "INSET" && it.getJSONArray("members").getString(1) == "child"
        }
        assertEquals("parent",inset.getJSONArray("members").getString(0))
        assertEquals(-3.0,inset.getJSONObject("x").getDouble("delta"),0.0)
        assertFalse(inset.getBoolean("passed"))
    }
    @Test fun alignmentMembershipIsTransitive() {
        for (shift in listOf(0.0,5.0)) {
            val result = ConformanceRelativeGeometry.evaluate(listOf(row("a",0.0,0.0),
                row("b",0.4,20.0,w=20.0),row("c",0.8,40.0,w=30.0,dx=shift)))
            val checks = result.getJSONArray("checks")
            val group = (0 until checks.length()).map { checks.getJSONObject(it) }.single {
                it.getString("check") == "ALIGN" && it.getString("edge") == "left"
            }
            assertEquals(3,group.getJSONArray("members").length())
            assertEquals(shift == 0.0,group.getBoolean("passed"))
            assertEquals(if (shift == 0.0) 0 else 1,result.getJSONObject("counts").getInt("ALIGN"))
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
