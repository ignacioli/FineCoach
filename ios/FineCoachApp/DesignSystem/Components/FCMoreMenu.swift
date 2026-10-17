import SwiftUI

/// The title-row ellipsis menu (`DS-MORE-MENU`,
/// `design/design-system/components.md` §4.8). Menu actions are supplied by
/// the caller; destructive actions must only present their confirmation flow.
public struct FCMoreMenu<MenuContent: View>: View {
    private let accessibilityIdentifier: String
    private let menuContent: MenuContent

    public init(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> MenuContent
    ) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.menuContent = content()
    }

    public var body: some View {
        let menu = Menu {
            menuContent
        } label: {
            Image(systemName: "ellipsis")
                .resizable()
                .scaledToFit()
                .fontWeight(.light)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .frame(width: 22, height: 20)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("designSystem.moreActions"))

        menu.accessibilityIdentifier(accessibilityIdentifier)
    }
}

#if DEBUG
    #Preview("More menu") {
        FCMoreMenu(accessibilityIdentifier: "preview.moreMenu") {
            Button("删除分区", role: .destructive) {}
        }
        .padding(.horizontal, FCPrimitives.space4)
    }
#endif
