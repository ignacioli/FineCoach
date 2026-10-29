import ActivityKit
import Foundation

public struct SessionActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let exerciseName: String
        public let completedSetCount: Int
        public let restEndsAt: Date?

        public init(exerciseName: String, completedSetCount: Int, restEndsAt: Date?) {
            self.exerciseName = exerciseName
            self.completedSetCount = completedSetCount
            self.restEndsAt = restEndsAt
        }

        // Keep the allowlisted key present even when there is no rest.
        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(exerciseName, forKey: .exerciseName)
            try values.encode(completedSetCount, forKey: .completedSetCount)
            try values.encode(restEndsAt, forKey: .restEndsAt)
        }
    }

    public let sessionID: String

    public init(sessionID: String) { self.sessionID = sessionID }
}

/// Presentation depends only on the allowlisted content and an explicit instant.
public enum SessionActivityContent {
    public static func title(_ content: SessionActivityAttributes.ContentState) -> String {
        content.exerciseName.isEmpty ? String(localized: "activity.session.generic") : content.exerciseName
    }

    public static func isOverdue(_ content: SessionActivityAttributes.ContentState, now: Date) -> Bool {
        content.restEndsAt.map { $0 <= now } ?? false
    }

    public static func secondaryText(_ content: SessionActivityAttributes.ContentState, now: Date) -> String? {
        guard content.completedSetCount > 0 else { return nil }
        let key: String.LocalizationValue
        if content.restEndsAt == nil {
            key = "activity.session.completed"
        } else if isOverdue(content, now: now) {
            key = "activity.session.restEnded"
        } else {
            key = "activity.session.resting"
        }
        return String(format: String(localized: key), content.completedSetCount)
    }

    public static var overdueLabel: String { String(localized: "activity.session.overdue") }

    public static func compactTrailingText(_ content: SessionActivityAttributes.ContentState, now: Date) -> String {
        guard let end = content.restEndsAt else {
            return String(format: String(localized: "activity.session.setCount"), content.completedSetCount)
        }
        let overdue = end <= now
        let seconds = overdue ? Int(floor(now.timeIntervalSince(end))) : Int(ceil(end.timeIntervalSince(now)))
        return (overdue ? "+" : "") + String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    public static func url(sessionID: String) -> URL? {
        guard let id = UUID(uuidString: sessionID) else { return nil }
        return URL(string: "finecoach://session/\(id.uuidString.lowercased())")
    }
}
