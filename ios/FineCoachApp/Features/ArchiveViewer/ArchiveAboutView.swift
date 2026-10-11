import SwiftUI

/// M2-17 关于本档案 (T062, M2-FR-046, D-007, D-008): where the archive came from, when, and what it
/// holds, then, only when the archive carries built-in exercises, one summarised attribution
/// block (source, licence names and a link). It never lists exercises one by one.
struct ArchiveAboutView: View {
    let content: ArchiveViewerContent

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.viewer.home.about"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveAboutBack)
                )
                VStack(spacing: 0) {
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.viewer.about.source"),
                        value: ArchiveImportPresentation.sourceLine(content.sourceLabel))
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.viewer.about.snapshotTime"),
                        value: ArchiveImportPresentation.snapshotTime(content.manifest.snapshotAtUTC))
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.viewer.about.contents"),
                        value: ArchiveImportPresentation.contentSummary(content.manifest.modules))
                    FCListRowDivider()
                }
                if content.hasExerciseInfo, let attribution = content.snapshot.attribution {
                    attributionSection(attribution)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveAboutRoot)
    }

    private func attributionSection(_ attribution: ArchiveAttribution) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            FCSectionLabel(String(localized: "archive.viewer.about.attribution.title"))
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    String(
                        format: String(localized: "archive.viewer.about.attribution.origin"),
                        attribution.sourceName,
                        ArchiveViewerPresentation.licenseDisplayName(attribution.licenseName))
                )
                if ArchiveViewerPresentation.showsLicenseLink(attribution),
                    let url = ArchiveViewerPresentation.licenseLinkURL
                {
                    FCLinkButton(title: ArchiveViewerPresentation.licenseLinkText) { openURL(url) }
                        .accessibilityIdentifier(FCAccessibilityID.archiveAboutLicenseLink)
                }
                Text(String(localized: "archive.viewer.about.attribution.custom"))
            }
            .fcFont(.caption)
            .foregroundStyle(FCSemanticColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(FCAccessibilityID.archiveAboutAttribution)
        }
    }
}
