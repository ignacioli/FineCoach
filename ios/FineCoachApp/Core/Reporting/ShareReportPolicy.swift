import Foundation

public enum ShareReportPolicy {
    /// 2 since T069j: exercise icon/body parts and opt-in personal bests.
    public static let schemaVersion = 2

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
        personalBests: [ShareReportPersonalBestDTO] = []
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
                let facet = exercise.sourceID.flatMap { PlaceholderExerciseCatalogLoader.facet(forExerciseID: $0.rawValue) }
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
                        FCEquipmentIcon.icon(equipmentClass: $0.equipmentClass, primaryMuscleGroup: $0.primaryMuscleGroup)?.rawValue
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
            personalBests: personalBests
        )
    }

    /// Personal bests (M1B-FR-029 rules, `Comparison.personalRecords`) that
    /// were SET in `completed`, judged against the student's full history.
    /// Used for the settings hint ("本次刷新 N 项") and, only when the coach
    /// opts in, the report's 个人最佳 section.
    public static func personalBestsSet(
        in completed: CompletedSession,
        history: [CompletedSession],
        assistedExerciseIDs: Set<StableExerciseID> = []
    ) -> [ShareReportPersonalBestDTO] {
        var seen = Set<String>()
        var result: [ShareReportPersonalBestDTO] = []
        let sessions = history.contains { $0.id == completed.id } ? history : history + [completed]
        for exercise in completed.exercises {
            guard let sourceID = exercise.sourceID else { continue }
            let mode = exercise.recordModeSnapshot
            guard seen.insert("\(sourceID.rawValue)|\(mode.rawValue)").inserted else { continue }
            let records = Comparison.personalRecords(
                exerciseID: sourceID,
                recordMode: mode,
                across: sessions,
                loadDirection: assistedExerciseIDs.contains(sourceID) ? .decreaseIsImprovement : .increaseIsImprovement
            )
            let name = exercise.displayNameSnapshot.value
            if let best = records.mostRepsAtWeight, best.sessionID == completed.id {
                result.append(.init(displayName: name, kind: .highestWeight, weightValue: best.weight, repetitionCount: best.reps))
            } else if records.mostRepsAtWeight == nil, let best = records.highestWeight, best.sessionID == completed.id {
                result.append(.init(displayName: name, kind: .highestWeight, weightValue: best.weight))
            } else if let best = records.longestDuration, best.sessionID == completed.id {
                result.append(.init(displayName: name, kind: .longestDuration, durationSeconds: best.seconds))
            } else if let best = records.longestDistance, best.sessionID == completed.id {
                result.append(.init(displayName: name, kind: .longestDistance, distanceValue: best.distance))
            }
        }
        return result
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
