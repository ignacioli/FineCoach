import SwiftUI

/// D-b: one read-only composition shared by the summary and coach history.
/// Revision 1.5 (C16): one "上次 … → 本次 …" row per action; a record action
/// carries the 「新纪录」 badge on that same row and never gets a second row.
struct SessionGainsSectionView: View {
    let gains: SessionGains

    var body: some View {
        if !gains.isEmpty {
            VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                FCSectionLabel(String(localized: "session.gains.title"))
                VStack(spacing: 0) {
                    ForEach(Array(gains.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { FCListRowDivider() }
                        FCListRow(
                            title: row.displayName,
                            subtitle: SessionGainsPresentation.progress(
                                previous: row.previous.displaySummary, current: row.current.displaySummary),
                            showsDisclosure: false,
                            showsNewRecordBadge: row.isNewRecord)
                    }
                    if let number = gains.milestoneSessionNumber {
                        if !gains.rows.isEmpty { FCListRowDivider() }
                        FCListRow(
                            title: SessionGainsPresentation.milestone(number),
                            subtitle: String(localized: "session.gains.milestone.subtitle"), showsDisclosure: false)
                    }
                    if let weeks = gains.attendanceStreakWeeks {
                        if !gains.rows.isEmpty || gains.milestoneSessionNumber != nil { FCListRowDivider() }
                        FCListRow(
                            title: SessionGainsPresentation.streak(weeks),
                            subtitle: String(localized: "session.gains.streak.subtitle"), showsDisclosure: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum SessionGainsPresentation {
    static func streak(_ weeks: Int) -> String {
        String(format: String(localized: "session.gains.streak.format"), Int64(weeks))
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
