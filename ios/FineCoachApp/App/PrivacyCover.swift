import SwiftUI

public struct PrivacyCover: View {
    public init() {}

    public var body: some View {
        Color.black
            .ignoresSafeArea()
            .allowsHitTesting(true)
            .accessibilityHidden(true)
    }
}
