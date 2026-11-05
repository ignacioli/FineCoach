package com.ignacioli.finecoach

import android.app.Activity
import android.app.Dialog
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import java.io.File
import java.util.zip.ZipFile
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowActivity
import org.robolectric.shadows.ShadowDialog

// Observe the real Activity API call, rather than a policy's self-reported flag.
@Implements(Activity::class)
class RecentsActivityShadow : ShadowActivity() {
    val recentsCalls = mutableListOf<Boolean>()
    @Implementation(minSdk = 33)
    fun setRecentsScreenshotEnabled(enabled: Boolean) { recentsCalls += enabled }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], shadows = [RecentsActivityShadow::class],
    qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PrivacyCoverTests {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun api33DisablesRecentsSnapshotsWithoutAnAppCover() {
        assertEquals(listOf(false), Shadow.extract<RecentsActivityShadow>(compose.activity).recentsCalls)
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.activityRule.scenario.onActivity { assertNull(cover(it.window.decorView)) }
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
    }

    @Test @Config(sdk = [31, 32])
    fun legacyDoesNotCallApi33Method() {
        assertTrue(Shadow.extract<RecentsActivityShadow>(compose.activity).recentsCalls.isEmpty())
    }

    @Test @Config(sdk = [31, 32])
    fun pauseCoversEntireShellAndResumeRemovesCoverAndRestoresProbe() {
        compose.onNodeWithTag("s0-probe-count").assertTextEquals("计数：0")
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.activityRule.scenario.onActivity { assertTopCover(it.window.decorView) }
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.activityRule.scenario.onActivity { assertNull(cover(it.window.decorView)) }
        compose.onNodeWithTag("s0-probe").assertIsDisplayed().performClick()
        compose.onNodeWithTag("s0-probe-count").assertTextEquals("计数：1")
    }

    @Test @Config(sdk = [31, 32])
    fun pauseCoversIndependentDialogAndShellAndResumeKeepsDialogInteractive() {
        compose.onNodeWithTag("s0-open-dialog").performClick()
        compose.onNodeWithTag("s0-dialog-sentinel").assertIsDisplayed()
        val dialog = requireNotNull(ShadowDialog.getLatestDialog())
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.activityRule.scenario.onActivity {
            assertTopCover(it.window.decorView)
            assertTopCover(requireNotNull(dialog.window).decorView)
        }
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.activityRule.scenario.onActivity {
            assertNull(cover(it.window.decorView))
            assertNull(cover(requireNotNull(dialog.window).decorView))
        }
        compose.onNodeWithTag("s0-dialog-probe-count").assertTextEquals("计数：0")
        compose.onNodeWithTag("s0-dialog-probe").assertIsDisplayed().performClick()
        compose.onNodeWithTag("s0-dialog-probe-count").assertTextEquals("计数：1")
        compose.onNodeWithTag("s0-close-dialog").performClick()
        compose.onNodeWithTag("s0-probe-count").assertTextEquals("计数：1")
    }

    @Test @Config(sdk = [31])
    fun lateWindowIsCoveredImmediatelyAndUnregisterAndDestroyReleaseCovers() {
        compose.activityRule.scenario.onActivity {
            val dialog = Dialog(it)
            dialog.setContentView(View(it))
            dialog.show()
            val window = requireNotNull(dialog.window)
            val policy = it.privacyCover
            policy.onPause()
            policy.registerWindow(window)
            assertTopCover(window.decorView)
            policy.registerWindow(window)
            assertEquals(1, (window.decorView as ViewGroup).let { root ->
                (0 until root.childCount).count { index -> root.getChildAt(index).tag == PrivacyCoverPolicy.COVER_TAG }
            })
            policy.unregisterWindow(window)
            assertNull(cover(window.decorView))
            policy.onDestroy()
            assertNull(cover(it.window.decorView))
            dialog.dismiss()
        }
    }

    @Test fun sampleEntriesAreVisibleClickableAndFillTheirContentContainer() {
        fun width(tag: String) = compose.onNodeWithTag(tag).getUnclippedBoundsInRoot().let { it.right - it.left }
        for (tag in listOf("s0-open-dialog", "s0-probe")) {
            compose.onNodeWithTag(tag).assertIsDisplayed()
            assertEquals(width("s0-shell-sentinel"), width(tag))
        }
        compose.onNodeWithTag("s0-open-dialog").performClick()
        for (tag in listOf("s0-dialog-probe", "s0-close-dialog")) {
            compose.onNodeWithTag(tag).assertIsDisplayed()
            assertEquals(width("s0-dialog-sentinel"), width(tag))
        }
        compose.onNodeWithTag("s0-close-dialog").performClick()
        compose.onNodeWithTag("s0-probe").performClick()
        compose.onNodeWithTag("s0-probe-count").assertTextEquals("计数：1")
    }

    @Test fun sourceAndBothMergedManifestsDoNotEnableSecureWindows() {
        val src = File(MergedPrivacyInputs.property("sourceRoot"))
        val files = src.listFiles().orEmpty().filter { it.name !in setOf("test", "androidTest") }
            .flatMap { it.walkTopDown().filter { file -> file.isFile && file.extension in setOf("kt", "java", "xml") }.toList() }
        assertTrue(files.isNotEmpty())
        files.forEach { assertFalse(it.path, Regex("FLAG_SECURE|flagSecure|windowSecure", RegexOption.IGNORE_CASE).containsMatchIn(it.readText())) }
        MergedPrivacyInputs.variants.forEach {
            val manifest = MergedPrivacyInputs.manifest(it)
            assertFalse(Regex("FLAG_SECURE|flagSecure|windowSecure", RegexOption.IGNORE_CASE).containsMatchIn(
                manifest.ownerDocument.let { doc ->
                    javax.xml.transform.TransformerFactory.newInstance().newTransformer().let { transformer ->
                        java.io.StringWriter().also { writer -> transformer.transform(
                            javax.xml.transform.dom.DOMSource(doc), javax.xml.transform.stream.StreamResult(writer)) }.toString()
                    }
                }))
        }
        compose.activityRule.scenario.onActivity {
            assertEquals(0, it.window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    @Test fun releaseApkDoesNotContainDebugSampleOrSentinels() {
        val apks = File(MergedPrivacyInputs.property("releaseApk")).walkTopDown()
            .filter { it.isFile && it.extension == "apk" }.toList()
        assertEquals(1, apks.size)
        ZipFile(apks.single()).use { zip ->
            val dex = zip.entries().asSequence().filter { Regex("classes[0-9]*\\.dex").matches(it.name) }.toList()
            assertTrue(dex.isNotEmpty())
            dex.forEach { entry ->
                val strings = zip.getInputStream(entry).use { String(it.readBytes(), Charsets.ISO_8859_1) }
                listOf("S0DebugApplication", "S0SENTINEL", "s0-open-dialog", "s0-dialog-probe").forEach {
                    assertFalse("Debug sample in release: $it", strings.contains(it))
                }
            }
        }
        assertEquals("", (MergedPrivacyInputs.manifest("release").getElementsByTagName("application").item(0)
            as org.w3c.dom.Element).getAttributeNS(MergedPrivacyInputs.ANDROID, "name"))
    }

    private fun cover(root: View): View? = root.findViewWithTag(PrivacyCoverPolicy.COVER_TAG)
    private fun assertTopCover(root: View) {
        val decor = root as ViewGroup
        val cover = requireNotNull(cover(root))
        assertSame(cover, decor.getChildAt(decor.childCount - 1))
        assertEquals(View.VISIBLE, cover.visibility)
        assertTrue(cover.isClickable)
        assertNotNull(cover.background)
        assertEquals(android.graphics.PixelFormat.OPAQUE, cover.background.opacity)
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, cover.layoutParams.width)
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, cover.layoutParams.height)
        assertEquals(0, cover.left)
        assertEquals(0, cover.top)
        assertEquals(decor.width, cover.width)
        assertEquals(decor.height, cover.height)
    }
}
