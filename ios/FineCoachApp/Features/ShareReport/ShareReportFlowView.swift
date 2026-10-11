import SwiftUI
import UIKit

@MainActor
final class ShareReportFlowViewModel: ObservableObject {
    // 包含内容 — every generation starts from the privacy-safe defaults
    // (M1A-FR-035): the three content groups on, volume and bests off.
    @Published var includeRecord = true
    @Published var includeExercises = true
    @Published var includeSummary = true
    @Published var includeVolume = false
    @Published var includePersonalBests = false
    @Published private(set) var dto: ShareReportDTO?
    @Published private(set) var bestsSetThisSession: [ShareReportPersonalBestDTO] = []
    @Published private(set) var subtitle = ""
    @Published var errorMessage: String?
    @Published var lastOutcome: SystemShareOutcome?
    @Published var handedOff = false
    @Published var isSharing = false

    let sessionID: StableUUID
    private let useCases: HistoryUseCases
    private let exerciseUseCases: ExerciseLibraryUseCases?
    private let reportsRootURL: URL
    private let shareAdapter: SystemShareAdapter
    private var report: ShareReport?
    private var completed: CompletedSession?
    private var lease: TempReportLease?

    init(
        sessionID: StableUUID,
        useCases: HistoryUseCases,
        exerciseUseCases: ExerciseLibraryUseCases? = nil,
        reportsRootURL: URL,
        shareAdapter: SystemShareAdapter
    ) {
        self.sessionID = sessionID
        self.useCases = useCases
        self.exerciseUseCases = exerciseUseCases
        self.reportsRootURL = reportsRootURL
        self.shareAdapter = shareAdapter
    }

    var modules: ShareReportModuleSelection {
        var selection = ShareReportModuleSelection.privacySafeDefaults
        selection.includeStudentDisplayName = includeRecord
        selection.includeDate = includeRecord
        selection.includeDuration = includeRecord
        selection.includeTrainingFocus = includeRecord
        selection.includeExercisesAndSets = includeExercises
        selection.includeStudentFacingSummary = includeSummary
        selection.includeTrainingVolume = includeVolume
        return selection
    }

