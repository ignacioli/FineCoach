import Foundation

/// Text derivation for the viewer pages. Pure: archive values in, strings out. Glossary words
/// only (「训练记录」), no English domain words (M2-FR-035).
enum ArchiveViewerPresentation {
    /// 「动作 N」 when the archive has no exercise info, else the exported name.
    static func exerciseName(_ exercise: ArchiveExercise) -> String {
        exercise.info?.name ?? String(format: String(localized: "archive.viewer.exercise.placeholder"), exercise.placeholderNumber)
    }

    static func exerciseName(_ entry: ArchiveExerciseEntry) -> String {
        entry.info?.name ?? String(format: String(localized: "archive.viewer.exercise.placeholder"), entry.placeholderNumber)
    }

    /// 「9月25日 周四」 for the coach's calendar day of the session.
    static func day(_ date: LocalDate, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: date.startOfDay(calendar: calendar))
    }

    /// 「大腿、臀 · 12 组 · 58 分钟」
    static func sessionMeta(_ session: ArchiveSession) -> String {
        var parts: [String] = []
        if let focus = BodyPart.joinedDisplayNames(for: session.trainingFocus, separator: "、") {
            parts.append(focus)
        }
        let sets = session.sections.flatMap(\.exercises).reduce(0) { $0 + $1.sets.count }
        parts.append(String(format: String(localized: "student.detail.setCountFormat"), sets))
        parts.append(String(format: String(localized: "today.durationFormat"), max(1, session.durationMinutes)))
        return parts.joined(separator: " · ")
    }

    /// 「个人训练档案」 title row of the home page.
    static func homeTitle(_ content: ArchiveViewerContent) -> String {
        if let name = content.studentDisplayName, !name.isEmpty {
            return name
        }
        return String(localized: "archive.viewer.home.genericTitle")
    }

    /// 「只读档案 · 来源 4821 · 9月25日」
    static func banner(_ content: ArchiveViewerContent) -> String {
        String(
            format: String(localized: "archive.viewer.home.bannerFormat"),
            content.sourceLabel,
            ArchiveImportPresentation.snapshotMonthDay(content.manifest.snapshotAtUTC)
        )
    }

    /// The reference day of 「近 N 天」: the day the archive was made, so an older archive still
    /// shows its latest weeks.
    static func referenceDay(_ content: ArchiveViewerContent, calendar: Calendar = .current) -> LocalDate {
        LocalDate(date: content.manifest.snapshotAtUTC, calendar: calendar)
    }

    /// 「90 kg」 style weight with the display unit; `value` is the stored kilogram value.
    static func weightText(_ value: DecimalValue, converter: ArchiveDisplayConverter) -> String {
        let quantity = converter.weight(value, storedUnit: .kilograms)
        return "\(quantity.value.canonicalString) \(quantity.unit)"
    }

    /// The best-record row of the trends page, one per exercise and record mode.
    static func personalBestRow(
        name: String,
        records: Comparison.PersonalRecordSet,
        dayOf: (StableUUID) -> String?,
        converter: ArchiveDisplayConverter
    ) -> (kind: String, value: String, day: String?, detail: String?)? {
        if let best = records.mostRepsAtWeight {
            let weight = converter.weight(best.weight, storedUnit: .kilograms)
            return (
                String(localized: "history.pb.highestWeight"),
                "\(weight.value.canonicalString) \(weight.unit)",
                dayOf(best.sessionID),
                String(
                    format: String(localized: "archive.viewer.pb.setDetailFormat"),
                    weight.value.canonicalString, weight.unit, best.reps.canonicalString)
            )
        }
        if let highest = records.highestWeight {
            return (
                String(localized: "history.pb.highestWeight"),
                weightText(highest.weight, converter: converter),
                dayOf(highest.sessionID), nil
            )
        }
        if let duration = records.longestDuration {
            return (
                String(localized: "history.pb.longestDuration"),
                DurationTextParser.formatForEditing(secondsText: duration.seconds.canonicalString),
                dayOf(duration.sessionID), nil
            )
        }
        if let distance = records.longestDistance {
            return (
                String(localized: "history.pb.longestDistance"),
                "\(distance.distance.canonicalString) km",
                dayOf(distance.sessionID), nil
            )
        }
        return nil
    }
}

/// Maps an archive session onto the value `ShareReportCardView` draws, so the viewer's record
/// page is the M1 35 page (same sections) fed from archive values (T047). No share report is
/// ever produced from it.
enum ArchiveSessionRecord {
    static func dto(
        session: ArchiveSession,
        content: ArchiveViewerContent,
        converter: ArchiveDisplayConverter,
        calendar: Calendar = .current
    ) -> ShareReportDTO? {
        let exercises: [ShareReportExerciseDTO] = session.sections.flatMap(\.exercises).map { entry in
            let archived = content.exercise(key: entry.exerciseKey)
            let info = archived?.info
            let name = archived.map(ArchiveViewerPresentation.exerciseName)
                ?? String(format: String(localized: "archive.viewer.exercise.placeholder"), 0)
            let icon = info.flatMap {
                FCEquipmentIcon.icon(equipmentClass: $0.equipment, primaryMuscleGroup: $0.primaryMuscles.first)
            }
            let parts = info.map { ExerciseBodyParts(catalogPrimary: $0.primaryMuscles.first, catalogSecondary: $0.secondaryMuscles) }
            return ShareReportExerciseDTO(
                displayName: name,
                confirmedSets: entry.sets.enumerated().map { index, set in
                    setDTO(set, index: index, mode: entry.recordMode, converter: converter)
                },
                equipmentIcon: icon?.rawValue,
                primaryBodyPart: parts?.primary,
                secondaryBodyParts: parts?.secondary ?? []
            )
        }
        let summaryText = ((try? content.summaries(forSessionKey: session.key)) ?? []).map(\.text).joined(separator: "\n")
        let noon = session.localDate.startOfDay(calendar: calendar).addingTimeInterval(12 * 3600)
        return ShareReportDTO(
            schemaVersion: ShareReportPolicy.schemaVersion,
            studentDisplayName: nil,
            sessionDateUTC: noon,
            durationSeconds: try? DecimalValue(String(max(0, session.durationMinutes) * 60)),
            trainingFocus: BodyPart.joinedDisplayNames(for: session.trainingFocus, separator: "、"),
            studentFacingSummary: summaryText.isEmpty ? nil : summaryText,
            trainingVolume: nil,
            exercises: exercises
        )
    }

    private static func setDTO(
        _ set: ArchiveSet, index: Int, mode: RecordMode, converter: ArchiveDisplayConverter
    ) -> ShareReportSetDTO {
        func convert(_ value: DecimalValue?) -> DecimalValue? {
            value.map { converter.weight($0, storedUnit: set.unit).value }
        }
        return ShareReportSetDTO(
            orderIndex: UInt32(index),
            recordMode: mode,
            weightValue: convert(set.weightValue),
            repetitionCount: set.repetitionCount,
            durationSeconds: set.durationSeconds,
            unit: set.unit,
            side: set.side,
            leftValue: convert(set.leftValue),
            rightValue: convert(set.rightValue),
            distanceValue: set.distanceValue,
            speedValue: set.speedValue,
            resistanceValue: set.resistanceValue
        )
    }
}
