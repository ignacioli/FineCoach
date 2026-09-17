import Foundation

public enum SetRecordingState: String, Codable, Sendable {
    case draft
    case pending
    case completed
}

public struct TrainingSetInput: Equatable, Sendable {
    public var recordMode: RecordMode
    public var weightValue: String?
    public var repetitionCount: String?
    public var durationSeconds: String?
    public var unit: MeasurementUnit
    public var side: SetSide
    public var leftValue: String?
    public var rightValue: String?
    public var distanceValue: String?
    public var speedValue: String?
    public var resistanceValue: String?

    public init(
        recordMode: RecordMode,
        weightValue: String? = nil,
        repetitionCount: String? = nil,
        durationSeconds: String? = nil,
        unit: MeasurementUnit,
        side: SetSide = .none,
        leftValue: String? = nil,
        rightValue: String? = nil,
        distanceValue: String? = nil,
        speedValue: String? = nil,
        resistanceValue: String? = nil
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
}

public struct TrainingSet: Hashable, Codable, Sendable, Identifiable {
    public let id: StableUUID
    public let sessionExerciseID: StableUUID
    public let orderIndex: UInt32
    public let state: SetRecordingState
    public let recordMode: RecordMode
    public let weightValue: DecimalValue?
    public let repetitionCount: DecimalValue?
    public let durationSeconds: DecimalValue?
    public let unit: MeasurementUnit
    public let side: SetSide
    public let leftValue: DecimalValue?
    public let rightValue: DecimalValue?
    /// Cardio-only planned/recorded fields (M1B-FR-022, D-008). `distanceValue`
    /// is required (alongside `durationSeconds`) for a cardio set to reach
    /// `.completed`; `speedValue`/`resistanceValue` are always optional and
    /// never gate completion.
    public let distanceValue: DecimalValue?
    public let speedValue: DecimalValue?
    public let resistanceValue: DecimalValue?
    public let createdAtUTC: Date
    public let updatedAtUTC: Date
    public let completedAtUTC: Date?

    public var contributesToStatistics: Bool {
        state == .completed
    }

    public func ordinaryVolumeContribution() throws -> DecimalValue? {
        guard state == .completed, recordMode == .weightReps, let repetitionCount else {
            return nil
        }
        let load: DecimalValue
        switch side {
        case .none:
            guard let weightValue else {
                return nil
            }
            load = weightValue
        case .bilateral:
            if let leftValue, let rightValue {
                load = try leftValue.adding(rightValue)
            } else if let weightValue, leftValue == nil, rightValue == nil {
                load = try weightValue.multiplied(by: DecimalValue("2"))
            } else {
                return nil
            }
        case .left:
            guard let value = leftValue ?? weightValue else {
                return nil
            }
            load = value
        case .right:
            guard let value = rightValue ?? weightValue else {
                return nil
            }
            load = value
        }
        return try load.multiplied(by: repetitionCount)
    }

    /// Single source of truth for rendering one Set's recorded values as a
    /// human-readable string, shared by ActiveSessionView (in-progress sets)
    /// and SessionDetailView (read-only History). Before this existed each
    /// View had its own copy; SessionDetailView's copy only ever handled
    /// weightReps, so .reps/.duration/.cardio sets rendered blank there.
    /// Cardio's durationSeconds is shown in minutes (see
    /// `DecimalValue.minutes(fromSeconds:)`) -- storage itself stays in
    /// seconds.
    public var displaySummary: String {
        switch recordMode {
        case .weightReps:
            let repsText = repetitionCount?.canonicalString ?? "-"
            switch side {
            case .none:
                return "\(weightValue?.canonicalString ?? "-")kg × \(repsText)次"
            case .left:
                return "左 \((leftValue ?? weightValue)?.canonicalString ?? "-")kg × \(repsText)次"
            case .right:
                return "右 \((rightValue ?? weightValue)?.canonicalString ?? "-")kg × \(repsText)次"
            case .bilateral:
                if let leftValue, let rightValue {
                    return "左 \(leftValue.canonicalString)kg / 右 \(rightValue.canonicalString)kg × \(repsText)次"
                }
                return "\(weightValue?.canonicalString ?? "-")kg（双侧） × \(repsText)次"
            }
        case .reps:
            return "\(repetitionCount?.canonicalString ?? "-")次"
        case .duration:
            return "\(durationSeconds?.canonicalString ?? "-")秒"
        case .cardio:
            var parts: [String] = []
            if let durationSeconds {
                parts.append("\(DecimalValue.minutes(fromSeconds: durationSeconds).canonicalString)分钟")
            } else {
                parts.append("-分钟")
            }
            parts.append("\(distanceValue?.canonicalString ?? "-")km")
            if let speedValue {
                parts.append("速度 \(speedValue.canonicalString)")
            }
            if let resistanceValue {
                parts.append("阻力 \(resistanceValue.canonicalString)")
            }
            return parts.joined(separator: " · ")
        }
    }

