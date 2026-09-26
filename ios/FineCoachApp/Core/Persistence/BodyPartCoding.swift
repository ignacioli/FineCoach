import Foundation

/// Bitmask encode/decode for `Set<BodyPart>` Core Data attributes (data-model
/// §2.0: "编码方式可仿照 RecurrenceSeries.weekdaysMask 的位掩码"). Bit position is
/// `BodyPart.allCases`' declaration order, so it is stable across saves as
/// long as that case order/list is never reordered or reused for a different
/// meaning -- shared by `SessionMO.trainingFocusMask`,
/// `TrainingTemplateMO.trainingFocusMask`, and `AppointmentMO.trainingFocusMask`.
enum BodyPartCoding {
    static func mask(_ parts: Set<BodyPart>) -> Int32 {
        BodyPart.allCases.enumerated().reduce(into: Int32(0)) { mask, entry in
            let (index, part) = entry
            if parts.contains(part) {
                mask |= Int32(1 << index)
            }
        }
    }

    static func parts(fromMask mask: Int32) -> Set<BodyPart> {
        Set(
            BodyPart.allCases.enumerated()
                .filter { index, _ in mask & Int32(1 << index) != 0 }
                .map(\.element)
        )
    }
}
