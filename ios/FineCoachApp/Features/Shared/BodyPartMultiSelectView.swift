import SwiftUI

/// Labeled multi-select of the 8 `BodyPart` cases (M1B-FR-033/FR-017),
/// rendered with the design-system body-part chips (§8.1 "部位多选胶囊";
/// T077). Shared by session edit/summary, the template editor, and the
/// trends focus filter.
struct BodyPartMultiSelectView: View {
    let title: String
    @Binding var selection: Set<BodyPart>
    let chipAccessibilityIdentifier: ((BodyPart) -> String)?

    init(
        title: String,
        selection: Binding<Set<BodyPart>>,
        chipAccessibilityIdentifier: ((BodyPart) -> String)? = nil
    ) {
        self.title = title
        self._selection = selection
        self.chipAccessibilityIdentifier = chipAccessibilityIdentifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            Text(title)
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            FCBodyPartPicker(
                selection: $selection,
                accessibilityIdentifier: chipAccessibilityIdentifier
            )
        }
        .accessibilityElement(children: .contain)
    }
}
