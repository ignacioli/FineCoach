import SwiftUI

/// Minimal, functional multi-select of the 8 `BodyPart` cases (M1B-FR-033/
/// FR-017). Deliberately plain (a labeled list of native `Toggle`s) -- this
/// is the compile-level adaptation for T073 only; T069 replaces it with the
/// designed body-part capsule picker (design system §8.1).
struct BodyPartMultiSelectView: View {
    let title: String
    @Binding var selection: Set<BodyPart>

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(FCSemanticColors.secondaryText)
            ForEach(BodyPart.allCases) { part in
                Toggle(
                    part.displayName,
                    isOn: Binding(
                        get: { selection.contains(part) },
                        set: { isOn in
                            if isOn {
                                selection.insert(part)
                            } else {
                                selection.remove(part)
                            }
                        }
                    )
                )
                .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}
