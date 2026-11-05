package com.ignacioli.finecoach

import org.junit.Assert.assertThrows
import org.junit.Test
import org.w3c.dom.Element

internal object BackupRulePolicy {
    val domains = setOf("root", "file", "database", "sharedpref", "external", "device_root", "device_file", "device_database", "device_sharedpref")
    fun exclusions(section: Element) {
        val children = MergedPrivacyInputs.children(section)
        require(children.all { it.tagName == "exclude" && it.getAttribute("path") == "." })
        require(children.size == domains.size && children.map { it.getAttribute("domain") }.toSet() == domains)
    }
    fun extraction(root: Element) {
        require(root.tagName == "data-extraction-rules")
        val sections = MergedPrivacyInputs.children(root)
        require(sections.size == 3 && sections.map { it.tagName }.toSet() ==
            setOf("cloud-backup", "device-transfer", "cross-platform-transfer"))
        require(sections.single { it.tagName == "cross-platform-transfer" }.getAttribute("platform") == "ios")
        sections.forEach(::exclusions)
    }
}

class BackupRulesTests {
    @Test fun mergedDebugAndReleaseRulesExcludeEveryDomain() {
        MergedPrivacyInputs.variants.forEach { variant ->
            val app = MergedPrivacyInputs.manifest(variant).getElementsByTagName("application").item(0) as Element
            require(app.getAttributeNS(MergedPrivacyInputs.ANDROID, "allowBackup") == "false")
            BackupRulePolicy.extraction(MergedPrivacyInputs.resource(variant, app.getAttributeNS(MergedPrivacyInputs.ANDROID, "dataExtractionRules")))
            val legacy = MergedPrivacyInputs.resource(variant, app.getAttributeNS(MergedPrivacyInputs.ANDROID, "fullBackupContent"))
            require(legacy.tagName == "full-backup-content")
            BackupRulePolicy.exclusions(legacy)
        }
    }
    private fun fixture(): Element = MergedPrivacyInputs.parse(requireNotNull(javaClass.getResource("/privacy/valid-extraction.xml")).readText())
    @Test fun rejectsMissingSection() {
        val root = fixture(); root.removeChild(root.getElementsByTagName("device-transfer").item(0))
        assertThrows(IllegalArgumentException::class.java) { BackupRulePolicy.extraction(root) }
    }
    @Test fun rejectsMissingDomain() {
        val root = fixture(); val section = root.getElementsByTagName("cloud-backup").item(0)
        section.removeChild(root.getElementsByTagName("exclude").item(0))
        assertThrows(IllegalArgumentException::class.java) { BackupRulePolicy.extraction(root) }
    }
    @Test fun rejectsInclude() {
        val root = fixture(); root.getElementsByTagName("device-transfer").item(0).appendChild(root.ownerDocument.createElement("include"))
        assertThrows(IllegalArgumentException::class.java) { BackupRulePolicy.extraction(root) }
    }
    @Test fun rejectsInvalidResourceReference() {
        assertThrows(IllegalArgumentException::class.java) { MergedPrivacyInputs.resource("debug", "@xml/missing/invalid") }
    }
}
