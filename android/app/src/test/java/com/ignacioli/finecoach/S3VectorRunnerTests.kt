// fictional-data: deterministic S3 parity scenarios; outputs contain only vector IDs and digests.
package com.ignacioli.finecoach
import java.io.File
import java.security.MessageDigest
import java.time.*
import org.junit.Test

class S3VectorRunnerTests {
    @Test fun gains() = run("gains", 35)
    @Test fun insights() = run("insights", 24)
    @Test fun e1rm() = run("e1rm", 9)
    @Test fun comparison() = run("comparison", 6)
    @Test fun body() = run("body", 3)
    @Suppress("UNCHECKED_CAST")
    private fun run(group: String, count: Int) {
        val manifestFile = File(VectorFiles.root, "s3-manifest.json")
        val manifest = VectorJSON(manifestFile.readText()).parse() as Map<String, Any?>
        val entries = manifest.getValue("vectors") as List<Map<String, Any?>>
        check(manifest["version"] == 1L && manifest["count"] == 77L && entries.size == 77 && entries.map { it["id"] }.toSet().size == 77)
        val batch = entries.filter { (it["path"] as String).startsWith("s3/$group/") }
        check(batch.size == count)
        for (entry in batch) {
            val file = File(VectorFiles.root, entry["path"] as String)
            check(file.canonicalPath.startsWith(VectorFiles.root.canonicalPath + File.separator))
            check(digest(file) == entry["sha256"])
            val root = VectorJSON(file.readText()).parse() as Map<String, Any?>
            check(root["id"] == entry["id"])
            val given = root.getValue("given") as Map<String, Any?>
            val now = Instant.parse((given.getValue("clock") as Map<*, *>)["now"] as String)
            val zone = ZoneId.of(given.getValue("timeZone") as String)
            val op = entry.getValue("androidAdapter") as String
            check(entry["iosAdapter"] == op)
            val adapter = S3VectorAdapter(now, zone)
            SharedVectorRunner(false, setOf(op)) { dispatched, resolved -> check(dispatched == op); adapter.evaluate(dispatched, resolved) }.run(file.readBytes(), file.name)
            VectorFiles.report(file)
        }
        println("S3-MANIFEST sha256=${digest(manifestFile)} count=77 group=$group executed=$count")
    }
    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
}
