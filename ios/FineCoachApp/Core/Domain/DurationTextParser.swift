import Foundation

/// Parses coach-entered duration text for the `.duration` RecordMode
/// (isometric holds like planks, and free-standing timed activities like
/// running when no distance is tracked) into canonical whole seconds for
/// storage, and formats a stored seconds value back into the same style of
/// text for re-editing.
///
/// Supported input formats (whitespace around the unit markers is ignored):
/// - Full: "5分30秒" / "5m30s"
/// - Minutes only: "5分" / "5m"
/// - Seconds only: "30秒" / "30s"
/// - Bare number: "30" (interpreted as seconds; preserves the original
///   raw-seconds behavior and decimal input for backward compatibility)
///
/// Anything else is not recognized and returns nil so the caller can pass
/// the original text through to existing validation, which will reject it
/// with the standard invalid-number error.
public enum DurationTextParser {
    // Full-format patterns are intentionally two separate,
    // language-consistent regexes ("5分30秒" or "5m30s") rather than one
    // pattern with independent character classes per marker -- the latter
    // would silently accept a mixed "5分30s", which is outside the two
    // formats this parser is scoped to support.
    private static let fullChinesePattern = try! NSRegularExpression(
        pattern: "^(\\d+)\\s*分\\s*(\\d+)\\s*秒$"
    )
    private static let fullLatinPattern = try! NSRegularExpression(
        pattern: "^(\\d+)\\s*[mM]\\s*(\\d+)\\s*[sS]$"
    )
    private static let minutesOnlyPattern = try! NSRegularExpression(
        pattern: "^(\\d+)\\s*[分mM]$"
    )
    private static let secondsOnlyPattern = try! NSRegularExpression(
        pattern: "^(\\d+)\\s*[秒sS]$"
    )

    public static func parseSeconds(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let (minutes, seconds) = firstMatch(fullChinesePattern, in: trimmed, groups: 2) {
            return String(minutes * 60 + seconds)
        }
        if let (minutes, seconds) = firstMatch(fullLatinPattern, in: trimmed, groups: 2) {
            return String(minutes * 60 + seconds)
        }
        if let (minutes, _) = firstMatch(minutesOnlyPattern, in: trimmed, groups: 1) {
            return String(minutes * 60)
        }
        if let (seconds, _) = firstMatch(secondsOnlyPattern, in: trimmed, groups: 1) {
            return String(seconds)
        }
        if let value = try? DecimalValue(trimmed) {
            return value.canonicalString
        }
        return nil
    }

    public static func formatForEditing(secondsText: String?) -> String {
        guard let secondsText, let value = try? DecimalValue(secondsText) else { return "" }
        let totalSeconds = NSDecimalNumber(decimal: value.decimal).intValue
        guard totalSeconds >= 0 else { return secondsText }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0, seconds > 0 {
            return "\(minutes)分\(seconds)秒"
        }
        if minutes > 0 {
            return "\(minutes)分"
        }
        return "\(seconds)秒"
    }

    /// Matches `pattern` against the full `text` and returns up to two
    /// captured integer groups (the second is 0 when `groups == 1`).
    /// Returns nil if the pattern doesn't match the entire string or any
    /// captured group isn't a valid non-negative integer.
    private static func firstMatch(
        _ pattern: NSRegularExpression, in text: String, groups: Int
    ) -> (Int, Int)? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = pattern.firstMatch(in: text, range: range), match.range == range else {
            return nil
        }
        guard let first = intValue(match, group: 1, in: text) else { return nil }
        if groups == 1 {
            return (first, 0)
        }
        guard let second = intValue(match, group: 2, in: text) else { return nil }
        return (first, second)
    }

    private static func intValue(_ match: NSTextCheckingResult, group: Int, in text: String) -> Int? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }
}
