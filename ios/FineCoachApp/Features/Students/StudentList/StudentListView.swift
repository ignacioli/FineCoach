import SwiftUI

@MainActor
final class StudentListViewModel: ObservableObject {
    @Published var students: [Student] = []
    @Published var query = ""
    @Published var inProgress: InProgressTrainingSummary?
    @Published var errorMessage: String?

    let showsArchived: Bool
    private let useCases: StudentUseCases

    init(useCases: StudentUseCases, showsArchived: Bool = false) {
        self.useCases = useCases
        self.showsArchived = showsArchived
    }

    var title: String {
        showsArchived ? String(localized: "student.list.archivedTitle") : String(localized: "student.list.title")
    }

    func reload() async {
        do {
            if showsArchived {
                students = try await useCases.listArchived()
                inProgress = nil
            } else {
                students = try await useCases.searchActive(query: query)
                inProgress = try await useCases.inProgressTraining()
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }
}

struct StudentListView: View {
    @StateObject private var viewModel: StudentListViewModel
    @Binding var path: [RootDestination]
    /// Set only for the root 学员 screen, which shows the 今日/学员 switch.
    private let rootTab: Binding<RootTab>?

    init(
        useCases: StudentUseCases,
        showsArchived: Bool = false,
        rootTab: Binding<RootTab>? = nil,
        path: Binding<[RootDestination]>
    ) {
        self.rootTab = rootTab
        _viewModel = StateObject(
            wrappedValue: StudentListViewModel(useCases: useCases, showsArchived: showsArchived)
        )
        _path = path
    }

    var body: some View {
        VStack(spacing: 0) {
            // T069a moved the switch out of RootTabContainer; T069b restyles
            // this screen's header per 21-student-list-v2.
            if let rootTab {
                RootSegmentSwitch(rootTab: rootTab)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FCPrimitives.space4)
            }
            if !viewModel.showsArchived {
                FCTextField(String(localized: "student.list.search"), text: $viewModel.query)
                    .padding(.horizontal, FCPrimitives.spacingMedium)
                    .padding(.vertical, FCPrimitives.spacingSmall)
                    .accessibilityIdentifier(FCAccessibilityID.studentListSearch)
                    .onChange(of: viewModel.query) { _, _ in
                        Task { await viewModel.reload() }
                    }
                if let inProgress = viewModel.inProgress, viewModel.query.isEmpty {
                    Button {
                        path.append(
                            .activeSession(inProgress.studentID.rawValue)
                        )
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            VStack(alignment: .leading) {
                                Text(String(localized: "student.list.trainingBanner"))
                                    .font(.headline)
                                Text(inProgress.studentDisplayName)
                                    .font(.subheadline)
                                    .foregroundStyle(FCSemanticColors.secondaryText)
                            }
                            Spacer()
                            Text(String(localized: "student.list.continue"))
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, FCPrimitives.spacingMedium)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.studentListInProgress)
                    .accessibilityLabel(String(localized: "student.list.trainingBanner"))
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(FCSemanticColors.destructive)
                    .padding()
            }

            if viewModel.students.isEmpty, !viewModel.showsArchived, viewModel.query.isEmpty {
                noStudentsEmptyState
            } else if viewModel.students.isEmpty {
                VStack(spacing: FCPrimitives.spacingSmall) {
                    Text(emptyTitle)
                        .font(.title3.weight(.semibold))
                    Text(emptyBody)
                        .foregroundStyle(FCSemanticColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .accessibilityIdentifier(FCAccessibilityID.studentListEmpty)
            } else {
                List(viewModel.students) { student in
                    Button {
                        path.append(.studentDetail(student.id.rawValue))
                    } label: {
                        HStack(spacing: FCPrimitives.spacingSmall) {
                            sexBadge(student.sex)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(student.displayName.value)
                                    .font(.headline)
                                    .foregroundStyle(FCSemanticColors.primaryText)
                                Text(subtitle(for: student))
                                    .font(.subheadline)
                                    .foregroundStyle(FCSemanticColors.secondaryText)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.studentRow(student.id))
                    .accessibilityLabel("\(student.displayName.value), \(StudentSexPresentation.title(student.sex))")
                    .listRowBackground(FCSemanticColors.elevatedSurface)
                }
                .listStyle(.plain)
            }
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.showsArchived {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "exercise.library.entry")) {
                        path.append(.exerciseLibrary)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryEntry)
                    .accessibilityLabel(String(localized: "exercise.library.entry"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "student.list.add")) {
                        path.append(.editor(.add))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.studentListAdd)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(.archivedList)
                    } label: {
                        Image(systemName: "archivebox")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(String(localized: "student.list.archivedTitle"))
                    .accessibilityIdentifier(FCAccessibilityID.studentListArchived)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "templates.entry")) {
                        path.append(.templates)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.templatesEntry)
                    .accessibilityLabel(String(localized: "templates.entry"))
                }
            }
        }
        .task { await viewModel.reload() }
        .onChange(of: path) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    /// 16 空态 (T067, §8 "空态"): mascot 220×220 (decorative) → title
    /// `headline` `action.primary` → note `caption` `text.secondary` →
    /// pinned primary button.
    private var noStudentsEmptyState: some View {
        VStack(spacing: FCPrimitives.space3) {
            Spacer(minLength: FCPrimitives.space6)
            Image("mascot-empty-state")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .accessibilityHidden(true)
            Text(String(localized: "student.list.emptyTitle"))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .padding(.top, FCPrimitives.space6)
            Text(String(localized: "student.list.emptyBody"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            FCButton(title: String(localized: "student.list.emptyAction")) {
                path.append(.editor(.add))
            }
            .accessibilityIdentifier(FCAccessibilityID.studentListEmptyAdd)
            .padding(.bottom, FCPrimitives.space4)
        }
        .padding(.horizontal, FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(FCAccessibilityID.studentListEmpty)
    }

    private var emptyTitle: String {
        if viewModel.showsArchived {
            return String(localized: "student.list.archivedEmptyTitle")
        }
        if viewModel.query.isEmpty {
            return String(localized: "student.list.emptyTitle")
        }
        return String(localized: "student.list.searchEmptyTitle")
    }

    private var emptyBody: String {
        if viewModel.showsArchived {
            return String(localized: "student.list.archivedEmptyBody")
        }
        if viewModel.query.isEmpty {
            return String(localized: "student.list.emptyBody")
        }
        return String(localized: "student.list.searchEmptyBody")
    }

    private func subtitle(for student: Student) -> String {
        var parts: [String] = []
        if let goal = student.trainingGoal?.value, !goal.isEmpty {
            parts.append(goal)
        }
        if let note = student.privateCoachNote?.value, !note.isEmpty {
            parts.append(String(localized: "student.list.notePrefix") + note)
        }
        return parts.isEmpty ? String(localized: "student.list.noGoal") : parts.joined(separator: " · ")
    }

    private func sexBadge(_ sex: StudentSex) -> some View {
        HStack(spacing: 4) {
            Image(systemName: StudentSexPresentation.symbolName(sex))
            Text(StudentSexPresentation.title(sex))
                .font(.footnote)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "student.field.sex") + StudentSexPresentation.title(sex))
    }
}
