import SwiftUI
import UIKit

/// 11 训练中 (T069h; `30-training-v2`, `31-add-exercise-sheet`, D8 variant
/// B): titleEmphasis "训练中", "学员 · 部位" with a running clock, flat
/// exercise blocks (equipment icon + exerciseTitle), set rows, then the two
/// link buttons "＋ 添加动作" (sheet with 动作库 / 从模板 tabs — 应用模板 now
/// lives there) and "＋ 新建分区" (in-place sheet). 另存为模板 moved to the
/// post-training summary (FR-017 works on a completed session).
struct ActiveSessionView: View {
    private enum AddTab {
        case library
        case template
    }

    @StateObject private var viewModel: ActiveSessionViewModel
    @Binding var path: [RootDestination]
    @State private var didPushSummary = false
    @State private var addTab: AddTab = .library
    @State private var isCreatingSection = false
    @State private var studentName = ""
    private let sessionUseCases: ActiveSessionUseCases
    private let templateUseCases: TemplateUseCases?
    private let studentUseCases: StudentUseCases?
    /// The per-Exercise sets live in a non-scrolling `List` (native
    /// `.swipeActions` only works inside a `List`), and a `List` nested in a
    /// `ScrollView` needs an explicit height. Each row reports its measured
    /// height here (including an open set editor), and the list is sized to
    /// their sum, so there is no blank gap after an edited set (owner
    /// walkthrough 2026-09-27; the old fixed +460pt editor estimate left
    /// one). The scaled values below are only the first-frame fallback for
    /// a row not yet measured.
    @State private var measuredSetRowHeights: [StableUUID: CGFloat] = [:]
    @ScaledMetric private var setRowHeight: CGFloat = 76
    @ScaledMetric private var setEditorExtraHeight: CGFloat = 460

    init(
        studentID: StableUUID,
        useCases: ActiveSessionUseCases,
        templateUseCases: TemplateUseCases? = nil,
        studentUseCases: StudentUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        self.sessionUseCases = useCases
        self.templateUseCases = templateUseCases
        self.studentUseCases = studentUseCases
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
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                header
                SaveStatusView(status: viewModel.saveStatus) {
                    Task { await viewModel.retrySave() }
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if viewModel.session?.state == .completed {
                    Label(String(localized: "session.status.completed"), systemImage: "checkmark.circle.fill")
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionCompletedStatus)
                } else if viewModel.session?.state == .abandonedEmpty {
                    Text(String(localized: "session.status.abandoned"))
                }

                if let session = viewModel.session, session.exercises.isEmpty, session.state == .inProgress {
                    Text(String(localized: "session.empty.hint"))
                        .fcFont(.callout, weight: .regular)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionEmptyHint)
                }

