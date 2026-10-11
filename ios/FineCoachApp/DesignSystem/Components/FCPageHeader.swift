import SwiftUI

/// The secondary-page header (`DS-PAGE-HEADER`, components.md §4.7): an
/// in-page `titleLarge` `text.primary` title (a header for VoiceOver) → an
/// optional `callout` 400 `text.secondary` subtitle (`space.2` below) → an
/// optional trailing text action on the title's line (`callout` 600
/// `action.primary`, `text.disabled` when disabled; hit area >= 44).
///
/// With a `back` action the small `‹` (22/400 `text.secondary`, a Noto Sans SC
/// glyph, README §7.2) sits on the title's first line, immediately left of the
/// title (title starts at x = 32 = page margin + 16), baseline-aligned; its hit
/// area is 44×44 and extends over the glyph's surroundings without taking
/// layout space. The calling page hides the system navigation bar with
/// `fcSecondaryPage(...)`, which also keeps the edge swipe-back working.
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

    /// The inline back control. A `nil` handler pops the current navigation
    /// destination (`dismiss`); pass a handler for a flow's own step-back.
    public struct BackAction {
        public let accessibilityIdentifier: String?
        public let handler: (() -> Void)?

        public init(accessibilityIdentifier: String? = nil, handler: (() -> Void)? = nil) {
            self.accessibilityIdentifier = accessibilityIdentifier
            self.handler = handler
        }
    }

    /// Width the glyph occupies in layout: the title starts at page margin + this.
    static let backLayoutWidth: CGFloat = FCPrimitives.space4

    private let title: String
    private let subtitle: String?
    private let trailingAction: TrailingAction?
    private let back: BackAction?

    @Environment(\.dismiss) private var dismiss

    public init(
        title: String,
        subtitle: String? = nil,
        back: BackAction? = nil,
        trailingAction: TrailingAction? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.trailingAction = trailingAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack(alignment: .center, spacing: FCPrimitives.space2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if let back {
                        backControl(back)
                    }
                    if title.isEmpty {
                        // No title (29 share preview, a not-yet-loaded page): back and
                        // the trailing action only.
                        Spacer(minLength: 0)
                    } else {
                        Text(title)
                            .fcFont(.titleLarge)
                            .foregroundStyle(FCSemanticColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
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

    private func backControl(_ back: BackAction) -> some View {
        FCSymbol(.pageBack)
            .frame(width: Self.backLayoutWidth, alignment: .leading)
            .overlay(alignment: .leading) {
                let button = Button {
                    if let handler = back.handler { handler() } else { dismiss() }
                } label: {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.back"))
                if let identifier = back.accessibilityIdentifier {
                    button.accessibilityIdentifier(identifier)
                } else {
                    button
                }
            }
            .zIndex(1)
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
    #Preview("Back + title") {
        FCPageHeader(title: "导出个人训练档案", subtitle: "王小明", back: .init())
            .padding(FCPrimitives.space4)
    }

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

// MARK: - Secondary page chrome

public extension View {
    /// The secondary-page chrome (`DS-PAGE-SECONDARY`): hides the system
    /// navigation bar (the back control is `FCPageHeader`'s inline `‹`) and
    /// keeps the interactive edge swipe-back working, which SwiftUI/UIKit
    /// disable once the bar is hidden. Pass `swipeBackEnabled: false` on a
    /// page whose back is a step inside a flow (M2-03 to M2-05).
    func fcSecondaryPage(swipeBackEnabled: Bool = true) -> some View {
        toolbar(.hidden, for: .navigationBar)
            .background(FCSwipeBackEnabler(isEnabled: swipeBackEnabled).frame(width: 0, height: 0))
    }
}

/// Re-enables (or, with `isEnabled == false`, disables) the enclosing
/// `UINavigationController`'s edge-swipe and content-swipe pop gestures while
/// the page shows. The pop recognizer's delegate refuses to begin when the
/// navigation bar is hidden; the replacement delegate allows it whenever a
/// page is underneath. The previous state is restored when the page goes away.
struct FCSwipeBackEnabler: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(context: Context) -> Controller { Controller(isEnabled: isEnabled) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isEnabled = isEnabled
        controller.apply()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var isEnabled: Bool
        private var originalDelegate: UIGestureRecognizerDelegate?
        private weak var configuredNavigation: UINavigationController?

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restore()
        }

        func apply() {
            guard let navigation = navigationController else { return }
            let pop = navigation.interactivePopGestureRecognizer
            if configuredNavigation !== navigation {
                originalDelegate = pop?.delegate
                configuredNavigation = navigation
            }
            pop?.delegate = self
            pop?.isEnabled = isEnabled
            setContentPop(isEnabled, navigation)
        }

        private func restore() {
            guard let navigation = configuredNavigation else { return }
            navigation.interactivePopGestureRecognizer?.isEnabled = true
            navigation.interactivePopGestureRecognizer?.delegate = originalDelegate
            setContentPop(true, navigation)
            configuredNavigation = nil
        }

        private func setContentPop(_ enabled: Bool, _ navigation: UINavigationController) {
            if #available(iOS 26.0, *) {
                navigation.interactiveContentPopGestureRecognizer?.isEnabled = enabled
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let navigation = configuredNavigation else { return false }
            return navigation.viewControllers.count > 1
        }
    }
}
