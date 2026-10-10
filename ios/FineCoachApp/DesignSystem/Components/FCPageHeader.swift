import SwiftUI

/// The secondary-page header (`DS-PAGE-HEADER`, components.md §4.7): an
/// in-page `titleLarge` `text.primary` title (a header for VoiceOver) → an
/// optional `callout` 400 `text.secondary` subtitle (`space.2` below) → an
/// optional trailing text action on the title's line (`callout` 600
/// `action.primary`, `text.disabled` when disabled; hit area >= 44).
///
/// The system navigation bar (back `‹` only) is the calling page's concern
/// (`.navigationBarTitleDisplayMode(.inline)` + `.toolbarRole(.editor)`).
/// Title and subtitle wrap, never truncate; with a trailing action the title
/// yields width to it instead of overlapping.
public struct FCPageHeader: View {
    /// The trailing text action (e.g. 26「编辑资料」).
    public struct TrailingAction {
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

    private let title: String
    private let subtitle: String?
    private let trailingAction: TrailingAction?

    public init(title: String, subtitle: String? = nil, trailingAction: TrailingAction? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailingAction = trailingAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack(alignment: .center, spacing: FCPrimitives.space2) {
                Text(title)
                    .fcFont(.titleLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if let trailingAction {
                    actionButton(trailingAction)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionButton(_ action: TrailingAction) -> some View {
        let button = Button(action: action.handler) {
            Text(action.title)
                .fcFont(.callout, weight: .semibold)
                .foregroundStyle(action.isEnabled ? FCSemanticColors.actionPrimary : FCSemanticColors.textDisabled)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        if let identifier = action.accessibilityIdentifier {
            button.accessibilityIdentifier(identifier)
        } else {
            button
        }
    }
}

#if DEBUG
    #Preview("Title only") {
        FCPageHeader(title: "资料库")
            .padding(FCPrimitives.space4)
    }

    #Preview("Subtitle") {
        FCPageHeader(title: "备份与恢复", subtitle: "在这台设备上创建或恢复加密备份")
            .padding(FCPrimitives.space4)
    }

    #Preview("Trailing action") {
        VStack(spacing: FCPrimitives.space6) {
            FCPageHeader(
                title: "李明",
                trailingAction: .init(title: "编辑资料") {}
            )
            FCPageHeader(
                title: "李明",
                trailingAction: .init(title: "编辑资料", isEnabled: false) {}
            )
        }
        .padding(FCPrimitives.space4)
    }

    #Preview("Long title") {
        FCPageHeader(
            title: "一个非常非常长的学员名称用来检查标题换行而不是截断或者与尾部操作重叠",
            subtitle: "副标题同样很长，需要随动态字体换行显示，不能被截断，也不能与上面的标题发生重叠。",
            trailingAction: .init(title: "编辑资料") {}
        )
        .padding(FCPrimitives.space4)
    }
#endif
