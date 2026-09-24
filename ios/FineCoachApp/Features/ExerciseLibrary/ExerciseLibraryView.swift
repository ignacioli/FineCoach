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

struct ExerciseLibraryView: View {
    @StateObject private var viewModel: ExerciseLibraryViewModel
    @State private var editorRoute: CustomEditorRoute?

    init(useCases: ExerciseLibraryUseCases) {
        _viewModel = StateObject(wrappedValue: ExerciseLibraryViewModel(useCases: useCases))
    }

    var body: some View {
        VStack(spacing: 0) {
            FCTextField(String(localized: "exercise.library.search"), text: $viewModel.query)
                .padding(.horizontal, FCPrimitives.spacingMedium)
                .padding(.vertical, FCPrimitives.spacingSmall)
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibrarySearch)
                .onChange(of: viewModel.query) { _, _ in
                    viewModel.scheduleReload()
                }

            filterRow(
                title: String(localized: "exercise.library.filter.muscle"),
                allTitle: String(localized: "exercise.library.filter.all"),
                allID: FCAccessibilityID.exerciseLibraryMuscleAll,
                values: ExerciseCatalogBrowse.muscleGroupOrder,
                selected: viewModel.muscleFilter,
                chipID: FCAccessibilityID.exerciseLibraryMuscle,
                onSelectAll: { viewModel.selectMuscle(nil) },
                onSelect: { viewModel.selectMuscle($0) }
            )

            filterRow(
                title: String(localized: "exercise.library.filter.equipment"),
                allTitle: String(localized: "exercise.library.filter.all"),
                allID: FCAccessibilityID.exerciseLibraryEquipmentAll,
                values: ExerciseCatalogBrowse.equipmentClassOrder,
                selected: viewModel.equipmentFilter,
                chipID: FCAccessibilityID.exerciseLibraryEquipment,
                onSelectAll: { viewModel.selectEquipment(nil) },
                onSelect: { viewModel.selectEquipment($0) }
            )

            Button(String(localized: "exercise.library.showHidden")) {
                viewModel.includeHidden.toggle()
                Task { await viewModel.reload() }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, FCPrimitives.spacingMedium)
            .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryShowHidden)
            .accessibilityLabel(String(localized: "exercise.library.showHidden"))
            .accessibilityAddTraits(viewModel.includeHidden ? [.isSelected] : [])

            FCButton(title: String(localized: "exercise.library.addCustom")) {
                editorRoute = .create
            }
            .padding(.horizontal, FCPrimitives.spacingMedium)
            .padding(.bottom, FCPrimitives.spacingSmall)
            .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryAddCustom)

            if let conflictMessage = viewModel.conflictMessage {
                Text(conflictMessage)
                    .foregroundStyle(FCSemanticColors.destructive)
                    .padding(.horizontal, FCPrimitives.spacingMedium)
                    .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryConflict)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(FCSemanticColors.destructive)
                    .padding(.horizontal, FCPrimitives.spacingMedium)
            }

            List {
                ForEach(viewModel.sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            row(for: entry)
                                .listRowBackground(FCSemanticColors.elevatedSurface)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: FCPrimitives.spacingSmall,
                                        leading: FCPrimitives.spacingMedium,
                                        bottom: FCPrimitives.spacingSmall,
                                        trailing: FCPrimitives.spacingMedium
                                    )
                                )
                        }
                    } header: {
                        Text(sectionTitle(section.id))
                            .font(.headline)
                            .foregroundStyle(FCSemanticColors.primaryText)
                            .accessibilityIdentifier(FCAccessibilityID.exerciseLibrarySection(section.id))
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "exercise.library.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryRoot)
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

    private func filterRow(
        title: String,
        allTitle: String,
        allID: String,
        values: [String],
        selected: String?,
        chipID: @escaping (String) -> String,
        onSelectAll: @escaping () -> Void,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
                .padding(.horizontal, FCPrimitives.spacingMedium)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FCPrimitives.spacingSmall) {
                    filterChip(
                        title: allTitle,
                        id: allID,
                        isSelected: selected == nil,
                        accessibilityLabel: "\(title), \(allTitle)",
                        action: onSelectAll
                    )
                    ForEach(values, id: \.self) { value in
                        filterChip(
                            title: value,
                            id: chipID(value),
                            isSelected: selected == value,
                            accessibilityLabel: "\(title), \(value)",
                            action: { onSelect(value) }
                        )
                    }
                }
                .padding(.horizontal, FCPrimitives.spacingMedium)
            }
        }
        .padding(.bottom, FCPrimitives.spacingSmall)
    }

    private func filterChip(
        title: String,
        id: String,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .frame(minHeight: 44)
            .padding(.horizontal, FCPrimitives.spacingSmall)
            .background(isSelected ? FCSemanticColors.primaryText : FCSemanticColors.separator)
            .foregroundStyle(
                isSelected ? FCSemanticColors.elevatedSurface : FCSemanticColors.primaryText
            )
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSmall))
            .accessibilityIdentifier(id)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func row(for entry: ExerciseLibraryEntry) -> some View {
        HStack(spacing: FCPrimitives.spacingSmall) {
            if entry.item.kind == .custom {
                Button {
                    editorRoute = .edit(entry.item)
                } label: {
                    nameContent(entry)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryRow(entry.id))
                .accessibilityLabel(entry.displayedName)
            } else {
                nameContent(entry)
                    .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryRow(entry.id))
            }

            Spacer(minLength: 0)

            Button {
                Task { await viewModel.toggleFavorite(entry) }
            } label: {
                Image(systemName: (entry.preference?.isFavorite ?? false) ? "star.fill" : "star")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryFavorite(entry.id))
            .accessibilityLabel("\(String(localized: "exercise.library.favorite")), \(entry.displayedName)")
            .accessibilityAddTraits((entry.preference?.isFavorite ?? false) ? [.isSelected] : [])

            Button {
                Task { await viewModel.toggleHidden(entry) }
            } label: {
                Image(systemName: (entry.preference?.isHidden ?? false) ? "eye" : "eye.slash")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryHide(entry.id))
            .accessibilityLabel(
                (entry.preference?.isHidden ?? false)
                    ? "\(String(localized: "exercise.library.unhide")), \(entry.displayedName)"
                    : "\(String(localized: "exercise.library.hide")), \(entry.displayedName)"
            )

            Toggle(
                isOn: Binding(
                    get: { entry.preference?.isAssisted ?? false },
                    set: { _ in Task { await viewModel.toggleAssisted(entry) } }
                )
            ) {
                Image(systemName: (entry.preference?.isAssisted ?? false) ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .accessibilityIdentifier(FCAccessibilityID.exerciseLibraryAssisted(entry.id))
            .accessibilityLabel("\(String(localized: "exercise.library.assisted")), \(entry.displayedName)")
            .accessibilityAddTraits((entry.preference?.isAssisted ?? false) ? [.isSelected] : [])
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    private func nameContent(_ entry: ExerciseLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayedName)
                .font(.headline)
                .foregroundStyle(FCSemanticColors.primaryText)
            Text(subtitle(for: entry))
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
                .accessibilityLabel(subtitle(for: entry))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func subtitle(for entry: ExerciseLibraryEntry) -> String {
        if entry.item.kind == .custom {
            return String(localized: "exercise.kind.custom")
        }
        if let equipment = entry.equipmentClass, !equipment.isEmpty {
            return equipment
        }
        return String(localized: "exercise.kind.builtIn")
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
}
