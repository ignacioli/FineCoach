package com.ignacioli.finecoach.core.crypto

import java.text.Normalizer
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/** FCBK v1 KDF only; password creation policy belongs to its future caller. */
object BackupKDF {
    const val ITERATIONS = 600_000
    const val ALGORITHM = "PBKDF2withHmacSHA256"

    fun normalizedPasswordUTF8(password: String): ByteArray =
        Normalizer.normalize(password, Normalizer.Form.NFC).toByteArray(Charsets.UTF_8)

    fun deriveKey(password: String, salt: ByteArray, iterations: Int): ByteArray {
        val canonical = Normalizer.normalize(password, Normalizer.Form.NFC)
        require(salt.size == 32 && iterations == ITERATIONS && canonical.toByteArray(Charsets.UTF_8).isNotEmpty()) {
            "Invalid KDF parameters"
        }
        val chars = canonical.toCharArray()
        val spec = PBEKeySpec(chars, salt, iterations, 256)
        try {
            return SecretKeyFactory.getInstance(ALGORITHM).generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
            chars.fill('\u0000')
        }
    }
}
