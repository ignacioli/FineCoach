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
    public static func summary(for values: TrainingSetDisplayValues) -> String {
        switch values.recordMode {
        case .weightReps:
            let repsText = values.repetitionCount?.canonicalString ?? "-"
            switch values.side {
            case .none:
                return "\(values.weightValue?.canonicalString ?? "-")kg × \(repsText)次"
            case .left:
                return "左 \((values.leftValue ?? values.weightValue)?.canonicalString ?? "-")kg × \(repsText)次"
            case .right:
                return "右 \((values.rightValue ?? values.weightValue)?.canonicalString ?? "-")kg × \(repsText)次"
            case .bilateral:
                if let leftValue = values.leftValue, let rightValue = values.rightValue {
                    return "左 \(leftValue.canonicalString)kg / 右 \(rightValue.canonicalString)kg × \(repsText)次"
                }
                return "\(values.weightValue?.canonicalString ?? "-")kg（双侧） × \(repsText)次"
            }
        case .reps:
            return "\(values.repetitionCount?.canonicalString ?? "-")次"
        case .duration:
            guard let durationSeconds = values.durationSeconds else { return "-" }
            return DurationTextParser.formatForEditing(secondsText: durationSeconds.canonicalString)
        case .cardio:
            var parts: [String] = []
            parts.append(
                values.durationSeconds.map { DurationTextParser.formatForEditing(secondsText: $0.canonicalString) }
                    ?? "-"
            )
            parts.append("\(values.distanceValue?.canonicalString ?? "-")km")
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
