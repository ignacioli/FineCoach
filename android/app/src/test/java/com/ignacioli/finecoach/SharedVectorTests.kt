package com.ignacioli.finecoach

import java.io.File
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class SharedVectorTests(private val fixture: File) {
    @Test fun realDomainBalance() {
        SharedVectorRunner(false).run(fixture.readBytes(), fixture.name)
        VectorFiles.report(fixture)
    }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}")
        fun vectors(): Collection<Array<Any>> {
            val files = VectorFiles.files("s1/course-packages")
            check(files.size == 5) { "Normal sample inventory changed: ${files.size}" }
            val ids = files.map { (VectorJSON(it.readText()).parse() as Map<*, *>)["id"] }
            check(ids.toSet().size == files.size) { "Duplicate normal vector id" }
            println("VECTOR-SUMMARY normal=5")
            return files.map { arrayOf<Any>(it) }
        }
    }
}
