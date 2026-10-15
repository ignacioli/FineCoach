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
    @ScaledMetric private var setRowHeight: CGFloat = 52
    @ScaledMetric private var exerciseHeaderHeight: CGFloat = 52
    /// The exercise whose row swipe asked to move it to a section (P0-D13).
    @State private var movingExerciseID: StableUUID?
    @ScaledMetric private var setEditorExtraHeight: CGFloat = 460
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        studentID: StableUUID,
        useCases: ActiveSessionUseCases,
        templateUseCases: TemplateUseCases? = nil,
        studentUseCases: StudentUseCases? = nil,
        creditSettlement: SessionCreditSettlement? = nil,
        notifications: (any LocalNotificationScheduling)? = RestEndNotification.scheduler(),
        path: Binding<[RootDestination]>
    ) {
        self.sessionUseCases = useCases
        self.templateUseCases = templateUseCases
        self.studentUseCases = studentUseCases
        _viewModel = StateObject(
            wrappedValue: ActiveSessionViewModel(
                studentID: studentID,
                useCases: useCases,
                templateUseCases: templateUseCases,
                creditSettlement: creditSettlement,
                notifications: notifications
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
                VStack(spacing: FCPrimitives.space2) {
                    if let restTimer = viewModel.restTimer {
                        RestTimerBar(
                            timer: restTimer,
                            onAdjust: { viewModel.adjustRest(by: $0) },
                            onSkip: { viewModel.dismissRest() },
                            onDismiss: { viewModel.dismissRest() }
                        )
                        .transition(restBarTransition)
                    }
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
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionFinish)
                }
                .padding(.horizontal, FCPrimitives.space4)
                .padding(.vertical, FCPrimitives.space2)
                .animation(.easeInOut(duration: 0.25), value: viewModel.restTimer != nil)
                .background(FCSemanticColors.surfacePage)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
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
        .confirmationDialog(
            String(localized: "activeSession.moveToSection"),
            isPresented: Binding(
                get: { movingExerciseID != nil },
                set: { if !$0 { movingExerciseID = nil } }
            ),
            presenting: movingExerciseID
        ) { exerciseID in
            Button(String(localized: "activeSession.unsectioned")) {
                Task { await viewModel.moveExercise(exerciseID, toSectionID: nil) }
            }
            ForEach(viewModel.orderedSections) { section in
                Button(section.name.value) {
                    Task { await viewModel.moveExercise(exerciseID, toSectionID: section.id) }
                }
            }
        }
        .onChange(of: viewModel.session?.state) { _, _ in
            pushSummaryIfReady()
        }
        .fcConfirmationDialog(isPresented: creditPromptPresented) {
            creditDialog(viewModel.creditPrompt)
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

    /// The summary is pushed once the Session is completed and any credit
    /// question (M1B-FR-013/014) has been answered.
    private func pushSummaryIfReady(then next: RootDestination? = nil) {
        guard viewModel.session?.state == .completed, viewModel.creditPrompt == nil, !didPushSummary,
            let sessionID = viewModel.session?.id
        else {
            return
        }
        didPushSummary = true
        path.append(.sessionSummary(sessionID.rawValue))
        if let next {
            path.append(next)
        }
    }

    /// Tapping the scrim is the same as "不扣课": nothing is written.
    private var creditPromptPresented: Binding<Bool> {
        Binding(
            get: { viewModel.creditPrompt != nil },
            set: { isPresented in
                guard !isPresented else { return }
                viewModel.skipCreditDebit()
                pushSummaryIfReady()
            }
        )
    }

    private func creditDialog(_ prompt: SessionCreditPrompt?) -> FCConfirmationDialog {
        let skip = FCConfirmationDialog.Action(title: String(localized: "sessionCredit.skip")) {
            viewModel.skipCreditDebit()
            pushSummaryIfReady()
        }
        guard let prompt else {
            return FCConfirmationDialog(title: "", message: "", cancelAction: skip, confirmAction: skip)
        }
        let packageName = prompt.package.displayName
        let noticeMessage = String(format: String(localized: "sessionCredit.notice.messageFormat"), packageName)
        let adjust = FCConfirmationDialog.Action(title: String(localized: "sessionCredit.adjust")) {
            let packageID = prompt.package.id
            viewModel.skipCreditDebit()
            pushSummaryIfReady(then: .manualCreditAdjustment(packageID.rawValue))
        }
        switch prompt {
        case .adhocChoice(_, let balance):
            return FCConfirmationDialog(
                title: String(localized: "sessionCredit.adhoc.title"),
                message: String(
                    format: String(localized: "sessionCredit.adhoc.messageFormat"),
                    packageName,
                    "\(balance)"
                ),
                cancelAction: skip,
                confirmAction: .init(title: String(localized: "sessionCredit.adhoc.debit")) {
                    Task {
                        if await viewModel.debitAdhocSession() {
                            pushSummaryIfReady()
                        }
                    }
                }
            )
        case .unusable(_, .expired):
            return FCConfirmationDialog(
                title: String(localized: "sessionCredit.expired.title"),
                message: noticeMessage,
                cancelAction: skip,
                confirmAction: adjust
            )
        case .unusable(_, .insufficientBalance):
            return FCConfirmationDialog(
                title: String(localized: "sessionCredit.insufficient.title"),
                message: noticeMessage,
                cancelAction: skip,
                confirmAction: adjust
            )
        case .failed:
            return FCConfirmationDialog(
                title: String(localized: "sessionCredit.failed.title"),
                message: noticeMessage,
                cancelAction: skip,
                confirmAction: adjust
            )
        }
    }

    private func exerciseCard(_ exercise: SessionExercise, index: Int) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            // The header and the sets share one non-scrolling `List` so the
            // header can carry the row swipe (P0-D10, P0-D13): delete and
            // move-to-section replace the old always-visible action row.
            List {
                exerciseHeader(exercise, index: index)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(FCSemanticColors.surfacePage)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                        measuredSetRowHeights[exercise.id] = height
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        exerciseSwipeActions(exercise)
                    }
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
            .frame(height: listHeight(for: exercise))

            if viewModel.selectedExerciseID == exercise.id, viewModel.session?.state == .inProgress {
                SetEditor(viewModel: viewModel, exercise: exercise)
            }
            FCListRowDivider()
        }
    }

    @ViewBuilder
    private func exerciseSwipeActions(_ exercise: SessionExercise) -> some View {
        if viewModel.session?.state == .inProgress {
            Button(role: .destructive) {
                viewModel.requestDeleteExercise(exercise.id)
            } label: {
                Label(String(localized: "session.action.deleteExercise"), systemImage: "trash")
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionDeleteExercise)
            if !viewModel.orderedSections.isEmpty {
                Button {
                    movingExerciseID = exercise.id
                } label: {
                    Label(String(localized: "activeSession.moveToSection"), systemImage: "folder")
                }
                .tint(FCSemanticColors.textSecondary)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionMoveToSection)
            }
        }
    }

    private func exerciseHeader(_ exercise: SessionExercise, index: Int) -> some View {
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
                exerciseTrailingCaption(exercise, index: index)
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
            "\(exercise.displayNameSnapshot.value)，\(exerciseTrailingTitle(exercise))"
        )
        .accessibilityAddTraits(
            viewModel.selectedExerciseID == exercise.id ? [.isSelected] : []
        )
    }

    /// Shows a Section header immediately before the first Exercise that
    /// belongs to it (M1B-FR-020/021: unsectioned Exercises and Sections
    /// coexist with an unambiguous combined order -- `session.exercises` is
    /// already sorted by the unified `orderIndex` axis, so this only needs
    /// to detect the boundary where `sectionID` changes).
    @ViewBuilder
    private func sectionHeaderIfNeeded(before exercise: SessionExercise, in session: Session, at index: Int)
        -> some View
    {
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
            // 11/30 use the 22/700 title; the inline back matches every other secondary page
            // (owner 2026-10-10).
            FCPageHeader(title: String(localized: "session.title"), back: .init(), titleStyle: .titleEmphasis)
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
                        FCFilterChip(title: String(localized: "session.add.tabLibrary"), isSelected: addTab == .library)
                        {
                            addTab = .library
                        }
                        FCFilterChip(
                            title: String(localized: "session.add.tabTemplate"), isSelected: addTab == .template
                        ) {
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

    private func exerciseTrailingCaption(_ exercise: SessionExercise, index: Int) -> some View {
        let last = viewModel.lastPerformance(for: exercise)
        return Text(last?.referenceText ?? modeTitle(exercise.recordModeSnapshot))
            .fcFont(.caption)
            .foregroundStyle(FCSemanticColors.textSecondary)
            .lineLimit(1)
            .accessibilityIdentifier(
                last == nil
                    ? FCAccessibilityID.exerciseMode(index)
                    : FCAccessibilityID.exerciseLastReference(index)
            )
    }

    private func exerciseTrailingTitle(_ exercise: SessionExercise) -> String {
        viewModel.lastPerformance(for: exercise)?.referenceText ?? modeTitle(exercise.recordModeSnapshot)
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
                onEdit: { viewModel.beginEditingSet(trainingSet) },
                onUndo: viewModel.undoableSetID == trainingSet.id
                    ? { Task { await viewModel.undoRecentSet() } }
                    : nil
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

    /// Header plus the sum of the measured set-row heights (see
    /// `measuredSetRowHeights`); a row not measured yet falls back to the
    /// scaled estimate.
    private func listHeight(for exercise: SessionExercise) -> CGFloat {
        let header = measuredSetRowHeights[exercise.id] ?? exerciseHeaderHeight
        return exercise.sets.reduce(header) { total, trainingSet in
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
        String(format: String(localized: "session.set.ordinal"), index + 1)
    }

    private func setValue(_ set: TrainingSet) -> String {
        set.displaySummary
    }

    /// P0 motion table: slide up on appear, fade on dismiss. Reduce Motion
    /// keeps the fade and drops the slide.
    private var restBarTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
    }

}

/// The between-sets rest bar (P0-a / P0-b, feature-owned `DS-REST-TIMER`).
/// Sits above 结束训练. Running: caption, countdown, −15 / +15 / 跳过.
/// Finished: "✓ 休息结束，可以开始下一组" and 关闭, then it dismisses itself
/// `finishedHold` seconds after `endsAt`. One `.warning` haptic when it
/// finishes. The countdown rolls with `.numericText` unless Reduce Motion
/// is on.
struct RestTimerBar: View {
    let timer: RestTimerState
    let onAdjust: (TimeInterval) -> Void
    let onSkip: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let finished = timer.isFinished(at: context.date)
            Group {
                if finished {
                    ended
                } else {
                    running(seconds: timer.remainingSeconds(at: context.date))
                }
            }
            .sensoryFeedback(.warning, trigger: finished) { _, isFinished in
                isFinished
            }
        }
        .task(id: timer.endsAt) {
            let delay = timer.autoDismissDelay(at: Date())
            if delay > 0 {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private func running(seconds: Int) -> some View {
        HStack(alignment: .center, spacing: FCPrimitives.space2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "session.rest.title"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                Text(RestTimerState.text(seconds: seconds))
                    .fcFont(.numeralLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .default, value: seconds)
                    .accessibilityLabel(Text(String(localized: "session.rest.title")))
                    .accessibilityValue(Text(RestTimerState.text(seconds: seconds)))
                    .accessibilityIdentifier(FCAccessibilityID.activeSessionRestRemaining)
            }
            Spacer(minLength: FCPrimitives.space2)
            FCLinkButton(title: String(localized: "session.rest.minus")) {
                onAdjust(-RestTimerState.adjustmentStep)
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionRestMinus)
            FCLinkButton(title: String(localized: "session.rest.plus")) {
                onAdjust(RestTimerState.adjustmentStep)
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionRestPlus)
            FCLinkButton(title: String(localized: "session.rest.skip")) {
                onSkip()
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionRestSkip)
        }
        .modifier(RestTimerChrome())
        .accessibilityIdentifier(FCAccessibilityID.activeSessionRest)
    }

    private var ended: some View {
        HStack(alignment: .center, spacing: FCPrimitives.space3) {
            FCSymbol(.check)
            Text(String(localized: "session.rest.ended"))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(FCAccessibilityID.activeSessionRestEnded)
            FCLinkButton(title: String(localized: "session.rest.close")) {
                onDismiss()
            }
            .accessibilityIdentifier(FCAccessibilityID.activeSessionRestClose)
        }
        .modifier(RestTimerChrome())
        .accessibilityIdentifier(FCAccessibilityID.activeSessionRest)
    }
}

/// Shared chrome for both rest-bar states: `surface.canvas`, `radius.lg`,
/// height at least 64, inset `space.4`.
private struct RestTimerChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, FCPrimitives.space4)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: FCPrimitives.radiusLg)
                    .fill(FCSemanticColors.surfaceCanvas)
            )
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
