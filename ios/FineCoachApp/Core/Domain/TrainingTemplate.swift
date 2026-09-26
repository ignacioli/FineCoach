import Foundation

/// A reusable, cross-Student training template (data-model §2.5, M1B-FR-017).
/// Deliberately has NO Student identity field -- it MUST be reusable across
/// Students, and that is enforced structurally here (there is nowhere to put
/// a `studentID` even if a caller wanted to).
public struct TrainingTemplate: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    /// Required, non-empty (M1B-FR-017). A blank name-only skeleton with no
    /// Exercises yet is still valid -- `name` is the only required field.
    public let name: NormalizedName
    /// M1B-FR-017/D-013: selected/empty body-part set, unified with
    /// Appointment/Session (§2.0); brought into the Session as part of the
    /// deep-value snapshot when this template is applied.
    public let trainingFocus: Set<BodyPart>
    public let createdAtUTC: Date
    public let updatedAtUTC: Date

    public init(
        id: StableUUID,
        name: String,
        trainingFocus: Set<BodyPart> = [],
        createdAtUTC: Date,
        updatedAtUTC: Date
    ) throws {
        self.id = id
        self.name = try NormalizedName(name)
        self.trainingFocus = trainingFocus
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
    }

    public func renamed(_ name: String, now: Date) throws -> TrainingTemplate {
        try TrainingTemplate(
            id: id,
            name: name,
            trainingFocus: trainingFocus,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }

    public func updatingTrainingFocus(_ value: Set<BodyPart>, now: Date) throws -> TrainingTemplate {
        try TrainingTemplate(
            id: id,
            name: name.value,
            trainingFocus: value,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now
        )
    }
}

/// One planned target for a `TemplateExercise` (data-model §2.6): the same
/// value shape as a `TrainingSet`'s recordable fields, but it is NEVER itself
/// a completed group -- it only becomes a real `.pending` `TrainingSet` when
/// the template is applied to a Session (M1B-FR-019). Carries no id, state,
/// or timestamps of its own.
public struct TemplatePlannedSet: Hashable, Codable, Sendable {
    public let recordMode: RecordMode
    public let weightValue: DecimalValue?
    public let repetitionCount: DecimalValue?
    public let durationSeconds: DecimalValue?
    public let unit: MeasurementUnit
    public let side: SetSide
    public let leftValue: DecimalValue?
    public let rightValue: DecimalValue?
    public let distanceValue: DecimalValue?
    public let speedValue: DecimalValue?
    public let resistanceValue: DecimalValue?

    public init(
        recordMode: RecordMode,
        weightValue: DecimalValue? = nil,
        repetitionCount: DecimalValue? = nil,
        durationSeconds: DecimalValue? = nil,
        unit: MeasurementUnit,
        side: SetSide = .none,
        leftValue: DecimalValue? = nil,
        rightValue: DecimalValue? = nil,
        distanceValue: DecimalValue? = nil,
        speedValue: DecimalValue? = nil,
        resistanceValue: DecimalValue? = nil
    ) {
        self.recordMode = recordMode
        self.weightValue = weightValue
        self.repetitionCount = repetitionCount
        self.durationSeconds = durationSeconds
        self.unit = unit
        self.side = side
        self.leftValue = leftValue
        self.rightValue = rightValue
        self.distanceValue = distanceValue
        self.speedValue = speedValue
        self.resistanceValue = resistanceValue
    }

    /// Copies ONLY the planned-value fields of an existing `TrainingSet` --
    /// never its id, state, or timestamps (used by
    /// `TrainingTemplate.snapshotFromSession`, M1B-FR-018).
    public init(copyingValuesFrom set: TrainingSet) {
        self.recordMode = set.recordMode
        self.weightValue = set.weightValue
        self.repetitionCount = set.repetitionCount
        self.durationSeconds = set.durationSeconds
        self.unit = set.unit
        self.side = set.side
        self.leftValue = set.leftValue
        self.rightValue = set.rightValue
        self.distanceValue = set.distanceValue
        self.speedValue = set.speedValue
        self.resistanceValue = set.resistanceValue
    }

