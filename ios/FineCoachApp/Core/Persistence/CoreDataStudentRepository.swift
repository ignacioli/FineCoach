import CoreData
import Foundation

public struct StudentDeletionImpact: Equatable, Sendable {
    public let displayName: String
    public let completedSessionCount: Int
    public let hasInProgressSession: Bool

    public init(displayName: String, completedSessionCount: Int, hasInProgressSession: Bool) {
        self.displayName = displayName
        self.completedSessionCount = completedSessionCount
        self.hasInProgressSession = hasInProgressSession
    }
}

public struct InProgressTrainingSummary: Equatable, Sendable {
    public let studentID: StableUUID
    public let studentDisplayName: String
    /// For the "已训练 N 分钟" line (01 hero card, 21 in-training bar).
    public let startedAtUTC: Date?
    public let trainingFocus: Set<BodyPart>

    public init(
        studentID: StableUUID,
        studentDisplayName: String,
        startedAtUTC: Date? = nil,
        trainingFocus: Set<BodyPart> = []
    ) {
        self.studentID = studentID
        self.studentDisplayName = studentDisplayName
        self.startedAtUTC = startedAtUTC
        self.trainingFocus = trainingFocus
    }

    /// Whole minutes elapsed since the session started, never negative.
    public func elapsedMinutes(now: Date) -> Int? {
        startedAtUTC.map { max(0, Int(now.timeIntervalSince($0) / 60)) }
    }
}

public struct CoreDataStudentRepository: Sendable {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func create(_ student: Student) async throws -> Student {
        try await writer.transaction { context in
            if try StudentManagedObjectMapping.fetchStudent(id: student.id.rawValue, in: context) != nil {
                throw DomainError.conflict
            }
            let object = NSEntityDescription.insertNewObject(
                forEntityName: StudentManagedObjectMapping.entityName,
                into: context
            )
            StudentManagedObjectMapping.apply(student, to: object)
            return try StudentManagedObjectMapping.makeStudent(from: object)
        }
    }

    public func update(_ student: Student) async throws -> Student {
        try await writer.transaction { context in
            let object = try StudentManagedObjectMapping.requireStudent(id: student.id.rawValue, in: context)
            StudentManagedObjectMapping.apply(student, to: object)
            return try StudentManagedObjectMapping.makeStudent(from: object)
        }
    }

    public func student(id: StableUUID) async throws -> Student {
        try await writer.read { context in
            let object = try StudentManagedObjectMapping.requireStudent(id: id.rawValue, in: context)
            return try StudentManagedObjectMapping.makeStudent(from: object)
        }
    }

    public func searchActive(displayNameQuery: String) async throws -> [Student] {
        try await writer.read { context in
            try Self.fetchStudents(
                lifecycle: .active,
                displayNameQuery: displayNameQuery,
                in: context
            )
        }
    }

    public func listArchived() async throws -> [Student] {
        try await writer.read { context in
            try Self.fetchStudents(lifecycle: .archived, displayNameQuery: "", in: context)
        }
    }

    public func archive(_ student: Student, now: Date) async throws -> Student {
        try await writer.transaction { context in
            let object = try StudentManagedObjectMapping.requireStudent(id: student.id.rawValue, in: context)
            let current = try StudentManagedObjectMapping.makeStudent(from: object)
            let archived = try current.archived(now: now)
            StudentManagedObjectMapping.apply(archived, to: object)
            return try StudentManagedObjectMapping.makeStudent(from: object)
        }
    }

    public func restore(_ student: Student, now: Date) async throws -> Student {
        try await writer.transaction { context in
            let object = try StudentManagedObjectMapping.requireStudent(id: student.id.rawValue, in: context)
            let current = try StudentManagedObjectMapping.makeStudent(from: object)
            let restored = try current.restored(now: now)
            StudentManagedObjectMapping.apply(restored, to: object)
            return try StudentManagedObjectMapping.makeStudent(from: object)
        }
    }

