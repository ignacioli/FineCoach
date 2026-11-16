package com.ignacioli.finecoach.core.domain.student

enum class StudentDomainError {
    emptyText,
    textTooLong,
    invalidState,
}

class StudentDomainException(
    val code: StudentDomainError,
    message: String,
) : IllegalArgumentException(message)
