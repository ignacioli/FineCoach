import SwiftUI

/// `DS-LIST-ROW` geometry (components.md §4.7), measured from M2-02a/02b/03:
/// the rows sit inside the page's own 16pt margins (no extra leading inset, so
/// titles start at the divider's x); a row is 52pt tall (+ the 1pt divider = a
/// 53pt pitch); a child row is indented by `space.4` and its divider starts at
/// the same indent.
enum FCListRowGeometry {
    static let minHeight: CGFloat = 52
    /// Row height in the archive viewer's 「紧凑」 list density (the 44pt hit-area minimum).
    static let compactMinHeight: CGFloat = 44
    static let indent: CGFloat = FCPrimitives.space4
}

/// The standard list row (§8 "列表行": left margin 16; main text `headline` or
/// `body`; meta text `caption` `text.secondary`; trailing `›`; rows separated
/// by a 1pt divider), with the M2 slots of `DS-LIST-ROW` (components.md §4.7):
/// a leading equipment icon slot, an indented sub-row, multi-line meta, a
/// trailing note, and a trailing `›` XOR selection circle.
///
/// The trailing accessory is chosen by the initializer, so `›` and the
/// selection circle can never appear together:
/// - `init(title:…showsDisclosure:action:)` — optional `›` (original API).
/// - `init(title:…isSelected:toggle:)` — selection circle; the whole row is
///   one tap target and reads `.isSelected`.
/// - `FCListRow.unavailable(title:…reason:)` — `text.disabled` title, the
///   reason as trailing note, no accessory, no action.
/// Group rows with a tri-state circle are `FCListGroupRow`.
public struct FCListRow: View {
    @Environment(\.fcCompactRows) private var isCompact

    public enum TitleStyle {
        case headline
        case body
    }

    /// The optional leading slot. `.equipmentSlot(nil)` reserves the 24×24
    /// space for a row that has no icon, so titles stay aligned.
    public enum Leading {
        case none
        case equipmentSlot(FCEquipmentIcon?)
    }

    private enum Interaction {
        case plain(showsDisclosure: Bool, action: (() -> Void)?)
        case selectable(isSelected: Bool, toggle: () -> Void)
        case unavailable(reason: String)
    }

    private let title: String
    private let titleStyle: TitleStyle
    private let subtitle: String?
    private let leading: Leading
    private let isIndented: Bool
    private let note: String?
    private let interaction: Interaction

