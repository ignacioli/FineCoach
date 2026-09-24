import SwiftUI

@MainActor
final class StudentDetailViewModel: ObservableObject {
    @Published var student: Student?
    @Published var inProgress = false
    @Published var notesExpanded = false
    @Published var errorMessage: String?
    /// The Student's most recently COMPLETED session, newest-by-`completedAtUTC`
    /// (not array/fetch order -- deliberately re-sorted below). `nil` means
    /// there is genuinely no completed session yet, which keeps
    /// `student.detail.recentPlaceholder` as the correct empty-state copy.
    @Published var mostRecentCompletedSession: CompletedSession?

    let studentID: StableUUID
    let useCases: StudentUseCases
    private let historyUseCases: HistoryUseCases

    init(studentID: StableUUID, useCases: StudentUseCases, historyUseCases: HistoryUseCases) {
        self.studentID = studentID
        self.useCases = useCases
        self.historyUseCases = historyUseCases
    }

    func reload() async {
        do {
            student = try await useCases.student(id: studentID)
            let summary = try await useCases.inProgressTraining()
            inProgress = summary?.studentID == studentID
            let history = try await historyUseCases.listHistory(studentID: studentID)
            mostRecentCompletedSession = CompletedSession.mostRecent(in: history)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func restore() async -> Bool {
        do {
            student = try await useCases.restore(id: studentID)
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
            return false
        }
    }
}

private enum StudentDetailCover: String, Identifiable {
    case archive
    case delete

    var id: String { rawValue }
}

struct StudentDetailView: View {
    @StateObject private var viewModel: StudentDetailViewModel
    @Binding var path: [RootDestination]
    @State private var cover: StudentDetailCover?

    init(
        studentID: StableUUID,
        useCases: StudentUseCases,
        historyUseCases: HistoryUseCases,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: StudentDetailViewModel(
                studentID: studentID,
                useCases: useCases,
                historyUseCases: historyUseCases
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(FCSemanticColors.destructive)
                    .padding()
            }
            if let student = viewModel.student {
                VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                    if viewModel.inProgress {
                        Button {
                            path.append(.activeSession(student.id.rawValue))
                        } label: {
                            banner(title: String(localized: "student.list.trainingBanner"))
                        }
                        .accessibilityIdentifier(FCAccessibilityID.detailContinueTraining)
                    }

                    if student.lifecycle == .archived {
                        Label(String(localized: "student.detail.archived"), systemImage: "archivebox")
                            .accessibilityIdentifier(FCAccessibilityID.detailArchivedStatus)
                        Text(String(localized: "student.detail.archivedHint"))
                            .foregroundStyle(FCSemanticColors.secondaryText)
                        FCButton(title: String(localized: "student.detail.restore")) {
                            Task { _ = await viewModel.restore() }
                        }
                        .accessibilityIdentifier(FCAccessibilityID.detailRestore)
                    } else if !viewModel.inProgress {
                        FCButton(title: String(localized: "student.detail.startTraining")) {
                            path.append(.activeSession(student.id.rawValue))
                        }
                        .accessibilityIdentifier(FCAccessibilityID.detailStartTraining)
                    }

                    if student.lifecycle == .active {
                        Button {
                            cover = .archive
                        } label: {
                            Text(String(localized: "student.detail.archive"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        .accessibilityIdentifier(FCAccessibilityID.detailArchive)
                    }

                    FCButton(title: String(localized: "student.detail.delete")) {
                        cover = .delete
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailDelete)

                    FCButton(title: String(localized: "student.detail.backup")) {
                        path.append(.backupRestore)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailBackup)

                    FCButton(title: String(localized: "student.detail.coursePackages")) {
                        path.append(.coursePackages(student.id.rawValue))
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailCoursePackages)

                    FCButton(title: String(localized: "student.detail.bodyData")) {
                        path.append(.bodyData(student.id.rawValue))
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailBodyData)

                    FCButton(title: String(localized: "student.detail.trends")) {
                        path.append(.trends(student.id.rawValue))
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailTrends)

                    Button {
                        path.append(.history(student.id.rawValue))
                    } label: {
                        summaryCard(
                            kicker: String(localized: "student.detail.recentKicker"),
                            title: recentTrainingTitle
                        )
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailRecentTraining)

                    profile(student)

                    notesFold(student)

                    Button {
                        path.append(.history(student.id.rawValue))
                    } label: {
                        summaryCard(
                            kicker: String(localized: "student.detail.historyKicker"),
                            title: String(localized: "student.detail.historyPlaceholder")
                        )
                    }
                    .accessibilityIdentifier(FCAccessibilityID.detailHistory)
                }
                .padding(FCPrimitives.spacingMedium)
            }
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(viewModel.student?.displayName.value ?? String(localized: "student.list.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "student.detail.edit")) {
                    path.append(.editor(.edit(viewModel.studentID.rawValue)))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("studentDetail.edit")
            }
        }
        .task { await viewModel.reload() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
        .fullScreenCover(item: $cover) { item in
            NavigationStack {
                if item == .archive {
                    ArchiveStudentView(
                        studentID: viewModel.studentID,
                        useCases: viewModel.useCases,
                        onCancel: { cover = nil },
                        onArchived: {
                            cover = nil
                            Task { await viewModel.reload() }
                        }
                    )
                } else {
                    DeleteStudentFlow(
                        studentID: viewModel.studentID,
                        useCases: viewModel.useCases,
                        onFinish: { result in
                            cover = nil
                            switch result {
                            case .cancelled:
                                break
                            case .deleted:
                                path.removeAll()
                            case .backup:
                                path.append(.backupRestore)
                            case .continueTraining:
                                path.append(.activeSession(viewModel.studentID.rawValue))
                            }
                        }
                    )
                }
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.detailRoot)
    }

    /// Real most-recent-completed-session summary (M1B data-model §2.4-adjacent
    /// traceability expectation) when one exists; the genuine "no completed
    /// sessions yet" case still falls back to the static placeholder copy.
    private var recentTrainingTitle: String {
        guard let session = viewModel.mostRecentCompletedSession else {
            return String(localized: "student.detail.recentPlaceholder")
        }
        let dateText = Self.dateText(session.completedAtUTC)
        if let focus = session.trainingFocus?.value, !focus.isEmpty {
            return String(format: String(localized: "student.detail.recentSummaryFormat"), dateText, focus)
        }
        return String(
            format: String(localized: "student.detail.recentSummarySetsFormat"),
            dateText,
            Int64(session.statistics.completedSetCount)
        )
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func profile(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            HStack {
                Image(systemName: StudentSexPresentation.symbolName(student.sex))
                Text(StudentSexPresentation.title(student.sex))
                Text(student.displayName.value)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(student.displayName.value), \(StudentSexPresentation.title(student.sex))")

            labeled(String(localized: "student.field.trainingGoal"), student.trainingGoal?.value)
            labeled(String(localized: "student.field.phone"), student.phone?.value)
            labeled(String(localized: "student.field.wechat"), student.wechatID?.value)
            labeled(String(localized: "student.field.privateNote"), student.privateCoachNote?.value)
            Text(String(localized: "student.editor.contactHint"))
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
        }
        .padding(FCPrimitives.spacingSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
    }

    private func notesFold(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            Button {
                viewModel.notesExpanded.toggle()
            } label: {
                HStack {
                    Text(String(localized: "student.field.injuryNotes"))
                        .font(.headline)
                    Spacer()
                    Text(
                        student.injuryNotes == nil
                            ? String(localized: "student.detail.notesEmpty")
                            : String(localized: "student.detail.notesHidden")
                    )
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)
                    Image(systemName: viewModel.notesExpanded ? "chevron.up" : "chevron.down")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier(FCAccessibilityID.detailNotesFold)
            .accessibilityValue(
                viewModel.notesExpanded
                    ? String(localized: "student.detail.notesExpanded")
                    : String(localized: "student.detail.notesCollapsed")
            )

            if viewModel.notesExpanded {
                Text(student.injuryNotes?.value ?? String(localized: "student.detail.notesEmpty"))
                    .accessibilityIdentifier(FCAccessibilityID.detailNotesBody)
                Text(String(localized: "student.detail.notesDisclaimer"))
                    .font(.footnote)
                    .foregroundStyle(FCSemanticColors.secondaryText)
            }
        }
        .padding(FCPrimitives.spacingSmall)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
    }

    private func labeled(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "student.detail.unfilled"))
        }
    }

    private func banner(title: String) -> some View {
        HStack {
            Image(systemName: "play.fill")
            Text(title).font(.headline)
            Spacer()
            Text(String(localized: "student.list.continue"))
        }
        .frame(minHeight: 44)
        .padding(.horizontal, FCPrimitives.spacingSmall)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
    }

    private func summaryCard(kicker: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .padding(FCPrimitives.spacingSmall)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
    }
}
