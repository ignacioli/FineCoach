package com.ignacioli.finecoach

import java.awt.Color
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*

internal object ConformanceSsimCalibration {
    private fun copyImage(source: BufferedImage) = BufferedImage(source.width,source.height,BufferedImage.TYPE_INT_RGB).also {
        it.createGraphics().apply { drawImage(source,0,0,null); dispose() }
    }
    fun samples(android: BufferedImage): List<Pair<String, BufferedImage>> {
        // Fixed approved viewport coordinates; no product-code or baseline mutations.
        val removed=copyImage(android).also { it.createGraphics().apply { color=Color.WHITE; fillRect(32,1520,716,104); dispose() } }
        val shifted=copyImage(android).also { it.createGraphics().apply {
            color=Color.WHITE; fillRect(32,1368,716,144)
            drawImage(android.getSubimage(32,1368,716,128),32,1384,null); dispose()
        } }
        val recolored=copyImage(android).also { image ->
            for(y in 0 until image.height) for(x in 0 until image.width)
                if(image.getRGB(x,y) and 0xffffff == 0x2a2822) image.setRGB(x,y,0x0000ff)
        }
        return listOf("training" to android,"removed-finish-control" to removed,"row-down-8dp" to shifted,"non-token-primary" to recolored)
    }
    fun evaluate(app: File, out: File): JSONObject {
        val design=ImageIO.read(File(app,"../../design/experience-p0/screens/P0-a2-training.png"))
        val samples=samples(ImageIO.read(File(out,"P0-a2-training.android.png")))
        val rows=JSONArray()
        for((name,image) in samples) {
            val score=ConformanceSsim.compare(design,image)
            rows.put(score.json(false).put("sample",name))
            println("SSIM_CALIBRATION $name global=${score.global} minimum=${score.minimum} passed=${score.passes()}")
        }
        val report = JSONObject().put("samples",rows)
            .put("mutations", "删除结束训练控件[16,760,358,52]dp；休息行[16,684,358,64]dp下移8dp；所有精确#2a2822像素替换#0000ff；均基于本次真实截图，不改设计或基线。")
        File(out,"P1.2-ssim-calibration.json").writeText(report.toString(2))
        return report
    }
    fun assertDiagnostics(report: JSONObject) {
        val rows = report.getJSONArray("samples")
        assertEquals("Training and three fixed mutations must be reported", 4, rows.length())
        for(i in 0 until rows.length()) {
            val row=rows.getJSONObject(i)
            assertFalse("SSIM is diagnostic only", row.getBoolean("gated"))
            assertTrue(row.getDouble("global").isFinite())
            assertTrue(row.getDouble("minimumStrip").isFinite())
        }
    }
}
