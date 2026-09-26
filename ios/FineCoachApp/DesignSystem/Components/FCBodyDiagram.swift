import SwiftUI

/// The trained-body-part diagram (§9.1, D7 scheme A, `29-share-preview`):
/// front and back simplified figures built from rounded rectangles and
/// ellipses, split only by the 8 `BodyPart`s. Primary parts fill with
/// `action.primary`, secondary parts with `text.disabled`, everything else
/// (and the unscored head/pelvis) with `surface.subtle`; every block has a
/// 1pt `border.control` stroke. Below the figures, a legend of 10pt dots +
/// `caption` text ("主练 · …", "次要 · …").
///
/// Feed it a `TrainedBodyPartsSummary`; the view itself holds no data rules.
public struct FCBodyDiagram: View {
    private let summary: TrainedBodyPartsSummary

    public init(summary: TrainedBodyPartsSummary) {
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            HStack(alignment: .top, spacing: FCPrimitives.space8) {
                figure(FCBodyDiagramGeometry.front, label: "bodyDiagram.front")
                figure(FCBodyDiagramGeometry.back, label: "bodyDiagram.back")
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: FCPrimitives.space6) {
                if let primaryText = BodyPart.joinedDisplayNames(for: summary.primary, separator: "、") {
                    legendItem(color: FCSemanticColors.actionPrimary, title: "bodyDiagram.legend.primary", parts: primaryText)
                }
                if let secondaryText = BodyPart.joinedDisplayNames(for: summary.secondary, separator: "、") {
                    legendItem(color: FCSemanticColors.textDisabled, title: "bodyDiagram.legend.secondary", parts: secondaryText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private func figure(_ shapes: [FCBodyDiagramGeometry.Block], label: LocalizedStringKey) -> some View {
        VStack(spacing: FCPrimitives.space2) {
            Canvas { context, size in
                let scale = size.width / FCBodyDiagramGeometry.canvasSize.width
                for block in shapes {
                    let path = block.path(scale: scale)
                    context.fill(path, with: .color(fill(for: block.part)))
                    context.stroke(path, with: .color(FCSemanticColors.borderControl), lineWidth: 1)
                }
            }
            .aspectRatio(FCBodyDiagramGeometry.canvasSize, contentMode: .fit)
            .frame(width: FCBodyDiagramGeometry.figureWidth)

            Text(label)
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
        }
    }

    private func legendItem(color: Color, title: LocalizedStringKey, parts: String) -> some View {
        HStack(spacing: FCPrimitives.space2) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            (Text(title) + Text(" · ") + Text(parts))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textPrimary)
        }
    }

    private func fill(for part: BodyPart?) -> Color {
        guard let part else { return FCSemanticColors.surfaceSubtle }
        if summary.primary.contains(part) { return FCSemanticColors.actionPrimary }
        if summary.secondary.contains(part) { return FCSemanticColors.textDisabled }
        return FCSemanticColors.surfaceSubtle
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let primary = BodyPart.joinedDisplayNames(for: summary.primary, separator: "、") {
            parts.append(String(format: String(localized: "bodyDiagram.accessibility.primaryFormat"), primary))
        }
        if let secondary = BodyPart.joinedDisplayNames(for: summary.secondary, separator: "、") {
            parts.append(String(format: String(localized: "bodyDiagram.accessibility.secondaryFormat"), secondary))
        }
        return parts.isEmpty ? String(localized: "bodyDiagram.accessibility.empty") : parts.joined(separator: "，")
    }
}

/// Block layout measured from the approved `29-share-preview` artwork, in a
/// 188×508 unit canvas per figure (scaled to `figureWidth` on screen). A
/// `nil` part is an unscored block (head, pelvis). Order is draw order.
enum FCBodyDiagramGeometry {
    enum Shape {
        case ellipse
        case capsule
        case rounded(CGFloat)
    }

    struct Block {
        let rect: CGRect
        let shape: Shape
        let part: BodyPart?

        func path(scale: CGFloat) -> Path {
            let scaled = CGRect(
                x: rect.minX * scale,
                y: rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            switch shape {
            case .ellipse:
                return Path(ellipseIn: scaled)
            case .capsule:
                return Path(roundedRect: scaled, cornerRadius: min(scaled.width, scaled.height) / 2)
            case .rounded(let radius):
                return Path(roundedRect: scaled, cornerRadius: radius * scale)
            }
        }
    }

    static let canvasSize = CGSize(width: 188, height: 508)
    /// On-screen figure width in the artwork (≈103pt).
    static let figureWidth: CGFloat = 104

    private static func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ shape: Shape, _ part: BodyPart?) -> Block {
        Block(rect: CGRect(x: x, y: y, width: w, height: h), shape: shape, part: part)
    }

    private static let head = block(68, 0, 50, 50, .ellipse, nil)
    private static let shoulders = [
        block(10, 62, 40, 38, .ellipse, .shoulders),
        block(137, 62, 40, 38, .ellipse, .shoulders),
    ]
    private static let arms = [
        block(0, 106, 28, 144, .capsule, .arms),
        block(160, 106, 28, 144, .capsule, .arms),
    ]
    private static let thighs = [
        block(47, 258, 43, 130, .rounded(20), .thighs),
        block(98, 258, 43, 130, .rounded(20), .thighs),
    ]
    private static let calves = [
        block(50, 396, 36, 112, .capsule, .calves),
        block(101, 396, 36, 112, .capsule, .calves),
    ]

    /// Front: shoulders, arms, chest, core, thighs, calves (+ head, pelvis).
    static let front: [Block] = [head] + shoulders + arms + [
        block(43, 62, 101, 64, .rounded(14), .chest),
        block(47, 134, 94, 84, .rounded(12), .core),
        block(50, 225, 87, 24, .capsule, nil),
    ] + thighs + calves

    /// Back: shoulders, arms, back, glutes, thighs, calves (+ head).
    static let back: [Block] = [head] + shoulders + arms + [
        block(43, 62, 102, 130, .rounded(16), .back),
        block(47, 200, 94, 54, .rounded(24), .glutes),
    ] + thighs + calves
}
