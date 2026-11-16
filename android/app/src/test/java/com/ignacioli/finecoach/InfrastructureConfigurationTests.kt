package com.ignacioli.finecoach

import android.content.pm.ApplicationInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.w3c.dom.Element
import java.io.File
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class InfrastructureConfigurationTests {
    private val androidNamespace = "http://schemas.android.com/apk/res/android"

    private fun mergedManifest(): Element {
        val manifest = File(requireNotNull(System.getProperty("finecoach.mergedManifest")))
        check(manifest.isFile) { "Merged manifest missing: $manifest" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        }
        return factory.newDocumentBuilder().parse(manifest).documentElement
    }

    @Test
    fun approvedSdkConfiguration() {
        assertEquals("37", System.getProperty("finecoach.compileSdk"))
        val sdk = mergedManifest().getElementsByTagName("uses-sdk").item(0) as Element
        assertEquals("31", sdk.getAttributeNS(androidNamespace, "minSdkVersion"))
        assertEquals("36", sdk.getAttributeNS(androidNamespace, "targetSdkVersion"))
    }

    @Test
    fun mergedManifestDisablesBackupAndHasNoInternetPermission() {
        val manifest = mergedManifest()
        for (tag in listOf("uses-permission", "uses-permission-sdk-23")) {
            val permissions = manifest.getElementsByTagName(tag)
            for (index in 0 until permissions.length) {
                val permission = permissions.item(index) as Element
                assertFalse(
                    permission.getAttributeNS(androidNamespace, "name") == "android.permission.INTERNET",
                )
            }
        }
        val application = manifest.getElementsByTagName("application").item(0) as Element
        assertEquals("false", application.getAttributeNS(androidNamespace, "allowBackup"))
    }

    @Test
    fun mergedManifestHasExactlyOneLauncherActivity() {
        val launchers = mutableListOf<String>()
        val manifest = mergedManifest()
        for (tag in listOf("activity", "activity-alias")) {
            val activities = manifest.getElementsByTagName(tag)
            for (index in 0 until activities.length) {
                val activity = activities.item(index) as Element
                val filters = activity.getElementsByTagName("intent-filter")
                for (filterIndex in 0 until filters.length) {
                    val filter = filters.item(filterIndex) as Element
                    fun hasName(tagName: String, name: String): Boolean {
                        val nodes = filter.getElementsByTagName(tagName)
                        return (0 until nodes.length).any {
                            (nodes.item(it) as Element).getAttributeNS(androidNamespace, "name") == name
                        }
                    }
                    if (hasName("action", "android.intent.action.MAIN") &&
                        hasName("category", "android.intent.category.LAUNCHER")
                    ) {
                        assertEquals("true", activity.getAttributeNS(androidNamespace, "exported"))
                        launchers += activity.getAttributeNS(androidNamespace, "name")
                    }
                }
            }
        }
        assertEquals(listOf("com.ignacioli.finecoach.MainActivity"), launchers)
    }

    @Test
    fun mainActivityStartsOnJvm() {
        Robolectric.buildActivity(MainActivity::class.java).use { controller ->
            val activity = controller.setup().get()
            assertEquals("com.ignacioli.finecoach", activity.packageName)
            assertEquals(31, activity.applicationInfo.minSdkVersion)
            assertEquals(36, activity.applicationInfo.targetSdkVersion)
            assertEquals(0, activity.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
            assertNotNull(activity.window.decorView)
            assertFalse(activity.isFinishing)
        }
    }
}
