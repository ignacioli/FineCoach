import SwiftUI

/// The top-level segmented switch (`design/design-system/README.md` §8
/// "顶部分段切换（今日 / 学员）": selected item is a 50×32 capsule, `action.primary`
/// bg + `headline` white text; unselected items are plain text, `body`
/// `text.secondary`).
public struct FCSegmentedSwitch: View {
    public struct Option: Identifiable, Hashable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    private let options: [Option]
    @Binding private var selection: Option.ID

    public init(options: [Option], selection: Binding<Option.ID>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: FCPrimitives.space2) {
            ForEach(options) { option in
                let isSelected = option.id == selection
                Button {
                    selection = option.id
                } label: {
                    Text(option.title)
                        .fcFont(isSelected ? .headline : .body)
                        .foregroundStyle(isSelected ? FCSemanticColors.actionOn : FCSemanticColors.textSecondary)
                        .frame(minWidth: 50, minHeight: 32)
                        .background(
                            isSelected ? Capsule().fill(FCSemanticColors.actionPrimary) : nil
                        )
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
