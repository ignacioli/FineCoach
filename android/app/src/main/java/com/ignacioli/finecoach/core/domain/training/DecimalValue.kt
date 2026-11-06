package com.ignacioli.finecoach.core.domain.training

import java.math.BigDecimal
import java.math.RoundingMode

@JvmInline
value class DecimalValue private constructor(val canonicalString: String) : Comparable<DecimalValue> {
    val decimal: BigDecimal
        get() = canonicalString.toBigDecimal()

    val isZero: Boolean
        get() = this == ZERO

    val isPositive: Boolean
        get() = compareTo(ZERO) > 0

    val isInteger: Boolean
        get() = decimal.stripTrailingZeros().scale() <= 0

    fun adding(other: DecimalValue): DecimalValue = fromBigDecimal(decimal.add(other.decimal))

    fun multipliedBy(other: DecimalValue): DecimalValue = fromBigDecimal(decimal.multiply(other.decimal))

    override fun compareTo(other: DecimalValue): Int = decimal.compareTo(other.decimal)

    companion object {
        private val DECIMAL_PATTERN = Regex("^-?(?:\\d+(?:\\.\\d*)?|\\.\\d+)$")

        val ZERO: DecimalValue = parse("0")

        fun parse(raw: String): DecimalValue {
            val input = raw.trim()
            if (input.isEmpty()) {
                fail(DomainError.invalidDecimal)
            }
            if (!DECIMAL_PATTERN.matches(input)) {
                fail(DomainError.invalidDecimal)
            }
            val parsed = input.toBigDecimalOrNull() ?: fail(DomainError.invalidDecimal)
            return fromBigDecimal(parsed)
        }

        fun seconds(intervalSeconds: Double): DecimalValue {
            val clamped = if (intervalSeconds < 0.0) {
                0.0
            } else {
                intervalSeconds
            }
            val floored = BigDecimal.valueOf(clamped).setScale(0, RoundingMode.FLOOR)
            return fromBigDecimal(floored)
        }

        fun fromBigDecimal(value: BigDecimal): DecimalValue {
            var canonical = value.stripTrailingZeros().toPlainString()
            if (canonical == "-0") {
                canonical = "0"
            }
            if (canonical.toByteArray(Charsets.UTF_8).size > MAX_UTF8_BYTES) {
                fail(DomainError.textTooLong)
            }
            return DecimalValue(canonical)
        }
    }
}
