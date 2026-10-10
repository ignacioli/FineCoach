import SwiftUI

public struct FCSaveStatusView: View {
    public enum Status: Sendable {
        case saving
        case saved
        case failed

        /// The state text (localized keys; zh-Hans: 保存中 / 已保存 / 保存失败).
        public var text: String {
            switch self {
            case .saving: return String(localized: "designSystem.saveStatus.saving")
            case .saved: return String(localized: "designSystem.saveStatus.saved")
            case .failed: return String(localized: "designSystem.saveStatus.failed")
            }
        }
    }

    private let status: Status

    public init(status: Status) {
        self.status = status
    }

    public var body: some View {
        Label {
            Text(status.text)
                .fcFont(.body)
        } icon: {
            Image(systemName: iconName)
                .accessibilityHidden(true)
        }
        .foregroundStyle(status == .failed ? FCSemanticColors.statusDestructive : FCSemanticColors.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(status.text))
        .frame(minHeight: 44)
    }

    private var iconName: String {
        switch status {
        case .saving:
            return "arrow.triangle.2.circlepath"
        case .saved:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}
