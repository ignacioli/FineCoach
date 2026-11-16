package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.crypto.BackupKDF
import java.security.MessageDigest
import javax.crypto.SecretKeyFactory
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PlatformCryptoParityTests {
    // This fixed fixture uses ASCII JSON with only Unicode string escapes.
    // Fail on unsupported escapes or duplicate leaf names instead of guessing.
    private val fixture = checkNotNull(javaClass.classLoader!!.getResourceAsStream(
        "s0/crypto/m1a-fr-044__kdf-nfc-equivalence.json"
    )).bufferedReader(Charsets.UTF_8).use { it.readText() }

    private fun string(name: String): String {
        val matches = Regex("\"$name\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\u[0-9a-fA-F]{4})*)\"")
            .findAll(fixture).toList()
        check(matches.size == 1) { "Expected one fixture field: $name" }
        return Regex("\\\\u([0-9a-fA-F]{4})").replace(matches.single().groupValues[1]) {
            it.groupValues[1].toInt(16).toChar().toString()
        }
    }

    private fun iterations(): Int {
        val matches = Regex("\"iterations\"\\s*:\\s*([0-9]+)\\s*[,}]").findAll(fixture).toList()
        check(matches.size == 1)
        return matches.single().groupValues[1].toInt()
    }

    @Test fun nfcMatchesIndependentKey() = assertParity("passwordNFC")
    @Test fun nfdMatchesSameIndependentKey() = assertParity("passwordNFD")

    private fun assertParity(field: String) {
        assertEquals("kdf-nfc-equivalence", string("id"))
        assertEquals("backup-kdf.derive-equivalent", string("op"))
        val password = string(field)
        val normalized = BackupKDF.normalizedPasswordUTF8(password)
        val digest = MessageDigest.getInstance("SHA-256").digest(normalized).hex()
        val key = BackupKDF.deriveKey(password, string("saltHex").unhex(), iterations())
        assertArrayEquals(BackupKDF.normalizedPasswordUTF8(string("passwordNFC")), normalized)
        assertEquals(string("passwordNFCUTF8SHA256"), digest)
        assertEquals(32, key.size)
        assertEquals(string("keyHex"), key.hex())
        println("JVM java=${System.getProperty("java.version")} provider=${SecretKeyFactory.getInstance(BackupKDF.ALGORITHM).provider.name} input=$field digest=$digest key=${key.hex()}")
    }

    @Test fun rejectsInvalidParameters() {
        for (size in listOf(0, 31, 33)) {
            assertThrows(IllegalArgumentException::class.java) {
                BackupKDF.deriveKey("x", ByteArray(size), 600_000)
            }
        }
        for (count in listOf(-1, 0, 599_999, 600_001)) {
            assertThrows(IllegalArgumentException::class.java) {
                BackupKDF.deriveKey("x", ByteArray(32), count)
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            BackupKDF.deriveKey("", ByteArray(32), 600_000)
        }
    }

    private fun String.unhex(): ByteArray {
        require(length == 64 && matches(Regex("[0-9a-f]{64}")))
        return chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }
    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it.toInt() and 255) }
}
