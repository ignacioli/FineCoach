import Foundation

/// The raw fields needed to render one recorded Set as a human-readable
/// string. Exists so `TrainingSet.displaySummary` (in-progress/History UI)
/// and `ShareReportPolicy.setLine` (Share Report) -- two different types
/// with overlapping but non-identical field sets -- can share exactly one
/// formatting implementation instead of drifting into independent copies.
public protocol TrainingSetDisplayValues {
    var recordMode: RecordMode { get }
    var weightValue: DecimalValue? { get }
    var repetitionCount: DecimalValue? { get }
    var durationSeconds: DecimalValue? { get }
    var side: SetSide { get }
    var leftValue: DecimalValue? { get }
    var rightValue: DecimalValue? { get }
    var distanceValue: DecimalValue? { get }
    var speedValue: DecimalValue? { get }
    var resistanceValue: DecimalValue? { get }
}

/// Single source of truth for rendering one Set's recorded values as a
/// human-readable string. `.duration` and `.cardio` both show
/// `durationSeconds` via `DurationTextParser.formatForEditing` (e.g.
/// "5分30秒") -- gym cardio never runs past an hour, so minutes+seconds is
/// precise enough and matches the same text format the coach types in.
/// Storage itself always stays in seconds.
public enum TrainingSetDisplayFormatting {
    /// - Parameter weightUnit: the unit label printed after weights. Defaults to "kg", what every
    ///   Coach-side caller shows; the archive viewer passes "lb" when the local display setting
    ///   asks for it (the values are converted by the caller, not here).
    /// A number and its unit per design-system README §13: one space before
    /// the unit (N1/N3), except "%" which follows the number directly (N2).
    public static func quantity(_ number: String, unit: String) -> String {
        unit == "%" ? "\(number)%" : "\(number) \(unit)"
    }

    public static func summary(for values: TrainingSetDisplayValues, weightUnit: String = "kg") -> String {
        switch values.recordMode {
        case .weightReps:
            let repsText = values.repetitionCount?.canonicalString ?? "-"
            switch values.side {
            case .none:
                return "\(values.weightValue?.canonicalString ?? "-") \(weightUnit) × \(repsText)"
            case .left:
                return "左 \((values.leftValue ?? values.weightValue)?.canonicalString ?? "-") \(weightUnit) × \(repsText)"
            case .right:
                return "右 \((values.rightValue ?? values.weightValue)?.canonicalString ?? "-") \(weightUnit) × \(repsText)"
            case .bilateral:
                if let leftValue = values.leftValue, let rightValue = values.rightValue {
                    return "左 \(leftValue.canonicalString) \(weightUnit) / 右 \(rightValue.canonicalString) \(weightUnit) × \(repsText)"
                }
                return "\(values.weightValue?.canonicalString ?? "-") \(weightUnit)（双侧） × \(repsText)"
            }
        case .reps:
            return "\(values.repetitionCount?.canonicalString ?? "-") 次"
        case .duration:
            guard let durationSeconds = values.durationSeconds else { return "-" }
            return DurationTextParser.formatForEditing(secondsText: durationSeconds.canonicalString)
        case .cardio:
            var parts: [String] = []
            parts.append(
                values.durationSeconds.map { DurationTextParser.formatForEditing(secondsText: $0.canonicalString) }
                    ?? "-"
            )
            parts.append("\(values.distanceValue?.canonicalString ?? "-") km")
            if let speedValue = values.speedValue {
                parts.append("速度 \(speedValue.canonicalString)")
            }
            if let resistanceValue = values.resistanceValue {
                parts.append("阻力 \(resistanceValue.canonicalString)")
            }
            return parts.joined(separator: " · ")
        }
    }
}

extension TrainingSet: TrainingSetDisplayValues {}