    func load() async {
        do {
            let generated = try await useCases.generateReport(sessionID: sessionID, modules: modules)
            completed = generated.completed
            report = generated.report
            subtitle = String(
                format: String(localized: "share.subtitleFormat"),
                generated.completed.studentDisplayName.value,
                PackageDetailPresentation.day(generated.completed.completedAtUTC)
            )
            let history = (try? await useCases.listHistory(studentID: generated.completed.studentID)) ?? []
            var assisted = Set<StableExerciseID>()
            if let exerciseUseCases, let entries = try? await exerciseUseCases.search(query: "", includeHidden: true) {
                assisted = Set(entries.filter { $0.preference?.isAssisted == true }.map(\.id))
            }
            bestsSetThisSession = ShareReportPolicy.personalBestsSet(
                in: generated.completed,
                history: history,
                assistedExerciseIDs: assisted
            )
            refreshPreview()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    /// Rebuilds the DTO through the privacy gate after any toggle.
    func refreshPreview() {
        guard let completed else { return }
        do {
            dto = try ShareReportPolicy.makeDTO(
                from: completed,
                modules: modules,
                personalBests: includePersonalBests ? bestsSetThisSession : []
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    /// Renders the report images (one, or several ordered ones for a very
    /// long report) from the current DTO, then hands them to the system
    /// share sheet.
    func share() async {
        guard !isSharing, let dto else { return }
        isSharing = true
        defer { isSharing = false }
        do {
            let pages = try ShareReportCardRenderer.render(dto: dto)
            var currentLease = try lease ?? TempReportLease(rootURL: reportsRootURL, flowID: UUID())
            _ = try currentLease.replacePreview(pages: pages)
            lease = currentLease
            let outcome = await shareAdapter.share(fileURLs: currentLease.fileURLs)
            if let report {
                self.report = try await useCases.recordHandoff(report: report, outcome: outcome)
            }
            try finishShare(outcome: outcome)
        } catch {
            lastOutcome = .failed
            handedOff = false
            lease?.retainForRetry()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func close() {
        guard var lease else { return }
        try? lease.close()
        self.lease = nil
    }

    private func finishShare(outcome: SystemShareOutcome) throws {
        lastOutcome = outcome
        switch outcome {
        case .completed:
            handedOff = true
            if var lease {
                try lease.completeSystemHandoff()
            }
            self.lease = nil
        case .cancelled, .failed:
            handedOff = false
            lease?.retainForRetry()
        }
    }
}

/// 分享报告设置 (T069j; `28-share-settings-v2`, owner-approved 2026-09-28):
/// live thumbnail, 包含内容 check circles (tappable, haptic), 个人最佳
/// (default off, hint when this session set bests), 训练容量 (default off),
/// privacy line with the mascot, and 生成报告卡 → the preview (29).
struct ShareReportFlowView: View {
    @StateObject private var viewModel: ShareReportFlowViewModel
    @Binding var path: [RootDestination]
    @State private var isShowingPreview = false

    init(
        sessionID: StableUUID,
        useCases: HistoryUseCases,
        exerciseUseCases: ExerciseLibraryUseCases? = nil,
        reportsRootURL: URL,
        shareAdapter: SystemShareAdapter,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: ShareReportFlowViewModel(
                sessionID: sessionID,
                useCases: useCases,
                exerciseUseCases: exerciseUseCases,
                reportsRootURL: reportsRootURL,
                shareAdapter: shareAdapter
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                    FCPageHeader(title: String(localized: "share.title"), back: .init())
                    Text(viewModel.subtitle)
                        .fcFont(.callout, weight: .regular)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if let dto = viewModel.dto {
                    thumbnail(dto)
                }

                contentSection
                privacyLine
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .safeAreaInset(edge: .bottom) {
            FCButton(title: String(localized: "share.generateCard"), isEnabled: viewModel.dto != nil) {
                isShowingPreview = true
            }
            .accessibilityIdentifier(FCAccessibilityID.shareReportGenerateCard)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .navigationDestination(isPresented: $isShowingPreview) {
            ShareReportPreviewPage(viewModel: viewModel)
        }
        .task { await viewModel.load() }
    }

    // MARK: Thumbnail (2)

    private func thumbnail(_ dto: ShareReportDTO) -> some View {
        Button {
            isShowingPreview = true
        } label: {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                HStack(alignment: .firstTextBaseline) {
                    if let date = dto.sessionDateUTC {
                        Text(ShareReportCardPresentation.day(date))
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                    Spacer(minLength: FCPrimitives.space2)
                    Text(String(localized: "share.viewFull"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.actionPrimary)
                }
                Text(ShareReportCardPresentation.title(dto))
                    .fcFont(.title)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                HStack(alignment: .bottom, spacing: FCPrimitives.space4) {
                    ForEach(Array(ShareReportCardPresentation.stats(dto).enumerated()), id: \.offset) { _, stat in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(stat.value)
                                .fcFont(.headline)
                                .foregroundStyle(FCSemanticColors.textPrimary)
                            Text(stat.label)
                                .fcFont(.caption)
                                .foregroundStyle(FCSemanticColors.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let parts = thumbnailParts(dto) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(localized: "shareCard.trainedParts"))
                                .fcFont(.sectionLabel)
                                .foregroundStyle(FCSemanticColors.textSecondary)
                            Text(parts)
                                .fcFont(.caption)
                                .foregroundStyle(FCSemanticColors.textPrimary)
                        }
                        .padding(FCPrimitives.space2)
                        .background(FCSemanticColors.surfacePage)
                        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMd))
                    }
                }
            }
            .padding(FCPrimitives.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FCSemanticColors.surfaceCanvas)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusLg))
            .animation(.easeOut(duration: 0.2), value: dto)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("share.viewFull"))
        .accessibilityIdentifier(FCAccessibilityID.shareReportPreview)
    }

    private func thumbnailParts(_ dto: ShareReportDTO) -> String? {
        guard !dto.exercises.isEmpty else { return nil }
        let summary = TrainedBodyPartsSummary(exercises: dto.exercises.map {
            ExerciseBodyParts(primary: $0.primaryBodyPart, secondary: $0.secondaryBodyParts)
        })
        return BodyPart.joinedDisplayNames(for: summary.primary, separator: "、")
    }

    // MARK: 包含内容 (1, 3)

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FCSectionLabel(String(localized: "share.modules"))
                .padding(.bottom, FCPrimitives.space2)
            FCListRowDivider()
            checkRow(String(localized: "share.module.record"), note: String(localized: "share.module.recordNote"), isOn: $viewModel.includeRecord)
            FCListRowDivider()
            checkRow(String(localized: "share.module.exercises"), note: String(localized: "share.module.exercisesNote"), isOn: $viewModel.includeExercises)
            FCListRowDivider()
            checkRow(String(localized: "share.module.summary"), note: nil, isOn: $viewModel.includeSummary)
            FCListRowDivider()
            toggleRow(
                String(localized: "history.pb.title"),
                note: viewModel.bestsSetThisSession.isEmpty
                    ? String(localized: "share.pb.none")
                    : String(format: String(localized: "share.pb.hintFormat"), viewModel.bestsSetThisSession.count),
                emphasizedNote: !viewModel.bestsSetThisSession.isEmpty,
                isOn: $viewModel.includePersonalBests,
                isEnabled: !viewModel.bestsSetThisSession.isEmpty
            )
            .accessibilityIdentifier(FCAccessibilityID.shareReportPersonalBestToggle)
            FCListRowDivider()
            toggleRow(
                String(localized: "share.module.volume"),
                note: String(localized: "share.defaultOff"),
                emphasizedNote: false,
                isOn: $viewModel.includeVolume,
                isEnabled: true
            )
            .accessibilityIdentifier(FCAccessibilityID.shareReportVolumeToggle)
            FCListRowDivider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.shareReportModules)
    }

    private func checkRow(_ title: String, note: String?, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            viewModel.refreshPreview()
        } label: {
            HStack(spacing: FCPrimitives.space2) {
                Text(title)
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                Spacer(minLength: FCPrimitives.space2)
                if let note {
                    Text(note)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                FCSetStateCircle(isOn.wrappedValue ? .completed : .pending)
                    .scaleEffect(isOn.wrappedValue ? 1 : 0.9)
                    .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isOn.wrappedValue)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private func toggleRow(
        _ title: String,
        note: String,
        emphasizedNote: Bool,
        isOn: Binding<Bool>,
        isEnabled: Bool
    ) -> some View {
        HStack(spacing: FCPrimitives.space2) {
            Text(title)
                .fcFont(.body)
                .foregroundStyle(isEnabled ? FCSemanticColors.textPrimary : FCSemanticColors.textDisabled)
            Spacer(minLength: FCPrimitives.space2)
            Text(note)
                .fcFont(.caption, weight: emphasizedNote ? .semibold : nil)
                .foregroundStyle(emphasizedNote ? FCSemanticColors.actionPrimary : FCSemanticColors.textSecondary)
            Toggle(title, isOn: Binding(
                get: { isOn.wrappedValue },
                set: { value in
                    isOn.wrappedValue = value
                    viewModel.refreshPreview()
                }
            ))
            .toggleStyle(FCToggleStyle())
            .labelsHidden()
            .disabled(!isEnabled)
        }
        .frame(minHeight: 52)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    // MARK: Privacy (4, 5)

    private var privacyLine: some View {
        HStack(alignment: .center, spacing: FCPrimitives.space3) {
            // The owner's whole mascot portrait, uncropped, in an app-icon
            // style rounded square (design/design-system/assets/mascot-avatar.png).
            Image("mascot-avatar")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMd))
                .accessibilityHidden(true)
            Image(systemName: "lock.fill")
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityHidden(true)
            Text(String(localized: "share.privacyNote"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, FCPrimitives.space2)
    }
}

/// 分享报告预览 (29): the full card, 分享 in the top-right; shares one long
/// image rendered from the same DTO.
struct ShareReportPreviewPage: View {
    @ObservedObject var viewModel: ShareReportFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                // 29: back and 分享 share the top row; there is no page title.
                FCPageHeader(
                    title: "",
                    back: .init(),
                    trailingAction: .init(
                        title: String(localized: "share.shareAction"),
                        isEnabled: !viewModel.isSharing,
                        accessibilityIdentifier: FCAccessibilityID.shareReportShare
                    ) {
                        Task { await viewModel.share() }
                    }
                )
                .padding(.horizontal, FCPrimitives.space4)
                if let dto = viewModel.dto {
                    ShareReportCardView(dto: dto)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                }
                statusLine
                    .padding(.horizontal, FCPrimitives.space4)
            }
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .onDisappear { viewModel.close() }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.statusDestructive)
        }
        if viewModel.handedOff {
            Text(String(localized: "share.handedToSystem"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .accessibilityIdentifier(FCAccessibilityID.shareReportHandedOffStatus)
        } else if viewModel.lastOutcome == .cancelled || viewModel.lastOutcome == .failed {
            HStack {
                Text(String(localized: "share.notSent"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .accessibilityIdentifier(FCAccessibilityID.shareReportNotSentStatus)
                Spacer()
                FCLinkButton(title: String(localized: "share.retry")) {
                    Task { await viewModel.share() }
                }
                .accessibilityIdentifier(FCAccessibilityID.shareReportRetry)
            }
        }
    }
}
