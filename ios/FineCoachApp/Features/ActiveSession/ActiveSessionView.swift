import SwiftUI
import UIKit

struct ActiveSessionView: View {
    @StateObject private var viewModel: ActiveSessionViewModel
    @Binding var path: [RootDestination]
    @State private var didPushSummary = false
    /// Estimated per-row height for the non-scrolling `List` embedded under
    /// each Exercise (needed so native `.swipeActions` works -- that
    /// modifier only has an effect inside a `List`, and a `List` nested in
    /// a `ScrollView` must be given an explicit height). Scales with
    /// Dynamic Type; deliberately generous so growing content is never
    /// clipped -- worst case is a little extra blank space, verified by a
    /// human on-device per this repo's UI acceptance rules, not by an
    /// automated screenshot loop.
    @ScaledMetric private var setRowHeight: CGFloat = 76
    @ScaledMetric private var setEditorExtraHeight: CGFloat = 460

    init(
        studentID: StableUUID,
        useCases: ActiveSessionUseCases,
        templateUseCases: TemplateUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: ActiveSessionViewModel(
                studentID: studentID,
                useCases: useCases,
                templateUseCases: templateUseCases
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
                        sectionHeaderIfNeeded(before: exercise, in: session, at: index)
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

                if viewModel.session?.state == .inProgress {
                    Divider()
                    templateAndSectionControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "session.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .confirmationDialog(
            String(localized: "activeSession.deleteSection"),
            isPresented: Binding(
                get: { viewModel.pendingSectionDeletion != nil },
                set: { if !$0 { viewModel.pendingSectionDeletion = nil } }
            ),
            presenting: viewModel.pendingSectionDeletion
        ) { section in
            Button(String(localized: "templateEditor.deleteSection.moveOut")) {
                Task { await viewModel.deleteSection(section, disposition: .moveExercisesTo(sectionID: nil)) }
            }
            Button(String(localized: "templateEditor.deleteSection.deleteExercises"), role: .destructive) {
                Task { await viewModel.deleteSection(section, disposition: .deleteWithExercises) }
            }
        }
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
                HStack(spacing: FCPrimitives.space2) {
                    // T065 / §7.1: 24×24, name starts 8pt after it; none for
                    // custom exercises or unmapped equipment.
                    if let icon = exercise.sourceID.flatMap({ FCEquipmentIcon.icon(forExerciseID: $0.rawValue) }) {
                        FCEquipmentIconView(icon)
                    }
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

            if !exercise.sets.isEmpty {
                List {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, trainingSet in
                        setRow(trainingSet, index: setIndex, in: exercise)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(FCSemanticColors.elevatedSurface)
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: trainingSet.state != .completed
                            ) {
                                Button(role: .destructive) {
                                    Task { await viewModel.removeSet(setID: trainingSet.id) }
                                } label: {
                                    Label(String(localized: "session.action.deleteSet"), systemImage: "trash")
                                }
                                .accessibilityIdentifier(FCAccessibilityID.setDeleteAt(setIndex))
                            }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 44)
                .frame(height: setsListHeight(for: exercise))
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

                    Menu(String(localized: "activeSession.moveToSection")) {
                        Button(String(localized: "activeSession.unsectioned")) {
                            Task { await viewModel.moveExercise(exercise.id, toSectionID: nil) }
                        }
                        ForEach(viewModel.orderedSections) { section in
                            Button(section.name.value) {
                                Task { await viewModel.moveExercise(exercise.id, toSectionID: section.id) }
                            }
                        }
                    }
                    .frame(minHeight: 44)
                }
                SetEditor(viewModel: viewModel, exercise: exercise)
            }
        }
        .padding(FCPrimitives.spacingSmall)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
    }

    /// Shows a Section header immediately before the first Exercise that
    /// belongs to it (M1B-FR-020/021: unsectioned Exercises and Sections
    /// coexist with an unambiguous combined order -- `session.exercises` is
    /// already sorted by the unified `orderIndex` axis, so this only needs
    /// to detect the boundary where `sectionID` changes).
    @ViewBuilder
    private func sectionHeaderIfNeeded(before exercise: SessionExercise, in session: Session, at index: Int) -> some View {
        let previousSectionID = index > 0 ? session.exercises[index - 1].sectionID : nil
        if let sectionID = exercise.sectionID, sectionID != previousSectionID,
            let section = viewModel.sections.first(where: { $0.id == sectionID })
        {
            HStack {
                Text(section.name.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FCSemanticColors.secondaryText)
                Spacer()
                if viewModel.session?.state == .inProgress {
                    Button(String(localized: "activeSession.deleteSection")) {
                        viewModel.requestDeleteSection(section)
                    }
                    .frame(minHeight: 44)
                    .foregroundStyle(FCSemanticColors.destructive)
                }
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionSectionHeader(section.id))
        }
    }

    private var templateAndSectionControls: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            FCTextField(String(localized: "activeSession.sectionNamePrompt"), text: $viewModel.newSectionName)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionSectionName)
            FCButton(title: String(localized: "activeSession.action.createSection")) {
                Task { await viewModel.createSection() }
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionCreateSection)

            if viewModel.isSavingAsTemplate {
                FCTextField(
                    String(localized: "activeSession.saveAsTemplateNamePrompt"),
                    text: $viewModel.saveAsTemplateName
                )
                .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveAsTemplateName)
                FCButton(title: String(localized: "activeSession.saveAsTemplateConfirm")) {
                    Task { await viewModel.saveAsTemplate() }
                }
                .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveAsTemplateConfirm)
            } else {
                Button(String(localized: "activeSession.action.saveAsTemplate")) {
                    viewModel.isSavingAsTemplate = true
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionSaveAsTemplate)
            }

            Button(String(localized: "activeSession.action.applyTemplate")) {
                path.append(.applyTemplate)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier(FCAccessibilityID.activeSessionApplyTemplate)
        }
    }

    private func modeTitle(_ mode: RecordMode) -> String {
        switch mode {
        case .weightReps: return String(localized: "session.mode.weightReps")
        case .reps: return String(localized: "session.mode.reps")
        case .duration: return String(localized: "session.mode.duration")
        case .cardio: return String(localized: "session.mode.cardio")
        }
    }

    @ViewBuilder
    private func setRow(_ trainingSet: TrainingSet, index: Int, in exercise: SessionExercise) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            FCSetRow(
                title: setTitle(trainingSet, index: index),
                value: setValue(trainingSet),
                state: rowState(trainingSet.state),
                onConfirm: trainingSet.state == .completed
                    ? nil
                    : { Task { await viewModel.confirmSet(setID: trainingSet.id) } },
                onEdit: { viewModel.beginEditingSet(trainingSet) }
            )
            .accessibilityIdentifier(FCAccessibilityID.setAt(index))
            .accessibilityAddTraits(.updatesFrequently)
            .background {
                Text(trainingSet.state.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier(FCAccessibilityID.setState(trainingSet.state))
            }

            if viewModel.editingSetID == trainingSet.id {
                SetEditor(viewModel: viewModel, exercise: exercise, targetSetID: trainingSet.id)
                    .padding(.bottom, FCPrimitives.spacingSmall)
            }
        }
    }

    /// See the `setRowHeight`/`setEditorExtraHeight` doc comment -- a
    /// deliberately generous, Dynamic-Type-scaled estimate for the
    /// non-scrolling per-Exercise sets `List`.
    private func setsListHeight(for exercise: SessionExercise) -> CGFloat {
        let base = CGFloat(exercise.sets.count) * setRowHeight
        let isEditingHere = exercise.sets.contains { $0.id == viewModel.editingSetID }
        return base + (isEditingHere ? setEditorExtraHeight : 0)
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
        set.displaySummary
    }

}
