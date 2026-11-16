package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.crypto.BackupKDF
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import org.junit.Assert.assertTrue
import org.junit.Test

class PlatformCryptoAvailabilityTests {
    @Test
    fun requiredAlgorithmsAreAvailable() {
        val kdf = SecretKeyFactory.getInstance(BackupKDF.ALGORITHM)
        val aead = Cipher.getInstance("AES/GCM/NoPadding")
        assertTrue(kdf.provider.name.isNotEmpty())
        assertTrue(aead.provider.name.isNotEmpty())
        println("JVM java=${System.getProperty("java.version")} PBKDF2=${kdf.provider.name} AES-GCM=${aead.provider.name}")
    }
}
