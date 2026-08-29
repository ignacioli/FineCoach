import Foundation

public enum ShareReportPolicy {
    public static let schemaVersion = 1

    public static let allowedDTOPropertyNames: Set<String> = [
        "schemaVersion",
        "studentDisplayName",
        "sessionDateUTC",
        "durationSeconds",
        "trainingFocus",
        "studentFacingSummary",
        "trainingVolume",
        "exercises",
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
        modules: ShareReportModuleSelection = .privacySafeDefaults
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
                ShareReportExerciseDTO(
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
                            rightValue: trainingSet.rightValue
                        )
                    }
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
            trainingFocus: modules.includeTrainingFocus ? completed.trainingFocus?.value : nil,
            studentFacingSummary: summary,
            trainingVolume: modules.includeTrainingVolume ? completed.statistics.ordinaryTrainingVolume : nil,
            exercises: exercises
        )
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
            lines.append("训练容量 \(volume.canonicalString)")
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
        var parts = ["组\(trainingSet.orderIndex + 1)"]
        if let weight = trainingSet.weightValue {
            parts.append(weight.canonicalString)
        }
        if let reps = trainingSet.repetitionCount {
            parts.append("×\(reps.canonicalString)")
        }
        if let duration = trainingSet.durationSeconds {
            parts.append("\(duration.canonicalString)s")
        }
        if let left = trainingSet.leftValue {
            parts.append("L\(left.canonicalString)")
        }
        if let right = trainingSet.rightValue {
            parts.append("R\(right.canonicalString)")
        }
        return parts.joined(separator: " ")
    }

    private static func formattedDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
