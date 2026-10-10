import SwiftUI

/// Presentation state for the M2 export flow (T035). It holds no rules: every transition is
/// validated by `ArchiveExportFlow`, and after each call the view model re-reads `state` and
/// `selection` because the flow has no change callback. The password lives here only between
/// typing and `submitPassword`; it is cleared as soon as the flow has taken it.
@MainActor
final class ArchiveExportViewModel: ObservableObject {
    enum Load: Equatable {
        case loading
        case ready
        case failed
    }

    enum PasswordIssue: Equatable {
        case tooShort
        case mismatch
    }

    @Published private(set) var load: Load = .loading
    @Published private(set) var state: ArchiveExportFlowState = .selecting
    @Published private(set) var selection: ArchiveModuleSelection?
    @Published private(set) var preview: ArchivePreviewModel?
    @Published private(set) var displayName = ""
    @Published private(set) var passwordIssue: PasswordIssue?
    /// A step was refused or failed unexpectedly (for example an invalid transition).
    @Published private(set) var actionFailed = false
    @Published private(set) var isBusy = false
    @Published private(set) var expandedGroups: Set<ArchiveModuleGroup> = []
    @Published var password = ""
    @Published var confirmation = ""

    let studentID: StableUUID
    private let useCases: ArchiveExportUseCases
    private let studentUseCases: StudentUseCases
    private var flow: ArchiveExportFlow?
    private var isDelivering = false

    init(studentID: StableUUID, useCases: ArchiveExportUseCases, studentUseCases: StudentUseCases) {
        self.studentID = studentID
        self.useCases = useCases
        self.studentUseCases = studentUseCases
    }

    // MARK: Derived

    /// Steps with a previous step use the custom back button; the system back button would skip
    /// steps. Selection and the delivery results use the system back (it leaves the flow).
    var usesStepBack: Bool {
        switch state {
        case .previewing, .confirmingFacts, .settingPassword: return !isBusy
        default: return false
        }
    }

    var hidesSystemBack: Bool {
        switch state {
        case .selecting, .generated, .handedToSystem, .cancelled, .failed: return isBusy
        case .previewing, .confirmingFacts, .settingPassword, .generating: return true
        }
    }

    // MARK: Loading

    func start() async {
        guard flow == nil, load != .ready else { return }
        load = .loading
        do {
            displayName = try await studentUseCases.student(id: studentID).displayName.value
            let started = try await useCases.beginFlow(studentID: studentID)
            flow = started
            await sync()
            load = .ready
        } catch {
            load = .failed
        }
    }

    // MARK: Selection

    func toggleExpansion(_ group: ArchiveModuleGroup) {
        if expandedGroups.contains(group) {
            expandedGroups.remove(group)
        } else {
            expandedGroups.insert(group)
        }
    }

    func toggleGroup(_ group: ArchiveModuleGroup) async {
        await perform { try await $0.toggleGroup(group) }
    }

    func toggleItem(_ item: ArchiveModuleItem) async {
        guard let selection else { return }
        let target = !selection.state(of: item).isSelected
        await perform { _ = try await $0.setSelected(target, item: item) }
    }

    // MARK: Steps

    func showPreview() async {
        await perform { flow in
            let snapshot = try await flow.preview()
            self.preview = ArchivePreviewModel(snapshot: snapshot)
        }
    }

    func confirmPreview() async {
        await perform { try await $0.confirmPreview() }
    }

    func confirmFacts() async {
        await perform { try await $0.confirmFacts() }
    }

    func stepBack() async {
        password = ""
        confirmation = ""
        passwordIssue = nil
        await perform { try await $0.back() }
    }

    func submitPassword() async {
        guard let flow, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        passwordIssue = nil
        actionFailed = false
        do {
            try await flow.submitPassword(password, confirmation: confirmation)
            password = ""
            confirmation = ""
        } catch ArchiveExportFlowError.passwordTooShort {
            passwordIssue = .tooShort
        } catch ArchiveExportFlowError.passwordMismatch {
            passwordIssue = .mismatch
        } catch {
            actionFailed = true
        }
        await sync()
    }

    /// 「交给系统…」: delivers a generated archive; after 「已取消」 or 「交付失败」 it first
    /// regenerates from the flow's in-memory snapshot (retry), then delivers.
    func deliver() async {
        guard let flow, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        actionFailed = false
        do {
            await sync()
            if state == .cancelled || state == .failed {
                try await flow.retry()
                await sync()
            }
            guard state == .generated else { return }
            isDelivering = true
            defer { isDelivering = false }
            try await flow.deliver()
        } catch {
            actionFailed = true
        }
        await sync()
    }

    // MARK: Leaving

    /// Ends the flow (deletes the temporary archive, drops password and snapshot). Idempotent.
    /// A delivery in progress keeps the flow open: the system panel is on top of this page.
    func leave() async {
        guard !isDelivering else { return }
        password = ""
        confirmation = ""
        guard let flow else { return }
        await flow.leave()
    }

    // MARK: Plumbing

    private func perform(_ step: (ArchiveExportFlow) async throws -> Void) async {
        guard let flow, !isBusy else { return }
        actionFailed = false
        do {
            try await step(flow)
        } catch {
            actionFailed = true
        }
        await sync()
    }

    private func sync() async {
        guard let flow else { return }
        state = await flow.state
        selection = await flow.selection
        switch state {
        case .previewing, .confirmingFacts, .settingPassword, .generating:
            break
        default:
            // The preview carries free text; hold it only while the steps that need it are open.
            preview = nil
        }
    }
}
