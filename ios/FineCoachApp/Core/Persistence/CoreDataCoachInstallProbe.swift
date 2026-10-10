import CoreData
import Foundation

/// What the install-state resolver needs to know about the Coach store.
public struct CoachInstallSnapshot: Equatable, Sendable {
    public let onboardingCompleted: Bool
    /// Any Coach work data (data-model §4, D-002).
    public let hasWorkData: Bool

    public init(onboardingCompleted: Bool, hasWorkData: Bool) {
        self.onboardingCompleted = onboardingCompleted
        self.hasWorkData = hasWorkData
    }
}

/// Count source injected into `InstallStateResolver`.
public protocol CoachInstallProbe: Sendable {
    func read() async throws -> CoachInstallSnapshot
}

/// Read-only Core Data implementation: one transaction of `count` queries.
public struct CoreDataCoachInstallProbe: CoachInstallProbe {
    private let writer: PersistenceWriter

    public init(writer: PersistenceWriter) {
        self.writer = writer
    }

    public func read() async throws -> CoachInstallSnapshot {
        try await writer.read { context in
            let onboarding = try StudentManagedObjectMapping.onboardingCompleted(in: context)
            return CoachInstallSnapshot(
                onboardingCompleted: onboarding,
                hasWorkData: try Self.hasCoachWorkData(in: context)
            )
        }
    }

    /// Students (including archived), custom exercises, sessions of any status, templates,
    /// appointments, recurrence series, course packages, credit adjustments, body
    /// measurements and custom body metrics. The built-in exercise seed, preferences,
    /// built-in metric rows and the onboarding marker never count.
    private static func hasCoachWorkData(in context: NSManagedObjectContext) throws -> Bool {
        let queries: [(String, NSPredicate?)] = [
            (StudentManagedObjectMapping.entityName, nil),
            (
                ExerciseManagedObjectMapping.catalogEntityName,
                NSPredicate(format: "kind == %@", ExerciseKind.custom.rawValue)
            ),
            (StudentManagedObjectMapping.sessionEntityName, nil),
            (TemplateManagedObjectMapping.templateEntityName, nil),
            (AppointmentManagedObjectMapping.entityName, nil),
            (RecurrenceSeriesManagedObjectMapping.entityName, nil),
            (CoursePackageManagedObjectMapping.entityName, nil),
            (CoursePackageManagedObjectMapping.adjustmentEntityName, nil),
            (BodyMetricManagedObjectMapping.measurementEntityName, nil),
            (
                BodyMetricManagedObjectMapping.metricEntityName,
                NSPredicate(format: "kind == %@", BodyMetricKind.custom.rawValue)
            ),
        ]
        for (entityName, predicate) in queries {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = predicate
            if try context.count(for: request) > 0 {
                return true
            }
        }
        return false
    }
}
