package com.ignacioli.finecoach

import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// Run the real Node CLI against private temporary README fixtures. These tests
// exercise parser failures rather than reconstructing its parsing logic in Kotlin.
class TokenGeneratorTests {
    @get:Rule val temporary = TemporaryFolder()

    private val repository: File
        get() = File(checkNotNull(System.getProperty("finecoach.storageProjectDirectory")) {
            "Missing app project path for generator tests"
        }).canonicalFile.parentFile.parentFile

    private val readme: String
        get() = File(repository, "design/design-system/README.md").readText()

    private data class Result(val status: Int, val output: String)

    private fun run(input: File, output: File, check: Boolean = false): Result {
        val log = temporary.newFile()
        val arguments = mutableListOf("node", File(repository, "scripts/android/generate-tokens.mjs").path,
            "--input", input.path, "--output", output.path)
        if (check) arguments += "--check"
        val process = ProcessBuilder(arguments).directory(repository).redirectErrorStream(true).redirectOutput(log).start()
        val exited = process.waitFor(30, TimeUnit.SECONDS)
        if (!exited) process.destroyForcibly()
        assertTrue("Generator CLI timed out: ${log.readText()}", exited)
        return Result(process.exitValue(), log.readText())
    }

    private fun fixture(source: String): File = temporary.newFile().apply { writeText(source) }

    private fun rejects(source: String) {
        assertNotEquals("Fixture mutation must affect the actual README", readme, source)
        val output = File(temporary.root, "output")
        val result = run(fixture(source), output)
        assertNotEquals("Malformed input unexpectedly succeeded: ${result.output}", 0, result.status)
        assertTrue("Missing explicit CLI failure diagnostic: ${result.output}", result.output.contains("generate-tokens:"))
        assertFalse("Invalid input must not generate Kotlin output", output.walkTopDown().any { it.isFile && it.extension == "kt" })
    }

    @Test fun validReadmeGeneratesExactlyFourFilesAndCheckDoesNotRewriteThem() {
        val input = fixture(readme)
        val output = File(temporary.root, "output")
        val generated = run(input, output)
        assertEquals(generated.output, 0, generated.status)
        val files = output.walkTopDown().filter { it.isFile }.toList()
        assertEquals(setOf("FcColors.kt", "FcTypography.kt", "FcSpacing.kt", "FcShapes.kt"), files.map { it.name }.toSet())
        assertEquals(4, files.size)
        val before = files.associate { it.relativeTo(output).path to it.readBytes().toList() }
        val checked = run(input, output, check = true)
        assertEquals(checked.output, 0, checked.status)
        assertEquals(before, files.associate { it.relativeTo(output).path to it.readBytes().toList() })
    }

    @Test fun missingRequiredTableFails() = rejects(readme.replace("### 2.1 原子色（FC Primitives）", "### removed primitive table"))

    @Test fun duplicateTokenFails() {
        val row = "| `space.1` | 4 |"
        rejects(readme.replace(row, "$row\n$row"))
    }

    @Test fun duplicateStyleFails() {
        val row = readme.lineSequence().single { it.startsWith("| `display` |") }
        rejects(readme.replace(row, "$row\n$row"))
    }

    @Test fun malformedNumericValueFails() = rejects(readme.replace("| `space.1` | 4 |", "| `space.1` | four |"))

    @Test fun malformedTableRowFails() = rejects(readme.replace("| `space.1` | 4 |", "| `space.1` | 4 | unexpected |"))

    @Test fun unknownColumnFails() = rejects(readme.replace("| Token | 值 | 备注 |", "| Token | 值 | unknown |"))

    @Test fun inconsistentSemanticAliasFails() = rejects(readme.replace(
        "| `color.action.primary` | brand.primary | `#2A2822` |",
        "| `color.action.primary` | brand.primary | `#FFFFFF` |",
    ))

    @Test fun manualGeneratedFileEditFailsCheckAndIsNotSilentlyRepaired() {
        val input = fixture(readme)
        val output = File(temporary.root, "output")
        val generated = run(input, output)
        assertEquals(generated.output, 0, generated.status)
        val colors = File(output, "com/ignacioli/finecoach/designsystem/FcColors.kt")
        colors.appendText("\n// Deliberate fixture tampering.\n")
        val tampered = colors.readText()
        val checked = run(input, output, check = true)
        assertNotEquals("Tampered generated file must fail: ${checked.output}", 0, checked.status)
        assertTrue(checked.output, checked.output.contains("Generated token changed"))
        assertEquals(tampered, colors.readText())
    }
}
