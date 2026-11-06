package com.ignacioli.finecoach.core.domain.student

@JvmInline
value class NormalizedName private constructor(val value: String) {
    companion object {
        fun parse(raw: String): NormalizedName = NormalizedName(ValidatedText.parse(raw).value)
    }
}
