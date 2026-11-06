package com.ignacioli.finecoach.core.domain.student

import java.text.Normalizer

private const val MAX_UTF8_BYTES = 64 * 1024

private fun canonicalText(raw: String): String {
    return Normalizer.normalize(raw.trim(), Normalizer.Form.NFC)
}

@JvmInline
value class ValidatedText private constructor(val value: String) {
    companion object {
        val maximumUTF8Bytes: Int = MAX_UTF8_BYTES

        fun parse(raw: String, allowEmpty: Boolean = false): ValidatedText {
            val canonical = canonicalText(raw)
            if (!allowEmpty && canonical.isEmpty()) {
                throw StudentDomainException(StudentDomainError.emptyText, "Text must not be empty")
            }
            if (canonical.toByteArray(Charsets.UTF_8).size > maximumUTF8Bytes) {
                throw StudentDomainException(
                    StudentDomainError.textTooLong,
                    "Text exceeds max UTF-8 length: $maximumUTF8Bytes",
                )
            }
            return ValidatedText(canonical)
        }
    }
}
