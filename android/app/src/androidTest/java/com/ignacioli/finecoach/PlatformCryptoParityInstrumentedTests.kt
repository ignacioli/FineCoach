package com.ignacioli.finecoach

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ignacioli.finecoach.core.crypto.BackupKDF
import java.security.MessageDigest
import javax.crypto.SecretKeyFactory
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlatformCryptoParityInstrumentedTests {
    private val fixture: JSONObject
        get() = InstrumentationRegistry.getInstrumentation().context.assets.open(
            "s0/crypto/m1a-fr-044__kdf-nfc-equivalence.json"
        ).bufferedReader(Charsets.UTF_8).use { JSONObject(it.readText()) }

    @Test fun nfcMatchesIndependentKey() = assertParity("passwordNFC")
    @Test fun nfdMatchesSameIndependentKey() = assertParity("passwordNFD")

    private fun assertParity(field: String) {
        val vector = fixture
        assertEquals("kdf-nfc-equivalence", vector.getString("id"))
        assertEquals("backup-kdf.derive-equivalent", vector.getJSONObject("when").getString("op"))
        val input = vector.getJSONObject("given").getJSONObject("state")
        val expected = vector.getJSONObject("then").getJSONObject("state")
        val normalized = BackupKDF.normalizedPasswordUTF8(input.getString(field))
        assertArrayEquals(BackupKDF.normalizedPasswordUTF8(input.getString("passwordNFC")), normalized)
        val digest = MessageDigest.getInstance("SHA-256").digest(normalized).hex()
        val saltHex = input.getString("saltHex")
        require(saltHex.matches(Regex("[0-9a-f]{64}")))
        val salt = saltHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val key = BackupKDF.deriveKey(input.getString(field), salt, input.getInt("iterations"))
        assertEquals(expected.getString("passwordNFCUTF8SHA256"), digest)
        assertEquals(32, key.size)
        assertEquals(expected.getString("keyHex"), key.hex())
        println("Android API=${Build.VERSION.SDK_INT} build=${Build.FINGERPRINT} provider=${SecretKeyFactory.getInstance(BackupKDF.ALGORITHM).provider.name} input=$field digest=$digest key=${key.hex()}")
    }

    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it.toInt() and 255) }
}
