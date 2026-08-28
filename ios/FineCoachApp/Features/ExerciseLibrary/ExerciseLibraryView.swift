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

            List(viewModel.entries) { entry in
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
            .listStyle(.plain)
        }
        .background(FCSemanticColors.background)
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
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    private func nameContent(_ entry: ExerciseLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayedName)
                .font(.headline)
                .foregroundStyle(FCSemanticColors.primaryText)
            Text(kindTitle(entry.item.kind))
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
                .accessibilityLabel(kindTitle(entry.item.kind))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func kindTitle(_ kind: ExerciseKind) -> String {
        switch kind {
        case .builtIn:
            return String(localized: "exercise.kind.builtIn")
        case .custom:
            return String(localized: "exercise.kind.custom")
        }
    }
}
