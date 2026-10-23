import SwiftUI

/// The body-part multi-select chip (§8.1 "部位多选胶囊": height 28, same
/// color scheme as the filter chip; wraps with 8pt line spacing via
/// `FCBodyPartPicker`).
public struct FCBodyPartChip: View {
    private let part: BodyPart
    private let isSelected: Bool
    private let accessibilityIdentifier: String?
    private let action: () -> Void

    public init(
        part: BodyPart,
        isSelected: Bool,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.part = part
        self.isSelected = isSelected
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        chipButton
    }

    @ViewBuilder
    private var chipButton: some View {
        let button = Button(action: action) {
            Text(part.displayName)
                .fcFont(.chipLabel)
                .foregroundStyle(isSelected ? FCSemanticColors.actionOn : FCSemanticColors.textPrimary)
                .padding(.horizontal, FCPrimitives.space4)
                .frame(minWidth: 48, minHeight: 28)
                .background(
                    Capsule().fill(isSelected ? FCSemanticColors.actionPrimary : FCSemanticColors.surfaceSelected)
                )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        if let accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }
}

/// All 8 `BodyPart` chips in their spec order, toggling membership in
/// `selection` (M1B-FR-033 training focus, `23-new-appointment-v2`).
public struct FCBodyPartPicker: View {
    @Binding private var selection: Set<BodyPart>
    private let accessibilityIdentifier: ((BodyPart) -> String)?

    public init(
        selection: Binding<Set<BodyPart>>,
        accessibilityIdentifier: ((BodyPart) -> String)? = nil
    ) {
        self._selection = selection
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        // Each chip pads its 28pt capsule out to a 44pt hit area (8pt above and
        // below), so lines overlap by those 16pt to leave the §8.1 8pt visual
        // gap between capsules; hit areas of adjacent lines overlap by 8pt.
        FCFlowLayout(horizontalSpacing: FCPrimitives.space2, verticalSpacing: FCPrimitives.space2 - (44 - 28)) {
            ForEach(BodyPart.allCases) { part in
                FCBodyPartChip(
                    part: part,
                    isSelected: selection.contains(part),
                    accessibilityIdentifier: accessibilityIdentifier?(part)
                ) {
                    if selection.contains(part) {
                        selection.remove(part)
                    } else {
                        selection.insert(part)
                    }
                }
            }
        }
    }
}

/// A left-aligned wrapping row layout for chips.
public struct FCFlowLayout: Layout {
    private let horizontalSpacing: CGFloat
    private let verticalSpacing: CGFloat

    public init(horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            if !current.indices.isEmpty, proposedWidth > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
