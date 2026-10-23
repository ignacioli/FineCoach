import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var errorMessage: String?

    private let useCases: StudentUseCases

    init(useCases: StudentUseCases) {
        self.useCases = useCases
    }

    func skip() async -> Bool {
        do {
            try await useCases.completeOnboarding()
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
            return false
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onFinished: () -> Void
    /// Set while the install is still `unselected`: back to the first-launch choice (M2-07).
    /// Nothing is written until the coach adds a first student or skips below.
    var onBack: (() -> Void)?
    @State private var path: [RootDestination] = []
    @State private var isDataSheetPresented = false
    /// Entry animation (welcome-redesign.md §10): plays once; sheet close and returning from
    /// the editor keep this view alive, so it never replays.
    @State private var isRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if let onBack {
                    FCPageHeader(
                        title: "",
                        back: .init(accessibilityIdentifier: FCAccessibilityID.onboardingBack, handler: onBack)
                    )
                    .padding(.horizontal, FCPrimitives.space4)
                }
                ScrollView {
                    welcomeContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, FCPrimitives.space4)
                        .padding(.top, onBack == nil ? FCPrimitives.space8 : FCPrimitives.space6)
                }
                .scrollBounceBehavior(.basedOnSize)
                bottomActions
            }
            .background(FCSemanticColors.surfacePage)
            .fcBottomSheet(isPresented: $isDataSheetPresented) { dataSheet }
            .fcSecondaryPage()
            .onAppear(perform: playEntryAnimation)
            .navigationDestination(for: RootDestination.self) { destination in
                if case .editor(let mode) = destination {
                    StudentEditorView(
                        viewModel: StudentEditorViewModel(mode: mode, useCases: viewModelUseCases),
                        path: $path,
                        onFinished: { _ in
                            Task {
                                _ = await viewModel.skip()
                                onFinished()
                            }
                        }
                    )
                }
            }
        }
    }

    private var viewModelUseCases: StudentUseCases {
        viewModel.useCasesForEditor
    }

    // MARK: W-01b content

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Image("mascot-avatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusLg))
                    .accessibilityHidden(true)
                Text(String(localized: "onboarding.title"))
                    .fcFont(.display)
                    .foregroundStyle(FCSemanticColors.actionPrimary)
                    .padding(.top, FCPrimitives.space6)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(FCAccessibilityID.onboardingTitle)
                Text(String(localized: "onboarding.subtitle"))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .padding(.top, FCPrimitives.space2)
                    .accessibilityIdentifier(FCAccessibilityID.onboardingLead)
            }
            .welcomeReveal(isRevealed, delay: 0, reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                pointRow("doc.text", "onboarding.point.offline", delay: EntryTiming.pointOne)
                pointRow("iphone", "onboarding.point.local", delay: EntryTiming.pointTwo)
                pointRow("lock", "onboarding.point.private", delay: EntryTiming.pointThree)
            }
            .padding(.top, FCPrimitives.space8)

            FCLinkButton(title: String(localized: "onboarding.link")) {
                isDataSheetPresented = true
            }
            .accessibilityIdentifier(FCAccessibilityID.onboardingDataLink)
            .welcomeReveal(
                isRevealed, delay: EntryTiming.link, duration: EntryTiming.linkDuration, reduceMotion: reduceMotion
            )
            .padding(.top, FCPrimitives.space6)
        }
    }

    /// Static icon + `headline` title row (W-WELCOME part, not a `DS-HUB-ROW`): not tappable,
    /// icon hidden from VoiceOver, the row reads as its title.
    private func pointRow(_ symbol: String, _ key: String, delay: Double) -> some View {
        HStack(spacing: FCPrimitives.space4) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(FCSemanticColors.actionPrimary)
                .accessibilityHidden(true)
            Text(String(localized: String.LocalizationValue(key)))
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.textPrimary)
        }
        .padding(.vertical, FCPrimitives.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .welcomeReveal(isRevealed, delay: delay, reduceMotion: reduceMotion)
    }

    /// Primary and secondary actions are outside the animation: visible and tappable from the
    /// first frame.
    private var bottomActions: some View {
        VStack(spacing: FCPrimitives.space2) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            FCButton(title: String(localized: "onboarding.start")) {
                path.append(.editor(.firstCreate))
            }
            .accessibilityIdentifier(FCAccessibilityID.onboardingStart)
            FCLinkButton(title: String(localized: "onboarding.skip")) {
                Task { @MainActor in
                    if await viewModel.skip() {
                        onFinished()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(FCAccessibilityID.onboardingSkip)
        }
        .padding(.horizontal, FCPrimitives.space4)
        .padding(.vertical, FCPrimitives.space2)
    }

    // MARK: W-02 data sheet

    private var dataSheet: some View {
        FCBottomSheet(
            title: String(localized: "onboarding.sheet.title"),
            titleStyle: .title,
            subtitle: String(localized: "onboarding.sheet.subtitle")
        ) {
            VStack(spacing: FCPrimitives.space2) {
                // Rows grow with Dynamic Type; scroll only when they no longer fit.
                ViewThatFits(in: .vertical) {
                    sheetRows
                    ScrollView { sheetRows }
                }
                FCLinkButton(title: String(localized: "onboarding.sheet.close")) {
                    isDataSheetPresented = false
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(FCAccessibilityID.onboardingSheetClose)
            }
        }
        .accessibilityIdentifier(FCAccessibilityID.onboardingSheet)
    }

    private var sheetRows: some View {
        VStack(spacing: 0) {
            FCHubRow(
                icon: .symbol("doc.text"),
                title: String(localized: "onboarding.point.offline"),
                subtitle: .text(String(localized: "onboarding.sheet.offline.detail")),
                mode: .informational
            )
            FCListRowDivider()
            FCHubRow(
                icon: .symbol("iphone"),
                title: String(localized: "onboarding.point.local"),
                subtitle: .text(String(localized: "onboarding.sheet.local.detail")),
                mode: .informational
            )
            .accessibilityIdentifier(FCAccessibilityID.onboardingLocalRule)
            FCListRowDivider()
            FCHubRow(
                icon: .symbol("lock"),
                title: String(localized: "onboarding.point.private"),
                subtitle: .text(String(localized: "onboarding.sheet.private.detail")),
                mode: .informational
            )
            .accessibilityIdentifier(FCAccessibilityID.onboardingShareRule)
            FCListRowDivider()
            FCHubRow(
                icon: .symbol("person"),
                title: String(localized: "onboarding.sheet.operator.title"),
                subtitle: .text(String(localized: "onboarding.sheet.operator.detail")),
                mode: .informational
            )
            FCListRowDivider()
            FCHubRow(
                icon: .symbol("bell"),
                title: String(localized: "onboarding.sheet.permission.title"),
                subtitle: .text(String(localized: "onboarding.sheet.permission.detail")),
                mode: .informational
            )
        }
    }

    // MARK: Entry animation (welcome-redesign.md §10)

    private func playEntryAnimation() {
        guard !isRevealed else { return }
        // Reduce Motion: the modifier fades only (no offset); the state flip is the same.
        isRevealed = true
    }
}

/// Animation parameters (seconds), not design tokens.
private enum EntryTiming {
    static let pointOne = 0.25
    static let pointTwo = 0.35
    static let pointThree = 0.45
    static let link = 0.55
    static let linkDuration = 0.25
    static let standardDuration = 0.35
    static let reduceMotionDuration = 0.2
}

extension View {
    /// Fade in and rise `space.2`; with Reduce Motion a plain 0.2 s fade, no offset, no delay.
    /// The view is in the accessibility tree from the first frame; only opacity/offset change.
    fileprivate func welcomeReveal(
        _ isRevealed: Bool,
        delay: Double,
        duration: Double = EntryTiming.standardDuration,
        reduceMotion: Bool
    ) -> some View {
        opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : FCPrimitives.space2)
            .animation(
                reduceMotion
                    ? .easeOut(duration: EntryTiming.reduceMotionDuration)
                    : .easeOut(duration: duration).delay(delay),
                value: isRevealed
            )
    }
}

extension OnboardingViewModel {
    var useCasesForEditor: StudentUseCases { useCases }
}