    public init(
        title: String,
        titleStyle: TitleStyle = .body,
        subtitle: String? = nil,
        leading: Leading = .none,
        isIndented: Bool = false,
        note: String? = nil,
        showsDisclosure: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: title, titleStyle: titleStyle, subtitle: subtitle, leading: leading,
            isIndented: isIndented, note: note,
            interaction: .plain(showsDisclosure: showsDisclosure, action: action)
        )
    }

    /// A row with a selection circle; tapping anywhere on the row calls `toggle`.
    public init(
        title: String,
        titleStyle: TitleStyle = .body,
        subtitle: String? = nil,
        leading: Leading = .none,
        isIndented: Bool = false,
        note: String? = nil,
        isSelected: Bool,
        toggle: @escaping () -> Void
    ) {
        self.init(
            title: title, titleStyle: titleStyle, subtitle: subtitle, leading: leading,
            isIndented: isIndented, note: note,
            interaction: .selectable(isSelected: isSelected, toggle: toggle)
        )
    }

    /// An unavailable row: no circle, no `›`, no action; reads "title, reason".
    public static func unavailable(
        title: String,
        titleStyle: TitleStyle = .body,
        subtitle: String? = nil,
        leading: Leading = .none,
        isIndented: Bool = false,
        reason: String
    ) -> FCListRow {
        FCListRow(
            title: title, titleStyle: titleStyle, subtitle: subtitle, leading: leading,
            isIndented: isIndented, note: nil, interaction: .unavailable(reason: reason)
        )
    }

    private init(
        title: String,
        titleStyle: TitleStyle,
        subtitle: String?,
        leading: Leading,
        isIndented: Bool,
        note: String?,
        interaction: Interaction
    ) {
        self.title = title
        self.titleStyle = titleStyle
        self.subtitle = subtitle
        self.leading = leading
        self.isIndented = isIndented
        self.note = note
        self.interaction = interaction
    }

    public var body: some View {
        switch interaction {
        case .plain(_, let action?):
            Button(action: action) { content }
                .buttonStyle(.plain)
        case .selectable(let isSelected, let toggle):
            Button(action: toggle) { content }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        case .plain, .unavailable:
            content
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = interaction { return true }
        return false
    }

    private var trailingNote: String? {
        if case .unavailable(let reason) = interaction { return reason }
        return note
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: FCPrimitives.space3) {
            if case .equipmentSlot(let icon) = leading {
                Group {
                    if let icon {
                        FCEquipmentIconView(icon)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 24, height: 24)
            }
            HStack(spacing: FCPrimitives.space2) {
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(title)
                        .fcFont(titleStyle == .headline ? .headline : .body)
                        .foregroundStyle(isUnavailable ? FCSemanticColors.textDisabled : FCSemanticColors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: FCPrimitives.space2)
                if let trailingNote {
                    Text(trailingNote)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                accessory
            }
        }
        .padding(.leading, isIndented ? FCListRowGeometry.indent : 0)
        .frame(
            maxWidth: .infinity,
            minHeight: isCompact ? FCListRowGeometry.compactMinHeight : FCListRowGeometry.minHeight
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var accessory: some View {
        switch interaction {
        case .plain(let showsDisclosure, _):
            if showsDisclosure {
                FCSymbol(.forward)
            }
        case .selectable(let isSelected, _):
            FCListSelectionCircle(isSelected ? .selected : .unselected)
        case .unavailable:
            EmptyView()
        }
    }
}

/// The group row of `DS-LIST-ROW` (§4.7, M2-02): `headline` title → trailing
/// note → expand symbol (`FCSymbol(.collapse)`, rotated up while expanded) →
/// tri-state selection circle. Two separate hit areas, each >= 44: the circle
/// toggles the whole group, the rest of the row expands / collapses.
///
/// The circle state is never set by the caller: `selectionState` is computed
/// from `childSelections`, so a partial state can only come from the
/// children. VoiceOver reads one element ("title, note, selection state,
/// expanded state") with 「切换选择」and 「展开 / 折叠」actions.
public struct FCListGroupRow: View {
    public enum SelectionState: Sendable, Equatable {
        case noneSelected
        case partiallySelected
        case allSelected

        /// No children, or no child selected → `noneSelected`; every child
        /// selected → `allSelected`; otherwise `partiallySelected`.
        public init(childSelections: [Bool]) {
            let selectedCount = childSelections.filter { $0 }.count
            if selectedCount == 0 {
                self = .noneSelected
            } else if selectedCount == childSelections.count {
                self = .allSelected
            } else {
                self = .partiallySelected
            }
        }
    }

    private let title: String
    private let note: String?
    private let childSelections: [Bool]
    private let isExpanded: Bool
    private let onToggleSelection: () -> Void
    private let onToggleExpansion: () -> Void

    public init(
        title: String,
        note: String? = nil,
        childSelections: [Bool],
        isExpanded: Bool,
        onToggleSelection: @escaping () -> Void,
        onToggleExpansion: @escaping () -> Void
    ) {
        self.title = title
        self.note = note
        self.childSelections = childSelections
        self.isExpanded = isExpanded
        self.onToggleSelection = onToggleSelection
        self.onToggleExpansion = onToggleExpansion
    }

    public var selectionState: SelectionState {
        SelectionState(childSelections: childSelections)
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleExpansion) {
                HStack(spacing: FCPrimitives.space2) {
                    Text(title)
                        .fcFont(.headline)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: FCPrimitives.space2)
                    if let note {
                        Text(note)
                            .fcFont(.caption)
                            .foregroundStyle(FCSemanticColors.textSecondary)
                    }
                    FCSymbol(.collapse)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: FCListRowGeometry.minHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleSelection) {
                FCListSelectionCircle(circleState)
                    .frame(minWidth: 44, minHeight: FCListRowGeometry.minHeight, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: FCListRowGeometry.minHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityAction(.default, onToggleExpansion)
        .accessibilityAction(named: Text("designSystem.listRow.action.toggleSelection"), onToggleSelection)
        .accessibilityAction(
            named: Text(
                isExpanded
                    ? LocalizedStringKey("designSystem.listRow.action.collapse")
                    : LocalizedStringKey("designSystem.listRow.action.expand")
            ),
            onToggleExpansion
        )
    }

    private var circleState: FCListSelectionCircle.State {
        switch selectionState {
        case .noneSelected: return .unselected
        case .partiallySelected: return .partial
        case .allSelected: return .selected
        }
    }

    private var accessibilityLabelText: String {
        guard let note else { return title }
        return "\(title)，\(note)"
    }

    private var accessibilityValueText: String {
        let selection: String
        switch selectionState {
        case .noneSelected: selection = String(localized: "designSystem.listRow.state.none")
        case .partiallySelected: selection = String(localized: "designSystem.listRow.state.partial")
        case .allSelected: selection = String(localized: "designSystem.listRow.state.all")
        }
        let expansion = isExpanded
            ? String(localized: "designSystem.listRow.state.expanded")
            : String(localized: "designSystem.listRow.state.collapsed")
        return "\(selection)，\(expansion)"
    }
}

/// The selection circle of `FCListRow` / `FCListGroupRow`: unselected and
/// selected reuse `FCSetStateCircle` (pending / completed); partial is an
/// `action.primary` fill with a white `−`. Decorative.
struct FCListSelectionCircle: View {
    enum State {
        case unselected
        case partial
        case selected
    }

    private let state: State

    init(_ state: State) {
        self.state = state
    }

    var body: some View {
        switch state {
        case .unselected:
            FCSetStateCircle(.pending)
        case .selected:
            FCSetStateCircle(.completed)
        case .partial:
            ZStack {
                Circle().fill(FCSemanticColors.actionPrimary)
                FCSymbol(.minus, color: FCSemanticColors.actionOn)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
        }
    }
}

#if DEBUG
    #Preview("List rows") {
        VStack(spacing: 0) {
            FCListRow(title: "学员资料", showsDisclosure: true) {}
            FCListRowDivider()
            FCListRow(title: "上次训练", subtitle: "深蹲 5×5，感觉不错。\n下次加重 2.5 kg，注意左膝。", note: "3 天前", action: {})
            FCListRowDivider()
            FCListRow(
                title: "杠铃卧推", leading: .equipmentSlot(.barbell), note: "12 次",
                isSelected: true, toggle: {}
            )
            FCListRowDivider()
            FCListRow(
                title: "自重俯卧撑", leading: .equipmentSlot(nil), isIndented: true,
                isSelected: false, toggle: {}
            )
            FCListRowDivider()
            FCListRow.unavailable(title: "身体数据", reason: "档案未包含")
        }
    }

    #Preview("Group rows") {
        VStack(spacing: 0) {
            FCListGroupRow(
                title: "胸", note: "3 个动作", childSelections: [true, false, true], isExpanded: true,
                onToggleSelection: {}, onToggleExpansion: {}
            )
            FCListRow(title: "杠铃卧推", isIndented: true, isSelected: true, toggle: {})
            FCListGroupRow(
                title: "背", note: "2 个动作", childSelections: [true, true], isExpanded: false,
                onToggleSelection: {}, onToggleExpansion: {}
            )
            FCListGroupRow(
                title: "腿", childSelections: [false, false], isExpanded: false,
                onToggleSelection: {}, onToggleExpansion: {}
            )
        }
    }
#endif

/// The 1pt divider between list rows (§6: "分割线：1pt，`surface.divider`").
/// A separate view rather than baked into `FCListRow` so callers composing
/// rows in a plain `VStack` (not a native `List`, which draws its own
/// separators) control exactly where dividers appear.
public struct FCListRowDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(FCSemanticColors.surfaceDivider)
            .frame(height: 1)
    }
}

/// The section label (§8 "区段标签": `sectionLabel`, `text.secondary`).
public struct FCSectionLabel: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .fcFont(.sectionLabel)
            .foregroundStyle(FCSemanticColors.textSecondary)
    }
}

