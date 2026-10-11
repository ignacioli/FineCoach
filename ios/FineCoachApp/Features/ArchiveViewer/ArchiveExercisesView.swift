import SwiftUI

/// M2-16 动作资料 (T062, M2-FR-045, AC-011): the exercises that appear in the archive's training
/// records, name search, and one read-only row each: equipment icon, name, 「主：… · 次：… · 器材」.
/// Text only: the archive carries no image. Rows are not tappable.
struct ArchiveExercisesView: View {
    let content: ArchiveViewerContent
    @ObservedObject var model: ArchiveViewerModel

    @State private var query = ""

    private var total: Int {
        ((try? content.exercises()) ?? []).count
    }

    private var entries: [ArchiveExerciseEntry] {
        (try? content.exercises(nameQuery: query)) ?? []
    }

    var body: some View {
        let shown = entries
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.export.item.exerciseInfo"),
                    subtitle: String(format: String(localized: "archive.viewer.exercises.subtitleFormat"), total),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveExercisesBack)
                )
                FCSearchField(String(localized: "archive.viewer.exercises.search"), text: $query)
                    .accessibilityIdentifier(FCAccessibilityID.archiveExercisesSearch)
                if shown.isEmpty {
                    Text(String(localized: "archive.viewer.exercises.empty"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, FCPrimitives.space2)
                        .accessibilityIdentifier(FCAccessibilityID.archiveExercisesEmpty)
                } else {
                    VStack(spacing: 0) {
                        FCListRowDivider()
                        ForEach(Array(shown.enumerated()), id: \.element.key) { index, entry in
                            FCListRow(
                                title: ArchiveViewerPresentation.exerciseName(entry),
                                titleStyle: .headline,
                                subtitle: ArchiveViewerPresentation.exerciseMeta(entry),
                                leading: .equipmentSlot(icon(for: entry)),
                                showsDisclosure: false
                            )
                            .accessibilityIdentifier(FCAccessibilityID.archiveExercisesRow(index))
                            FCListRowDivider()
                        }
                    }
                    .environment(\.fcCompactRows, model.settings.density == .compact)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveExercisesRoot)
    }

    /// Only built-in exercises have an icon; custom and session-only ones leave the slot empty.
    private func icon(for entry: ArchiveExerciseEntry) -> FCEquipmentIcon? {
        guard entry.kind == .builtIn, let info = entry.info else { return nil }
        return FCEquipmentIcon.icon(equipmentClass: info.equipment, primaryMuscleGroup: info.primaryMuscles.first)
    }
}
