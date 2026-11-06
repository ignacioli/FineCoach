package com.ignacioli.finecoach.domain

/** Pure balance projection; mirrors CreditLedger.swift:95-106, including negative balances. */
object CreditLedger {
    enum class Direction { debit, credit }
    data class Adjustment(val direction: Direction, val amount: Long)

    fun balance(totalCredits: Long, adjustments: List<Adjustment>): Long {
        var balance = totalCredits
        for (adjustment in adjustments) {
            balance = when (adjustment.direction) {
                Direction.debit -> Math.subtractExact(balance, adjustment.amount)
                Direction.credit -> Math.addExact(balance, adjustment.amount)
            }
        }
        return balance
    }
}
