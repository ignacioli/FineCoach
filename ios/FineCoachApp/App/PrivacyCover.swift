import SwiftUI

public struct PrivacyCover: View {
    public init() {}

    public var body: some View {
        FCSemanticColors.actionPrimary
            .ignoresSafeArea()
            .allowsHitTesting(true)
            .accessibilityIdentifier(FCAccessibilityID.privacyCover)
            .accessibilityHidden(true)
    }
}

/// System modals (`fullScreenCover`, `sheet`) are presented above the root
/// `ZStack` that holds the app-wide cover, so each modal's content carries
/// its own (NFR-003, T050b). The system file picker is outside our control.
private struct PrivacyCoveredModifier: ViewModifier {
    @EnvironmentObject private var privacyCoordinator: ScenePrivacyCoordinator

    func body(content: Content) -> some View {
        content.overlay {
            if privacyCoordinator.isCovered {
                PrivacyCover()
            }
        }
    }
}

extension View {
    func fcPrivacyCovered() -> some View {
        modifier(PrivacyCoveredModifier())
    }
}
