// fictional-data: synthetic precision boundaries; diagnostics contain no measurements.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.features.body.BodyDataDisplay
import java.math.BigDecimal
import org.junit.Test

class BodyDataDisplayTests {
    private fun verify(input: String, unit: String, expected: String, custom: Boolean = false) {
        check(BodyDataDisplay.format(BigDecimal(input), unit, custom) == expected) { "Display precision mismatch" }
    }
    @Test fun canonicalUnitsRoundHalfUpAndStripZeros() {
        for (unit in listOf("kg", "cm", "%")) {
            verify("63", unit, "63"); verify("62.96", unit, "63")
            verify("62.94", unit, "62.9"); verify("62.95", unit, "63")
            verify("62.85", unit, "62.9"); verify("0.04", unit, "0")
            verify("0.05", unit, "0.1"); verify("0", unit, "0")
        }
    }
    @Test fun imperialUnitsKeepTwoDecimalConvention() {
        for (unit in listOf("lb", "in")) {
            verify("12.345", unit, "12.35"); verify("12.344", unit, "12.34")
            verify("12.999", unit, "13"); verify("12", unit, "12")
        }
    }
    @Test fun customPreservesRecordedPrecisionEvenWhenUnitMatchesBuiltIn() {
        verify("62.9994", "kg", "62.9994", true)
        verify("3.125", "格", "3.125", true)
    }
    @Test fun roundingDoesNotIntroduceNegativeZeroOrNegativePositiveInput() {
        verify("-0.04", "kg", "0")
        for (unit in listOf("kg", "cm", "%", "lb", "in")) {
            check(BigDecimal(BodyDataDisplay.format(BigDecimal("0.0001"), unit)).signum() >= 0) { "Display introduced a negative value" }
        }
    }
}