                if let session = viewModel.session {
                    ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                        sectionHeaderIfNeeded(before: exercise, in: session, at: index)
                        exerciseCard(exercise, index: index)
                    }
                }

                if viewModel.session?.state == .inProgress {
                    HStack(spacing: FCPrimitives.space6) {
                        FCLinkButton(title: String(localized: "session.action.addExerciseLink")) {
                            addTab = .library
                            viewModel.isAddingExercise = true
                        }
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionAddExercise)
                        FCLinkButton(title: String(localized: "activeSession.action.createSectionLink")) {
                            isCreatingSection = true
                        }
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionCreateSection)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
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
                .padding(.horizontal, FCPrimitives.space4)
                .padding(.vertical, FCPrimitives.space2)
                .background(FCSemanticColors.surfacePage)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionFinish)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .fcBottomSheet(isPresented: $viewModel.isAddingExercise) {
            addExerciseSheet
        }
        .fcBottomSheet(isPresented: $isCreatingSection) {
            createSectionSheet
        }
        .task {
            await viewModel.load()
            if let studentUseCases, let student = try? await studentUseCases.student(id: viewModel.studentID) {
                studentName = student.displayName.value
            }
        }
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
        .accessibilityElement(children: .contain)
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
            .fcPrivacyCovered()
        }
    }

    private func exerciseCard(_ exercise: SessionExercise, index: Int) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            Button {
                viewModel.selectExercise(exercise.id)
            } label: {
                HStack(spacing: FCPrimitives.space2) {
                    // T065 / §7.1: 24×24, name starts 8pt after it; none for
                    // custom exercises or unmapped equipment.
                    if let icon = exercise.sourceID.flatMap({ FCEquipmentIcon.icon(forExerciseID: $0.rawValue) }) {
                        FCEquipmentIconView(icon)
                    }
                    Text(exercise.displayNameSnapshot.value)
                        .fcFont(.exerciseTitle)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    Spacer(minLength: FCPrimitives.space2)
                    Text(modeTitle(exercise.recordModeSnapshot))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                    if viewModel.selectedExerciseID == exercise.id {
                        FCSymbol(.check)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                            .listRowBackground(FCSemanticColors.surfacePage)
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
                HStack(spacing: FCPrimitives.space4) {
                    FCLinkButton(title: String(localized: "session.action.moveUp")) {
                        Task { await viewModel.moveExercise(offset: -1) }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionMoveUp)

                    FCLinkButton(title: String(localized: "session.action.moveDown")) {
                        Task { await viewModel.moveExercise(offset: 1) }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionMoveDown)

                    Button {
                        viewModel.requestDeleteExercise()
                    } label: {
                        Text(String(localized: "session.action.deleteExercise"))
                            .fcFont(.callout, weight: .semibold)
                            .foregroundStyle(FCSemanticColors.statusDestructive)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionDeleteExercise)

                    Menu {
                        Button(String(localized: "activeSession.unsectioned")) {
                            Task { await viewModel.moveExercise(exercise.id, toSectionID: nil) }
                        }
                        ForEach(viewModel.orderedSections) { section in
                            Button(section.name.value) {
                                Task { await viewModel.moveExercise(exercise.id, toSectionID: section.id) }
                            }
                        }
                    } label: {
                        Text(String(localized: "activeSession.moveToSection"))
                            .fcFont(.callout, weight: .semibold)
                            .foregroundStyle(FCSemanticColors.actionPrimary)
                            .frame(minHeight: 44)
                    }
                }
                SetEditor(viewModel: viewModel, exercise: exercise)
            }
            FCListRowDivider()
        }
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
                FCSectionLabel(section.name.value)
                Spacer()
                if viewModel.session?.state == .inProgress {
                    Button {
                        viewModel.requestDeleteSection(section)
                    } label: {
                        Text(String(localized: "activeSession.deleteSection"))
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.statusDestructive)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionSectionHeader(section.id))
        }
    }

    // MARK: Header (30)

    private var header: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            Text(String(localized: "session.title"))
                .fcFont(.titleEmphasis)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline) {
                Text(TodayRowPresentation.nameAndFocus(studentName, viewModel.session?.trainingFocus ?? []))
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                Spacer(minLength: FCPrimitives.space2)
                if let session = viewModel.session, session.state == .inProgress {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(ActiveSessionClock.text(from: session.startedAtUTC, to: context.date))
                            .fcFont(.headline)
                            .monospacedDigit()
                            .foregroundStyle(FCSemanticColors.textPrimary)
                    }
                    .accessibilityLabel(Text("session.clock.a11y"))
                }
            }
            Text(viewModel.statsText)
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionStats)
        }
    }

    // MARK: Sheets (31, 新建分区)

    private var addExerciseSheet: some View {
        FCBottomSheet(title: String(localized: "session.action.addExercise")) {
            VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                if templateUseCases != nil {
                    HStack(spacing: FCPrimitives.space2) {
                        FCFilterChip(title: String(localized: "session.add.tabLibrary"), isSelected: addTab == .library) {
                            addTab = .library
                        }
                        FCFilterChip(title: String(localized: "session.add.tabTemplate"), isSelected: addTab == .template) {
                            addTab = .template
                        }
                        .accessibilityIdentifier(FCAccessibilityID.activeSessionApplyTemplate)
                    }
                }
                ScrollView {
                    if addTab == .template, let templateUseCases {
                        TemplatePickList(templateUseCases: templateUseCases, sessionUseCases: sessionUseCases) {
                            viewModel.isAddingExercise = false
                            Task { await viewModel.load() }
                        }
                    } else {
                        QuickCreateExerciseFlow(viewModel: viewModel)
                    }
                }
                .frame(maxHeight: 460)
            }
        }
    }

    private var createSectionSheet: some View {
        FCBottomSheet(title: String(localized: "activeSession.action.createSection")) {
            VStack(spacing: FCPrimitives.space3) {
                FCTextField(String(localized: "activeSession.sectionNamePrompt"), text: $viewModel.newSectionName)
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionSectionName)
                FCButton(
                    title: String(localized: "activeSession.action.createSection"),
                    isEnabled: !viewModel.newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task {
                        await viewModel.createSection()
                        isCreatingSection = false
                    }
                }
            }
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
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
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
                    .fcFont(.caption)
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier(FCAccessibilityID.setState(trainingSet.state))
            }

            if viewModel.editingSetID == trainingSet.id {
                SetEditor(viewModel: viewModel, exercise: exercise, targetSetID: trainingSet.id)
                    .padding(.bottom, FCPrimitives.space2)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            measuredSetRowHeights[trainingSet.id] = height
        }
    }

    /// Sum of the measured row heights (see `measuredSetRowHeights`); a
    /// row not measured yet falls back to the scaled estimate.
    private func setsListHeight(for exercise: SessionExercise) -> CGFloat {
        exercise.sets.reduce(0) { total, trainingSet in
            if let measured = measuredSetRowHeights[trainingSet.id] {
                return total + measured
            }
            let isEditing = trainingSet.id == viewModel.editingSetID
            return total + setRowHeight + (isEditing ? setEditorExtraHeight : 0)
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
        set.displaySummary
    }

}

/// "32:00" / "1:02:03" since the session started (display only; the
/// persisted duration and its review rules are unchanged).
enum ActiveSessionClock {
    static func text(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
