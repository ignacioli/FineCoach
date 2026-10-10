import SwiftUI

/// Viewer-mode root. Placeholder until the viewer home replaces it (M2-11). It takes no
/// parameters on purpose: viewer mode never holds the Coach store handle or any Coach write
/// use case, and this placeholder has no control that changes data.
struct ArchiveViewerRoot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(localized: "archive.viewer.placeholder.title"))
                .fcFont(.title)
                .foregroundStyle(FCSemanticColors.textPrimary)
            Text(String(localized: "archive.viewer.placeholder.body"))
                .foregroundStyle(FCSemanticColors.textSecondary)
            Spacer()
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.surfacePage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveViewerRoot)
    }
}
