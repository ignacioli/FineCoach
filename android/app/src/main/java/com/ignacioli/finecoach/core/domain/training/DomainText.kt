package com.ignacioli.finecoach.core.domain.training

import java.text.Normalizer

internal const val MAX_UTF8_BYTES: Int = 64 * 1024

internal fun normalized(raw: String): String =
    Normalizer.normalize(raw.trim(), Normalizer.Form.NFC)

internal fun requiredText(raw: String, field: String): String {
    val canonical = normalized(raw)
    if (canonical.isEmpty()) {
        fail(DomainError.emptyText, field)
    }
    if (canonical.toByteArray(Charsets.UTF_8).size > MAX_UTF8_BYTES) {
        fail(DomainError.textTooLong, field)
    }
    return canonical
}

internal fun optionalText(raw: String?): String? {
    if (raw == null) {
        return null
    }
    val canonical = normalized(raw)
    if (canonical.isEmpty()) {
        return null
    }
    if (canonical.toByteArray(Charsets.UTF_8).size > MAX_UTF8_BYTES) {
        fail(DomainError.textTooLong)
    }
    return canonical
}
