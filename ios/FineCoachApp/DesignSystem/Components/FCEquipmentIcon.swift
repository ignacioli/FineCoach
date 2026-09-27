import SwiftUI

/// The 18 equipment icons (§7.1; source of truth `design/m1-b-hifi/icons/`,
/// imported as template-rendered `equipment-<rawValue>` assets).
public enum FCEquipmentIcon: String, CaseIterable, Sendable {
    case barbell
    case bike
    case bodyweight
    case cableCrossover = "cable-crossover"
    case cableMachine = "cable-machine"
    case dumbbell
    case hackSquat = "hack-squat"
    case hipAdduction = "hip-adduction"
    case jumpRope = "jump-rope"
    case kettlebell
    case legExtension = "leg-extension"
    case pecDeck = "pec-deck"
    case resistanceBand = "resistance-band"
    case rowingMachine = "rowing-machine"
    case shoulderPress = "shoulder-press"
    case smithMachine = "smith-machine"
    case tbarRow = "tbar-row"
    case treadmill

    public var assetName: String { "equipment-\(rawValue)" }

    /// §7.1 exercise → icon table (owner 2026-09-23): by the catalog's
    /// `equipmentClass`, and for 固定器械 further by `primaryMuscleGroup`.
    /// `nil` means "no icon" (臂/核心 machines, 其他, custom exercises) —
    /// never a fallback icon. A lookup table only; no new data fields.
    public static func icon(equipmentClass: String?, primaryMuscleGroup: String?) -> FCEquipmentIcon? {
        switch equipmentClass {
        case "杠铃": return .barbell
        case "哑铃": return .dumbbell
        case "徒手": return .bodyweight
        case "龙门架": return .cableCrossover
        case "史密斯机": return .smithMachine
        case "壶铃": return .kettlebell
        case "固定器械":
            switch primaryMuscleGroup {
            case "胸": return .pecDeck
            case "肩": return .shoulderPress
            case "大腿": return .legExtension
            case "臀": return .hipAdduction
            case "小腿": return .hackSquat
            case "背": return .tbarRow
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Looks the exercise up in the built-in catalog; custom exercises have
    /// no catalog facet and therefore no icon.
    public static func icon(forExerciseID id: String) -> FCEquipmentIcon? {
        guard let facet = PlaceholderExerciseCatalogLoader.facet(forExerciseID: id) else {
            return nil
        }
        return icon(equipmentClass: facet.equipmentClass, primaryMuscleGroup: facet.primaryMuscleGroup)
    }
}

/// An equipment icon tinted `action.primary` (§7.1). Decorative: hidden from
/// accessibility because the exercise name next to it carries the meaning.
public struct FCEquipmentIconView: View {
    private let icon: FCEquipmentIcon
    private let size: CGFloat

    public init(_ icon: FCEquipmentIcon, size: CGFloat = 24) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Image(icon.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(FCSemanticColors.actionPrimary)
            .accessibilityHidden(true)
    }
}
