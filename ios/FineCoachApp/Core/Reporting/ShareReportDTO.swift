import Foundation

public struct ShareReportDTO: Hashable, Sendable {
    public let schemaVersion: Int
    public let studentDisplayName: String?
    public let sessionDateUTC: Date?
    public let durationSeconds: DecimalValue?
    public let trainingFocus: String?
    public let studentFacingSummary: String?
    public let trainingVolume: DecimalValue?
    public let exercises: [ShareReportExerciseDTO]
    /// Bests set in THIS session; empty unless the coach opted in for this
    /// generation (M1B-FR-030 default off; not persisted, so every
    /// generation starts without it, M1A-FR-035).
    public let personalBests: [ShareReportPersonalBestDTO]

    /// One "上次 … → 本次 …" row per action, in session order (D-FR-022).
    /// Records appear in this same row with `isNewRecord`, never as a separate row.
    public let gainRows: [ShareReportGainRowDTO]
    public let milestoneSessionNumber: Int?
    public let attendanceStreakWeeks: Int?

    public init(
        schemaVersion: Int,
        studentDisplayName: String?,
        sessionDateUTC: Date?,
        durationSeconds: DecimalValue?,
        trainingFocus: String?,
        studentFacingSummary: String?,
        trainingVolume: DecimalValue?,
        exercises: [ShareReportExerciseDTO],
        personalBests: [ShareReportPersonalBestDTO] = [],
        gainRows: [ShareReportGainRowDTO] = [],
        milestoneSessionNumber: Int? = nil,
        attendanceStreakWeeks: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.studentDisplayName = studentDisplayName
        self.sessionDateUTC = sessionDateUTC
        self.durationSeconds = durationSeconds
        self.trainingFocus = trainingFocus
        self.studentFacingSummary = studentFacingSummary
        self.trainingVolume = trainingVolume
        self.exercises = exercises
        self.personalBests = personalBests
        self.gainRows = gainRows
        self.milestoneSessionNumber = milestoneSessionNumber
        self.attendanceStreakWeeks = attendanceStreakWeeks
    }
}

/// One personal best achieved in the shared session (M1B-FR-029 rules).
public struct ShareReportPersonalBestDTO: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case highestWeight
        case longestDuration
        case longestDistance
        /// `reps` mode record: strictly more repetitions (spec 004 Revision 1.5).
        case mostReps
    }

    public let displayName: String
    public let kind: Kind
    public let weightValue: DecimalValue?
    public let repetitionCount: DecimalValue?
    public let durationSeconds: DecimalValue?
    public let distanceValue: DecimalValue?

    public init(
        displayName: String,
        kind: Kind,
        weightValue: DecimalValue? = nil,
        repetitionCount: DecimalValue? = nil,
        durationSeconds: DecimalValue? = nil,
        distanceValue: DecimalValue? = nil
    ) {
        self.displayName = displayName
        self.kind = kind
        self.weightValue = weightValue
        self.repetitionCount = repetitionCount
        self.durationSeconds = durationSeconds
        self.distanceValue = distanceValue
    }
}

public struct ShareReportExerciseDTO: Hashable, Sendable {
    public let displayName: String
    public let confirmedSets: [ShareReportSetDTO]
    /// Catalog-derived presentation data (T069j, 29 preview): the §7.1
    /// equipment icon and the exercise's primary/secondary body parts for
    /// the trained-parts diagram. Derived from the built-in catalog only —
    /// never from the student's body data. `nil`/empty for custom exercises.
    public let equipmentIcon: String?
    public let primaryBodyPart: BodyPart?
    public let secondaryBodyParts: Set<BodyPart>

    public init(
        displayName: String,
        confirmedSets: [ShareReportSetDTO],
        equipmentIcon: String? = nil,
        primaryBodyPart: BodyPart? = nil,
        secondaryBodyParts: Set<BodyPart> = []
    ) {
        self.displayName = displayName
        self.confirmedSets = confirmedSets
        self.equipmentIcon = equipmentIcon
        self.primaryBodyPart = primaryBodyPart
        self.secondaryBodyParts = secondaryBodyParts
    }
}

public struct ShareReportSetDTO: Hashable, Sendable {
    public let orderIndex: UInt32
    public let recordMode: RecordMode
    public let weightValue: DecimalValue?
    public let repetitionCount: DecimalValue?
    public let durationSeconds: DecimalValue?
    public let unit: MeasurementUnit
    public let side: SetSide
    public let leftValue: DecimalValue?
    public let rightValue: DecimalValue?
    /// Cardio-only fields (M1B-FR-022, D-008), mirroring `TrainingSet`'s
    /// `distanceValue`/`speedValue`/`resistanceValue`. Training performance
    /// data, not privacy-sensitive body/identity data -- not subject to
    /// `ShareReportPolicy.forbiddenIdentifierTokens`.
    public let distanceValue: DecimalValue?
    public let speedValue: DecimalValue?
    public let resistanceValue: DecimalValue?

    public init(
        orderIndex: UInt32,
        recordMode: RecordMode,
        weightValue: DecimalValue?,
        repetitionCount: DecimalValue?,
        durationSeconds: DecimalValue?,
        unit: MeasurementUnit,
        side: SetSide,
        leftValue: DecimalValue?,
        rightValue: DecimalValue?,
        distanceValue: DecimalValue? = nil,
        speedValue: DecimalValue? = nil,
        resistanceValue: DecimalValue? = nil
    ) {
        self.orderIndex = orderIndex
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
}

extension ShareReportSetDTO: TrainingSetDisplayValues {}

/// Allowlisted training performance only, shared with the summary's derived result.
public struct ShareReportGainRowDTO: Hashable, Sendable {
    public let displayName: String
    /// True when this action also set a record in the shared session; the card
    /// draws it as the row badge and never as a second row (D-FR-021).
    public let isNewRecord: Bool
    public let previous: ShareReportSetDTO
    public let current: ShareReportSetDTO

    public init(
        displayName: String, isNewRecord: Bool, previous: ShareReportSetDTO, current: ShareReportSetDTO
    ) {
        self.displayName = displayName
        self.isNewRecord = isNewRecord
        self.previous = previous
        self.current = current
    }
}
