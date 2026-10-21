import SwiftUI

/// D-b: one read-only composition shared by the summary and coach history.
struct SessionGainsSectionView: View {
    let gains: SessionGains

    var body: some View {
        if !gains.isEmpty {
            VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                FCSectionLabel(String(localized: "session.gains.title"))
                VStack(spacing: 0) {
                    ForEach(Array(gains.records.enumerated()), id: \.offset) { index, record in
                        if index > 0 { FCListRowDivider() }
                        PersonalBestRowView(
                            name: record.displayName, kind: SessionGainsPresentation.kind(record.kind),
                            value: SessionGainsPresentation.value(record), day: nil,
                            detail: record.kind == .mostRepsAtWeight ? record.set.displaySummary : nil,
                            allowsValueWrapping: true)
                    }
                    ForEach(Array(gains.progress.enumerated()), id: \.offset) { index, progress in
                        if index > 0 || !gains.records.isEmpty { FCListRowDivider() }
                        FCListRow(
                            title: progress.displayName,
                            subtitle: SessionGainsPresentation.progress(
                                previous: progress.previous.displaySummary, current: progress.current.displaySummary))
                    }
                    if let number = gains.milestoneSessionNumber {
                        if !gains.records.isEmpty || !gains.progress.isEmpty { FCListRowDivider() }
                        FCListRow(
                            title: SessionGainsPresentation.milestone(number),
                            subtitle: String(localized: "session.gains.milestone.subtitle"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum SessionGainsPresentation {
    static func kind(_ kind: SessionGains.RecordKind) -> String {
        switch kind {
        case .mostRepsAtWeight, .highestWeight: return String(localized: "history.pb.highestWeight")
        case .longestDuration: return String(localized: "history.pb.longestDuration")
        case .longestDistance: return String(localized: "history.pb.longestDistance")
        }
    }

    static func value(_ record: SessionGains.Record) -> String {
        switch record.kind {
        case .mostRepsAtWeight, .highestWeight: return "\(record.set.weightValue?.canonicalString ?? "-") kg"
        case .longestDuration:
            return DurationTextParser.formatForEditing(secondsText: record.set.durationSeconds?.canonicalString ?? "0")
        case .longestDistance: return "\(record.set.distanceValue?.canonicalString ?? "-") km"
        }
    }

    static func progress(previous: String, current: String) -> String {
        String(format: String(localized: "session.gains.progress.format"), previous, current)
    }

    static func milestone(_ number: Int) -> String {
        String(format: String(localized: "session.gains.milestone.format"), Int64(number))
    }
}

#if DEBUG
    #Preview("三类收获") {
        SessionGainsSectionView(gains: try! previewGains(includeExercises: true))
            .padding(FCPrimitives.space4)
    }
    #Preview("只有里程碑") {
        SessionGainsSectionView(gains: try! previewGains(includeExercises: false))
            .padding(FCPrimitives.space4)
    }

    private func previewGains(includeExercises: Bool) throws -> SessionGains {
        let student = StableUUID(UUID())
        func completed(_ number: Int) throws -> CompletedSession {
            let date = Date(timeIntervalSince1970: Double(number * 1000))
            let id = StableUUID(UUID())
            let exercises: [SessionExercise] =
                try includeExercises
                ? (0..<2).map { index in
                    let exerciseID = StableUUID(UUID())
                    let weight = index == 0 ? (number == 10 ? "85" : "80") : (number == 1 ? "100" : "80")
                    let set = try TrainingSet.makeDraft(
                        id: StableUUID(UUID()), sessionExerciseID: exerciseID, orderIndex: 0,
                        input: TrainingSetInput(
                            recordMode: .weightReps, weightValue: weight,
                            repetitionCount: number == 10 ? "7" : "5", unit: .kilograms), now: date
                    )
                    .confirmed(now: date)
                    return SessionExercise(
                        id: exerciseID, sessionID: id, orderIndex: UInt32(index), sourceKind: .builtIn,
                        sourceID: StableExerciseID(rawValue: "fictional.preview.\(index)"),
                        displayNameSnapshot: try NormalizedName("合成动作 \(index + 1)"), recordModeSnapshot: .weightReps,
                        actionPrivateNote: nil, sets: [set])
                } : []
            return CompletedSession(
                id: id, studentID: student, studentDisplayName: try NormalizedName("合成学员"),
                startedAtUTC: date, completedAtUTC: date, trainingFocus: [],
                notes: SessionNotes(privateCoachNote: nil, studentFacingSummary: nil, actionPrivateNotes: [:]),
                exercises: exercises,
                statistics: SessionStatistics(
                    completedSetCount: exercises.count, displayedDurationSeconds: .zero,
                    ordinaryTrainingVolume: nil), revision: 1, latestReport: nil)
        }
        return try SessionGains(current: completed(10), history: (1..<10).map(completed))
    }
#endif
