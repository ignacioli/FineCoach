import SwiftUI
import UIKit

struct ActiveSessionView: View {
    @StateObject private var viewModel: ActiveSessionViewModel
    @Binding var path: [RootDestination]
    @State private var didPushSummary = false

    init(
        studentID: StableUUID,
        useCases: ActiveSessionUseCases,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: ActiveSessionViewModel(
                studentID: studentID,
                useCases: useCases
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                SaveStatusView(status: viewModel.saveStatus) {
                    Task { await viewModel.retrySave() }
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                if viewModel.session?.state == .completed {
                    Label(String(localized: "session.status.completed"), systemImage: "checkmark.circle.fill")
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionCompletedStatus)
                } else if viewModel.session?.state == .abandonedEmpty {
                    Text(String(localized: "session.status.abandoned"))
                }

                Text(viewModel.statsText)
                    .font(.headline)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionStats)

                if let session = viewModel.session, session.exercises.isEmpty, session.state == .inProgress {
                    Text(String(localized: "session.empty.hint"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionEmptyHint)
                }

                if let session = viewModel.session {
                    ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseCard(exercise, index: index)
                    }
                }

                if viewModel.isAddingExercise {
                    QuickCreateExerciseFlow(viewModel: viewModel)
                } else if viewModel.session?.state == .inProgress {
                    FCButton(title: String(localized: "session.action.addExercise")) {
                        viewModel.isAddingExercise = true
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionAddExercise)
                }
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.session?.state == .inProgress {
                FCButton(
                    title: String(localized: "session.action.finish"),
                    isEnabled: viewModel.canCompleteSession
                ) {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                    viewModel.requestFinish()
                }
                .padding(.horizontal, FCPrimitives.spacingMedium)
                .padding(.bottom, FCPrimitives.spacingSmall)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionFinish)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.background)
        .navigationTitle(String(localized: "session.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onChange(of: viewModel.session?.state) { _, state in
            guard state == .completed, !didPushSummary, let sessionID = viewModel.session?.id else {
                return
            }
            didPushSummary = true
            path.append(.sessionSummary(sessionID.rawValue))
        }
        .accessibilityIdentifier(FCAccessibilityID.activeSessionRoot)
        .fullScreenCover(item: $viewModel.presentedSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .finish(let gate):
                    FinishSessionFlow(
                        gate: gate,
                        onAbandon: {
                            Task {
                                await viewModel.abandon()
                                path.removeAll()
                            }
                        },
                        onDiscard: { Task { await viewModel.discardDraftsAndFinish() } },
                        onReturn: { viewModel.returnToDrafts() }
                    )
                case .deleteExercise(let exerciseID):
                    if let exercise = viewModel.session?.exercises.first(where: { $0.id == exerciseID }) {
                        DeleteExerciseFlow(
                            exercise: exercise,
                            onCancel: { viewModel.returnToDrafts() },
                            onConfirm: { Task { await viewModel.confirmDeleteExercise() } }
                        )
                    } else {
                        Color.clear.onAppear { viewModel.returnToDrafts() }
                    }
                case .durationReview:
                    DurationReviewFlow(
                        elapsedSeconds: viewModel.session?.elapsedSeconds.canonicalString ?? "0",
                        onCancel: { viewModel.returnToDrafts() },
                        onConfirm: { seconds in
                            Task { await viewModel.confirmDurationReview(seconds) }
                        }
                    )
                }
            }
        }
    }

    private func exerciseCard(_ exercise: SessionExercise, index: Int) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            Button {
                viewModel.selectExercise(exercise.id)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(exercise.displayNameSnapshot.value)
                            .font(.headline)
                        Text(modeTitle(exercise.recordModeSnapshot))
                            .font(.footnote)
                            .foregroundStyle(FCSemanticColors.secondaryText)
                    }
                    Spacer()
                    if viewModel.selectedExerciseID == exercise.id {
                        Image(systemName: "checkmark")
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier(FCAccessibilityID.exerciseAt(index))
            .accessibilityLabel(
                "\(exercise.displayNameSnapshot.value)，\(modeTitle(exercise.recordModeSnapshot))"
            )
            .accessibilityAddTraits(
                viewModel.selectedExerciseID == exercise.id ? [.isSelected] : []
            )

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, trainingSet in
                FCSetRow(
                    title: setTitle(trainingSet, index: setIndex),
                    value: setValue(trainingSet),
                    state: rowState(trainingSet.state)
                )
                .accessibilityIdentifier(FCAccessibilityID.setAt(setIndex))
                .accessibilityAddTraits(.updatesFrequently)
                .background {
                    Text(trainingSet.state.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier(FCAccessibilityID.setState(trainingSet.state))
                }
            }

            if viewModel.selectedExerciseID == exercise.id, viewModel.session?.state == .inProgress {
                HStack(spacing: FCPrimitives.spacingSmall) {
                    Button(String(localized: "session.action.moveUp")) {
                        Task { await viewModel.moveExercise(offset: -1) }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionMoveUp)

                    Button(String(localized: "session.action.moveDown")) {
                        Task { await viewModel.moveExercise(offset: 1) }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionMoveDown)

                    Button(String(localized: "session.action.deleteExercise")) {
                        viewModel.requestDeleteExercise()
                    }
                    .frame(minHeight: 44)
                    .foregroundStyle(FCSemanticColors.destructive)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionDeleteExercise)
                }
                SetEditor(viewModel: viewModel, exercise: exercise)
            }
        }
        .padding(FCPrimitives.spacingSmall)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
    }

    private func modeTitle(_ mode: RecordMode) -> String {
        switch mode {
        case .weightReps: return String(localized: "session.mode.weightReps")
        case .reps: return String(localized: "session.mode.reps")
        case .duration: return String(localized: "session.mode.duration")
        case .cardio: return String(localized: "session.mode.cardio")
        }
    }

    private func rowState(_ state: SetRecordingState) -> FCSetRow.State {
        switch state {
        case .draft: return .draft
        case .pending: return .pending
        case .completed: return .completed
        }
    }

    private func setTitle(_ set: TrainingSet, index: Int) -> String {
        "\(String(localized: "session.set.label")) \(index + 1)"
    }

    private func setValue(_ set: TrainingSet) -> String {
        switch set.recordMode {
        case .weightReps:
            return "\(set.weightValue?.canonicalString ?? "-") × \(set.repetitionCount?.canonicalString ?? "-")"
        case .reps:
            return set.repetitionCount?.canonicalString ?? "-"
        case .duration:
            return set.durationSeconds?.canonicalString ?? "-"
        case .cardio:
            return "\(set.durationSeconds?.canonicalString ?? "-")s / \(set.distanceValue?.canonicalString ?? "-")"
        }
    }

}
