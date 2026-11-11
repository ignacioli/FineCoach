package com.ignacioli.finecoach

import java.awt.Color
import java.awt.image.BufferedImage
import kotlin.random.Random
import org.junit.Assert.*
import org.junit.Test

@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner::class)
@org.robolectric.annotation.Config(sdk = [36])
class ConformanceSsimTests {
    private fun copy(source: BufferedImage) = BufferedImage(source.width,source.height,BufferedImage.TYPE_INT_RGB).also {
        it.createGraphics().apply { drawImage(source,0,0,null); dispose() }
    }
    private fun synthetic() = BufferedImage(192,192,BufferedImage.TYPE_INT_RGB).also { image ->
        image.createGraphics().apply {
            color=Color.WHITE; fillRect(0,0,192,192)
            color=Color(42,40,34); fillRect(20,20,100,36)
            color=Color.BLACK
            for(y in 75..145 step 14) for(x in 16..160 step 12) fillRect(x,y,7,9)
            dispose()
        }
    }
    @Test fun identicalIsOne() { assertEquals(1.0,ConformanceSsim.compare(synthetic(),synthetic()).global,1e-10) }
    @Test fun lightNoiseIsCloseToOne() {
        val a=synthetic(); val b=copy(a); val random=Random(17)
        for(y in 0 until b.height) for(x in 0 until b.width) {
            val value=((b.getRGB(x,y) and 255)+random.nextInt(-1,2)).coerceIn(0,255)
            b.setRGB(x,y,(value shl 16) or (value shl 8) or value)
        }
        // Keep the colored control unchanged, only perturb the grayscale region.
        b.createGraphics().apply { drawImage(a.getSubimage(20,20,100,36),20,20,null); dispose() }
        assertTrue(ConformanceSsim.compare(a,b).global>0.99)
    }
    @Test fun translationColorAndTextRemovalDecreaseSimilarity() {
        val a=synthetic()
        val shifted=copy(a).also { it.createGraphics().apply { color=Color.WHITE; fillRect(0,0,192,192); drawImage(a,8,8,null); dispose() } }
        val recolored=copy(a).also { it.createGraphics().apply { color=Color.MAGENTA; fillRect(20,20,100,36); dispose() } }
        val removed=copy(a).also { it.createGraphics().apply { color=Color.WHITE; fillRect(16,75,160,79); dispose() } }
        for(b in listOf(shifted,recolored,removed)) assertTrue(ConformanceSsim.compare(a,b).global<0.97)
    }
    @Test fun uniformImagesMatchStandardLuminanceFormula() {
        fun uniform(value: Int) = BufferedImage(32,32,BufferedImage.TYPE_INT_RGB).also { image ->
            for(y in 0 until 32) for(x in 0 until 32) image.setRGB(x,y,(value shl 16) or (value shl 8) or value)
        }
        val expected=(2.0*64*128+6.5025)/(64.0*64+128.0*128+6.5025)
        assertEquals(expected,ConformanceSsim.compare(uniform(64),uniform(128)).global,1e-10)
    }
    @Test fun trailingStripWithNoValidCentersIsNotAnEmptyBlock() {
        val image=BufferedImage(32,97,BufferedImage.TYPE_INT_RGB)
        val score=ConformanceSsim.compare(image,image)
        assertEquals(1,score.strips().size)
        assertEquals(1.0,score.minimum,1e-10)
    }
    @Test fun dimensionsMustMatch() {
        try { ConformanceSsim.compare(synthetic(),BufferedImage(193,192,BufferedImage.TYPE_INT_RGB)); fail("must reject dimensions") }
        catch(expected: IllegalArgumentException) { /* Expected. */ }
    }
}
