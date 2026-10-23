import Foundation

public enum ShareReportPolicy {
    /// 4: opt-in session gains as one "上次 → 本次" row per action (spec 004
    /// Revision 1.5), plus the session milestone.
    public static let schemaVersion = 4

    public static let allowedDTOPropertyNames: Set<String> = [
        "schemaVersion",
        "studentDisplayName",
        "sessionDateUTC",
        "durationSeconds",
        "trainingFocus",
        "studentFacingSummary",
        "trainingVolume",
        "exercises",
        "personalBests",
        "gainRows",
        "milestoneSessionNumber",
    ]

    public static let forbiddenIdentifierTokens: [String] = [
        "sex",
        "injury",
        "phone",
        "wechat",
        "privateCoach",
        "actionPrivate",
        "recipient",
        "delivery",
        "sent",
        "revoked",
        "bodyMass",
        "bodyFat",
        "StudentMO",
    ]

    public static func makeDTO(
        from completed: CompletedSession,
        modules: ShareReportModuleSelection = .privacySafeDefaults,
        personalBests: [ShareReportPersonalBestDTO] = [],
        gains: SessionGains? = nil
    ) throws -> ShareReportDTO {
        guard completed.completedAtUTC.timeIntervalSince1970.isFinite else {
            throw DomainError.invalidState
        }

        let displayName: String?
        if modules.includeStudentDisplayName {
            if let override = modules.studentDisplayNameOverride?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !override.isEmpty {
                displayName = override
            } else {
                displayName = completed.studentDisplayName.value
            }
        } else {
            displayName = nil
        }

        let summary: String?
        if modules.includeStudentFacingSummary {
            let value = completed.notes.studentFacingSummary?.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            summary = (value?.isEmpty == false) ? value : nil
        } else {
            summary = nil
        }

        let exercises: [ShareReportExerciseDTO]
        if modules.includeExercisesAndSets {
            exercises = completed.exercises.map { exercise in
                let facet = exercise.sourceID.flatMap {
                    PlaceholderExerciseCatalogLoader.facet(forExerciseID: $0.rawValue)
                }
                let parts = ExerciseBodyParts(
                    catalogPrimary: facet?.primaryMuscleGroup,
                    catalogSecondary: facet?.secondaryMuscleGroups ?? []
                )
                return ShareReportExerciseDTO(
                    displayName: exercise.displayNameSnapshot.value,
                    confirmedSets: exercise.sets.filter(\.contributesToStatistics).map { trainingSet in
                        ShareReportSetDTO(
                            orderIndex: trainingSet.orderIndex,
                            recordMode: trainingSet.recordMode,
                            weightValue: trainingSet.weightValue,
                            repetitionCount: trainingSet.repetitionCount,
                            durationSeconds: trainingSet.durationSeconds,
                            unit: trainingSet.unit,
                            side: trainingSet.side,
                            leftValue: trainingSet.leftValue,
                            rightValue: trainingSet.rightValue,
                            distanceValue: trainingSet.distanceValue,
                            speedValue: trainingSet.speedValue,
                            resistanceValue: trainingSet.resistanceValue
                        )
                    },
                    equipmentIcon: facet.flatMap {
                        FCEquipmentIcon.icon(
                            equipmentClass: $0.equipmentClass, primaryMuscleGroup: $0.primaryMuscleGroup)?.rawValue
                    },
                    primaryBodyPart: parts.primary,
                    secondaryBodyParts: parts.secondary
                )
            }
        } else {
            exercises = []
        }

        return ShareReportDTO(
            schemaVersion: schemaVersion,
            studentDisplayName: displayName,
            sessionDateUTC: modules.includeDate ? completed.completedAtUTC : nil,
            durationSeconds: modules.includeDuration ? completed.statistics.displayedDurationSeconds : nil,
            trainingFocus: modules.includeTrainingFocus
                ? BodyPart.joinedDisplayNames(for: completed.trainingFocus, separator: "、") : nil,
            studentFacingSummary: summary,
            trainingVolume: modules.includeTrainingVolume ? completed.statistics.ordinaryTrainingVolume : nil,
            exercises: exercises,
            personalBests: gains.map { personalBestsSet(from: $0) } ?? personalBests,
            gainRows: gains?.rows.map {
                ShareReportGainRowDTO(
                    displayName: $0.displayName, isNewRecord: $0.isNewRecord, previous: reportSet($0.previous),
                    current: reportSet($0.current))
            } ?? [],
            milestoneSessionNumber: gains?.milestoneSessionNumber
        )
    }

