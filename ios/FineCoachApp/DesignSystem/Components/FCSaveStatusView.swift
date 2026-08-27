import SwiftUI

public struct FCSaveStatusView: View {
    public enum Status: String, Sendable {
        case saving = "保存中"
        case saved = "已保存"
        case failed = "保存失败"
    }

    private let status: Status

    public init(status: Status) {
        self.status = status
    }

    public var body: some View {
        Label {
            Text(status.rawValue)
        } icon: {
            Image(systemName: iconName)
                .accessibilityHidden(true)
        }
        .foregroundStyle(status == .failed ? FCSemanticColors.destructive : FCSemanticColors.secondaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(status.rawValue))
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