    public func deletionImpact(id: StableUUID) async throws -> StudentDeletionImpact {
        try await writer.read { context in
            let object = try StudentManagedObjectMapping.requireStudent(id: id.rawValue, in: context)
            let student = try StudentManagedObjectMapping.makeStudent(from: object)
            let hasInProgress = try StudentManagedObjectMapping.hasInProgressSession(
                studentID: id.rawValue,
                in: context
            )
            let sessionCount = try StudentManagedObjectMapping.sessionCount(studentID: id.rawValue, in: context)
            let completedCount = hasInProgress ? max(0, sessionCount - 1) : sessionCount
            return StudentDeletionImpact(
                displayName: student.displayName.value,
                completedSessionCount: completedCount,
                hasInProgressSession: hasInProgress
            )
        }
    }

    public func delete(id: StableUUID, confirmedDisplayName: String) async throws {
        try await writer.transaction { context in
            let object = try StudentManagedObjectMapping.requireStudent(id: id.rawValue, in: context)
            let student = try StudentManagedObjectMapping.makeStudent(from: object)
            let hasInProgress = try StudentManagedObjectMapping.hasInProgressSession(
                studentID: id.rawValue,
                in: context
            )
            try StudentDeletionPolicy.ensureCanDelete(hasInProgressSession: hasInProgress)
            try StudentDeletionPolicy.confirmDisplayName(
                expected: student.displayName,
                typed: confirmedDisplayName
            )
            context.delete(object)
        }
    }

    public func inProgressTraining() async throws -> InProgressTrainingSummary? {
        try await writer.read { context in
            guard let session = try StudentManagedObjectMapping.inProgressSession(in: context) else {
                return nil
            }
            guard let studentID = session.value(forKey: "studentID") as? UUID else {
                throw DomainError.incompatibleInput
            }
            let object = try StudentManagedObjectMapping.requireStudent(id: studentID, in: context)
            let student = try StudentManagedObjectMapping.makeStudent(from: object)
            return InProgressTrainingSummary(
                studentID: StableUUID(studentID),
                studentDisplayName: student.displayName.value,
                startedAtUTC: session.value(forKey: "startedAtUTC") as? Date,
                trainingFocus: BodyPartCoding.parts(fromMask: session.value(forKey: "trainingFocusMask") as? Int32 ?? 0)
            )
        }
    }

    public func isOnboardingCompleted() async throws -> Bool {
        try await writer.read { context in
            try StudentManagedObjectMapping.onboardingCompleted(in: context)
        }
    }

    public func markOnboardingCompleted() async throws {
        try await writer.transaction { context in
            try StudentManagedObjectMapping.setOnboardingCompleted(in: context)
        }
    }

    #if DEBUG
        public func insertInProgressSessionForTesting(
            studentID: StableUUID,
            sessionID: UUID,
            now: Date
        ) async throws {
            try await writer.transaction { context in
                try StudentManagedObjectMapping.insertInProgressSession(
                    studentID: studentID.rawValue,
                    sessionID: sessionID,
                    now: now,
                    into: context
                )
            }
        }

        public func insertCompletedSessionForTesting(
            studentID: StableUUID,
            sessionID: UUID,
            now: Date
        ) async throws {
            try await writer.transaction { context in
                try StudentManagedObjectMapping.insertCompletedSession(
                    studentID: studentID.rawValue,
                    sessionID: sessionID,
                    now: now,
                    into: context
                )
            }
        }
    #endif

    private static func fetchStudents(
        lifecycle: StudentLifecycle,
        displayNameQuery: String,
        in context: NSManagedObjectContext
    ) throws -> [Student] {
        let request = NSFetchRequest<NSManagedObject>(entityName: StudentManagedObjectMapping.entityName)
        var predicates = [NSPredicate(format: "lifecycle == %@", lifecycle.rawValue)]
        let query =
            displayNameQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        if !query.isEmpty {
            predicates.append(NSPredicate(format: "displayName CONTAINS[cd] %@", query))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(key: "displayName", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]
        return try context.fetch(request).map { try StudentManagedObjectMapping.makeStudent(from: $0) }
    }
}
