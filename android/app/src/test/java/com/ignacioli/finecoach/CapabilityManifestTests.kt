package com.ignacioli.finecoach

import org.junit.Assert.assertThrows
import org.junit.Test
import org.w3c.dom.Element

internal object CapabilityPolicy {
    private const val permission = "com.ignacioli.finecoach.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
    fun validate(manifest: Element, variant: String) {
        require(variant in MergedPrivacyInputs.variants)
        fun Element.attr(name: String) = getAttributeNS(MergedPrivacyInputs.ANDROID, name)
        val requested = MergedPrivacyInputs.children(manifest).filter { it.tagName.startsWith("uses-permission") }
        require(requested.size == 1 && requested.single().tagName == "uses-permission" && requested.single().attr("name") == permission)
        require(!requested.single().hasAttributeNS(MergedPrivacyInputs.ANDROID, "maxSdkVersion"))
        val declared = MergedPrivacyInputs.children(manifest).filter { it.tagName == "permission" }
        require(declared.size == 1 && declared.single().attr("name") == permission && declared.single().attr("protectionLevel") == "signature")
        val instrumentation = MergedPrivacyInputs.children(manifest).filter { it.tagName == "instrumentation" }
        if (variant == "debug") {
            require(instrumentation.size == 1)
            require(instrumentation.single().attr("name") == "com.ignacioli.finecoach.seed.DebugSeedInstrumentation")
            require(instrumentation.single().attr("targetPackage") == "com.ignacioli.finecoach")
            require(instrumentation.single().attr("functionalTest") == "true")
        } else require(instrumentation.isEmpty()) { "Release must not expose instrumentation" }
        val app = manifest.getElementsByTagName("application").item(0) as Element
        val components = MergedPrivacyInputs.children(app).filter { it.tagName in setOf("activity", "activity-alias", "service", "receiver", "provider") }
        val expectedComponents = setOf(
            "activity" to "com.ignacioli.finecoach.MainActivity",
            "receiver" to "androidx.profileinstaller.ProfileInstallReceiver",
            "provider" to "androidx.startup.InitializationProvider",
            // Library entry contributed by room-runtime 2.8.5 in both variants.
            "service" to "androidx.room.MultiInstanceInvalidationService",
        ) + if (variant == "debug") setOf("activity" to "androidx.activity.ComponentActivity") else emptySet()
        require(components.size == expectedComponents.size &&
            components.map { it.tagName to it.attr("name") }.toSet() == expectedComponents)
        val external = components.filter { it.attr("exported") != "false" }
        require(external.size == 2 && external.all { it.attr("exported") == "true" } &&
            external.map { it.tagName to it.attr("name") }.toSet() == setOf(
                "activity" to "com.ignacioli.finecoach.MainActivity",
                "receiver" to "androidx.profileinstaller.ProfileInstallReceiver",
            ))
        val receiver = external.single { it.tagName == "receiver" }
        require(receiver.attr("permission") == "android.permission.DUMP") { "Library profile receiver must require DUMP" }
        val launcher = external.single { it.tagName == "activity" }
        val filters = MergedPrivacyInputs.children(launcher).filter { it.tagName == "intent-filter" }
        require(filters.size == 1)
        require(MergedPrivacyInputs.children(filters.single()).map { it.tagName to it.attr("name") }.toSet() == setOf(
            "action" to "android.intent.action.MAIN", "category" to "android.intent.category.LAUNCHER"))
        require(components.filter { it !== launcher && it !== receiver }.all { it.attr("exported") == "false" })
        val roomService = components.single { it.tagName == "service" && it.attr("name") == "androidx.room.MultiInstanceInvalidationService" }
        require(roomService.attr("exported") == "false") { "Room invalidation service must not be exported" }
        require(MergedPrivacyInputs.children(roomService).none { it.tagName == "intent-filter" }) { "Room invalidation service must not have intent filters" }
    }
}

