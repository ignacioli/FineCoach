import SwiftUI

/// The in-place result of one operation on the current page
/// (`DS-INLINE-RESULT`, components.md §4.7; 38/39): a 22×22 `FCStatusBadge`
/// and a `callout` 600 title on one line, the message (`caption`
/// `text.secondary`, wraps, never truncates) below the title, and an
/// optional centred 「重试」`FCLinkButton`.
///
/// Exactly three variants (`Variant`): failure (`status.destructive` "!",
/// destructive title), success (`action.primary` ✓, `text.primary` title) and
/// info (`action.primary` "i", `text.primary` title). Every variant has a
/// glyph and a title, so a result is never colour-only. The badge is hidden
/// from accessibility; title and message read as one element; the retry
/// button is separately accessible (hit area >= 44).
///
/// Persistent business states that need coach action belong to `FCStatusLabel`;
/// save progress to `FCSaveStatusView`.
public struct FCInlineResult: View {
    public enum Variant: CaseIterable, Sendable {
        case failure
        case success
        case info

        public var symbolName: String {
            switch self {
            case .failure: return "exclamationmark"
            case .success: return "checkmark"
            case .info: return "info"
            }
        }

        public var badgeColor: Color {
            switch self {
            case .failure: return FCSemanticColors.statusDestructive
            case .success, .info: return FCSemanticColors.actionPrimary
            }
        }

        public var titleColor: Color {
            switch self {
            case .failure: return FCSemanticColors.statusDestructive
            case .success, .info: return FCSemanticColors.textPrimary
            }
        }
    }

    public struct Retry {
        public let title: String
        public let isEnabled: Bool
        public let accessibilityIdentifier: String?
        public let handler: () -> Void

        public init(
            title: String,
            isEnabled: Bool = true,
            accessibilityIdentifier: String? = nil,
            handler: @escaping () -> Void
        ) {
            self.title = title
            self.isEnabled = isEnabled
            self.accessibilityIdentifier = accessibilityIdentifier
            self.handler = handler
        }
    }

    private let variant: Variant
    private let title: String
    private let message: String?
    private let retry: Retry?
    private let accessibilityIdentifier: String?

    /// - Parameter accessibilityIdentifier: identifies the title + message
    ///   element; the retry button has its own on `Retry`.
    public init(
        _ variant: Variant,
        title: String,
        message: String? = nil,
        retry: Retry? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.variant = variant
        self.title = title
        self.message = message
        self.retry = retry
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        VStack(spacing: FCPrimitives.space3) {
            result
            if let retry {
                retryButton(retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var result: some View {
        let block = VStack(alignment: .leading, spacing: FCPrimitives.space1) {
            HStack(spacing: FCPrimitives.space2) {
                FCStatusBadge(symbolName: variant.symbolName, color: variant.badgeColor)
                Text(title)
                    .fcFont(.callout, weight: .semibold)
                    .foregroundStyle(variant.titleColor)
            }
            if let message {
                Text(message)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        if let accessibilityIdentifier {
            block.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            block
        }
    }

    @ViewBuilder
    private func retryButton(_ retry: Retry) -> some View {
        let button = FCLinkButton(title: retry.title, isEnabled: retry.isEnabled, action: retry.handler)
            .frame(maxWidth: .infinity)
        if let identifier = retry.accessibilityIdentifier {
            button.accessibilityIdentifier(identifier)
        } else {
            button
        }
    }
}

#if DEBUG
    #Preview("Variants") {
        VStack(alignment: .leading, spacing: FCPrimitives.space6) {
            FCInlineResult(
                .failure,
                title: "恢复失败",
                message: "备份文件无法读取或密码不正确，当前数据没有改动。",
                retry: .init(title: "重试") {}
            )
            FCInlineResult(.success, title: "恢复完成", message: "检查恢复后的学员、课程与训练记录。")
            FCInlineResult(.info, title: "已取消", message: "没有交付任何文件。", retry: .init(title: "重试") {})
        }
        .padding(FCPrimitives.space4)
    }
#endif
