import SwiftUI

/// D-a informational badge; the containing row owns its accessible name.
public struct FCNewRecordBadge: View {
    public init() {}

    public var body: some View {
        Text(String(localized: "session.set.newRecord"))
            .fcFont(.sectionLabel)
            .foregroundStyle(FCSemanticColors.actionPrimary)
            .padding(.horizontal, FCPrimitives.space2)
            .padding(.vertical, FCPrimitives.space1)
            .background(FCSemanticColors.surfaceSelected, in: Capsule())
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        FCNewRecordBadge()
    }
#endif
