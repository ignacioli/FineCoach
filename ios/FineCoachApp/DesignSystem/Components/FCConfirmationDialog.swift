import SwiftUI

/// The confirmation dialog (§8 "确认弹窗": width 300 on-screen — the artwork's
/// own Foundations swatch export is 320, a swatch-canvas artifact, not the
/// in-screen truth, §1.1/§8 — `radius.lg`, white bg; title `headline`;
/// message `caption` `text.secondary`; two 36-tall buttons at
/// `radius.dialogAction`: the conservative/cancel action is `surface.selected`
/// bg + `callout` 600 `action.primary`, the confirm action is `action.primary`
/// bg + white text).
///
/// This is a content view, not a presentation API — callers own how/where it
/// is shown (e.g. as a custom overlay). §10 C8 only registers the 36pt
/// *visual* height and its off-scale radius (`radius.dialogAction`) — it
/// does NOT exempt these buttons from the general >=44x44 touch-target rule
/// (§7.2 last line, §11 last line). The visible button stays 36pt tall; the
/// tappable hit area is padded out to >=44pt via an outer frame + expanded
/// hit-testing shape (same pattern as `FCChip`), not by resizing the
/// button's own visual background.
public struct FCConfirmationDialog: View {
    public struct Action {
        public let title: String
        public let handler: () -> Void

        public init(title: String, handler: @escaping () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    private let title: String
    private let message: String
    private let cancelAction: Action
    private let confirmAction: Action

    public init(
        title: String,
        message: String,
        cancelAction: Action,
        confirmAction: Action
    ) {
        self.title = title
        self.message = message
        self.cancelAction = cancelAction
        self.confirmAction = confirmAction
    }

    /// Growth rules (components.md §4.7 `DS-CONFIRM-DIALOG`), all inside the
    /// component so callers never pass a size:
    /// - width 300, or the screen width minus 2×`space.4` when narrower;
    /// - height follows the content; once the card would exceed 80% of the
    ///   container height the message scrolls while title and buttons stay;
    /// - title and message wrap, never truncate;
    /// - if either button title cannot fit on one line in its half of the
    ///   row, the buttons stack — confirm on top, cancel below, each the full
    ///   card width — and grow with their text.
    public var body: some View {
        VStack(spacing: FCPrimitives.space4) {
            Text(title)
                .fcFont(.headline)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            messageView
                .layoutPriority(-1)

            ViewThatFits(in: .horizontal) {
                FCDialogEqualWidthRow(spacing: FCPrimitives.space2) {
                    dialogButton(cancelAction, isPrimary: false, wraps: false)
                    dialogButton(confirmAction, isPrimary: true, wraps: false)
                }
                VStack(spacing: FCPrimitives.space2) {
                    dialogButton(confirmAction, isPrimary: true, wraps: true)
                    dialogButton(cancelAction, isPrimary: false, wraps: true)
                }
            }
        }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity)
        // A cap, not a fill: `.frame(maxHeight:)` would stretch the card to 80% of the screen
        // whenever its content is shorter (owner T070 walkthrough, 2026-10-11).
        .modifier(FCDialogHeightCap(maxHeight: maxCardHeight))
        .background(FCSemanticColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusLg))
        .frame(maxWidth: 300)
        .padding(.horizontal, FCPrimitives.space4)
        .background {
            // Measures 80% of the container height without affecting layout.
            Color.clear
                .containerRelativeFrame(.vertical) { length, _ in length * 0.8 }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    maxCardHeight = $0
                }
        }
    }

    @State private var maxCardHeight: CGFloat = .infinity

    private var messageView: some View {
        ViewThatFits(in: .vertical) {
            messageText
            ScrollView {
                messageText
            }
        }
    }

    private var messageText: some View {
        Text(message)
            .fcFont(.caption)
            .foregroundStyle(FCSemanticColors.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dialogButton(_ action: Action, isPrimary: Bool, wraps: Bool) -> some View {
        Button(action: action.handler) {
            Text(action.title)
                .fcFont(.callout, weight: .semibold)
                .foregroundStyle(isPrimary ? FCSemanticColors.actionOn : FCSemanticColors.actionPrimary)
                .lineLimit(wraps ? nil : 1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: wraps)
                .padding(.horizontal, FCPrimitives.space2)
                .padding(.vertical, wraps ? FCPrimitives.space2 : 0)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isPrimary ? FCSemanticColors.actionPrimary : FCSemanticColors.surfaceSelected)
                .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusDialogAction))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Proposes at most `maxHeight` to the card and reports the card's own height, so the card
/// hugs its content and only a too-long message (the `ScrollView` branch) reaches the cap.
private struct FCDialogHeightCap: ViewModifier {
    let maxHeight: CGFloat

    func body(content: Content) -> some View {
        HeightCapLayout(maxHeight: maxHeight) { content }
    }

    private struct HeightCapLayout: Layout {
        let maxHeight: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let subview = subviews.first else { return .zero }
            let size = subview.sizeThatFits(capped(proposal))
            return CGSize(width: size.width, height: min(size.height, maxHeight))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
            )
        }

        private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
            ProposedViewSize(width: proposal.width, height: min(proposal.height ?? maxHeight, maxHeight))
        }
    }
}

/// Lays two children side by side in equal-width columns. Its ideal width is
/// twice the widest child's ideal width, so `ViewThatFits` rejects it when
/// either button title would need more than its half of the row.
private struct FCDialogEqualWidthRow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = CGFloat(subviews.count)
        let gaps = spacing * max(0, count - 1)
        let idealColumn = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        } else {
            width = idealColumn * count + gaps
        }
        let column = count > 0 ? max(0, (width - gaps) / count) : 0
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let columnWidth = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        var x = bounds.minX
        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: bounds.height)
            )
            x += columnWidth + spacing
        }
    }
}

/// Presents a design-system confirmation dialog centered over
/// `overlay.scrim` (§2.2/§8). Tapping the scrim dismisses it (the same as
/// the cancel action). Apply at a container that covers the screen.
private struct FCConfirmationDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let dialog: () -> FCConfirmationDialog

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if isPresented {
                        FCSemanticColors.overlayScrim
                            .ignoresSafeArea()
                            .onTapGesture { isPresented = false }
                            .accessibilityHidden(true)
                        dialog()
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape) { isPresented = false }
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: isPresented)
            }
    }
}

extension View {
    public func fcConfirmationDialog(
        isPresented: Binding<Bool>,
        dialog: @escaping () -> FCConfirmationDialog
    ) -> some View {
        modifier(FCConfirmationDialogModifier(isPresented: isPresented, dialog: dialog))
    }
}
