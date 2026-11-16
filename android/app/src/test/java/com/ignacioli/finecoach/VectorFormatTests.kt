package com.ignacioli.finecoach

import java.io.File
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class VectorFormatTests(private val fixture: File) {
    @Test fun conformance() = VectorFiles.checkConformance(fixture)

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}")
        fun vectors(): Collection<Array<Any>> {
            val files = VectorFiles.files("runner-conformance")
            check(files.size == 72) { "Conformance inventory changed: ${files.size}" }
            val outcomes = files.groupingBy {
                val root = VectorJSON(it.readText()).parse() as Map<*, *>
                ((root["meta"] as Map<*, *>)["conformance"] as Map<*, *>)["outcome"]
            }.eachCount()
            check(outcomes == mapOf("pass" to 15, "format" to 44, "compare" to 13))
            println("VECTOR-SUMMARY conformance=72 positive=15 negative=57")
            return files.map { arrayOf<Any>(it) }
        }
    }
}
