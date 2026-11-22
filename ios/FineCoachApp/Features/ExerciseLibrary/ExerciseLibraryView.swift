import SwiftUI

/// Cell identity. Cases cannot collide: a restored exercise whose raw value is
/// `title` is still `.recentRow` or `.row`, not `.recentTitle`.
private enum LibraryCellID: Hashable {
    case recentTitle
    case recentRow(StableExerciseID)
    case sectionTitle(String)
    case row(StableExerciseID)
}

/// One lazy row or heading. The page header stays outside this list so it is
/// not released when it scrolls away.
private enum LibraryListItem: Identifiable {
    case recentTitle
    case recentRow(ExerciseLibraryEntry, isFirst: Bool)
    case sectionTitle(id: String, title: String)
    case row(ExerciseLibraryEntry, isFirst: Bool)

    var id: LibraryCellID {
        switch self {
        case .recentTitle:
            return .recentTitle
        case .recentRow(let entry, _):
            return .recentRow(entry.id)
        case .sectionTitle(let id, _):
            return .sectionTitle(id)
        case .row(let entry, _):
            return .row(entry.id)
        }
    }
}

private enum CustomEditorRoute: Hashable, Identifiable {
    case create
    case edit(ExerciseCatalogItem)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let item):
            return item.id.rawValue
        }
    }
}

/// 动作库 (T069c; `20-exercise-library`): titleLarge + "＋ 自定义", search
/// with a filter button, body-part chips, grouped rows (equipment icon,
/// name, "器材 · 次要：…", ›). Equipment filter and "显示已隐藏" live in the
/// filter sheet (owner 2026-09-27; keeps M1-A 按部位/器械浏览). Tapping a
/// row opens its options sheet (收藏 / 隐藏 / 辅助器械, 编辑 for custom).
struct ExerciseLibraryView: View {
    @StateObject private var viewModel: ExerciseLibraryViewModel
    @FCInstantState private var editorRoute: CustomEditorRoute?
    @State private var isFilterSheetPresented = false
    @State private var optionsEntryID: StableExerciseID?

    init(useCases: ExerciseLibraryUseCases, historyUseCases: HistoryUseCases) {
        _viewModel = StateObject(
            wrappedValue: ExerciseLibraryViewModel(useCases: useCases, historyUseCases: historyUseCases)
        )
    }

    private var optionsEntry: ExerciseLibraryEntry? {
        optionsEntryID.flatMap { id in viewModel.entries.first { $0.id == id } }
    }

    private var hasSheetFilters: Bool {
        viewModel.equipmentFilter != nil || viewModel.includeHidden
    }

    var body: some View {
        ScrollView {
            // spacing 0: the old outer gap was space4 and the label-to-divider gap
            // was space2. Those stay on the heading cell; row cells stay flush so
            // the 1pt dividers do not pick up an extra gap.
            // Header is a plain stack child so it stays mounted and is read first.
            // Rows stay in the inner lazy stack.
            VStack(alignment: .leading, spacing: 0) {
                libraryChrome
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(libraryListItems) { item in
                        libraryListItem(item)
                    }
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryRoot)
        .fcBottomSheet(isPresented: $isFilterSheetPresented) {
            filterSheet
        }
        .fcBottomSheet(isPresented: optionsPresented) {
            if let entry = optionsEntry {
                optionsSheet(entry)
            }
        }
        .task { await viewModel.load() }
        .onChange(of: editorRoute) { _, newValue in
            if newValue == nil {
                Task { await viewModel.reload() }
            }
        }
        .navigationDestination(item: $editorRoute) { route in
            CustomExerciseEditorView(
                useCases: viewModel.useCases,
                existing: {
                    if case .edit(let item) = route {
                        return item
                    }
                    return nil
                }(),
                onFinished: {
                    editorRoute = nil
                }
            )
        }
    }

    // MARK: Header, search, chips

    private var header: some View {
        HStack(alignment: .center) {
            FCPageHeader(title: String(localized: "exercise.library.title"), back: .init())
            FCLinkButton(title: String(localized: "exercise.library.addCustomShort")) {
                editorRoute = .create
            }
            .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryAddCustom)
            .accessibilityLabel(Text("exercise.library.addCustom"))
        }
    }

