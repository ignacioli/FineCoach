package com.ignacioli.finecoach

import java.io.File
import java.security.MessageDigest
import javax.xml.parsers.DocumentBuilderFactory
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner::class)
@org.robolectric.annotation.Config(sdk = [36])
class S1ComponentAssetTests {
    private val app = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))
    private val root = app.parentFile.parentFile
    private val androidNS = "http://schemas.android.com/apk/res/android"
    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    private fun xml(file: File) = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        setFeature(javax.xml.XMLConstants.FEATURE_SECURE_PROCESSING, true)
        setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
    }.newDocumentBuilder().parse(file).documentElement

    @Test fun allEquipmentVectorsRetainApprovedGeometryAndHashes() {
        val assets = File(root, "android/design-assets")
        val records = JSONObject(File(assets, "equipment-provenance.json").readText()).getJSONArray("icons")
        val sums = File(assets, "equipment-SHA256SUMS").readLines().associate { it.substringAfter("  ") to it.substringBefore("  ") }
        assertEquals(21, records.length()); assertEquals(42, sums.size)
        for (index in 0 until records.length()) {
            val row = records.getJSONObject(index)
            val source = File(root, row.getString("source")); val vector = File(root, "android/${row.getString("drawable")}")
            assertEquals(digest(source), row.getString("sourceSha256")); assertEquals(digest(vector), row.getString("drawableSha256"))
            assertEquals(digest(source), sums.getValue(row.getString("source")))
            assertEquals(digest(vector), sums.getValue("android/${row.getString("drawable")}"))
            val svg = xml(source); val v = xml(vector)
            assertEquals("24", v.getAttributeNS(androidNS, "viewportWidth")); assertEquals("24", v.getAttributeNS(androidNS, "viewportHeight"))
            assertEquals("24dp", v.getAttributeNS(androidNS, "width")); assertEquals("24dp", v.getAttributeNS(androidNS, "height"))
            val original = svg.getElementsByTagName("path"); val paths = v.getElementsByTagName("path")
            assertEquals(original.length, paths.length)
            for (p in 0 until paths.length) {
                val from = original.item(p) as org.w3c.dom.Element; val to = paths.item(p) as org.w3c.dom.Element
                assertEquals(from.getAttribute("d"), to.getAttributeNS(androidNS, "pathData"))
                val isFill = from.getAttribute("fill") == "#2A2822"
                if (isFill) assertEquals("kettlebell", row.getString("name"))
                assertEquals(if (isFill) "#FFFFFFFF" else "#00000000", to.getAttributeNS(androidNS, "fillColor"))
                if (!isFill) {
                    assertEquals("2", to.getAttributeNS(androidNS, "strokeWidth"))
                    assertEquals("round", to.getAttributeNS(androidNS, "strokeLineCap")); assertEquals("round", to.getAttributeNS(androidNS, "strokeLineJoin"))
                }
            }
        }
    }

    @Test fun filledSymbolsUsePinnedFillOneSourceAndApprovedWeights() {
        val records = JSONObject(File(root, "android/design-assets/material-symbols-provenance.json").readText()).getJSONArray("icons")
        val rows = (0 until records.length()).associate { records.getJSONObject(it).let { r -> r.getString("symbol") to r } }
        mapOf("filter_alt" to 300, "filter_alt_filled" to 300, "info_i" to 600, "list_alt" to 300,
            "folder" to 400, "check_circle_filled" to 400, "star_filled" to 400).forEach { (name, weight) ->
            val row = rows.getValue(name)
            assertEquals(weight, row.getInt("weight")); assertEquals(if (name.endsWith("_filled")) 1 else 0, row.getInt("fill"))
            assertEquals("10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7", row.getString("upstreamCommit"))
            assertEquals(name.endsWith("_filled"), row.getString("upstreamPath").contains("fill1"))
        }
        assertFalse("filter_list" in rows); assertFalse("info" in rows)
    }

    @Test fun launchThemeIsWhiteAndHasNoVisibleIconOrAnimation() {
        val theme = xml(File(app, "src/main/res/values/themes.xml"))
        val items = theme.getElementsByTagName("item")
        val values = (0 until items.length).associate { (items.item(it) as org.w3c.dom.Element).let { e -> e.getAttribute("name") to e.textContent } }
        assertEquals("@android:color/white", values["android:windowBackground"])
        assertEquals("@android:color/white", values["android:windowSplashScreenBackground"])
        assertEquals("@drawable/launch_blank", values["android:windowSplashScreenAnimatedIcon"])
        assertEquals("0", values["android:windowSplashScreenAnimationDuration"])
        val blank = xml(File(app, "src/main/res/drawable/launch_blank.xml"))
        assertEquals("@android:color/transparent", (blank.getElementsByTagName("solid").item(0) as org.w3c.dom.Element).getAttributeNS(androidNS, "color"))
        val launch = File(app, "src/main/java/com/ignacioli/finecoach/designsystem/FcPages.kt").readText().substringAfter("fun FcLaunch(")
        listOf("Text(", "Image(", "clickable", "LaunchedEffect", "delay(").forEach { assertFalse(it, launch.contains(it)) }
    }
}
