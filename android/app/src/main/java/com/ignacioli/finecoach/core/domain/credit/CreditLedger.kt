package com.ignacioli.finecoach.core.domain.credit

import com.ignacioli.finecoach.core.domain.common.CreditDirection

/**
 * Pure ledger rules (FR-012/FR-015).
 *
 * Mirrors iOS `CreditLedger` (`ios/FineCoachApp/Core/Domain/CreditLedger.swift:88-141`).
 * This type is deliberately stateless: persistence owns the dedup-by-source-event-key
 * upsert and the transactional read-then-write that makes the non-negative balance
 * check race free. The rules here only state what the invariants are.
 *
 * The S0-06 entry point `com.ignacioli.finecoach.domain.CreditLedger` is left
 * untouched because `SharedVectorRunner` depends on it and both files are outside
 * the T003 whitelist; [balance] keeps the same exact-arithmetic behaviour.
 */
object CreditLedger {
    /**
     * Authoritative balance derivation (FR-012): `totalCredits + credits - debits`.
     *
     * Uses exact arithmetic, matching the S0 shared-vector entry point: overflow
     * fails instead of silently wrapping.
     */
    fun balance(totalCredits: Long, adjustments: List<CreditAdjustment>): Long {
        var balance = totalCredits
        for (adjustment in adjustments) {
            balance = when (adjustment.direction) {
                CreditDirection.debit -> Math.subtractExact(balance, adjustment.amount)
                CreditDirection.credit -> Math.addExact(balance, adjustment.amount)
            }
        }
        return balance
    }

    /**
     * Debit precondition (FR-012/FR-014): a debit must never push the balance
     * negative. Callers must evaluate this against a balance read inside the same
     * transaction that records the debit, not a stale snapshot.
     */
    fun canDebit(currentBalance: Long, amount: Long): Boolean =
        Math.subtractExact(currentBalance, amount) >= 0
}
