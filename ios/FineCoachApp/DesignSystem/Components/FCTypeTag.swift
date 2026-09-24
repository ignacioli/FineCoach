import SwiftUI

/// The type tag (§8 "类型标签（15「有氧」）": 48×24 capsule, `surface.selected`
/// bg, `sectionLabel` `action.primary` text).
public struct FCTypeTag: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .fcFont(.sectionLabel)
            .foregroundStyle(FCSemanticColors.actionPrimary)
            .frame(width: 48, height: 24)
            .background(Capsule().fill(FCSemanticColors.surfaceSelected))
    }
}