    private var searchRow: some View {
        HStack(spacing: FCPrimitives.space2) {
            FCSearchField(String(localized: "exercise.library.search"), text: $viewModel.query)
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibrarySearch)
                .onChange(of: viewModel.query) { _, _ in
                    viewModel.scheduleReload()
                }
            FCTitleIconButton(
                systemImage: hasSheetFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle",
                accessibilityLabel: String(localized: "exercise.library.filter.title")
            ) {
                isFilterSheetPresented = true
            }
            .accessibilityValue(Text(hasSheetFilters ? "exercise.library.filter.active" : ""))
            .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryFilter)
        }
    }

    private var muscleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FCPrimitives.space2) {
                FCFilterChip(
                    title: String(localized: "exercise.library.filter.all"),
                    isSelected: viewModel.muscleFilter == nil
                ) {
                    viewModel.selectMuscle(nil)
                }
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryMuscleAll)
                ForEach(ExerciseCatalogBrowse.muscleGroupOrder, id: \.self) { muscle in
                    FCFilterChip(title: muscle, isSelected: viewModel.muscleFilter == muscle) {
                        viewModel.selectMuscle(muscle)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryMuscle(muscle))
                }
            }
        }
        .accessibilityLabel(Text("exercise.library.filter.muscle"))
    }

    // MARK: Rows

    /// One cell per heading or row, after the header slot. Same order as the
    /// old `VStack`: recent, then catalog sections.
    private var libraryListItems: [LibraryListItem] {
        var items: [LibraryListItem] = []
        if viewModel.showsRecentEntries {
            items.append(.recentTitle)
            for (index, entry) in viewModel.recentEntries.enumerated() {
                items.append(.recentRow(entry, isFirst: index == 0))
            }
        }
        for section in viewModel.sections {
            items.append(
                .sectionTitle(
                    id: section.id,
                    title: "\(sectionTitle(section.id)) · \(section.entries.count)"
                )
            )
            for (index, entry) in section.entries.enumerated() {
                items.append(.row(entry, isFirst: index == 0))
            }
        }
        return items
    }

    @ViewBuilder
    private func libraryListItem(_ item: LibraryListItem) -> some View {
        switch item {
        case .recentTitle:
            librarySectionHeading(
                String(localized: "exercise.library.recent"),
                identifier: FCAccessibilityID.exerciseLibraryRecent
            )
        case .recentRow(let entry, let isFirst):
            dividedRow(isFirst: isFirst) {
                Button {
                    optionsEntryID = entry.id
                } label: {
                    FCExerciseLibraryRowLabel(entry: entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryRecentRow(entry.id))
            }
        case .sectionTitle(let id, let title):
            librarySectionHeading(
                title,
                identifier: FCAccessibilityID.exerciseLibrarySection(id)
            )
        case .row(let entry, let isFirst):
            dividedRow(isFirst: isFirst) {
                row(for: entry)
            }
        }
    }

    private var libraryChrome: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            header
            searchRow
            muscleChips
            if let conflictMessage = viewModel.conflictMessage {
                Text(conflictMessage)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
                    .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryConflict)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
            }
        }
    }

    /// `space4` above the label replaces the old outer `VStack` spacing; `space2`
    /// below it replaces the old section `VStack` spacing before the first divider.
    private func librarySectionHeading(_ title: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            listGap(FCPrimitives.space4)
            FCSectionLabel(title)
                .accessibilityIdentifier(identifier)
            listGap(FCPrimitives.space2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Transparent, same as the old `VStack` spacing: the page background shows
    /// through, and the gap is not an accessibility element.
    private func listGap(_ height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .accessibilityHidden(true)
    }

    /// First row keeps the leading divider; every row keeps the trailing one.
    /// That is the old `divider / row / divider / row / divider` sequence.
    private func dividedRow<Content: View>(isFirst: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            if isFirst {
                FCListRowDivider()
            }
            content()
            FCListRowDivider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for entry: ExerciseLibraryEntry) -> some View {
        Button {
            optionsEntryID = entry.id
        } label: {
            FCExerciseLibraryRowLabel(entry: entry)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryRow(entry.id))
    }

    /// "杠铃 · 次要：肩、臂"; custom exercises read "自定义"; hidden ones are
    /// marked when "显示已隐藏" is on.
    private func subtitle(for entry: ExerciseLibraryEntry) -> String {
        FCExerciseLibraryRowLabel.subtitle(for: entry)
    }

    private func sectionTitle(_ id: String) -> String {
        switch id {
        case ExerciseCatalogBrowse.customSectionID:
            return String(localized: "exercise.kind.custom")
        case ExerciseCatalogBrowse.uncategorizedSectionID:
            return String(localized: "exercise.library.section.uncategorized")
        default:
            return id
        }
    }

    // MARK: Sheets

    private var filterSheet: some View {
        FCBottomSheet(title: String(localized: "exercise.library.filter.title")) {
            VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                FCSectionLabel(String(localized: "exercise.library.filter.equipment"))
                FCFlowLayout(horizontalSpacing: FCPrimitives.space2, verticalSpacing: FCPrimitives.space2 - (44 - 30)) {
                    FCFilterChip(
                        title: String(localized: "exercise.library.filter.all"),
                        isSelected: viewModel.equipmentFilter == nil
                    ) {
                        viewModel.selectEquipment(nil)
                    }
                    .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryEquipmentAll)
                    ForEach(ExerciseCatalogBrowse.equipmentClassOrder, id: \.self) { equipment in
                        FCFilterChip(title: equipment, isSelected: viewModel.equipmentFilter == equipment) {
                            viewModel.selectEquipment(equipment)
                        }
                        .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryEquipment(equipment))
                    }
                }
                FCListRowDivider()
                toggleRow(
                    String(localized: "exercise.library.showHidden"),
                    isOn: Binding(
                        get: { viewModel.includeHidden },
                        set: { value in
                            viewModel.includeHidden = value
                            Task { await viewModel.reload() }
                        }
                    )
                )
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryShowHidden)
                FCLinkButton(title: String(localized: "exercise.library.filter.done")) {
                    isFilterSheetPresented = false
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var optionsPresented: Binding<Bool> {
        Binding(
            get: { optionsEntry != nil },
            set: { if !$0 { optionsEntryID = nil } }
        )
    }

    private func optionsSheet(_ entry: ExerciseLibraryEntry) -> some View {
        FCBottomSheet(title: entry.displayedName, subtitle: subtitle(for: entry)) {
            VStack(spacing: 0) {
                FCListRowDivider()
                toggleRow(
                    String(localized: "exercise.library.favorite"),
                    isOn: Binding(
                        get: { entry.preference?.isFavorite ?? false },
                        set: { _ in Task { await viewModel.toggleFavorite(entry) } }
                    )
                )
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryFavorite(entry.id))
                FCListRowDivider()
                toggleRow(
                    String(localized: "exercise.library.hide"),
                    isOn: Binding(
                        get: { entry.preference?.isHidden ?? false },
                        set: { _ in Task { await viewModel.toggleHidden(entry) } }
                    )
                )
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryHide(entry.id))
                FCListRowDivider()
                toggleRow(
                    String(localized: "exercise.library.assisted"),
                    isOn: Binding(
                        get: { entry.preference?.isAssisted ?? false },
                        set: { _ in Task { await viewModel.toggleAssisted(entry) } }
                    )
                )
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryAssisted(entry.id))
                FCListRowDivider()
                toggleRow(
                    String(localized: "exercise.library.unilateral"),
                    isOn: Binding(
                        get: { entry.isUnilateral },
                        set: { _ in Task { await viewModel.toggleUnilateral(entry) } }
                    )
                )
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryUnilateral(entry.id))
                if entry.item.kind == .custom {
                    FCListRowDivider()
                    FCActionRow(title: String(localized: "exercise.library.editCustom")) {
                        optionsEntryID = nil
                        editorRoute = .edit(entry.item)
                    }
                }
                FCListRowDivider()
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .fcFont(.body)
                .foregroundStyle(FCSemanticColors.textPrimary)
            Spacer(minLength: FCPrimitives.space2)
            Toggle(title, isOn: isOn)
                .toggleStyle(FCToggleStyle())
                .labelsHidden()
        }
        .frame(minHeight: 52)
    }
}
