import Foundation

/// The 8 main training-focus body parts (M1B-FR-033, D-013, data-model §2.0),
/// shared verbatim by `Appointment.trainingFocus`, `Session.trainingFocus`,
/// and `TrainingTemplate.trainingFocus` (all `Set<BodyPart>`, selectable,
/// allowed to be empty). Raw values are stable English identifiers used for
/// persistence/backup; Chinese display names come from `Localizable.xcstrings`
/// via the existing localization pattern, not from the raw value.
public enum BodyPart: String, CaseIterable, Hashable, Codable, Sendable, Identifiable {
    case chest
    case shoulders
    case back
    case thighs
    case calves
    case arms
    case glutes
    case core

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chest: return String(localized: "bodyPart.chest")
        case .shoulders: return String(localized: "bodyPart.shoulders")
        case .back: return String(localized: "bodyPart.back")
        case .thighs: return String(localized: "bodyPart.thighs")
        case .calves: return String(localized: "bodyPart.calves")
        case .arms: return String(localized: "bodyPart.arms")
        case .glutes: return String(localized: "bodyPart.glutes")
        case .core: return String(localized: "bodyPart.core")
        }
    }

    /// A stable display order (declaration order above, i.e. the order the
    /// spec itself lists them: 胸/肩/背/大腿/小腿/臂/臀/核心) -- used wherever a
    /// `Set<BodyPart>` needs to render as ordered text rather than in
    /// undefined `Set` iteration order.
    public static func ordered(_ parts: Set<BodyPart>) -> [BodyPart] {
        allCases.filter { parts.contains($0) }
    }

    /// Joins a training-focus set into display text (e.g. "胸 · 核心"),
    /// matching this codebase's existing " · " join convention (see
    /// `TrainingSetDisplayFormatting`, `StudentListView`, `TrendsView`).
    /// Returns `nil` for an empty set so callers can fall back to their own
    /// "no focus set" placeholder rather than showing an empty string.
    /// The D1–D9 artwork lists parts inside one field with "、" (e.g. "大腿、臀");
    /// pass that as `separator` there.
    public static func joinedDisplayNames(for parts: Set<BodyPart>, separator: String = " · ") -> String? {
        guard !parts.isEmpty else { return nil }
        return ordered(parts).map(\.displayName).joined(separator: separator)
    }

    /// Maps the exercise catalog's Chinese muscle-group label (the
    /// `primaryMuscleGroup` / `secondaryMuscleGroups` values in
    /// `provenance.json`, ordered as `ExerciseCatalogBrowse.muscleGroupOrder`)
    /// onto a `BodyPart`. Returns `nil` for anything outside the 8 parts.
    public init?(catalogMuscleGroup label: String) {
        switch label {
        case "胸": self = .chest
        case "肩": self = .shoulders
        case "背": self = .back
        case "大腿": self = .thighs
        case "小腿": self = .calves
        case "臂": self = .arms
        case "臀": self = .glutes
        case "核心": self = .core
        default: return nil
        }
    }
}

/// The body parts one exercise works, as recorded in the built-in catalog.
/// Custom exercises have no catalog facet and are represented by a `nil`
/// primary, so they never color the diagram (design system §9.1).
public struct ExerciseBodyParts: Hashable, Sendable {
    public let primary: BodyPart?
    public let secondary: Set<BodyPart>

    public init(primary: BodyPart?, secondary: Set<BodyPart> = []) {
        self.primary = primary
        self.secondary = secondary
    }

    /// Builds from the catalog's raw labels; unknown labels are dropped.
    public init(catalogPrimary: String?, catalogSecondary: [String] = []) {
        self.init(
            primary: catalogPrimary.flatMap(BodyPart.init(catalogMuscleGroup:)),
            secondary: Set(catalogSecondary.compactMap(BodyPart.init(catalogMuscleGroup:)))
        )
    }
}

/// The trained-body-part summary behind the share-preview body diagram
/// (design system §9.1, D7 scheme A): the union of every exercise's primary
/// part, and the union of their secondary parts minus any part that is
/// already primary. Derived only — no new stored data.
public struct TrainedBodyPartsSummary: Hashable, Sendable {
    public let primary: Set<BodyPart>
    public let secondary: Set<BodyPart>

    public init(primary: Set<BodyPart>, secondary: Set<BodyPart>) {
        self.primary = primary
        self.secondary = secondary.subtracting(primary)
    }

    public init(exercises: [ExerciseBodyParts]) {
        var primary = Set<BodyPart>()
        var secondary = Set<BodyPart>()
        for exercise in exercises {
            // No primary part means a custom exercise (no catalog facet);
            // it contributes nothing, secondary included.
            guard let part = exercise.primary else { continue }
            primary.insert(part)
            secondary.formUnion(exercise.secondary)
        }
        self.init(primary: primary, secondary: secondary)
    }

    public var isEmpty: Bool { primary.isEmpty && secondary.isEmpty }
}