    public init(
        id: StableUUID,
        sessionExerciseID: StableUUID,
        orderIndex: UInt32,
        state: SetRecordingState,
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
        resistanceValue: DecimalValue? = nil,
        createdAtUTC: Date,
        updatedAtUTC: Date,
        completedAtUTC: Date?
    ) {
        self.id = id
        self.sessionExerciseID = sessionExerciseID
        self.orderIndex = orderIndex
        self.state = state
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
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
        self.completedAtUTC = completedAtUTC
    }

    public static func makeDraft(
        id: StableUUID,
        sessionExerciseID: StableUUID,
        orderIndex: UInt32,
        input: TrainingSetInput,
        now: Date
    ) throws -> TrainingSet {
        TrainingSet(
            id: id,
            sessionExerciseID: sessionExerciseID,
            orderIndex: orderIndex,
            state: .draft,
            parsed: try ParsedFields(input),
            createdAtUTC: now,
            updatedAtUTC: now,
            completedAtUTC: nil
        )
    }

    public func updating(input: TrainingSetInput, now: Date) throws -> TrainingSet {
        let parsed = try ParsedFields(input)
        let nextState: SetRecordingState
        switch state {
        case .completed:
            nextState = (try? parsed.validateForCompletion()) != nil ? .pending : .draft
        case .pending, .draft:
            nextState = .draft
        }
        return TrainingSet(
            id: id,
            sessionExerciseID: sessionExerciseID,
            orderIndex: orderIndex,
            state: nextState,
            parsed: parsed,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: now,
            completedAtUTC: nil
        )
    }

    public func confirmed(now: Date) throws -> TrainingSet {
        try ParsedFields(self).validateForCompletion()
        return replacing(state: .completed, orderIndex: orderIndex, updatedAtUTC: now, completedAtUTC: now)
    }

