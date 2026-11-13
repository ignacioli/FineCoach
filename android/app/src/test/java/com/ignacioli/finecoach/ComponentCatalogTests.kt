package com.ignacioli.finecoach

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class ComponentCatalogTests {
    private val app = File(requireNotNull(System.getProperty("finecoach.storageProjectDirectory")))
    private val root = app.parentFile.parentFile
    private val doc = File(root, "design/design-system/components.md").readText()
    private val main = File(app, "src/main/java/com/ignacioli/finecoach/designsystem")
    private val test = File(app, "src/test/java/com/ignacioli/finecoach/ComponentContractTests.kt").readText() +
        File(app, "src/test/java/com/ignacioli/finecoach/S1ComponentTests.kt").readText()
    private val approved = setOf("BASE", "BUTTON", "TITLE-ACTION", "SEGMENTED", "CHIP", "TOGGLE", "STEPPER", "TEXT-FIELD",
        "LIST-ROW", "SECTION", "LABEL-VALUE-ROW", "PAGE-HEADER", "HUB-ROW", "INLINE-RESULT", "ACTION-ROW", "UNDO-ROW",
        "BOTTOM-SHEET", "CONFIRM-DIALOG", "STATUS", "SAVE-STATUS", "AVATAR", "SYMBOL", "HINT-BAR", "HERO-CARD", "AMBIENT-SCENE", "SET-ROW", "EQUIPMENT-ICON", "PAGE-PRIMARY", "PAGE-SECONDARY", "EMPTY-STATE", "LAUNCH").map { "DS-$it" }.toSet()
    private val deferred = setOf("CALENDAR-DAY", "BODY-DIAGRAM").map { "DS-$it" }.toSet()

    private fun rows(start: String, end: String): List<List<String>> = doc.substringAfter("<!-- $start -->", "")
        .substringBefore("<!-- $end -->").lineSequence().filter { it.startsWith("| DS-") }
        .map { it.trim('|').split('|').map(String::trim) }.toList()

    @Test fun approvedRosterIsExactAndUnique() {
        val rows = rows("android-roster-start", "android-roster-end")
        assertEquals(31, rows.size)
        assertEquals(approved, rows.map { it[0] }.toSet())
        assertEquals(approved, (S0CatalogEntries + S1CatalogEntries).map { it.id }.toSet())
        assertEquals(31, (S0CatalogEntries + S1CatalogEntries).size)
    }

    @Test fun everyTypeFileAndIosSourceExists() {
        rows("android-roster-start", "android-roster-end").forEach { row ->
            val source = File(main, row[2]); assertTrue(source.path, source.isFile)
            row[1].split(';').forEach { type ->
                assertTrue("${row[0]} missing $type", Regex("(?:fun|class|enum class|object)\\s+${Regex.escape(type)}\\b").containsMatchIn(source.readText()))
            }
            row[4].split(';').forEach { assertTrue(it, File(root, "ios/FineCoachApp/DesignSystem/$it").isFile) }
        }
    }

    @Test fun everyRepresentativeStateHasARegisteredCaseAndContractMethod() {
        rows("android-roster-start", "android-roster-end").forEach { row ->
            assertEquals(row[0], row[3].split(';'), (S0CatalogEntries + S1CatalogEntries).single { it.id == row[0] }.states)
            assertTrue(row[0], Regex("@Test\\s+fun\\s+${row[5]}\\(").containsMatchIn(test))
            assertTrue("L3 must be explicit", row[6].isNotBlank())
        }
        assertTrue(File(app, "src/test/java/com/ignacioli/finecoach/ComponentCatalogStateTests.kt").isFile)
    }

    @Test fun deferredTableIsExactAndUnionCoversAuthorityIndexWithoutUnknownIds() {
        val rows = rows("android-deferred-start", "android-deferred-end")
        assertEquals(2, rows.size)
        assertEquals(deferred, rows.map { it[0] }.toSet())
        rows.forEach { assertTrue(it[1].startsWith("S")); assertTrue(it[2].contains("D07 2026-11-03")) }
        assertTrue(approved.intersect(deferred).isEmpty())
        val index = doc.substringAfter("## 3. 组件索引").substringBefore("**Penpot ID")
        val patterns = doc.substringAfter("### 4.6 页面组合模式").substringBefore("### 4.7")
        val ids = Regex("`(DS-[A-Z-]+)`").findAll(index + patterns).map { it.groupValues[1] }.toSet()
        assertEquals(ids, approved + deferred)
    }

    @Test fun catalogIsDebugOnlyAndPreservesPrivacyEntryTags() {
        assertFalse(File(app, "src/main/java/com/ignacioli/finecoach/S0ComponentCatalog.kt").exists())
        val source = File(app, "src/debug/java/com/ignacioli/finecoach/S0DebugApplication.kt").readText()
        listOf("s0-shell-sentinel", "s0-open-dialog", "s0-probe", "s0-open-catalog", "s0-dialog-probe", "s0-close-dialog").forEach {
            assertTrue(it, source.contains("\"$it\""))
        }
        val catalog = File(app, "src/debug/java/com/ignacioli/finecoach/S0ComponentCatalog.kt").readText()
        assertTrue(catalog.contains("fictional-data:"))
        assertTrue(catalog.contains("else -> error(\"Unknown catalog ID:"))
    }

    @Test fun iconRequestsHaveExplicitStyleWeightMappingAndNoIconDependency() {
        val assets = File(root, "android/design-assets")
        val manifest = File(assets, "material-symbols-manifest.txt").readLines()
            .filter { it.isNotBlank() && !it.startsWith('#') }
        assertEquals(19, manifest.size)
        val provenance = File(assets, "material-symbols-provenance.json").readText()
        val records = Regex("\\{[^{}]*\\\"symbol\\\"[^{}]*}").findAll(provenance).map { it.value }.toList()
        assertEquals(19, records.size)
        val sums = File(assets, "material-symbols-SHA256SUMS").readLines().associate {
            val parts = it.trim().split(Regex("\\s+"), limit = 2); parts[1] to parts[0]
        }
        fun digest(file: File) = java.security.MessageDigest.getInstance("SHA-256").digest(file.readBytes())
            .joinToString("") { "%02x".format(it) }
        fun field(record: String, key: String): String = requireNotNull(
            Regex("\\\"$key\\\": \\\"([^\\\"]+)\\\"").find(record)) { "Missing provenance $key" }.groupValues[1]
        val xml = javax.xml.parsers.DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            setFeature(javax.xml.XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        }
        val android = "http://schemas.android.com/apk/res/android"
        // Painter injection sites are explicit consumers; an occurrence in another file is no proof.
        val catalogFile = "src/debug/java/com/ignacioli/finecoach/S0ComponentCatalog.kt"
        val sourcePrefix = "src/main/java/com/ignacioli/finecoach/"
        val consumers = mapOf(
            "DS-TITLE-ACTION" to mapOf("add" to catalogFile, "calendar_month" to catalogFile,
                "settings" to catalogFile, "grid_view" to catalogFile,
                "filter_alt" to sourcePrefix + "features/exercises/ExerciseScreens.kt",
                "filter_alt_filled" to sourcePrefix + "features/exercises/ExerciseScreens.kt"),
            "DS-STEPPER" to mapOf("add" to catalogFile, "remove" to catalogFile),
            "DS-SYMBOL" to mapOf("add" to catalogFile, "remove" to catalogFile, "expand_more" to catalogFile),
            "DS-LIST-ROW" to mapOf("remove" to catalogFile, "expand_more" to catalogFile,
                "star_filled" to sourcePrefix + "designsystem/FcRows.kt"),
            "DS-HUB-ROW" to mapOf("settings" to catalogFile, "grid_view" to catalogFile,
                "list_alt" to sourcePrefix + "features/resources/ResourceHubScreen.kt"),
            "DS-ACTION-ROW" to mapOf("delete" to catalogFile),
            "DS-SAVE-STATUS" to mapOf("sync" to catalogFile, "check_circle" to catalogFile, "warning" to catalogFile),
            "DS-STATUS" to mapOf("priority_high" to catalogFile, "info_i" to catalogFile),
            "DS-INLINE-RESULT" to mapOf("priority_high" to catalogFile, "info_i" to catalogFile),
            "DS-SET-ROW" to mapOf("edit" to sourcePrefix + "designsystem/FcSetRow.kt"),
            "feature:session-swipe-row" to mapOf("folder" to sourcePrefix + "features/session/SessionSwipeRow.kt"),
            "feature:session-exercise-header" to mapOf("check_circle_filled" to sourcePrefix + "features/session/SessionChrome.kt"),
        )
        val implementationMap = File(root, "android/docs/s1/implementation-map.md").readText()
        (consumers.keys - approved).forEach { assertTrue("Unregistered feature component: $it", implementationMap.contains("| $it |")) }
        manifest.forEach {
            val columns = it.split('|').map(String::trim)
            assertEquals(5, columns.size)
            assertTrue(columns.all(String::isNotBlank))
            assertTrue(columns[1].matches(Regex("outlined/[0-9]+")))
            assertTrue(columns[3].split(',').all { id -> id in consumers })
            assertEquals("integrated", columns[4])
            val name = columns[0]
            val record = records.single { field(it, "symbol") == name }
            assertEquals("10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7", field(record, "upstreamCommit"))
            assertEquals(columns[2], field(record, "iosSymbol"))
            assertEquals("outlined", field(record, "style"))
            assertEquals(columns[1].substringAfter('/').toInt(),
                requireNotNull(Regex("\\\"weight\\\": ([0-9]+)").find(record)).groupValues[1].toInt())
            val original = File(assets, field(record, "sourceSvg"))
            assertEquals(sums.getValue("$name.svg"), digest(original))
            assertEquals(sums.getValue("$name.svg"), field(record, "sourceSha256"))
            val vector = File(root, "android/${field(record, "drawable")}")
            assertEquals("ic_ms_$name.xml", vector.name)
            assertEquals(field(record, "drawableSha256"), digest(vector))
            val svg = xml.newDocumentBuilder().parse(original).documentElement
            assertEquals("0 -960 960 960", svg.getAttribute("viewBox"))
            val drawable = xml.newDocumentBuilder().parse(vector).documentElement
            assertEquals("vector", drawable.tagName)
            assertEquals("960", drawable.getAttributeNS(android, "viewportWidth"))
            assertEquals("960", drawable.getAttributeNS(android, "viewportHeight"))
            assertEquals("24dp", drawable.getAttributeNS(android, "width"))
            assertEquals("24dp", drawable.getAttributeNS(android, "height"))
            val groups = drawable.getElementsByTagName("group")
            assertEquals(1, groups.length)
            assertEquals("960", (groups.item(0) as org.w3c.dom.Element).getAttributeNS(android, "translateY"))
            val svgPaths = svg.getElementsByTagName("path")
            val paths = drawable.getElementsByTagName("path")
            assertTrue(paths.length > 0); assertEquals(svgPaths.length, paths.length)
            for (index in 0 until paths.length) {
                val node = paths.item(index) as org.w3c.dom.Element
                assertEquals((svgPaths.item(index) as org.w3c.dom.Element).getAttribute("d"), node.getAttributeNS(android, "pathData"))
                assertEquals("@android:color/white", node.getAttributeNS(android, "fillColor"))
            }
        }
        assertEquals(sums.getValue("LICENSE"), digest(File(assets, "material-symbols-LICENSE.txt")))
        assertArrayEquals(File(assets, "material-symbols-LICENSE.txt").readBytes(),
            File(app, "src/main/assets/licenses/material-symbols-LICENSE.txt").readBytes())
        assertArrayEquals(File(assets, "material-symbols-NOTICE.txt").readBytes(),
            File(app, "src/main/assets/licenses/material-symbols-NOTICE.txt").readBytes())
        assertFalse(File(app, "build.gradle.kts").readText().contains("material-icons"))
        assertTrue(File(assets, "README.md").readText().contains("Apache License 2.0"))
        val catalog = File(app, "src/debug/java/com/ignacioli/finecoach/S0ComponentCatalog.kt").readText()
        manifest.forEach { line ->
            val columns = line.split('|').map(String::trim)
            val name = columns[0]
            columns[3].split(',').forEach { owner ->
                val file = File(app, consumers.getValue(owner).getValue(name))
                assertTrue(file.path, file.isFile)
                if (name == "check_circle_filled" && owner == "feature:session-exercise-header") {
                    // S1-D39 retires this consumer; its asset/hash/provenance remain validated above.
                    assertFalse(file.readText().contains("R.drawable.ic_ms_$name"))
                    assertFalse(file.readText().contains("FcSymbol(FcGlyph.Check)"))
                    assertTrue(file.readText().contains("this.selected = selected"))
                } else if (name == "folder" && owner == "feature:session-swipe-row") {
                    // P7 F5 follows P0-a2b: the move tile is text-only; retain asset provenance checks.
                    assertFalse(file.readText().contains("R.drawable.ic_ms_$name"))
                } else assertTrue("$name must be used by $owner in " + file.path, file.readText().contains("R.drawable.ic_ms_$name"))
            }
        }
        assertEquals(19, File(assets, "material-symbols-svg").listFiles()!!.count { it.extension == "svg" })
        assertEquals(19, File(app, "src/main/res/drawable").listFiles()!!.count { it.name.startsWith("ic_ms_") && it.extension == "xml" })
        val edit = records.single { field(it, "symbol") == "edit" }
        assertEquals("symbols/web/edit/materialsymbolsoutlined/edit_24px.svg", field(edit, "upstreamPath"))
        assertEquals("pencil", field(edit, "iosSymbol"))
        val setRow = File(main, "FcSetRow.kt").readText()
        // P0-a2 paths 45/46: the visible pencil viewport is 20dp; the separate hit target remains 44dp.
        assertTrue(setRow.contains("Modifier.size(FcSpacing.space4 + FcSpacing.space1)"))
        assertFalse(catalog.contains("S0PendingPainter")); assertFalse(catalog.contains("图标待接入"))
    }
}
