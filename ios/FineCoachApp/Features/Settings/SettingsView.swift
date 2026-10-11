import SwiftUI

/// 设置 (D15c/D15d, `42-settings`, `43-settings-notification-denied`): the
/// place for 通知, 备份与恢复 and 关于. Reached from the gear on the 今日 and
/// 学员 title rows. No last-backup date is recorded anywhere, so the backup
/// row has no subtitle rather than an invented one.
struct SettingsView: View {
    @Binding var path: [RootDestination]
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: NotificationAuthorizationStatus = .notDetermined

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(title: String(localized: "settings.title"), back: .init())

                VStack(spacing: 0) {
                    FCListRowDivider()
                    notificationsRow
                    FCListRowDivider()
                    FCHubRow(
                        icon: .symbol("externaldrive"),
                        title: String(localized: "backup.title"),
                        mode: .action { path.append(.backupRestore) }
                    )
                    .accessibilityIdentifier(FCAccessibilityID.settingsBackup)
                    FCListRowDivider()
                    FCHubRow(
                        icon: .symbol("info.circle"),
                        title: String(localized: "settings.about"),
                        subtitle: .text(versionText),
                        mode: .informational
                    )
                    .accessibilityIdentifier(FCAccessibilityID.settingsAbout)
                    FCListRowDivider()
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(FCAccessibilityID.settingsRoot)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .task(id: scenePhase) {
            notificationStatus = await SystemNotificationAdapter().currentStatus()
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(format: String(localized: "settings.about.versionFormat"), version, build)
    }

    private var notificationsRow: some View {
        let denied = notificationStatus == .denied
        return FCHubRow(
            icon: .symbol("bell"),
            title: String(localized: "settings.notifications"),
            subtitle: denied
                ? .status(.permissionDenied)
                : .text(
                    notificationStatus == .notDetermined
                        ? String(localized: "settings.notifications.undetermined")
                        : String(localized: "settings.notifications.on")
                ),
            trailing: denied ? .actionText(String(localized: "settings.notifications.openSettings")) : .none,
            mode: .action { SystemSettingsLink.openNotificationSettings() }
        )
        .accessibilityIdentifier(FCAccessibilityID.settingsNotifications)
    }
}
