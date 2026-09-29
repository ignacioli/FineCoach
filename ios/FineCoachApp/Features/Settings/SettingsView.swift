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
                Text(String(localized: "settings.title"))
                    .fcFont(.titleLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    FCListRowDivider()
                    notificationsRow
                    FCListRowDivider()
                    row(
                        symbol: "externaldrive",
                        title: String(localized: "backup.title"),
                        identifier: FCAccessibilityID.settingsBackup,
                        showsForward: true
                    ) {
                        path.append(.backupRestore)
                    } subtitle: {
                        EmptyView()
                    }
                    FCListRowDivider()
                    row(
                        symbol: "info.circle",
                        title: String(localized: "settings.about"),
                        identifier: FCAccessibilityID.settingsAbout,
                        showsForward: false,
                        action: nil
                    ) {
                        Text(versionText)
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                    FCListRowDivider()
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(FCAccessibilityID.settingsRoot)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
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

    @ViewBuilder
    private var notificationsRow: some View {
        if notificationStatus == .denied {
            row(
                symbol: "bell",
                title: String(localized: "settings.notifications"),
                identifier: FCAccessibilityID.settingsNotifications,
                showsForward: true,
                trailingLink: String(localized: "settings.notifications.openSettings")
            ) {
                SystemSettingsLink.openNotificationSettings()
            } subtitle: {
                FCStatusLabel(.permissionDenied)
            }
        } else {
            row(
                symbol: "bell",
                title: String(localized: "settings.notifications"),
                identifier: FCAccessibilityID.settingsNotifications,
                showsForward: true
            ) {
                SystemSettingsLink.openNotificationSettings()
            } subtitle: {
                Text(
                    notificationStatus == .notDetermined
                        ? String(localized: "settings.notifications.undetermined")
                        : String(localized: "settings.notifications.on")
                )
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
            }
        }
    }

    private func row<Subtitle: View>(
        symbol: String,
        title: String,
        identifier: String,
        showsForward: Bool,
        trailingLink: String? = nil,
        action: (() -> Void)?,
        @ViewBuilder subtitle: () -> Subtitle
    ) -> some View {
        let content = HStack(spacing: FCPrimitives.space4) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                Text(title)
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                subtitle()
            }
            Spacer(minLength: FCPrimitives.space2)
            if let trailingLink {
                Text(trailingLink)
                    .fcFont(.callout, weight: .semibold)
                    .foregroundStyle(FCSemanticColors.actionPrimary)
            }
            if showsForward {
                FCSymbol(.forward)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .contentShape(Rectangle())
        return Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content.accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}
