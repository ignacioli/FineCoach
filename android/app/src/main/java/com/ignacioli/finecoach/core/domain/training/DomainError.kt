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
