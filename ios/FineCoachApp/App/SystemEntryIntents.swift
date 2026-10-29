import AppIntents

struct TodayIntent: AppIntent {
    static let title: LocalizedStringResource = "shortcut.today.title"
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        SystemEntryRouter.shared.receive(SystemEntryPage.today.request)
        AppLogger.standard.info(.systemEntryShortcutOpened, operation: .systemEntry)
        return .result()
    }
}

struct StartTrainingIntent: AppIntent {
    static let title: LocalizedStringResource = "shortcut.startTraining.title"
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        SystemEntryRouter.shared.receive(SystemEntryPage.startTraining.request)
        AppLogger.standard.info(.systemEntryShortcutOpened, operation: .systemEntry)
        return .result()
    }
}

struct ContinueTrainingIntent: AppIntent {
    static let title: LocalizedStringResource = "shortcut.continueTraining.title"
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        SystemEntryRouter.shared.receive(SystemEntryPage.continueTraining.request)
        AppLogger.standard.info(.systemEntryShortcutOpened, operation: .systemEntry)
        return .result()
    }
}

struct FineCoachShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayIntent(), phrases: ["\(.applicationName) 今日"],
            shortTitle: "shortcut.today.title", systemImageName: "calendar")
        AppShortcut(
            intent: StartTrainingIntent(), phrases: ["\(.applicationName) 开始训练"],
            shortTitle: "shortcut.startTraining.title", systemImageName: "figure.strengthtraining.traditional")
        AppShortcut(
            intent: ContinueTrainingIntent(), phrases: ["\(.applicationName) 继续训练"],
            shortTitle: "shortcut.continueTraining.title", systemImageName: "play.circle")
    }
}
