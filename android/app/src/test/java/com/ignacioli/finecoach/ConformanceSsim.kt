package com.ignacioli.finecoach

import java.awt.image.BufferedImage
import kotlin.math.exp
import org.json.JSONArray
import org.json.JSONObject

/** Test-only SSIM: BT.601 luma in [0,255], Gaussian 11x11 sigma=1.5,
 * population moments, K1=.01/K2=.03, L=255. Valid windows only (no padding).
 * Every valid center has equal weight; strips partition centers without dropping boundaries.
 */
internal object ConformanceSsim {
    // Provisional calibration values, not product-owner acceptance thresholds.
    const val GLOBAL_THRESHOLD = 0.762
    const val MIN_STRIP_THRESHOLD = 0.26
    const val STRIP_PX = 96 // 48dp at the conformance viewport's density 2.
    private const val R = 5
    private val kernel = DoubleArray(11) { exp(-((it - R) * (it - R)) / 4.5) }.let { k ->
        val sum = k.sum(); DoubleArray(k.size) { k[it] / sum }
    }
    data class Result(val width: Int, val height: Int, val values: DoubleArray) {
        val global = mean(0, 0, width, height)
        private fun valid(i: Int) = i % width in R until width-R && i / width in R until height-R
        fun mean(x0: Int, y0: Int, x1: Int, y1: Int): Double {
            var sum = 0.0; var count = 0
            for (y in maxOf(R,y0) until minOf(height-R,y1)) for (x in maxOf(R,x0) until minOf(width-R,x1)) {
                sum += values[y*width+x]; count++
            }
            require(count > 0); return sum/count
        }
        fun strips(): List<JSONObject> = (0 until height step STRIP_PX).filter { it < height-R }.map { y ->
            JSONObject().put("yStartPx", y).put("yEndPxExclusive", minOf(y+STRIP_PX,height))
                .put("yStartDp", y/2.0).put("yEndDpExclusive", minOf(y+STRIP_PX,height)/2.0)
                .put("ssim", mean(0,y,width,minOf(y+STRIP_PX,height)))
        }
        val minimum get() = strips().minOf { it.getDouble("ssim") }
        fun passes() = global >= GLOBAL_THRESHOLD && minimum >= MIN_STRIP_THRESHOLD
        fun json(gated: Boolean): JSONObject = JSONObject().put("algorithm", "BT.601 Gaussian11 sigma1.5 K1=.01 K2=.03 L=255 valid/population")
            .put("global",global).put("minimumStrip",minimum).put("strips",JSONArray(strips()))
            .put("lowest5",JSONArray(strips().sortedBy { it.getDouble("ssim") }.take(5)))
            .put("globalThreshold", GLOBAL_THRESHOLD).put("minimumStripThreshold", MIN_STRIP_THRESHOLD)
            .put("gated", gated).put("thresholdPassed",passes())
        fun heatmap(): BufferedImage = BufferedImage(width,height,BufferedImage.TYPE_INT_RGB).also { image ->
            for (y in 0 until height) for (x in 0 until width) {
                val i=y*width+x
                val loss=((1-values[i]).coerceIn(0.0,1.0)*255).toInt()
                image.setRGB(x,y,if (!valid(i)) 0x808080 else (loss shl 16) or ((255-loss) shl 8))
            }
        }
        /** Loss attribution by window center, not a causal estimate or a waiver. */
        fun contribution(x0: Int,y0: Int,x1: Int,y1: Int): JSONObject {
            var loss=0.0; var n=0
            for(y in maxOf(R,y0) until minOf(height-R,y1)) for(x in maxOf(R,x0) until minOf(width-R,x1)) {
                loss+=1-values[y*width+x]; n++
            }
            val total=(width-2*R)*(height-2*R)
            return JSONObject().put("centerCount",n).put("ssim",if(n>0) 1-loss/n else JSONObject.NULL)
                .put("globalLossContribution",loss/total).put("totalLossShare",if(global<1) loss/(total*(1-global)) else 0.0)
        }
    }
    fun compare(a: BufferedImage,b: BufferedImage): Result {
        require(a.width==b.width && a.height==b.height && a.width>10 && a.height>10)
        val w=a.width; val h=a.height
        fun gray(image: BufferedImage)=DoubleArray(w*h) { i ->
            val rgb=image.getRGB(i%w,i/w)
            .299*(rgb shr 16 and 255)+.587*(rgb shr 8 and 255)+.114*(rgb and 255)
        }
        val x=gray(a); val y=gray(b)
        fun blur(input: DoubleArray): DoubleArray {
            val tmp=DoubleArray(w*h); val out=DoubleArray(w*h)
            for(row in 0 until h) for(col in R until w-R) {
                var s=0.0; for(k in -R..R) s+=kernel[k+R]*input[row*w+col+k]; tmp[row*w+col]=s
            }
            for(row in R until h-R) for(col in R until w-R) {
                var s=0.0; for(k in -R..R) s+=kernel[k+R]*tmp[(row+k)*w+col]; out[row*w+col]=s
            }
            return out
        }
        val mx=blur(x); val my=blur(y)
        val xx=blur(DoubleArray(w*h) { x[it]*x[it] }); val yy=blur(DoubleArray(w*h) { y[it]*y[it] })
        val xy=blur(DoubleArray(w*h) { x[it]*y[it] })
        val c1=6.5025; val c2=58.5225
        val scores=DoubleArray(w*h)
        for(row in R until h-R) for(col in R until w-R) {
            val i=row*w+col; val ax=mx[i]; val ay=my[i]
            val vx=(xx[i]-ax*ax).coerceAtLeast(0.0); val vy=(yy[i]-ay*ay).coerceAtLeast(0.0)
            scores[i]=(((2*ax*ay+c1)*(2*(xy[i]-ax*ay)+c2))/((ax*ax+ay*ay+c1)*(vx+vy+c2))).coerceIn(-1.0,1.0)
        }
        return Result(w,h,scores)
    }
}