    /// Produces a brand-new `.pending` `TrainingSet` from this planned target
    /// (M1B-FR-019: "所有预填 Set MUST 保持待完成"). Fresh id/timestamps every
    /// call -- there is no field here to carry a back-reference to whatever
    /// template this planned set came from.
    public func makePendingSet(id: StableUUID, sessionExerciseID: StableUUID, orderIndex: UInt32, now: Date)
        -> TrainingSet
    {
        TrainingSet(
            id: id,
            sessionExerciseID: sessionExerciseID,
            orderIndex: orderIndex,
            state: .pending,
            recordMode: recordMode,
            weightValue: weightValue,
            repetitionCount: repetitionCount,
            durationSeconds: durationSeconds,
            unit: unit,
            side: side,
            leftValue: leftValue,
            rightValue: rightValue,
            distanceValue: distanceValue,
            speedValue: speedValue,
            resistanceValue: resistanceValue,
            createdAtUTC: now,
            updatedAtUTC: now,
            completedAtUTC: nil
        )
    }
}

/// One planned Exercise slot within a `TrainingTemplate` (data-model §2.6).
/// Deliberately has no `actionPrivateNote` field -- Private per-Exercise
/// notes MUST NOT be copied into a template (M1B-FR-018), and there is
/// nowhere on this type to hold one even by mistake.
public struct TemplateExercise: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let templateID: StableUUID
    /// Optional `SessionSection`(`ownerKind == .template`) this planned
    /// Exercise belongs to; `nil` = unsectioned (data-model §2.6).
    public let sectionID: StableUUID?
    /// Unique within the template's unified order space, shared with
    /// `SessionSection` headers (data-model §2.6/§2.7).
    public let orderIndex: UInt32
    public let sourceKind: ExerciseSourceKind
    public let sourceID: StableExerciseID?
    public let displayNameSnapshot: NormalizedName
    public let recordModeSnapshot: RecordMode
    public let plannedSets: [TemplatePlannedSet]

    public init(
        id: StableUUID,
        templateID: StableUUID,
        sectionID: StableUUID?,
        orderIndex: UInt32,
        sourceKind: ExerciseSourceKind,
        sourceID: StableExerciseID?,
        displayNameSnapshot: NormalizedName,
        recordModeSnapshot: RecordMode,
        plannedSets: [TemplatePlannedSet]
    ) {
        self.id = id
        self.templateID = templateID
        self.sectionID = sectionID
        self.orderIndex = orderIndex
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.displayNameSnapshot = displayNameSnapshot
        self.recordModeSnapshot = recordModeSnapshot
        self.plannedSets = plannedSets
    }

    public func relocating(orderIndex: UInt32, sectionID: StableUUID?) -> TemplateExercise {
        TemplateExercise(
            id: id,
            templateID: templateID,
            sectionID: sectionID,
            orderIndex: orderIndex,
            sourceKind: sourceKind,
            sourceID: sourceID,
            displayNameSnapshot: displayNameSnapshot,
            recordModeSnapshot: recordModeSnapshot,
            plannedSets: plannedSets
        )
    }

    public func replacingPlannedSets(_ plannedSets: [TemplatePlannedSet]) -> TemplateExercise {
        TemplateExercise(
            id: id,
            templateID: templateID,
            sectionID: sectionID,
            orderIndex: orderIndex,
            sourceKind: sourceKind,
            sourceID: sourceID,
            displayNameSnapshot: displayNameSnapshot,
            recordModeSnapshot: recordModeSnapshot,
            plannedSets: plannedSets
        )
    }
}

/// Combined result of applying a `TrainingTemplate` to a Session: the
/// updated `Session` (with new `SessionExercise`/`TrainingSet` appended) and
/// the new `SessionSection` rows it needs alongside it (M1B-FR-019, D-009).
public struct TemplateApplicationResult: Sendable {
    public let session: Session
    public let newSections: [SessionSection]
}

private enum TemplateAxisEntry {
    case section(SessionSection)
    case exercise(TemplateExercise)

    var orderIndex: UInt32 {
        switch self {
        case .section(let section): return section.orderIndex
        case .exercise(let exercise): return exercise.orderIndex
        }
    }
}

