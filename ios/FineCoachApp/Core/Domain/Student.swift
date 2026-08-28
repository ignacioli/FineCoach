import Foundation

public enum StudentSex: String, Codable, Sendable, CaseIterable {
    case male
    case female
    case other
    case undisclosed
}

public enum StudentLifecycle: String, Codable, Sendable {
    case active
    case archived
}

public struct StudentDraft: Equatable, Sendable {
    public var displayName: String
    public var sex: StudentSex?
    public var trainingGoal: String
    public var injuryNotes: String
    public var privateCoachNote: String
    public var phone: String
    public var wechatID: String

    public init(
        displayName: String = "",
        sex: StudentSex? = nil,
        trainingGoal: String = "",
        injuryNotes: String = "",
        privateCoachNote: String = "",
        phone: String = "",
        wechatID: String = ""
    ) {
        self.displayName = displayName
        self.sex = sex
        self.trainingGoal = trainingGoal
        self.injuryNotes = injuryNotes
        self.privateCoachNote = privateCoachNote
        self.phone = phone
        self.wechatID = wechatID
    }

    public func makeStudent(id: StableUUID, now: Date) throws -> Student {
        try Student(
            id: id,
            draft: self,
            lifecycle: .active,
            createdAtUTC: now,
            updatedAtUTC: now
        )
    }
}

public struct Student: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let displayName: NormalizedName
    public let sex: StudentSex
    public let trainingGoal: ValidatedText?
    public let injuryNotes: ValidatedText?
    public let privateCoachNote: ValidatedText?
    public let phone: ValidatedText?
    public let wechatID: ValidatedText?
    public let lifecycle: StudentLifecycle
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    public init(
        id: StableUUID,
        displayName: NormalizedName,
        sex: StudentSex,
        trainingGoal: ValidatedText?,
        injuryNotes: ValidatedText?,
        privateCoachNote: ValidatedText?,
        phone: ValidatedText?,
        wechatID: ValidatedText?,
        lifecycle: StudentLifecycle,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.sex = sex
        self.trainingGoal = trainingGoal
        self.injuryNotes = injuryNotes
        self.privateCoachNote = privateCoachNote
        self.phone = phone
        self.wechatID = wechatID
        self.lifecycle = lifecycle
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }

    public init(
        id: StableUUID,
        draft: StudentDraft,
        lifecycle: StudentLifecycle,
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
        guard let sex = draft.sex else {
            throw DomainError.invalidState
        }
        self.id = id
        self.displayName = try NormalizedName(draft.displayName)
        self.sex = sex
        self.trainingGoal = try Self.optionalText(draft.trainingGoal)
        self.injuryNotes = try Self.optionalText(draft.injuryNotes)
        self.privateCoachNote = try Self.optionalText(draft.privateCoachNote)
        self.phone = try Self.optionalText(draft.phone)
        self.wechatID = try Self.optionalText(draft.wechatID)
        self.lifecycle = lifecycle
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }

    public var draft: StudentDraft {
        StudentDraft(
            displayName: displayName.value,
            sex: sex,
            trainingGoal: trainingGoal?.value ?? "",
            injuryNotes: injuryNotes?.value ?? "",
            privateCoachNote: privateCoachNote?.value ?? "",
            phone: phone?.value ?? "",
            wechatID: wechatID?.value ?? ""
        )
    }

    public func updating(from draft: StudentDraft, now: Date) throws -> Student {
        try Student(
            id: id,
            draft: draft,
            lifecycle: lifecycle,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }

    public func archived(now: Date) throws -> Student {
        guard lifecycle == .active else {
            throw DomainError.invalidState
        }
        return replacing(lifecycle: .archived, updatedAtUTC: now)
    }

    public func restored(now: Date) throws -> Student {
        guard lifecycle == .archived else {
            throw DomainError.invalidState
        }
        return replacing(lifecycle: .active, updatedAtUTC: now)
    }

    public func canStartSession() -> Bool {
        lifecycle == .active
    }

    private func replacing(lifecycle: StudentLifecycle, updatedAtUTC: Date) -> Student {
        Student(
            id: id,
            displayName: displayName,
            sex: sex,
            trainingGoal: trainingGoal,
            injuryNotes: injuryNotes,
            privateCoachNote: privateCoachNote,
            phone: phone,
            wechatID: wechatID,
            lifecycle: lifecycle,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC
        )
    }

    public static func optionalText(_ rawValue: String) throws -> ValidatedText? {
        let canonical =
            rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        if canonical.isEmpty {
            return nil
        }
        return try ValidatedText(rawValue)
    }
}

public enum StudentDeletionPolicy: Sendable {
    public static func ensureCanDelete(hasInProgressSession: Bool) throws {
        if hasInProgressSession {
            throw DomainError.invalidState
        }
    }

    public static func confirmDisplayName(expected: NormalizedName, typed: String) throws {
        let confirmed: NormalizedName
        do {
            confirmed = try NormalizedName(typed)
        } catch {
            throw DomainError.invalidState
        }
        guard confirmed == expected else {
            throw DomainError.invalidState
        }
    }
}
