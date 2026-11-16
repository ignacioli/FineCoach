package com.ignacioli.finecoach

import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import kotlin.math.exp
import org.json.JSONArray
import org.json.JSONObject

/** One-round diagnostic experiment. Never changes approved PNGs, baselines or gate thresholds. */
internal object ConformanceSsimAlignment {
    private fun objects(a: JSONArray) = (0 until a.length()).map { a.getJSONObject(it) }
    private fun gray(image: BufferedImage, x: Int, y: Int): Double {
        val rgb = image.getRGB(x, y)
        return .299 * (rgb shr 16 and 255) + .587 * (rgb shr 8 and 255) + .114 * (rgb and 255)
    }
    private fun blur(image: BufferedImage): BufferedImage {
        val w = image.width; val h = image.height
        val k = DoubleArray(7) { exp(-((it-3)*(it-3))/2.0) }.let { v -> val sum=v.sum(); v.map { it/sum } }
        val tmp = DoubleArray(w*h)
        for(y in 0 until h) for(x in 0 until w) for(i in -3..3)
            tmp[y*w+x] += k[i+3]*gray(image,(x+i).coerceIn(0,w-1),y)
        return BufferedImage(w,h,BufferedImage.TYPE_INT_RGB).also { out ->
            for(y in 0 until h) for(x in 0 until w) {
                var v=0.0
                for(i in -3..3) v+=k[i+3]*tmp[(y+i).coerceIn(0,h-1)*w+x]
                val c=v.toInt().coerceIn(0,255); out.setRGB(x,y,(c shl 16) or (c shl 8) or c)
            }
        }
    }
    private fun statistics(image: BufferedImage): JSONArray = JSONArray((768 until 864).map { y ->
        val row=DoubleArray(image.width) { x -> gray(image,x,y) }; val mean=row.average()
        JSONObject().put("yPx",y).put("mean",mean).put("variance",row.map { (it-mean)*(it-mean) }.average())
    })
    fun evaluate(app: File, out: File) {
        val names=listOf("P0-a2-training","D2b-exercise-library","D8c-add-exercise")
        // Exercise reports may not yet exist on a clean build; each producer retries this diagnostic.
        fun directory(name: String) = if(name==names[0]) out else File(out,name)
        if(names.any { !File(directory(it),"$it.report.json").isFile }) return
        val rows=JSONArray(); val evidence=JSONObject(); val metadata=JSONArray()
        for(name in names) {
            val dir=directory(name)
            val report=JSONObject(File(dir,"$name.report.json").readText())
            val map=JSONObject(File(app,"../design-assets/conformance/$name.map.json").readText())
            val layers=objects(JSONObject(File(app,"../design-assets/conformance/$name.layers.json").readText()).getJSONArray("layers"))
            val design=ImageIO.read(File(app,"../../${report.getString("designPath")}"))
            val actual=ImageIO.read(File(dir,"$name.android.png"))
            val offset=(map.getDouble("originOffsetY")*2).toInt()
            val aligned=BufferedImage(design.width,design.height,BufferedImage.TYPE_INT_RGB).also {
                it.createGraphics().apply { drawImage(design,0,offset,null); dispose() }
            }
            val pending=objects(map.getJSONArray("elements")).filter { it.has("pendingBoardFix") }
            val regions=JSONArray()
            for(entry in pending) {
                val layer=layers.single { it.getString("path")==entry.getString("path") }
                val fix=entry.getJSONObject("pendingBoardFix")
                val originalY=layer.getDouble("y")*2
                val alignedY=originalY+offset
                // Exclude both translated PNG and registered actual boxes (bottom anchors stay fixed).
                val actualY=originalY+(if(entry.optString("anchor")=="bottom") 0 else offset)+fix.optDouble("dy",0.0)*2
                val x=layer.getDouble("x")*2; val dx=fix.optDouble("dx",0.0)*2
                regions.put(JSONObject().put("path",entry.getString("path"))
                    .put("x0",minOf(x,x+dx)).put("x1",maxOf(x,x+dx)+layer.getDouble("w")*2)
                    .put("y0",minOf(alignedY,actualY)).put("y1",maxOf(alignedY,actualY)+layer.getDouble("h")*2))
            }
            metadata.put(JSONObject().put("screen",name).put("offsetPx",offset).put("pendingRegions",regions))
            val samples=if(name==names[0]) ConformanceSsimCalibration.samples(actual) else listOf(name to actual)
            if(name==names[0]) evidence.put("rawBandSsim",ConformanceSsim.compare(design,actual).mean(0,768,design.width,864)).put("designRows",statistics(design)).put("androidRows",statistics(actual))
                .put("alignedDesignRows",statistics(aligned))
            val excluded=objects(regions)
            for(mode in listOf("A","B","C")) {
                val radius=if(mode=="C") 8 else 5
                val a=if(mode=="C") blur(aligned) else aligned
                for((sample,image) in samples) {
                    val b=if(mode=="C") blur(image) else image
                    val score=ConformanceSsim.compare(a,b)
                    if(name==names[0] && sample=="training") evidence.put("${mode}UnmaskedBandSsim",score.mean(0,768,a.width,864))
                    val strips=JSONArray(); var total=0.0; var count=0
                    for(start in 0 until a.height step 96) {
                        var sum=0.0; var n=0
                        for(y in maxOf(start,radius) until minOf(start+96,a.height-radius)) for(x in radius until a.width-radius) {
                            // 52dp top safe area and 34dp bottom system area, in BOTH coordinate frames.
                            if(y-radius<104 || y+radius>=a.height-68 || y-offset-radius<104 || y-offset+radius>=a.height-68) continue
                            if(mode!="A" && excluded.any { r ->
                                x+radius>=r.getDouble("x0") && x-radius<r.getDouble("x1") &&
                                    y+radius>=r.getDouble("y0") && y-radius<r.getDouble("y1")
                            }) continue
                            sum+=score.values[y*a.width+x]; n++
                        }
                        if(n>0) strips.put(JSONObject().put("yStartDp",start/2.0).put("ssim",sum/n).put("centers",n))
                        total+=sum; count+=n
                    }
                    check(count>0)
                    val row=JSONObject().put("mode",mode).put("sample",sample).put("global",total/count)
                        .put("minimumStrip",objects(strips).minOf { it.getDouble("ssim") }).put("strips",strips).put("centers",count)
                    rows.put(row)
                    println("SSIM_ALIGN $mode $sample global=${row.getDouble("global")} minimum=${row.getDouble("minimumStrip")}")
                }
            }
        }
        File(out,"P1.2b-ssim-alignment.json").writeText(JSONObject().put("samples",rows).put("metadata",metadata)
            .put("strip384to432",evidence).put("maskRule","Exclude centers whose complete support touches masked pixels; A top52dp/bottom34dp in both frames; B registered pending boxes union; C grayscale Gaussian sigma1 radius3, total support radius8px. Whole PNG translation, bottom anchors are not piecewise realigned.").toString(2))
    }
}
