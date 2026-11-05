package com.ignacioli.finecoach

import java.io.File
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

internal object MergedPrivacyInputs {
    const val ANDROID = "http://schemas.android.com/apk/res/android"
    val variants = listOf("debug", "release")
    fun parse(file: File): Element {
        check(file.isFile) { "Missing merged input: $file" }
        return parse(file.readText())
    }
    fun parse(xml: String): Element = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
        setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
    }.newDocumentBuilder().parse(xml.byteInputStream()).documentElement
    fun manifest(variant: String): Element = parse(File(property("manifest.$variant")))
    fun property(key: String): String = requireNotNull(System.getProperty("finecoach.$key")) { key }
    fun resource(variant: String, reference: String): Element {
        require(Regex("@xml/[a-z_0-9]+").matches(reference)) { "Invalid rule reference: $reference" }
        val root = File(property("resources.$variant"))
        check(root.isDirectory) { "Missing merged resources: $root" }
        val name = reference.substringAfter('/') + ".xml"
        val matches = root.walkTopDown().filter { it.isFile && it.name == name && it.parentFile?.name == "xml" }.toList()
        check(matches.size == 1) { "Rule resource must resolve uniquely: $reference in $root" }
        return parse(matches.single())
    }
    fun children(root: Element): List<Element> = (0 until root.childNodes.length)
        .mapNotNull { root.childNodes.item(it) as? Element }
}
