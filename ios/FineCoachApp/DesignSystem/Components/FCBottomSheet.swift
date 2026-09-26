import SwiftUI

/// The bottom sheet (§8.1 "底部面板（sheet）": full width, top corners
/// `radius.lg`, white bg, `overlay.scrim` behind it; centered 36×5 drag
/// handle in `surface.divider`; title `headline` or `title`, subtitle
/// `callout` 400 `text.secondary`).
///
/// This is the sheet's content card only. Present it with
/// `View.fcBottomSheet(isPresented:content:)`, which draws the scrim — the
/// system `.sheet` dims with its own color, not `overlay.scrim`.
public struct FCBottomSheet<Accessory: View, Content: View>: View {
    public enum TitleStyle {
        case headline
        case title
    }

    private let title: String?
    private let titleStyle: TitleStyle
    private let subtitle: String?
    private let accessory: Accessory
    private let content: Content

    /// - Parameter accessory: Optional trailing element on the title line
    ///   (e.g. the status text in `18-course-action-sheet`).
    public init(
        title: String? = nil,
        titleStyle: TitleStyle = .headline,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleStyle = titleStyle
        self.subtitle = subtitle
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Capsule()
                .fill(FCSemanticColors.surfaceDivider)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, FCPrimitives.space2)
                .accessibilityHidden(true)

            if title != nil || subtitle != nil {
                HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space2) {
                    VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                        if let title {
                            Text(title)
                                .fcFont(titleStyle == .title ? .title : .headline)
                                .foregroundStyle(FCSemanticColors.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .fcFont(.callout, weight: .regular)
                                .foregroundStyle(FCSemanticColors.textSecondary)
                        }
                    }
                    Spacer(minLength: FCPrimitives.space2)
                    accessory
                }
            }

            content
        }
        .padding(.horizontal, FCPrimitives.space4)
        .padding(.bottom, FCPrimitives.space6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: FCPrimitives.radiusLg,
                topTrailingRadius: FCPrimitives.radiusLg
            )
            .fill(FCSemanticColors.surfacePage)
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

public extension FCBottomSheet where Accessory == EmptyView {
    init(
        title: String? = nil,
        titleStyle: TitleStyle = .headline,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, titleStyle: titleStyle, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// Presents `content` (normally an `FCBottomSheet`) pinned to the bottom
/// edge over an `overlay.scrim` layer. Tapping the scrim or dragging the
/// sheet down dismisses it. Apply at a container that covers the whole
/// screen so the scrim covers everything behind the sheet.
private struct FCBottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheetContent: () -> SheetContent

    @GestureState private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack(alignment: .bottom) {
                    if isPresented {
                        FCSemanticColors.overlayScrim
                            .ignoresSafeArea()
                            .onTapGesture { isPresented = false }
                            .accessibilityLabel(Text("designSystem.sheet.dismiss"))
                            .accessibilityAddTraits(.isButton)
                            .transition(.opacity)

                        sheetContent()
                            .offset(y: max(0, dragOffset))
                            .gesture(
                                DragGesture()
                                    .updating($dragOffset) { value, state, _ in
                                        state = value.translation.height
                                    }
                                    .onEnded { value in
                                        if value.translation.height > 80 { isPresented = false }
                                    }
                            )
                            .transition(.move(edge: .bottom))
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape) { isPresented = false }
                    }
                }
                .animation(.easeOut(duration: 0.25), value: isPresented)
            }
    }
}

public extension View {
    /// Presents a design-system bottom sheet over `overlay.scrim` (§8.1).
    func fcBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(FCBottomSheetModifier(isPresented: isPresented, sheetContent: content))
    }
}

/// The sheet action row (§8.1 "操作行": height 52; `body` text on the left;
/// optional trailing `caption` `text.secondary` note + `›`; destructive
/// actions use `status.destructive` text and no `›`). A destructive row does
/// not confirm by itself — the caller MUST show an `FCConfirmationDialog`
/// from `action` (§8.1). Rows are separated by `FCListRowDivider`.
///
/// With a `subtitle` (the two-line rows of `24-edit-occurrence-scope`), the
/// title is `headline` and the subtitle `caption` `text.secondary` below it.
/// A disabled row renders its text in `text.disabled` and ignores taps.
public struct FCActionRow: View {
    public enum Role {
        case normal
        case destructive
    }

    private let title: String
    private let subtitle: String?
    private let note: String?
    private let role: Role
    private let isEnabled: Bool
    private let action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        note: String? = nil,
        role: Role = .normal,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.note = note
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: FCPrimitives.space2) {
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(title)
                        .fcFont(subtitle == nil ? .body : .headline)
                        .foregroundStyle(titleColor)
                    if let subtitle {
                        Text(subtitle)
                            .fcFont(.caption)
                            .foregroundStyle(isEnabled ? FCSemanticColors.textSecondary : FCSemanticColors.textDisabled)
                    }
                }
                Spacer(minLength: FCPrimitives.space2)
                if let note {
                    Text(note)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                if role == .normal {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(isEnabled ? FCSemanticColors.textSecondary : FCSemanticColors.textDisabled)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, subtitle == nil ? 0 : FCPrimitives.space3)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var titleColor: Color {
        guard isEnabled else { return FCSemanticColors.textDisabled }
        return role == .destructive ? FCSemanticColors.statusDestructive : FCSemanticColors.textPrimary
    }
}
