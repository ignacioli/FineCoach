import SwiftUI

struct LaunchOverlay: View {
    var body: some View {
        ZStack {
            FCSemanticColors.surfacePage
            Image("launch-icon")
                .resizable()
                .frame(width: 180, height: 180)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