/// The list group entry row (§8.1 "列表分组入口行": "已归档 · N ›" /
/// "已处理 · N ›", `sectionLabel` `text.secondary` + trailing `›`).
public struct FCGroupEntryRow: View {
    private let title: String
    private let count: Int
    private let action: () -> Void

    public init(title: String, count: Int, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: FCPrimitives.space2) {
                Text(verbatim: "\(title) · \(count)")
                    .fcFont(.sectionLabel)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                Spacer(minLength: FCPrimitives.space2)
                FCSymbol(.forward)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The label–value row (§8.1 "标签-值两栏行": label `callout` 400
/// `text.secondary` at x=16, value at x=112 (a 96pt label column), row
/// height 48–52, rows separated by `FCListRowDivider`). Used by the 02
/// redraw, student-detail profile section, and edit-profile page.
///
/// `value` is any view: plain `body` text, a control such as a `Toggle`
/// with `FCToggleStyle`, or text plus a trailing element. Pass `action` to
/// make the whole row tappable with a trailing `›`; pass
/// `showsDisclosure: true` without an action when the row is the label of
/// an enclosing `Menu`. Rows with a view-builder value keep their children
/// separately accessible (controls stay operable); plain-text rows read as
/// one element.
public struct FCLabelValueRow<Value: View>: View {
    private let label: String
    private let value: Value
    private let action: (() -> Void)?
    private let showsDisclosure: Bool
    private let combinesAccessibility: Bool

    private static var labelColumnWidth: CGFloat { 112 - FCPrimitives.space4 }

    public init(
        label: String,
        showsDisclosure: Bool? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder value: () -> Value
    ) {
        self.init(label: label, showsDisclosure: showsDisclosure, action: action, combinesAccessibility: false, value: value())
    }

    fileprivate init(
        label: String,
        showsDisclosure: Bool?,
        action: (() -> Void)?,
        combinesAccessibility: Bool,
        value: Value
    ) {
        self.label = label
        self.action = action
        self.showsDisclosure = showsDisclosure ?? (action != nil)
        self.combinesAccessibility = combinesAccessibility
        self.value = value
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else if combinesAccessibility {
            content
                .accessibilityElement(children: .combine)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            Text(label)
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsDisclosure {
                FCSymbol(.forward)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }
}

public extension FCLabelValueRow where Value == FCLabelValueText {
    /// A row whose value is plain `body` `text.primary` text.
    init(label: String, value: String, showsDisclosure: Bool? = nil, action: (() -> Void)? = nil) {
        self.init(
            label: label,
            showsDisclosure: showsDisclosure,
            action: action,
            combinesAccessibility: true,
            value: FCLabelValueText(value)
        )
    }
}

/// The plain-text value of an `FCLabelValueRow` (`body`, `text.primary`).
public struct FCLabelValueText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .fcFont(.body)
            .foregroundStyle(FCSemanticColors.textPrimary)
    }
}

private struct FCCompactRowsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Compact list density (archive viewer 「列表密度 · 紧凑」): `FCListRow` uses its 44pt minimum
    /// height instead of 52. Off everywhere else.
    var fcCompactRows: Bool {
        get { self[FCCompactRowsKey.self] }
        set { self[FCCompactRowsKey.self] = newValue }
    }
}
