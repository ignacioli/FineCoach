package com.ignacioli.finecoach

import java.awt.Color
import java.awt.image.BufferedImage
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ConformanceIconPixelsTests {
    private fun box(x: Double = 0.0, y: Double = 0.0) = JSONObject().put("x",x).put("y",y).put("w",24.0).put("h",24.0)
    private fun image(x: Int = 0, y: Int = 0, different: Boolean = false) = BufferedImage(96,96,BufferedImage.TYPE_INT_RGB).apply {
        createGraphics().apply {
            color = Color.WHITE; fillRect(0,0,96,96)
            color = Color.BLACK
            if (different) fillRect(x+20,y+6,6,36) else { fillRect(x+6,y+20,36,6); fillRect(x+8,y+12,5,22); fillRect(x+35,y+12,5,22) }
            dispose()
        }
    }
    @Test fun parentCentreCancelsTranslationButDoesNotFitInk() {
        val a = ConformanceIconPixels.mask(image(),box(),48,48)
        val b = ConformanceIconPixels.mask(image(8,6),box(4.0,3.0),48,48)
        assertEquals(1.0,ConformanceIconPixels.iou(a,b),0.0)
        val displacedInk = ConformanceIconPixels.mask(image(8,6),box(),48,48)
        assertTrue(ConformanceIconPixels.iou(a,displacedInk) < ConformanceIconPixels.minimumIou)
    }
    @Test fun differentShapeAndOnePointFourScaleFail() {
        val a = ConformanceIconPixels.mask(image(),box(),48,48)
        val different = ConformanceIconPixels.mask(image(different=true),box(),48,48)
        assertTrue(ConformanceIconPixels.iou(a,different) < ConformanceIconPixels.minimumIou)
        assertTrue(ConformanceIconPixels.iou(a,ConformanceIconPixels.scaled(a,1.4)) < ConformanceIconPixels.minimumIou)
    }
    @Test fun blankInkCannotPassAndClippedCropCannotBeCompared() {
        val empty = ConformanceIconPixels.Mask(4,4,BooleanArray(16))
        assertEquals(0.0,ConformanceIconPixels.iou(empty,empty),0.0)
        assertThrows(IllegalArgumentException::class.java) { ConformanceIconPixels.mask(image(),box(-1.0),48,48) }
    }
    @Test fun backgroundAndInkThresholdAreLocalAndDeterministic() {
        val a = image()
        val b = image().apply { for (y in 0 until height) for (x in 0 until width) if (getRGB(x,y) and 0xffffff == 0xffffff) setRGB(x,y,0xffe0d0c0.toInt()) }
        assertEquals(1.0,ConformanceIconPixels.iou(ConformanceIconPixels.mask(a,box(),48,48),ConformanceIconPixels.mask(b,box(),48,48)),0.0)
    }
    @Test fun iconShapeFailureIsAnElementGateFailure() {
        val layer = box().put("path","icon").put("type","group").put("name","icon / synthetic")
        fun row() = JSONObject().put("path","icon").put("selector",JSONObject()).put("geometryMatches",true)
            .put("geometry",JSONObject().put("actualBounds",box())).put("status","PASS").put("category","PASS")
            .put("failedChecks",org.json.JSONArray())
        val pass = row()
        assertEquals(0,ConformanceIconPixels.evaluate(listOf(layer),listOf(pass),image(),image()).getInt("failed"))
        val fail = row()
        assertEquals(1,ConformanceIconPixels.evaluate(listOf(layer),listOf(fail),image(),image(different=true)).getInt("failed"))
        assertEquals("FAIL",fail.getString("status"))
        assertEquals("UI_DEVIATION",fail.getString("category"))
        assertEquals("ICON_PIXELS",fail.getJSONArray("failedChecks").getString(0))
        val blocked = row().put("geometryMatches",false).put("status","FAIL")
        ConformanceIconPixels.evaluate(listOf(layer),listOf(blocked),image(),image())
        assertEquals("BLOCKED_PARENT_GEOMETRY",blocked.getJSONObject("ICON_PIXELS").getString("status"))
        assertTrue(blocked.getJSONObject("ICON_PIXELS").isNull("iou"))
        val platform = JSONObject(layer.toString()).put("name","icon / filter")
        assertEquals(0,ConformanceIconPixels.evaluate(listOf(platform),listOf(row()),image(),image(different=true)).getJSONArray("checks").length())
    }
    @Test fun approvedAd01ComponentAliasIsExcluded() {
        assertEquals("edit",ConformanceMapping.platformIcon("DS-SET-ROW · edit (铅笔)"))
        assertNull(ConformanceMapping.platformIcon("icon / dumbbell"))
    }
    @Test fun canonicalDesignAssetsRejectScaleAndDifferentAsset() {
        val android = java.io.File(System.getProperty("finecoach.storageProjectDirectory")).parentFile
        val masks = mutableMapOf<String,ConformanceIconPixels.Mask>()
        for ((screen,png) in listOf("P0-a2-training" to "design/experience-p0/screens/P0-a2-training.png",
            "D2b-exercise-library" to "design/m1-b-hifi/screens/20-exercise-library.png")) {
            val layers = JSONObject(java.io.File(android,"design-assets/conformance/$screen.layers.json").readText()).getJSONArray("layers")
            val image = javax.imageio.ImageIO.read(java.io.File(android.parentFile,png))
            for (i in 0 until layers.length()) {
                val layer = layers.getJSONObject(i)
                val name = layer.getString("name")
                if (!name.startsWith("icon / ") || ConformanceMapping.platformIcon(name) != null) continue
                val mask = ConformanceIconPixels.mask(image,layer,(layer.getDouble("w")*2).toInt(),(layer.getDouble("h")*2).toInt())
                val metric = ConformanceIconPixels.iou(mask,ConformanceIconPixels.scaled(mask,1.4))
                assertTrue("$screen $name scale1.4 IoU=$metric",metric < ConformanceIconPixels.minimumIou)
                masks[name] = mask
            }
        }
        assertTrue(masks.size >= 6)
        val swapped = ConformanceIconPixels.iou(masks.getValue("icon / barbell"),masks.getValue("icon / dumbbell"))
        println("ICON_PIXELS negative swapped barbell/dumbbell IoU=$swapped")
        assertTrue(swapped < ConformanceIconPixels.minimumIou)
    }

}
