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

    public init(
        schemaVersion: Int,
        studentDisplayName: String?,
        sessionDateUTC: Date?,
        durationSeconds: DecimalValue?,
        trainingFocus: String?,
        studentFacingSummary: String?,
        trainingVolume: DecimalValue?,
        exercises: [ShareReportExerciseDTO]
    ) {
        self.schemaVersion = schemaVersion
        self.studentDisplayName = studentDisplayName
        self.sessionDateUTC = sessionDateUTC
        self.durationSeconds = durationSeconds
        self.trainingFocus = trainingFocus
        self.studentFacingSummary = studentFacingSummary
        self.trainingVolume = trainingVolume
        self.exercises = exercises
    }
}

public struct ShareReportExerciseDTO: Hashable, Sendable {
    public let displayName: String
    public let confirmedSets: [ShareReportSetDTO]

    public init(displayName: String, confirmedSets: [ShareReportSetDTO]) {
        self.displayName = displayName
        self.confirmedSets = confirmedSets
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

    public init(
        orderIndex: UInt32,
        recordMode: RecordMode,
        weightValue: DecimalValue?,
        repetitionCount: DecimalValue?,
        durationSeconds: DecimalValue?,
        unit: MeasurementUnit,
        side: SetSide,
        leftValue: DecimalValue?,
        rightValue: DecimalValue?
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
    }
}
