package com.ignacioli.finecoach.core.domain.progress

import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.training.DecimalValue
import java.math.BigDecimal
import java.math.RoundingMode
import java.math.BigInteger

/** Derived Epley estimate, never a personal-record or session-gains metric. */
object EstimatedOneRepMax {
    val exerciseIDs: Set<StableExerciseID> = setOf(
        "a2f5b6ef-b780-49c0-8d96-fdaff23e27ce", "3717d144-7815-4a97-9a56-956fb889c996",
        "ee8e8db4-2d82-49e1-ab7f-891e9a354934", "0c2d9b74-3d1e-481f-a7bf-3b3532f7d6b0",
        "8b0a0371-c0a9-42a7-aab7-68d520542fb2", "3f7b2244-8408-51fb-8211-3a764028d340",
        "9c31b616-0fe1-5fc1-bc97-9dba29be61ca", "2ab0f099-1041-5d03-9f63-f7a2a6ec11c9",
        "275fb49f-975c-4d6e-9d63-2c86ed740f40", "a390471f-f7ff-5371-850c-8eab07c68fb4",
        "db39aa20-bf4e-53d2-a3a7-e8cf4f2d24a8",
    ).map { StableExerciseID.parse(it) }.toSet()

    fun value(weight: DecimalValue, reps: DecimalValue, exerciseID: StableExerciseID): DecimalValue? {
        if (exerciseID !in exerciseIDs || !weight.isPositive || !reps.isInteger || reps < DecimalValue.parse("1") || reps > DecimalValue.parse("10")) return null
        if (reps.compareTo(DecimalValue.parse("1")) == 0) return weight
        return try {
            DecimalValue.fromBigDecimal(FoundationDecimal.add(weight.decimal, FoundationDecimal.divide(FoundationDecimal.multiply(weight.decimal, reps.decimal), BigDecimal(30))))
        } catch (_: ArithmeticException) { null } catch (_: IllegalArgumentException) { null }
    }

}

/** Mirrors Foundation 5.9 Decimal.swift's 8 UInt16 mantissa, division and normalization.
 * Reference: swiftlang/swift-corelibs-foundation, NSDecimalDivide / NSDecimalNormalize.
 */
object FoundationDecimal {
    private val ten = BigInteger.TEN
    private fun fit(raw: BigInteger, exponent: Int, round: Boolean = false): BigDecimal {
        var m = raw; var e = exponent
        while (m.abs().bitLength() > 144) { m /= BigInteger.valueOf(10000); e += 4 }
        while (m.abs().bitLength() > 128) { m /= ten; e++ }
        if (round && e > exponent) {
            m = BigDecimal(raw).divide(BigDecimal(ten.pow(e - exponent)), 0, RoundingMode.HALF_UP).toBigIntegerExact()
            if (m.abs().bitLength() > 128) { m /= ten; e++ }
        }
        require(e in -128..127) { "Decimal range" }
        return BigDecimal(m, -e).stripTrailingZeros()
    }
    fun multiply(lhs: BigDecimal, rhs: BigDecimal): BigDecimal {
        val a = lhs.stripTrailingZeros(); val b = rhs.stripTrailingZeros()
        return fit(a.unscaledValue() * b.unscaledValue(), -a.scale() - b.scale(), round = true)
    }
    fun divide(numerator: BigDecimal, denominator: BigDecimal): BigDecimal {
        val n = numerator.stripTrailingZeros(); val d = denominator.stripTrailingZeros()
        return fit(n.unscaledValue() * ten.pow(38) / d.unscaledValue(), -n.scale() + d.scale() - 38)
    }
    fun add(lhs: BigDecimal, rhs: BigDecimal): BigDecimal {
        val a = lhs.stripTrailingZeros(); val b = rhs.stripTrailingZeros()
        if (a.signum() == 0) return b
        if (b.signum() == 0) return a
        val large = if (a.scale() <= b.scale()) a else b
        val small = if (a.scale() <= b.scale()) b else a
        var scale = small.scale()
        if (large.unscaledValue().abs().multiply(ten.pow(scale - large.scale())).bitLength() > 128) {
            val words = (large.unscaledValue().abs().bitLength() + 15) / 16
            val shift = kotlin.math.floor((8 - words) * 4.81647993).toInt()
            scale = large.scale() + shift
        }
        return fit(large.setScale(scale).unscaledValue() + small.setScale(scale, RoundingMode.DOWN).unscaledValue(), -scale, round = true)
    }
}
