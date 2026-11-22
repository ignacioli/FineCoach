// fictional-data: sentinel payload only, no real identity or training content.
package com.ignacioli.finecoach

import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.Description
import org.junit.runners.model.Statement

class InsightTestPrivacyRuleTests {
    @Test fun diagnosticsStayInReportInsteadOfJUnitFailure() {
        val sentinel = "fictional-sensitive-payload"
        val wrapped = InsightTestPrivacyRule().apply(object : Statement() {
            override fun evaluate() { throw AssertionError(sentinel) }
        }, Description.createTestDescription(javaClass, "privacySentinel"))
        val failure = runCatching { wrapped.evaluate() }.exceptionOrNull()
        assertTrue("failure is preserved", failure is AssertionError)
        assertFalse("JUnit message is safe", failure?.message.orEmpty().contains(sentinel))
        assertNull("original exception must not reach XML", failure?.cause)
        val report = File(System.getProperty("finecoach.storageProjectDirectory"), "build/outputs/insight-test-diagnostics/privacySentinel.txt")
        assertTrue("local detail retained", report.readText().contains(sentinel))
    }
}
