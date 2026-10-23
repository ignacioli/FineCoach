import SwiftUI

/// M2-11 档案首页 (T046, M2-FR-030/034): the viewer-mode variant of the primary page. Title
/// row with the settings gear, the read-only banner, then one entry row per module. Modules the
/// archive does not hold are unavailable rows, not hidden. Core page: first human walkthrough
/// is T053.
///
/// 动作资料 (M2-16) opens only when the archive holds exercise info, otherwise it is an
/// unavailable row; 关于本档案 (M2-17) is always available (T062).
struct ArchiveHomeView: View {
    let content: ArchiveViewerContent
    let open: (ArchiveViewerDestination) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                HStack(alignment: .center, spacing: FCPrimitives.space2) {
                    Text(ArchiveViewerPresentation.homeTitle(content))
                        .fcFont(.display)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    FCTitleIconButton(
                        systemImage: "gearshape",
                        accessibilityLabel: String(localized: "archive.viewer.home.settings")
                    ) { open(.settings) }
                    .accessibilityIdentifier(FCAccessibilityID.archiveHomeSettings)
                }
                .padding(.top, FCPrimitives.space6)
                FCStatusLabel(
                    text: ArchiveViewerPresentation.banner(content),
                    symbolName: "info",
                    badgeColor: FCSemanticColors.actionPrimary
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(FCAccessibilityID.archiveHomeBanner)
                VStack(spacing: 0) {
                    FCListRowDivider()
                    records
                    FCListRowDivider()
                    body(of: content)
                    FCListRowDivider()
                    trends
                    FCListRowDivider()
                    exercises
                    FCListRowDivider()
                    about
                    FCListRowDivider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var notIncluded: FCHubRow.Mode {
        .unavailable(reason: String(localized: "archive.viewer.home.notIncluded"))
    }

    private var records: some View {
        FCHubRow(
            icon: .symbol("list.bullet.rectangle"),
            title: String(localized: "archive.export.item.trainingRecords"),
            trailing: .note(
                String(format: String(localized: "archive.viewer.home.recordCount"), content.snapshot.sessions.count)),
            mode: content.hasTrainingRecords ? .action { open(.records) } : notIncluded
        )
        .accessibilityIdentifier(FCAccessibilityID.archiveHomeRecords)
    }

    private func body(of content: ArchiveViewerContent) -> some View {
        FCHubRow(
            icon: .symbol("figure.stand"),
            title: String(localized: "archive.export.group.bodyData"),
            trailing: .note(
                String(format: String(localized: "archive.viewer.home.metricCount"), content.snapshot.bodyMetrics.count)
            ),
            mode: content.hasBodyData ? .action { open(.bodyData) } : notIncluded
        )
        .accessibilityIdentifier(FCAccessibilityID.archiveHomeBody)
    }

    private var trends: some View {
        FCHubRow(
            icon: .symbol("chart.line.uptrend.xyaxis"),
            title: String(localized: "archive.export.item.trends"),
            mode: content.isTrendsAvailable ? .action { open(.trends) } : notIncluded
        )
        .accessibilityIdentifier(FCAccessibilityID.archiveHomeTrends)
    }

    private var exercises: some View {
        FCHubRow(
            icon: .symbol("book"),
            title: String(localized: "archive.export.item.exerciseInfo"),
            mode: content.hasExerciseInfo ? .action { open(.exercises) } : notIncluded
        )
        .accessibilityIdentifier(FCAccessibilityID.archiveHomeExercises)
    }

    private var about: some View {
        FCHubRow(
            icon: .symbol("info.circle"),
            title: String(localized: "archive.viewer.home.about"),
            mode: .action { open(.about) }
        )
        .accessibilityIdentifier(FCAccessibilityID.archiveHomeAbout)
    }
}
