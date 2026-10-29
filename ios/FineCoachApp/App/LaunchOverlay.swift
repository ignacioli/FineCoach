import SwiftUI

struct LaunchOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                FCSemanticColors.surfaceLaunch
                Image("launch-mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.width)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
