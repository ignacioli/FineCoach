import SwiftUI

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
    @State private var editorRoute: CustomEditorRoute?
    @State private var isFilterSheetPresented = false
    @State private var optionsEntryID: StableExerciseID?

    init(useCases: ExerciseLibraryUseCases) {
        _viewModel = StateObject(wrappedValue: ExerciseLibraryViewModel(useCases: useCases))
    }

    private var optionsEntry: ExerciseLibraryEntry? {
        optionsEntryID.flatMap { id in viewModel.entries.first { $0.id == id } }
    }

    private var hasSheetFilters: Bool {
        viewModel.equipmentFilter != nil || viewModel.includeHidden
    }

    var body: some View {
        ScrollView {
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

                ForEach(viewModel.sections) { section in
                    VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                        FCSectionLabel("\(sectionTitle(section.id)) · \(section.entries.count)")
                            .accessibilityIdentifier(FCAccessibilityID.exerciseLibrarySection(section.id))
                        VStack(spacing: 0) {
                            FCListRowDivider()
                            ForEach(section.entries) { entry in
                                row(for: entry)
                                FCListRowDivider()
                            }
                        }
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
        .task { await viewModel.reload() }
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

    private func row(for entry: ExerciseLibraryEntry) -> some View {
        Button {
            optionsEntryID = entry.id
        } label: {
            HStack(spacing: FCPrimitives.space4) {
                if let icon = FCEquipmentIcon.icon(equipmentClass: entry.equipmentClass, primaryMuscleGroup: entry.primaryMuscleGroup) {
                    FCEquipmentIconView(icon)
                }
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(entry.displayedName)
                        .fcFont(.headline)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    Text(subtitle(for: entry))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                Spacer(minLength: FCPrimitives.space2)
                if entry.preference?.isFavorite == true {
                    Image(systemName: "star.fill")
                        .foregroundStyle(FCSemanticColors.actionPrimary)
                        .accessibilityLabel(Text("exercise.library.favorite"))
                }
                FCSymbol(.forward)
            }
            .padding(.vertical, FCPrimitives.space3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryRow(entry.id))
    }

    /// "杠铃 · 次要：肩、臂"; custom exercises read "自定义"; hidden ones are
    /// marked when "显示已隐藏" is on.
    private func subtitle(for entry: ExerciseLibraryEntry) -> String {
        var parts: [String] = []
        if entry.item.kind == .custom {
            parts.append(String(localized: "exercise.kind.custom"))
        } else {
            parts.append(entry.equipmentClass.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "exercise.kind.builtIn"))
            if !entry.secondaryMuscleGroups.isEmpty {
                parts.append(String(
                    format: String(localized: "exercise.library.secondaryFormat"),
                    entry.secondaryMuscleGroups.joined(separator: "、")
                ))
            }
        }
        if entry.preference?.isHidden == true {
            parts.append(String(localized: "exercise.library.hiddenTag"))
        }
        return parts.joined(separator: " · ")
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
