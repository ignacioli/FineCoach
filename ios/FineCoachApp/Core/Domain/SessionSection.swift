import Foundation

/// Which kind of owner a `SessionSection` belongs to (data-model §2.7).
public enum SessionSectionOwnerKind: String, Codable, Sendable {
    case session
    case template
}

/// A named grouping of Exercises within one Session or one `TrainingTemplate`
/// (data-model §2.7, M1B-FR-020/021). A blank Session/Template defaults to a
/// flat, entirely unsectioned Exercise list -- Sections are opt-in and MUST
/// NEVER be forced. Unsectioned Exercises and Sections coexist and share ONE
/// unified `orderIndex` axis per owner (both Section headers and Exercises
/// draw from the same integer space, unique within the owner) so the
/// combined display order is always unambiguous.
public struct SessionSection: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let ownerKind: SessionSectionOwnerKind
    public let ownerID: StableUUID
    public let name: NormalizedName
    public let orderIndex: UInt32

    public init(
        id: StableUUID,
        ownerKind: SessionSectionOwnerKind,
        ownerID: StableUUID,
        name: NormalizedName,
        orderIndex: UInt32
    ) {
        self.id = id
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.name = name
        self.orderIndex = orderIndex
    }

    public func renamed(_ name: NormalizedName) -> SessionSection {
        SessionSection(id: id, ownerKind: ownerKind, ownerID: ownerID, name: name, orderIndex: orderIndex)
    }

    func relocating(orderIndex: UInt32) -> SessionSection {
        SessionSection(id: id, ownerKind: ownerKind, ownerID: ownerID, name: name, orderIndex: orderIndex)
    }
}

/// One row on the owner's unified `orderIndex` axis: either a Section header
/// or an Exercise (sectioned or not). Used only to describe/validate/
/// renumber the combined order -- never persisted as its own object.
public enum SessionSectionAxisItem: Sendable {
    case section(StableUUID)
    case exercise(StableUUID)
}

/// Pure Domain policy for Section/unsectioned-Exercise ordering and the
/// mandatory disposition choice on non-empty Section deletion (T028,
/// M1B-FR-020/021). Nothing here touches persistence; callers (Application
/// layer, T030) own reading the current state and writing the result back.
public enum SessionSectionOrdering {
    /// Validates that `orderIndex` values across `sections` and `exerciseIDs`
    /// (paired with their current orderIndex) are unique within the owner's
    /// unified axis. Throws `DomainError.conflict` on any duplicate.
    public static func validateUnique(
        sectionOrderIndices: [UInt32],
        exerciseOrderIndices: [UInt32]
    ) throws {
        let all = sectionOrderIndices + exerciseOrderIndices
        guard Set(all).count == all.count else {
            throw DomainError.conflict
        }
    }

    /// Renumbers a caller-supplied combined display order (`axis`, already in
    /// the desired sequence) into a dense, unique `0..<axis.count` orderIndex
    /// space, returning the new orderIndex for every section id and every
    /// exercise id it was given. `axis` MUST mention every existing section
    /// and exercise id for the owner exactly once (callers assemble it from
    /// their current in-memory lists) -- this is how "create/rename/reorder
    /// sections" and "move an Exercise between sections/unsectioned" both
    /// resolve to a single renumbering step that can never produce a
    /// duplicate orderIndex by construction.
    public static func renumbering(_ axis: [SessionSectionAxisItem]) throws -> (
        sectionOrder: [StableUUID: UInt32], exerciseOrder: [StableUUID: UInt32]
    ) {
        var sectionOrder: [StableUUID: UInt32] = [:]
        var exerciseOrder: [StableUUID: UInt32] = [:]
        for (offset, item) in axis.enumerated() {
            let index = UInt32(offset)
            switch item {
            case .section(let id):
                guard sectionOrder[id] == nil else {
                    throw DomainError.conflict
                }
                sectionOrder[id] = index
            case .exercise(let id):
                guard exerciseOrder[id] == nil else {
                    throw DomainError.conflict
                }
                exerciseOrder[id] = index
            }
        }
        return (sectionOrder, exerciseOrder)
    }
}

/// The mandatory choice a Coach MUST make before a non-empty `SessionSection`
/// can be deleted (M1B-FR-020/021, data-model §2.7 edge case). There is
/// deliberately no default/no-argument overload for deleting a section with
/// Exercises still in it -- the disposition is a required parameter, so a
/// silent orphan or silent delete is structurally unreachable.
public enum SessionSectionDeletionDisposition: Sendable, Equatable {
    /// Move every Exercise currently in the deleted Section to `sectionID`
    /// (`nil` means "the unsectioned sequence").
    case moveExercisesTo(sectionID: StableUUID?)
    /// Delete the Section AND every Exercise still assigned to it.
    case deleteWithExercises
}

extension SessionSectionOrdering {
    /// Result of resolving a Section deletion: the surviving sections (minus
    /// the deleted one), the ids of Exercises that must be deleted (empty
    /// unless `.deleteWithExercises` was chosen), and the new `sectionID` to
    /// apply to Exercises that survive (nil = unsectioned). Callers still owe
    /// a renumbering pass afterwards via `renumbering`.
    public struct SectionDeletionResolution: Sendable {
        public let survivingSections: [SessionSection]
        public let exerciseIDsToDelete: Set<StableUUID>
        public let relocatedSectionID: StableUUID?
    }

    /// Resolves what MUST happen to a non-empty Section's Exercises before it
    /// can be removed (M1B-FR-021). `exerciseIDsInSection` is the caller's
    /// current membership list for `sectionID` (empty is fine -- an empty
    /// Section can always be deleted without a disposition mattering, but
    /// the caller still passes one to keep the call site uniform).
    public static func resolveSectionDeletion(
        sectionID: StableUUID,
        exerciseIDsInSection: Set<StableUUID>,
        disposition: SessionSectionDeletionDisposition,
        existingSections: [SessionSection]
    ) throws -> SectionDeletionResolution {
        guard existingSections.contains(where: { $0.id == sectionID }) else {
            throw DomainError.notFound
        }
        let surviving = existingSections.filter { $0.id != sectionID }
        switch disposition {
        case .deleteWithExercises:
            return SectionDeletionResolution(
                survivingSections: surviving,
                exerciseIDsToDelete: exerciseIDsInSection,
                relocatedSectionID: nil
            )
        case .moveExercisesTo(let targetSectionID):
            if let targetSectionID {
                guard targetSectionID != sectionID, surviving.contains(where: { $0.id == targetSectionID }) else {
                    throw DomainError.invalidState
                }
            }
            return SectionDeletionResolution(
                survivingSections: surviving,
                exerciseIDsToDelete: [],
                relocatedSectionID: targetSectionID
            )
        }
    }
}