extension TrainingTemplate {
    /// Builds the ordered `TemplateExercise` (+ `TemplatePlannedSet`) and
    /// `SessionSection` snapshot to save as a NEW template from an existing
    /// Session (M1B-FR-018). Reads ONLY the ordered Exercise list and each
    /// Exercise's planned Set shape -- this function never reads
    /// `session.studentID`, `session.privateCoachNote`,
    /// `session.studentFacingSummary`, or any `exercise.actionPrivateNote`,
    /// and `TemplateExercise`/`SessionSection` have no field to hold any of
    /// those even if it tried.
    public static func snapshotFromSession(
        _ session: Session,
        existingSessionSections: [SessionSection],
        newTemplateID: StableUUID,
        newExerciseIDGenerator: () -> UUID,
        newSectionIDGenerator: () -> UUID
    ) -> (exercises: [TemplateExercise], sections: [SessionSection]) {
        var sectionIDMap: [StableUUID: StableUUID] = [:]
        var newSections: [SessionSection] = []
        for section in existingSessionSections where section.ownerID == session.id {
            let newID = StableUUID(newSectionIDGenerator())
            sectionIDMap[section.id] = newID
            newSections.append(
                SessionSection(
                    id: newID,
                    ownerKind: .template,
                    ownerID: newTemplateID,
                    name: section.name,
                    orderIndex: section.orderIndex
                )
            )
        }
        let exercises = session.exercises.map { exercise -> TemplateExercise in
            TemplateExercise(
                id: StableUUID(newExerciseIDGenerator()),
                templateID: newTemplateID,
                sectionID: exercise.sectionID.flatMap { sectionIDMap[$0] },
                orderIndex: exercise.orderIndex,
                sourceKind: exercise.sourceKind,
                sourceID: exercise.sourceID,
                displayNameSnapshot: exercise.displayNameSnapshot,
                recordModeSnapshot: exercise.recordModeSnapshot,
                plannedSets: exercise.sets.map(TemplatePlannedSet.init(copyingValuesFrom:))
            )
        }
        return (exercises, newSections)
    }

    /// Applies this template's Exercise/Section snapshot onto `session` as an
    /// independent deep VALUE copy (M1B-FR-019, D-009). Every produced
    /// `SessionExercise`/`TrainingSet`/`SessionSection` gets a brand-new id;
    /// every `TrainingSet` is `.pending`. Neither `SessionExercise` nor
    /// `TrainingSet` HAS a field that could reference the source template,
    /// so there is no reference left to sever later -- subsequent edits or
    /// deletion of the template (or of `templateExercises`/`templateSections`
    /// themselves) structurally cannot reach anything this produces.
    public static func applying(
        exercises templateExercises: [TemplateExercise],
        sections templateSections: [SessionSection],
        trainingFocus: Set<BodyPart> = [],
        to session: Session,
        existingSessionSections: [SessionSection],
        newExerciseIDGenerator: () -> UUID,
        newSetIDGenerator: () -> UUID,
        newSectionIDGenerator: () -> UUID,
        now: Date
    ) throws -> TemplateApplicationResult {
        let existingOrderIndices = session.exercises.map(\.orderIndex) + existingSessionSections.map(\.orderIndex)
        var nextOrder: UInt32 = (existingOrderIndices.max().map { $0 + 1 }) ?? 0

        let combined = (templateSections.map(TemplateAxisEntry.section)
            + templateExercises.map(TemplateAxisEntry.exercise))
            .sorted { $0.orderIndex < $1.orderIndex }

        var sectionIDMap: [StableUUID: StableUUID] = [:]
        var newSections: [SessionSection] = []
        var newExercises: [SessionExercise] = []

        for entry in combined {
            switch entry {
            case .section(let templateSection):
                let newID = StableUUID(newSectionIDGenerator())
                sectionIDMap[templateSection.id] = newID
                newSections.append(
                    SessionSection(
                        id: newID,
                        ownerKind: .session,
                        ownerID: session.id,
                        name: templateSection.name,
                        orderIndex: nextOrder
                    )
                )
                nextOrder += 1
            case .exercise(let templateExercise):
                let newExerciseID = StableUUID(newExerciseIDGenerator())
                let mappedSectionID = templateExercise.sectionID.flatMap { sectionIDMap[$0] }
                let sets = templateExercise.plannedSets.enumerated().map { offset, planned in
                    planned.makePendingSet(
                        id: StableUUID(newSetIDGenerator()),
                        sessionExerciseID: newExerciseID,
                        orderIndex: UInt32(offset),
                        now: now
                    )
                }
                newExercises.append(
                    SessionExercise(
                        id: newExerciseID,
                        sessionID: session.id,
                        orderIndex: nextOrder,
                        sourceKind: templateExercise.sourceKind,
                        sourceID: templateExercise.sourceID,
                        displayNameSnapshot: templateExercise.displayNameSnapshot,
                        recordModeSnapshot: templateExercise.recordModeSnapshot,
                        actionPrivateNote: nil,
                        sectionID: mappedSectionID,
                        sets: sets
                    )
                )
                nextOrder += 1
            }
        }

        let appended = try session.appendingTemplateExercises(newExercises, now: now)
        let updatedSession = try appended.mergingTrainingFocus(trainingFocus, now: now)
        return TemplateApplicationResult(session: updatedSession, newSections: newSections)
    }
}
