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
    public static func joinedDisplayNames(for parts: Set<BodyPart>) -> String? {
        guard !parts.isEmpty else { return nil }
        return ordered(parts).map(\.displayName).joined(separator: " · ")
    }
}
