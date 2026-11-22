// fictional-data: diagnostics can include synthetic identity and training content.
package com.ignacioli.finecoach

import java.io.File
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

/** Keep Compose's automatic semantics dump out of JUnit XML; retain details only in local reports. */
internal class InsightTestPrivacyRule(private val methods: Set<String>? = null) : TestRule {
    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            if (methods != null && description.methodName !in methods) { base.evaluate(); return }
            try {
                base.evaluate()
            } catch (failure: Throwable) {
                val app = File(System.getProperty("finecoach.storageProjectDirectory"))
                val report = File(app, "build/outputs/insight-test-diagnostics/${description.methodName}.txt")
                report.parentFile.mkdirs()
                report.writeText(failure.stackTraceToString())
                val safe = failure.message?.takeIf { Regex("(Today S3|Student detail S3) strict: failed=[0-9]+ missing=[0-9]+").matches(it) }
                throw AssertionError(safe ?: "Insight check failed=1; details in local report")
            }
        }
    }
}
