import SwiftUI
import UIKit

@MainActor
final class ShareReportFlowViewModel: ObservableObject {
    @Published var includeVolume = false
    @Published var previewLines: [String] = []
    @Published var previewImages: [UIImage] = []
    @Published var errorMessage: String?
    @Published var lastOutcome: SystemShareOutcome?
    @Published var handedOff = false
    @Published var isSharing = false

    let sessionID: StableUUID
    private let useCases: HistoryUseCases
    private let reportsRootURL: URL
    private let renderer: ShareReportRenderer
    private let shareAdapter: SystemShareAdapter
    private var report: ShareReport?
    private var completed: CompletedSession?
    private var lease: TempReportLease?

    init(
        sessionID: StableUUID,
        useCases: HistoryUseCases,
        reportsRootURL: URL,
        renderer: ShareReportRenderer,
        shareAdapter: SystemShareAdapter
    ) {
        self.sessionID = sessionID
        self.useCases = useCases
        self.reportsRootURL = reportsRootURL
        self.renderer = renderer
        self.shareAdapter = shareAdapter
    }

    var modules: ShareReportModuleSelection {
        var selection = ShareReportModuleSelection.privacySafeDefaults
        selection.includeTrainingVolume = includeVolume
        return selection
    }

    func load() async {
        do {
            let generated = try await useCases.generateReport(sessionID: sessionID, modules: modules)
            completed = generated.completed
            report = generated.report
            try await renderPreview(dto: generated.dto)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func refreshPreview() async {
        guard let completed else {
            return
        }
        do {
            let dto = try ShareReportPolicy.makeDTO(from: completed, modules: modules)
            try await renderPreview(dto: dto)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    func share() async {
        guard !isSharing else { return }
        isSharing = true
        defer { isSharing = false }
        do {
            let urls = lease?.fileURLs ?? []
            let outcome = await shareAdapter.share(fileURLs: urls)
            if let report {
                let updated = try await useCases.recordHandoff(report: report, outcome: outcome)
                self.report = updated
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

    private func renderPreview(dto: ShareReportDTO) async throws {
        previewLines = ShareReportPolicy.previewLines(for: dto)
        let result = try renderer.render(dto: dto, scale: 1)
        previewImages = result.pages.compactMap { UIImage(data: $0) }
        var currentLease = try lease ?? TempReportLease(rootURL: reportsRootURL, flowID: UUID())
        _ = try currentLease.replacePreview(pages: result.pages)
        lease = currentLease
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

struct ShareReportFlowView: View {
    @StateObject private var viewModel: ShareReportFlowViewModel
    @Binding var path: [RootDestination]

    init(
        sessionID: StableUUID,
        useCases: HistoryUseCases,
        reportsRootURL: URL,
        renderer: ShareReportRenderer,
        shareAdapter: SystemShareAdapter,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: ShareReportFlowViewModel(
                sessionID: sessionID,
                useCases: useCases,
                reportsRootURL: reportsRootURL,
                renderer: renderer,
                shareAdapter: shareAdapter
            )
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                    Text(String(localized: "share.modules"))
                        .font(.headline)
                    Toggle(isOn: $viewModel.includeVolume) {
                        Text(String(localized: "share.module.volume"))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(FCAccessibilityID.shareReportVolumeToggle)
                    .onChange(of: viewModel.includeVolume) { _, _ in
                        Task { await viewModel.refreshPreview() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(FCAccessibilityID.shareReportModules)

                VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                    ForEach(Array(viewModel.previewLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                    ForEach(Array(viewModel.previewImages.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(FCAccessibilityID.shareReportPreview)

                if viewModel.handedOff {
                    Text(String(localized: "share.handedToSystem"))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier(FCAccessibilityID.shareReportHandedOffStatus)
                } else if viewModel.lastOutcome == .cancelled || viewModel.lastOutcome == .failed {
                    Text(String(localized: "share.notSent"))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier(FCAccessibilityID.shareReportNotSentStatus)
                    FCButton(title: String(localized: "share.retry")) {
                        Task { await viewModel.share() }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.shareReportRetry)
                }

                if !viewModel.handedOff {
                    FCButton(title: String(localized: "share.handToSystem")) {
                        Task { await viewModel.share() }
                    }
                    .accessibilityIdentifier(FCAccessibilityID.shareReportShare)
                }

                FCButton(title: String(localized: "share.close")) {
                    viewModel.close()
                    if !path.isEmpty {
                        path.removeLast()
                    }
                }
                .accessibilityIdentifier(FCAccessibilityID.shareReportClose)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "share.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onDisappear { viewModel.close() }
    }
}
