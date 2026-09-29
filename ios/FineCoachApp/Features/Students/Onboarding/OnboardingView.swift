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
    @State private var path: [RootDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                    Text(String(localized: "onboarding.kicker"))
                        .fcFont(.callout, weight: .regular)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                    Text(String(localized: "onboarding.title"))
                        .fcFont(.titleLarge)
                        .accessibilityIdentifier(FCAccessibilityID.onboardingTitle)
                    Text(String(localized: "onboarding.lead"))
                        .accessibilityIdentifier(FCAccessibilityID.onboardingLead)
                    rule(String(localized: "onboarding.local"), identifier: FCAccessibilityID.onboardingLocalRule)
                    rule(String(localized: "onboarding.share"), identifier: FCAccessibilityID.onboardingShareRule)
                    rule(String(localized: "onboarding.operator"), identifier: "onboarding.operator")
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(FCSemanticColors.statusDestructive)
                    }
                    FCButton(title: String(localized: "onboarding.start")) {
                        path.append(.editor(.firstCreate))
                    }
                    .accessibilityIdentifier(FCAccessibilityID.onboardingStart)
                    Button {
                        Task { @MainActor in
                            if await viewModel.skip() {
                                onFinished()
                            }
                        }
                    } label: {
                        Text(String(localized: "onboarding.skip"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .contentShape(Rectangle())
                    .accessibilityIdentifier(FCAccessibilityID.onboardingSkip)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FCPrimitives.space4)
            }
            .background(FCSemanticColors.surfacePage)
            .navigationTitle(String(localized: "app.title"))
            .navigationBarTitleDisplayMode(.inline)
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

    private func rule(_ text: String, identifier: String) -> some View {
        Text(text)
            .padding(FCPrimitives.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FCSemanticColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusSm))
            .accessibilityIdentifier(identifier)
    }
}

extension OnboardingViewModel {
    var useCasesForEditor: StudentUseCases { useCases }
}