    /// Strict improvements over compatible history before this session (D-FR-001–004).
    public static func personalBestsSet(
        in completed: CompletedSession,
        history: [CompletedSession],
        assistedExerciseIDs: Set<StableExerciseID> = []
    ) -> [ShareReportPersonalBestDTO] {
        personalBestsSet(
            from: SessionGains(current: completed, history: history, assistedExerciseIDs: assistedExerciseIDs))
    }

    public static func personalBestsSet(from gains: SessionGains) -> [ShareReportPersonalBestDTO] {
        gains.records.map { record in
            let kind: ShareReportPersonalBestDTO.Kind
            switch record.kind {
            case .highestWeight: kind = .highestWeight
            case .longestDuration: kind = .longestDuration
            case .mostReps: kind = .mostReps
            }
            return ShareReportPersonalBestDTO(
                displayName: record.displayName, kind: kind,
                weightValue: kind == .highestWeight ? record.set.weightValue : nil,
                // The set detail travels with a weight record; the record
                // itself is still judged on the weight alone (Revision 1.5).
                repetitionCount: kind == .highestWeight || kind == .mostReps
                    ? record.set.repetitionCount : nil,
                durationSeconds: kind == .longestDuration ? record.set.durationSeconds : nil,
                distanceValue: nil)
        }
    }

    /// A nil hint also means the settings row must be absent (D-FR-031).
    /// "N 项新纪录" counts record actions; "N 项进步" counts the action rows
    /// that improved without a record, so no action is counted twice.
    public static func gainsHint(for gains: SessionGains) -> String? {
        var parts: [String] = []
        if !gains.records.isEmpty {
            parts.append(String(format: String(localized: "share.gains.records.format"), gains.records.count))
        }
        if let number = gains.milestoneSessionNumber {
            parts.append(String(format: String(localized: "session.gains.milestone.format"), Int64(number)))
        }
        if !gains.progress.isEmpty {
            parts.append(String(format: String(localized: "share.gains.progress.format"), gains.progress.count))
        }
        return parts.isEmpty ? nil : parts.prefix(2).joined(separator: " · ")
    }

    private static func reportSet(_ set: TrainingSet) -> ShareReportSetDTO {
        ShareReportSetDTO(
            orderIndex: set.orderIndex, recordMode: set.recordMode, weightValue: set.weightValue,
            repetitionCount: set.repetitionCount, durationSeconds: set.durationSeconds, unit: set.unit,
            side: set.side, leftValue: set.leftValue, rightValue: set.rightValue,
            distanceValue: set.distanceValue, speedValue: set.speedValue, resistanceValue: set.resistanceValue)
    }

    public static func previewLines(for dto: ShareReportDTO) -> [String] {
        var lines: [String] = []
        if let name = dto.studentDisplayName, !name.isEmpty {
            lines.append(name)
        }
        if let date = dto.sessionDateUTC {
            lines.append(formattedDay(date))
        }
        if let duration = dto.durationSeconds {
            lines.append("时长 \(duration.canonicalString)")
        }
        if let focus = dto.trainingFocus, !focus.isEmpty {
            lines.append("训练重点 \(focus)")
        }
        if let summary = dto.studentFacingSummary, !summary.isEmpty {
            lines.append("课后总结 \(summary)")
        }
        if let volume = dto.trainingVolume {
            lines.append("训练容量 \(volume.canonicalString) kg")
        }
        for exercise in dto.exercises {
            lines.append(exercise.displayName)
            for trainingSet in exercise.confirmedSets {
                lines.append(setLine(trainingSet))
            }
        }
        if lines.isEmpty {
            lines.append("训练报告")
        }
        return lines
    }

    private static func setLine(_ trainingSet: ShareReportSetDTO) -> String {
        "组\(trainingSet.orderIndex + 1) " + TrainingSetDisplayFormatting.summary(for: trainingSet)
    }

    private static func formattedDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
