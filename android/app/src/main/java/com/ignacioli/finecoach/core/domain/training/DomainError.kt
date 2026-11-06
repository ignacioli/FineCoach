package com.ignacioli.finecoach.core.domain.training

enum class DomainError {
    emptyText,
    textTooLong,
    invalidDecimal,
    invalidNumber,
    invalidUnit,
    invalidMode,
    invalidState,
    invalidIdentifier,
    conflict,
    notFound,
    staleRevision,
    incompatibleInput,
}

class DomainException(
    val error: DomainError,
    val field: String? = null,
) : IllegalStateException(
    buildString {
        append(error.name)
        if (field != null) {
            append(":")
            append(field)
        }
    }
)

internal fun fail(error: DomainError, field: String? = null): Nothing = throw DomainException(error, field)

/** Parses a required name and maps common validation failures to [DomainError], as iOS ValidatedText does. */
internal fun parseDomainName(raw: String, field: String): com.ignacioli.finecoach.core.domain.common.NormalizedName {
    val canonical = try {
        com.ignacioli.finecoach.core.domain.common.ValidatedText.parse(raw, allowEmpty = true)
    } catch (_: IllegalArgumentException) {
        fail(DomainError.textTooLong, field)
    }
    if (canonical.isEmpty) fail(DomainError.emptyText, field)
    return com.ignacioli.finecoach.core.domain.common.NormalizedName.parse(canonical.value)
}