class CapabilityManifestTests {
    @Test fun debugMergedManifestHasOnlyApprovedCapabilities() = validateVariant("debug")
    @Test fun releaseMergedManifestHasOnlyApprovedCapabilities() = validateVariant("release")
    @Test fun rejectsUnexpectedInstrumentation() {
        for (variant in MergedPrivacyInputs.variants) {
            val manifest = MergedPrivacyInputs.manifest(variant)
            val entry = manifest.ownerDocument.createElement("instrumentation")
            entry.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:name", "fictional.UnapprovedInstrumentation")
            entry.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:targetPackage", "com.ignacioli.finecoach")
            manifest.appendChild(entry)
            assertThrows(IllegalArgumentException::class.java) { CapabilityPolicy.validate(manifest, variant) }
        }
    }
    private fun validateVariant(variant: String) {
        val manifest = MergedPrivacyInputs.manifest(variant)
        CapabilityPolicy.validate(manifest, variant)
        val app = manifest.getElementsByTagName("application").item(0) as Element
        require(app.getAttributeNS(MergedPrivacyInputs.ANDROID, "allowBackup") == "false")
        BackupRulePolicy.extraction(MergedPrivacyInputs.resource(variant, app.getAttributeNS(MergedPrivacyInputs.ANDROID, "dataExtractionRules")))
        if (variant == "release") require(app.getAttributeNS(MergedPrivacyInputs.ANDROID, "debuggable") != "true")
    }
    @Test fun rejectsInternetPermissionFixture() {
        val manifest = MergedPrivacyInputs.manifest("debug")
        val permission = manifest.ownerDocument.createElement("uses-permission")
        permission.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:name", "android.permission.INTERNET")
        manifest.appendChild(permission)
        assertThrows(IllegalArgumentException::class.java) { CapabilityPolicy.validate(manifest, "debug") }
    }
    @Test fun rejectsUnexpectedExportedEntryFixture() {
        val manifest = MergedPrivacyInputs.manifest("debug")
        val service = manifest.ownerDocument.createElement("service")
        service.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:name", "fictional.UnapprovedService")
        service.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:exported", "true")
        manifest.getElementsByTagName("application").item(0).appendChild(service)
        assertThrows(IllegalArgumentException::class.java) { CapabilityPolicy.validate(manifest, "debug") }
    }
    @Test fun rejectsNonSignaturePermissionFixture() {
        val manifest = MergedPrivacyInputs.manifest("debug")
        (manifest.getElementsByTagName("permission").item(0) as Element)
            .setAttributeNS(MergedPrivacyInputs.ANDROID, "android:protectionLevel", "normal")
        assertThrows(IllegalArgumentException::class.java) { CapabilityPolicy.validate(manifest, "debug") }
    }
    @Test fun rejectsExportedRoomInvalidationServiceFixture() {
        for (variant in MergedPrivacyInputs.variants) {
            val manifest = MergedPrivacyInputs.manifest(variant)
            val service = MergedPrivacyInputs.children(manifest.getElementsByTagName("application").item(0) as Element)
                .single { it.tagName == "service" && it.getAttributeNS(MergedPrivacyInputs.ANDROID, "name") == "androidx.room.MultiInstanceInvalidationService" }
            service.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:exported", "true")
            assertThrows(IllegalArgumentException::class.java) { CapabilityPolicy.validate(manifest, variant) }
        }
    }
    @Test fun rejectsProfileReceiverWithoutDumpPermissionFixture() {
        for (value in listOf("", "android.permission.INTERNET")) {
            val manifest = MergedPrivacyInputs.manifest("debug")
            val receiver = MergedPrivacyInputs.children(manifest.getElementsByTagName("application").item(0) as Element)
                .single { it.tagName == "receiver" && it.getAttributeNS(MergedPrivacyInputs.ANDROID, "name") == "androidx.profileinstaller.ProfileInstallReceiver" }
            if (value.isEmpty()) receiver.removeAttributeNS(MergedPrivacyInputs.ANDROID, "permission")
            else receiver.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:permission", value)
            assertThrows(IllegalArgumentException::class.java) { CapabilityPolicy.validate(manifest, "debug") }
        }
    }
    @Test fun rejectsReleaseWithDebugTestHostFixture() {
        val manifest = MergedPrivacyInputs.manifest("release")
        val activity = manifest.ownerDocument.createElement("activity")
        activity.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:name", "androidx.activity.ComponentActivity")
        activity.setAttributeNS(MergedPrivacyInputs.ANDROID, "android:exported", "false")
        manifest.getElementsByTagName("application").item(0).appendChild(activity)
        assertThrows(IllegalArgumentException::class.java) { CapabilityPolicy.validate(manifest, "release") }
    }
}
