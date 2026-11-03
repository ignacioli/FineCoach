import SwiftUI

struct CoachAboutView: View {
    static let provenanceURL = URL(
        string:
            "https://github.com/ignacioli/FineCoach/blob/main/ios/FineCoachApp/Resources/ExerciseCatalog/provenance.json"
    )!
    static let ccBySA4URL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
    static let ccBySA3URL = URL(string: "https://creativecommons.org/licenses/by-sa/3.0/")!

    @Environment(\.openURL) private var openURL
    @State private var sources: [CoachAboutSource] = []
    @State private var catalogUnavailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "settings.about"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.aboutBack))
                FCLabelValueRow(label: String(localized: "about.version"), value: SettingsView.versionText)
                FCSectionLabel(String(localized: "about.sources"))
                VStack(spacing: 0) {
                    FCListRowDivider()
                    ForEach(sources) { source in
                        FCHubRow(icon: .symbol("book"), title: source.text, mode: .informational)
                        FCListRowDivider()
                    }
                }
                if catalogUnavailable {
                    Text(String(localized: "about.sources.unavailable"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                Text(String(localized: "about.translation"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                VStack(spacing: 0) {
                    FCListRowDivider()
                    externalLink(
                        String(localized: "about.provenance"), url: Self.provenanceURL,
                        identifier: FCAccessibilityID.aboutProvenance)
                    FCListRowDivider()
                    externalLink(
                        "CC BY-SA 4.0", url: Self.ccBySA4URL,
                        identifier: FCAccessibilityID.aboutCCBySA4)
                    FCListRowDivider()
                    externalLink(
                        "CC BY-SA 3.0", url: Self.ccBySA3URL,
                        identifier: FCAccessibilityID.aboutCCBySA3)
                    FCListRowDivider()
                }
                FCSectionLabel(String(localized: "about.fonts"))
                FCHubRow(
                    icon: .symbol("textformat"), title: "Noto Sans SC · SIL Open Font License 1.1",
                    mode: .informational)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.aboutRoot)
        .task {
            do {
                sources = try CoachAboutSource.rows(catalog: PlaceholderExerciseCatalogLoader.loadFromBundle(.main))
            } catch {
                catalogUnavailable = true
            }
        }
    }

    private func externalLink(_ title: String, url: URL, identifier: String) -> some View {
        FCHubRow(
            icon: .symbol("chevron.left.forwardslash.chevron.right"), title: title,
            mode: .action { openURL(url) }
        )
        .accessibilityIdentifier(identifier)
    }
}