    public func copiedAsPending(id: StableUUID, orderIndex: UInt32, now: Date) throws -> TrainingSet {
        try ParsedFields(self).validateForCompletion()
        return TrainingSet(
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

    /// Deep-value copy as a fresh `.pending` set with a brand-new identity and
    /// no timestamps inherited from the source (M1B-FR-019/D-009: template
    /// application snapshots). Unlike `copiedAsPending`, the source is NOT
    /// required to already satisfy the completion threshold -- planned
    /// template data is copied as-is, whatever its current fields, so it can
    /// still be edited before completion.
    public func copiedAsPendingSnapshot(id: StableUUID, sessionExerciseID: StableUUID, orderIndex: UInt32, now: Date)
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

    public func undone(now: Date) throws -> TrainingSet {
        guard state == .completed else {
            throw DomainError.invalidState
        }
        return replacing(state: .pending, orderIndex: orderIndex, updatedAtUTC: now, completedAtUTC: nil)
    }

    func relocating(sessionExerciseID: StableUUID, orderIndex: UInt32) -> TrainingSet {
        TrainingSet(
            id: id,
            sessionExerciseID: sessionExerciseID,
            orderIndex: orderIndex,
            state: state,
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
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC,
            completedAtUTC: completedAtUTC
        )
    }

    private init(
        id: StableUUID,
        sessionExerciseID: StableUUID,
        orderIndex: UInt32,
        state: SetRecordingState,
        parsed: ParsedFields,
        createdAtUTC: Date,
        updatedAtUTC: Date,
        completedAtUTC: Date?
    ) {
        self.id = id
        self.sessionExerciseID = sessionExerciseID
        self.orderIndex = orderIndex
        self.state = state
        self.recordMode = parsed.recordMode
        self.weightValue = parsed.weightValue
        self.repetitionCount = parsed.repetitionCount
        self.durationSeconds = parsed.durationSeconds
        self.unit = parsed.unit
        self.side = parsed.side
        self.leftValue = parsed.leftValue
        self.rightValue = parsed.rightValue
        self.distanceValue = parsed.distanceValue
        self.speedValue = parsed.speedValue
        self.resistanceValue = parsed.resistanceValue
        self.createdAtUTC = createdAtUTC
        self.updatedAtUTC = updatedAtUTC
        self.completedAtUTC = completedAtUTC
    }

    private func replacing(
        state: SetRecordingState,
        orderIndex: UInt32,
        updatedAtUTC: Date,
        completedAtUTC: Date?
    ) -> TrainingSet {
        TrainingSet(
            id: id,
            sessionExerciseID: sessionExerciseID,
            orderIndex: orderIndex,
            state: state,
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
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC,
            completedAtUTC: completedAtUTC
        )
    }
}

private struct ParsedFields {
    let recordMode: RecordMode
    let weightValue: DecimalValue?
    let repetitionCount: DecimalValue?
    let durationSeconds: DecimalValue?
    let unit: MeasurementUnit
    let side: SetSide
    let leftValue: DecimalValue?
    let rightValue: DecimalValue?
    let distanceValue: DecimalValue?
    let speedValue: DecimalValue?
    let resistanceValue: DecimalValue?

    init(_ input: TrainingSetInput) throws {
        self.recordMode = input.recordMode
        self.weightValue = try Self.parseDecimal(input.weightValue)
        self.repetitionCount = try Self.parseDecimal(input.repetitionCount)
        self.durationSeconds = try Self.parseDecimal(input.durationSeconds)
        self.unit = input.unit
        self.side = input.side
        self.leftValue = try Self.parseDecimal(input.leftValue)
        self.rightValue = try Self.parseDecimal(input.rightValue)
        self.distanceValue = try Self.parseDecimal(input.distanceValue)
        self.speedValue = try Self.parseDecimal(input.speedValue)
        self.resistanceValue = try Self.parseDecimal(input.resistanceValue)
    }

    init(_ set: TrainingSet) {
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

    func validateForCompletion() throws {
        switch recordMode {
        case .weightReps:
            guard weightValue != nil else {
                throw DomainError.invalidNumber
            }
            try Self.requirePositiveInteger(repetitionCount)
            guard durationSeconds == nil else {
                throw DomainError.invalidMode
            }
            guard unit == .kilograms || unit == .pounds else {
                throw DomainError.invalidUnit
            }
            try Self.requireNoCardioFields(distanceValue, speedValue, resistanceValue)
        case .reps:
            guard weightValue == nil, durationSeconds == nil else {
                throw DomainError.invalidMode
            }
            try Self.requirePositiveInteger(repetitionCount)
            guard unit == .repetitions else {
                throw DomainError.invalidUnit
            }
            try Self.requireNoCardioFields(distanceValue, speedValue, resistanceValue)
        case .duration:
            guard weightValue == nil, repetitionCount == nil else {
                throw DomainError.invalidMode
            }
            guard let durationSeconds, durationSeconds.isPositive else {
                throw DomainError.invalidNumber
            }
            guard unit == .seconds else {
                throw DomainError.invalidUnit
            }
            try Self.requireNoCardioFields(distanceValue, speedValue, resistanceValue)
        case .cardio:
            // M1B-FR-022 / D-008: duration>0 AND distance>0 are both
            // required for a cardio set to complete; speed/resistance are
            // always optional and never gate completion.
            guard weightValue == nil, repetitionCount == nil else {
                throw DomainError.invalidMode
            }
            guard let durationSeconds, durationSeconds.isPositive else {
                throw DomainError.invalidNumber
            }
            guard let distanceValue, distanceValue.isPositive else {
                throw DomainError.invalidNumber
            }
            guard unit == .seconds else {
                throw DomainError.invalidUnit
            }
        }
        try validateSide()
    }

    private func validateSide() throws {
        switch side {
        case .none:
            guard leftValue == nil, rightValue == nil else {
                throw DomainError.invalidState
            }
        case .left:
            guard leftValue != nil, rightValue == nil else {
                throw DomainError.invalidNumber
            }
        case .right:
            guard rightValue != nil, leftValue == nil else {
                throw DomainError.invalidNumber
            }
        case .bilateral:
            guard leftValue != nil, rightValue != nil else {
                throw DomainError.invalidNumber
            }
        }
    }

    private static func requirePositiveInteger(_ value: DecimalValue?) throws {
        guard let value, value.isPositive, value.isInteger else {
            throw DomainError.invalidNumber
        }
    }

    private static func requireNoCardioFields(
        _ distanceValue: DecimalValue?,
        _ speedValue: DecimalValue?,
        _ resistanceValue: DecimalValue?
    ) throws {
        guard distanceValue == nil, speedValue == nil, resistanceValue == nil else {
            throw DomainError.invalidMode
        }
    }

    private static func parseDecimal(_ rawValue: String?) throws -> DecimalValue? {
        guard let rawValue else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        return try DecimalValue(trimmed)
    }
}
