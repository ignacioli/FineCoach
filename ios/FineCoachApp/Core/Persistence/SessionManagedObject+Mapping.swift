import CoreData
import Foundation

enum SessionManagedObjectMapping {
    static let sessionEntityName = "SessionMO"
    static let exerciseEntityName = "SessionExerciseMO"
    static let setEntityName = "TrainingSetMO"
    static let pointerEntityName = "ActiveSessionPointerMO"
    /// V4 column read/written only by `CoreDataSessionRepository`'s
    /// credit-settlement-note methods, never by `apply`/`makeSession`.
    static let creditSettlementNoteKey = "creditSettlementNote"

    static func apply(_ session: Session, to object: NSManagedObject) {
        object.setValue(session.id.rawValue, forKey: "id")
        object.setValue(session.studentID.rawValue, forKey: "studentID")
        object.setValue(session.state.rawValue, forKey: "state")
        object.setValue(session.startedAtUTC, forKey: "startedAtUTC")
        object.setValue(session.lastCheckpointUTC, forKey: "lastCheckpointUTC")
        object.setValue(NSDecimalNumber(decimal: session.elapsedSeconds.decimal), forKey: "elapsedSeconds")
        object.setValue(session.interruptionStartedAtUTC, forKey: "interruptionStartedAtUTC")
        object.setValue(session.durationNeedsReview, forKey: "durationNeedsReview")
        object.setValue(
            session.coachAdjustedDurationSeconds.map { NSDecimalNumber(decimal: $0.decimal) },
            forKey: "coachAdjustedDurationSeconds"
        )
        object.setValue(BodyPartCoding.mask(session.trainingFocus), forKey: "trainingFocusMask")
        object.setValue(session.studentFacingSummary?.value, forKey: "studentFacingSummary")
        object.setValue(session.privateCoachNote?.value, forKey: "privateCoachNote")
        object.setValue(Int64(session.revision), forKey: "revision")
        object.setValue(session.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(session.updatedAtUTC, forKey: "updatedAtUTC")
        object.setValue(session.completedAtUTC, forKey: "completedAtUTC")
    }

    static func apply(_ exercise: SessionExercise, to object: NSManagedObject) {
        object.setValue(exercise.id.rawValue, forKey: "id")
        object.setValue(exercise.sessionID.rawValue, forKey: "sessionID")
        object.setValue(Int32(exercise.orderIndex), forKey: "orderIndex")
        object.setValue(exercise.sourceKind.rawValue, forKey: "sourceKind")
        object.setValue(exercise.sourceID?.rawValue, forKey: "sourceID")
        object.setValue(exercise.displayNameSnapshot.value, forKey: "displayNameSnapshot")
        object.setValue(exercise.recordModeSnapshot.rawValue, forKey: "recordModeSnapshot")
        object.setValue(exercise.actionPrivateNote?.value, forKey: "actionPrivateNote")
        object.setValue(exercise.sectionID?.rawValue, forKey: "sectionID")
    }

    static func apply(_ trainingSet: TrainingSet, to object: NSManagedObject) {
        object.setValue(trainingSet.id.rawValue, forKey: "id")
        object.setValue(trainingSet.sessionExerciseID.rawValue, forKey: "sessionExerciseID")
        object.setValue(Int32(trainingSet.orderIndex), forKey: "orderIndex")
        object.setValue(trainingSet.state.rawValue, forKey: "state")
        object.setValue(trainingSet.recordMode.rawValue, forKey: "recordMode")
        object.setValue(storeDecimal(trainingSet.weightValue), forKey: "weightValue")
        object.setValue(storeDecimal(trainingSet.repetitionCount), forKey: "repetitionCount")
        object.setValue(storeDecimal(trainingSet.durationSeconds), forKey: "durationSeconds")
        object.setValue(trainingSet.unit.rawValue, forKey: "unit")
        object.setValue(trainingSet.side.rawValue, forKey: "side")
        object.setValue(storeDecimal(trainingSet.leftValue), forKey: "leftValue")
        object.setValue(storeDecimal(trainingSet.rightValue), forKey: "rightValue")
        object.setValue(storeDecimal(trainingSet.distanceValue), forKey: "distanceValue")
        object.setValue(storeDecimal(trainingSet.speedValue), forKey: "speedValue")
        object.setValue(storeDecimal(trainingSet.resistanceValue), forKey: "resistanceValue")
        object.setValue(trainingSet.createdAtUTC, forKey: "createdAtUTC")
        object.setValue(trainingSet.updatedAtUTC, forKey: "updatedAtUTC")
        object.setValue(trainingSet.completedAtUTC, forKey: "completedAtUTC")
    }

    static func makeSession(from object: NSManagedObject, exercises: [SessionExercise]) throws -> Session {
        guard let rawID = object.value(forKey: "id") as? UUID else {
            throw DomainError.incompatibleInput
        }
        guard let studentID = object.value(forKey: "studentID") as? UUID else {
            throw DomainError.incompatibleInput
        }
        guard let stateRaw = object.value(forKey: "state") as? String,
            let state = SessionState(rawValue: stateRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let startedAtUTC = object.value(forKey: "startedAtUTC") as? Date,
            let lastCheckpointUTC = object.value(forKey: "lastCheckpointUTC") as? Date,
            let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }
        let revision = object.value(forKey: "revision") as? Int64 ?? 0
        let durationNeedsReview = object.value(forKey: "durationNeedsReview") as? Bool ?? false
        return try Session(
            id: StableUUID(rawID),
            studentID: StableUUID(studentID),
            state: state,
            startedAtUTC: startedAtUTC,
            lastCheckpointUTC: lastCheckpointUTC,
            elapsedSeconds: try requireDecimal(object.value(forKey: "elapsedSeconds")),
            interruptionStartedAtUTC: object.value(forKey: "interruptionStartedAtUTC") as? Date,
            durationNeedsReview: durationNeedsReview,
            coachAdjustedDurationSeconds: try optionalDecimal(
                object.value(forKey: "coachAdjustedDurationSeconds")
            ),
            trainingFocus: BodyPartCoding.parts(fromMask: object.value(forKey: "trainingFocusMask") as? Int32 ?? 0),
            studentFacingSummary: try optionalText(object.value(forKey: "studentFacingSummary") as? String),
            privateCoachNote: try optionalText(object.value(forKey: "privateCoachNote") as? String),
            revision: UInt64(max(0, revision)),
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC,
            completedAtUTC: object.value(forKey: "completedAtUTC") as? Date,
            exercises: exercises
        )
    }

    static func makeExercise(from object: NSManagedObject, sets: [TrainingSet]) throws -> SessionExercise {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let sessionID = object.value(forKey: "sessionID") as? UUID
        else {
            throw DomainError.incompatibleInput
        }
        guard let sourceKindRaw = object.value(forKey: "sourceKind") as? String,
            let sourceKind = ExerciseSourceKind(rawValue: sourceKindRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let displayName = object.value(forKey: "displayNameSnapshot") as? String else {
            throw DomainError.incompatibleInput
        }
        guard let modeRaw = object.value(forKey: "recordModeSnapshot") as? String,
            let recordMode = RecordMode(rawValue: modeRaw)
        else {
            throw DomainError.incompatibleInput
        }
        let orderIndex = UInt32(truncatingIfNeeded: object.value(forKey: "orderIndex") as? Int32 ?? 0)
        let sourceID: StableExerciseID?
        if let rawSourceID = object.value(forKey: "sourceID") as? String {
            sourceID = try StableExerciseID(rawSourceID)
        } else {
            sourceID = nil
        }
        let sectionID = (object.value(forKey: "sectionID") as? UUID).map { StableUUID($0) }
        return try SessionExercise(
            id: StableUUID(rawID),
            sessionID: StableUUID(sessionID),
            orderIndex: orderIndex,
            sourceKind: sourceKind,
            sourceID: sourceID,
            displayNameSnapshot: NormalizedName(displayName),
            recordModeSnapshot: recordMode,
            actionPrivateNote: try optionalText(object.value(forKey: "actionPrivateNote") as? String),
            sectionID: sectionID,
            sets: sets
        )
    }

    static func makeTrainingSet(from object: NSManagedObject) throws -> TrainingSet {
        guard let rawID = object.value(forKey: "id") as? UUID,
            let sessionExerciseID = object.value(forKey: "sessionExerciseID") as? UUID
        else {
            throw DomainError.incompatibleInput
        }
        guard let stateRaw = object.value(forKey: "state") as? String,
            let state = SetRecordingState(rawValue: stateRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let modeRaw = object.value(forKey: "recordMode") as? String,
            let recordMode = RecordMode(rawValue: modeRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let unitRaw = object.value(forKey: "unit") as? String,
            let unit = MeasurementUnit(rawValue: unitRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let sideRaw = object.value(forKey: "side") as? String,
            let side = SetSide(rawValue: sideRaw)
        else {
            throw DomainError.incompatibleInput
        }
        guard let createdAtUTC = object.value(forKey: "createdAtUTC") as? Date,
            let updatedAtUTC = object.value(forKey: "updatedAtUTC") as? Date
        else {
            throw DomainError.incompatibleInput
        }
        let orderIndex = UInt32(truncatingIfNeeded: object.value(forKey: "orderIndex") as? Int32 ?? 0)
        return try TrainingSet(
            id: StableUUID(rawID),
            sessionExerciseID: StableUUID(sessionExerciseID),
            orderIndex: orderIndex,
            state: state,
            recordMode: recordMode,
            weightValue: try optionalDecimal(object.value(forKey: "weightValue")),
            repetitionCount: try optionalDecimal(object.value(forKey: "repetitionCount")),
            durationSeconds: try optionalDecimal(object.value(forKey: "durationSeconds")),
            unit: unit,
            side: side,
            leftValue: try optionalDecimal(object.value(forKey: "leftValue")),
            rightValue: try optionalDecimal(object.value(forKey: "rightValue")),
            distanceValue: try optionalDecimal(object.value(forKey: "distanceValue")),
            speedValue: try optionalDecimal(object.value(forKey: "speedValue")),
            resistanceValue: try optionalDecimal(object.value(forKey: "resistanceValue")),
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC,
            completedAtUTC: object.value(forKey: "completedAtUTC") as? Date
        )
    }

    static func fetchSession(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireSession(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let object = try fetchSession(id: id, in: context) else {
            throw DomainError.notFound
        }
        return object
    }

    static func inProgressSession(in context: NSManagedObjectContext) throws -> NSManagedObject? {
        if let pointed = try pointedSession(in: context) {
            return pointed
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: sessionEntityName)
        request.predicate = NSPredicate(format: "state == %@", SessionState.inProgress.rawValue)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func loadAggregate(from sessionObject: NSManagedObject, in context: NSManagedObjectContext)
        throws -> Session
    {
        guard let sessionID = sessionObject.value(forKey: "id") as? UUID else {
            throw DomainError.incompatibleInput
        }
        let exerciseRequest = NSFetchRequest<NSManagedObject>(entityName: exerciseEntityName)
        exerciseRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID as CVarArg)
        exerciseRequest.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        let exerciseObjects = try context.fetch(exerciseRequest)
        var exercises: [SessionExercise] = []
        exercises.reserveCapacity(exerciseObjects.count)
        for exerciseObject in exerciseObjects {
            guard let exerciseID = exerciseObject.value(forKey: "id") as? UUID else {
                throw DomainError.incompatibleInput
            }
            let setRequest = NSFetchRequest<NSManagedObject>(entityName: setEntityName)
            setRequest.predicate = NSPredicate(format: "sessionExerciseID == %@", exerciseID as CVarArg)
            setRequest.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
            let sets = try context.fetch(setRequest).map { try makeTrainingSet(from: $0) }
            exercises.append(try makeExercise(from: exerciseObject, sets: sets))
        }
        return try makeSession(from: sessionObject, exercises: exercises)
    }

    static func upsertAggregate(_ session: Session, in context: NSManagedObjectContext) throws -> Session {
        let student = try StudentManagedObjectMapping.requireStudent(
            id: session.studentID.rawValue,
            in: context
        )
        let sessionObject =
            try fetchSession(id: session.id.rawValue, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: sessionEntityName, into: context)
        apply(session, to: sessionObject)
        sessionObject.setValue(student, forKey: "student")

        try syncExercises(session, sessionObject: sessionObject, in: context)
        try syncPointer(for: session, in: context)
        return try loadAggregate(from: sessionObject, in: context)
    }

    static func pointedSession(in context: NSManagedObjectContext) throws -> NSManagedObject? {
        guard let pointer = try fetchPointer(in: context),
            let sessionID = pointer.value(forKey: "sessionID") as? UUID
        else {
            return nil
        }
        return try fetchSession(id: sessionID, in: context)
    }

    static func fetchPointer(in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: pointerEntityName)
        request.predicate = NSPredicate(format: "singletonKey == %@", ActiveSessionPointerKey.singleton)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func syncExercises(
        _ session: Session,
        sessionObject: NSManagedObject,
        in context: NSManagedObjectContext
    ) throws {
        let exerciseRequest = NSFetchRequest<NSManagedObject>(entityName: exerciseEntityName)
        exerciseRequest.predicate = NSPredicate(format: "sessionID == %@", session.id.rawValue as CVarArg)
        let existingExercises = try context.fetch(exerciseRequest)
        let desiredExerciseIDs = Set(session.exercises.map(\.id.rawValue))
        for object in existingExercises {
            guard let existingID = object.value(forKey: "id") as? UUID, desiredExerciseIDs.contains(existingID)
            else {
                context.delete(object)
                continue
            }
        }

        for exercise in session.exercises {
            let exerciseObject =
                try fetchObject(entityName: exerciseEntityName, id: exercise.id.rawValue, in: context)
                ?? NSEntityDescription.insertNewObject(forEntityName: exerciseEntityName, into: context)
            apply(exercise, to: exerciseObject)
            exerciseObject.setValue(sessionObject, forKey: "session")
            try syncSets(exercise, exerciseObject: exerciseObject, in: context)
        }
    }

    private static func syncSets(
        _ exercise: SessionExercise,
        exerciseObject: NSManagedObject,
        in context: NSManagedObjectContext
    ) throws {
        let setRequest = NSFetchRequest<NSManagedObject>(entityName: setEntityName)
        setRequest.predicate = NSPredicate(format: "sessionExerciseID == %@", exercise.id.rawValue as CVarArg)
        let existingSets = try context.fetch(setRequest)
        let desiredSetIDs = Set(exercise.sets.map(\.id.rawValue))
        for object in existingSets {
            guard let existingID = object.value(forKey: "id") as? UUID, desiredSetIDs.contains(existingID) else {
                context.delete(object)
                continue
            }
        }

        for trainingSet in exercise.sets {
            let setObject =
                try fetchObject(entityName: setEntityName, id: trainingSet.id.rawValue, in: context)
                ?? NSEntityDescription.insertNewObject(forEntityName: setEntityName, into: context)
            apply(trainingSet, to: setObject)
            setObject.setValue(exerciseObject, forKey: "sessionExercise")
        }
    }

    private static func syncPointer(for session: Session, in context: NSManagedObjectContext) throws {
        let pointer = try fetchPointer(in: context)
        if session.state == .inProgress {
            let object =
                pointer
                ?? NSEntityDescription.insertNewObject(forEntityName: pointerEntityName, into: context)
            object.setValue(ActiveSessionPointerKey.singleton, forKey: "singletonKey")
            object.setValue(session.id.rawValue, forKey: "sessionID")
        } else if let pointer {
            context.delete(pointer)
        }
    }

    private static func fetchObject(
        entityName: String,
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func storeDecimal(_ value: DecimalValue?) -> NSDecimalNumber? {
        value.map { NSDecimalNumber(decimal: $0.decimal) }
    }

    private static func optionalDecimal(_ value: Any?) throws -> DecimalValue? {
        guard let value else {
            return nil
        }
        return try requireDecimal(value)
    }

    private static func requireDecimal(_ value: Any?) throws -> DecimalValue {
        let number: NSDecimalNumber
        if let decimal = value as? Decimal {
            number = NSDecimalNumber(decimal: decimal)
        } else if let decimalNumber = value as? NSDecimalNumber {
            number = decimalNumber
        } else {
            throw DomainError.incompatibleInput
        }
        guard number != .notANumber else {
            throw DomainError.incompatibleInput
        }
        return try DecimalValue(number.stringValue)
    }

    private static func optionalText(_ rawValue: String?) throws -> ValidatedText? {
        try Student.optionalText(rawValue ?? "")
    }
}
