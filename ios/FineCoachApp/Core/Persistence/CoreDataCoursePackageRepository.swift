import CoreData
import Foundation

/// Persistence for `CoursePackage` + its `CreditAdjustment` ledger
/// (data-model §2.3/§2.4, T023). Two invariants are enforced entirely
/// inside single `PersistenceWriter` transactions (never split across two
/// awaits), so there is no read-then-write race window even though the
/// writer is a single serial actor:
///
/// 1. At most one `active` `CoursePackage` per Student -- mirrors M1-A's
///    `ExerciseNameClaim` pattern via a dedicated `ActiveCoursePackageClaimMO`
///    row with a Core Data uniqueness constraint on `studentID`.
/// 2. At most one effective `CreditAdjustment` per `sourceEventKey` -- an
///    upsert-style "fetch by key, no-op if present" guarded by the same
///    field's Core Data uniqueness constraint as a backstop.
public struct CoreDataCoursePackageRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    // MARK: - Package lifecycle

    /// Atomically ends the Student's current active package (if any) and
    /// activates `draft` in its place (M1B-FR-012). `draft.status` MUST be
    /// `.active`. If the Student already has an active package with the
    /// SAME id as `draft`, this is a no-op idempotent re-save rather than a
    /// conflict.
    public func activatePackage(_ draft: CoursePackage, now: Date) async throws -> CoursePackage {
        precondition(draft.status == .active)
        return try await writer.transaction { context in
            if let existingClaim = try CoursePackageManagedObjectMapping.fetchActiveClaim(
                studentID: draft.studentID.rawValue,
                in: context
            ) {
                guard let claimedPackageID = existingClaim.value(forKey: "packageID") as? UUID else {
                    throw DomainError.incompatibleInput
                }
                if claimedPackageID == draft.id.rawValue {
                    let object = try CoursePackageManagedObjectMapping.requirePackage(
                        id: draft.id.rawValue,
                        in: context
                    )
                    CoursePackageManagedObjectMapping.apply(draft, to: object)
                    return try CoursePackageManagedObjectMapping.makePackage(from: object)
                }
                // A different package is currently active for this Student --
                // end it first so the invariant "at most one active" never
                // observes two active rows, even transiently.
                let oldObject = try CoursePackageManagedObjectMapping.requirePackage(
                    id: claimedPackageID,
                    in: context
                )
                let oldPackage = try CoursePackageManagedObjectMapping.makePackage(from: oldObject)
                let ended = try oldPackage.ending(now: now)
                CoursePackageManagedObjectMapping.apply(ended, to: oldObject)
                context.delete(existingClaim)
            }
            let object = NSEntityDescription.insertNewObject(
                forEntityName: CoursePackageManagedObjectMapping.entityName,
                into: context
            )
            CoursePackageManagedObjectMapping.apply(draft, to: object)
            CoursePackageManagedObjectMapping.insertClaim(
                studentID: draft.studentID.rawValue,
                packageID: draft.id.rawValue,
                in: context
            )
            return try CoursePackageManagedObjectMapping.makePackage(from: object)
        }
    }

    /// Ends a package without activating a replacement (M1B-FR-012 "先结束当前").
    public func endPackage(id: StableUUID, now: Date) async throws -> CoursePackage {
        try await writer.transaction { context in
            let object = try CoursePackageManagedObjectMapping.requirePackage(id: id.rawValue, in: context)
            let current = try CoursePackageManagedObjectMapping.makePackage(from: object)
            let ended = try current.ending(now: now)
            CoursePackageManagedObjectMapping.apply(ended, to: object)
            if let claim = try CoursePackageManagedObjectMapping.fetchActiveClaim(
                studentID: current.studentID.rawValue,
                in: context
            ), (claim.value(forKey: "packageID") as? UUID) == id.rawValue {
                context.delete(claim)
            }
            return try CoursePackageManagedObjectMapping.makePackage(from: object)
        }
    }

    public func package(id: StableUUID) async throws -> CoursePackage {
        try await writer.read { context in
            let object = try CoursePackageManagedObjectMapping.requirePackage(id: id.rawValue, in: context)
            return try CoursePackageManagedObjectMapping.makePackage(from: object)
        }
    }

    public func activePackage(studentID: StableUUID) async throws -> CoursePackage? {
        try await writer.read { context in
            guard
                let claim = try CoursePackageManagedObjectMapping.fetchActiveClaim(
                    studentID: studentID.rawValue,
                    in: context
                ),
                let packageID = claim.value(forKey: "packageID") as? UUID,
                let object = try CoursePackageManagedObjectMapping.fetchPackage(id: packageID, in: context)
            else {
                return nil
            }
            return try CoursePackageManagedObjectMapping.makePackage(from: object)
        }
    }

    /// All packages for a Student, active + historical, newest first (T024
    /// "有效/历史课包" list).
    public func packages(studentID: StableUUID) async throws -> [CoursePackage] {
        try await writer.read { context in
            try CoursePackageManagedObjectMapping.fetchPackages(studentID: studentID.rawValue, in: context)
                .map { try CoursePackageManagedObjectMapping.makePackage(from: $0) }
        }
    }

    // MARK: - Credit ledger (append-only, idempotent by sourceEventKey)

    /// The single write path for every ledger entry, automatic or manual.
    /// Runs entirely inside one transaction: if an adjustment already exists
    /// for `sourceEventKey`, that existing entry is returned unchanged (the
    /// idempotent no-op repeated completion/reopen/absence-charge relies on);
    /// otherwise `makeAdjustment` is invoked with the balance read inside
    /// THIS SAME transaction (so the negative-balance precondition can never
    /// race against a concurrent write) and the result is inserted, with the
    /// package's non-authoritative `remainingCredits` cache refreshed to
    /// match.
    public func recordIdempotentAdjustment(
        packageID: StableUUID,
        sourceEventKey: String,
        now: Date,
        makeAdjustment: @escaping @Sendable (_ currentBalance: Int) throws -> CreditAdjustment
    ) async throws -> CreditAdjustment {
        try await writer.transaction { context in
            if let existing = try CoursePackageManagedObjectMapping.fetchAdjustment(
                sourceEventKey: sourceEventKey,
                in: context
            ) {
                return try CoursePackageManagedObjectMapping.makeAdjustment(from: existing)
            }
            let packageObject = try CoursePackageManagedObjectMapping.requirePackage(
                id: packageID.rawValue,
                in: context
            )
            let package = try CoursePackageManagedObjectMapping.makePackage(from: packageObject)
            let existingAdjustments = try CoursePackageManagedObjectMapping.fetchAdjustments(
                packageID: packageID.rawValue,
                in: context
            ).map { try CoursePackageManagedObjectMapping.makeAdjustment(from: $0) }
            let currentBalance = CreditLedger.balance(
                totalCredits: package.totalCredits, adjustments: existingAdjustments)

            let adjustment = try makeAdjustment(currentBalance)
            guard adjustment.packageID == packageID, adjustment.sourceEventKey == sourceEventKey else {
                throw DomainError.invalidState
            }

            let object = NSEntityDescription.insertNewObject(
                forEntityName: CoursePackageManagedObjectMapping.adjustmentEntityName,
                into: context
            )
            CoursePackageManagedObjectMapping.apply(adjustment, to: object)

            let newBalance = CreditLedger.balance(
                totalCredits: package.totalCredits,
                adjustments: existingAdjustments + [adjustment]
            )
            let cached = try package.cachingRemaining(newBalance, now: now)
            CoursePackageManagedObjectMapping.apply(cached, to: packageObject)

            return adjustment
        }
    }

    public func adjustment(sourceEventKey: String) async throws -> CreditAdjustment? {
        try await writer.read { context in
            guard
                let object = try CoursePackageManagedObjectMapping.fetchAdjustment(
                    sourceEventKey: sourceEventKey,
                    in: context
                )
            else {
                return nil
            }
            return try CoursePackageManagedObjectMapping.makeAdjustment(from: object)
        }
    }

    /// Full traceable trail for a package, oldest first (T024 "每笔余额变化可查看对应课时调整").
    public func adjustments(packageID: StableUUID) async throws -> [CreditAdjustment] {
        try await writer.read { context in
            try CoursePackageManagedObjectMapping.fetchAdjustments(packageID: packageID.rawValue, in: context)
                .map { try CoursePackageManagedObjectMapping.makeAdjustment(from: $0) }
        }
    }

    /// Authoritative balance, derived fresh from the ledger every call
    /// (data-model §2.3: the stored cache is never the source of truth).
    public func balance(packageID: StableUUID) async throws -> Int {
        try await writer.read { context in
            let packageObject = try CoursePackageManagedObjectMapping.requirePackage(
                id: packageID.rawValue,
                in: context
            )
            let package = try CoursePackageManagedObjectMapping.makePackage(from: packageObject)
            let adjustments = try CoursePackageManagedObjectMapping.fetchAdjustments(
                packageID: packageID.rawValue,
                in: context
            ).map { try CoursePackageManagedObjectMapping.makeAdjustment(from: $0) }
            return CreditLedger.balance(totalCredits: package.totalCredits, adjustments: adjustments)
        }
    }
}
