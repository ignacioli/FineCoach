package com.ignacioli.finecoach.storage.local

import com.ignacioli.finecoach.core.application.*
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import org.json.JSONObject

/** Per-coach display preferences, outside student data, Room and FCBK (same scope as iOS). */
class BodyDataUnitPreferences(filesDir: File? = null) {
    data class Units(val weight: String = "kg", val length: String = "cm")
    private val file = filesDir?.let { File(it, "BodyData/display-units.json") }
    private var memory = Units()

    @Synchronized fun read(): Units {
        val target = file ?: return memory
        return try {
            val root = JSONObject(target.readText())
            require(root.keys().asSequence().toSet() == setOf("version", "weight", "length") && root.getInt("version") == 1)
            val weight = root.getString("weight").takeIf { it in setOf("kg", "lb") } ?: "kg"
            val length = root.getString("length").takeIf { it in setOf("cm", "in") } ?: "cm"
            Units(weight, length)
        } catch (_: Exception) { Units() }
    }

    @Synchronized fun saveWeight(unit: String): ApplicationResult<Units> = save(unit, true)
    @Synchronized fun saveLength(unit: String): ApplicationResult<Units> = save(unit, false)

    private fun save(unit: String, weight: Boolean): ApplicationResult<Units> {
        if (unit !in if (weight) setOf("kg", "lb") else setOf("cm", "in"))
            return ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.incompatibleInput))
        return try {
            val current = read()
            val next = if (weight) current.copy(weight = unit) else current.copy(length = unit)
            file?.let { target ->
                check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
                val root = JSONObject().put("version", 1).put("weight", next.weight).put("length", next.length)
                val temp = File.createTempFile(".display-units-", ".tmp", target.parentFile)
                try {
                    FileOutputStream(temp).use { stream -> stream.write(root.toString().toByteArray(Charsets.UTF_8)); stream.fd.sync() }
                    Files.move(temp.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                } finally { temp.delete() }
            }
            memory = next
            ApplicationResult.Success(next)
        } catch (_: Exception) { ApplicationResult.Failure(ApplicationError(ApplicationErrorCode.persistenceFailed)) }
    }
}
