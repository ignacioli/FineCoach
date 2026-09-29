import SwiftUI

/// The number stepper (§8.1 "数字步进器", D13 option C, owner 2026-09-29;
/// artwork `36-new-package-stepper`, `37-manual-adjustment-stepper`): one
/// `surface.canvas` capsule, 112×36 at the default text size, holding
/// "−" value "+". Glyphs are §7.2 `− / +` (20/600 `text.primary`); the side
/// that hits the range limit turns `text.disabled` and stops responding. The
/// value is `numeralLarge`. Each glyph's hit area is ≥ 44×44 (it may extend
/// beyond the capsule). Replaces the system `Stepper`, whose grey rounded
/// block is outside this palette.
///
/// VoiceOver reads it as one adjustable element (label + value; swipe up or
/// down to change), the same contract as the system `Stepper`.
public struct FCStepper: View {
    private let title: String
    @Binding private var value: Int
    private let range: ClosedRange<Int>

    private static let glyphColumnWidth: CGFloat = 36

    public init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>) {
        self.title = title
        self._value = value
        self.range = range
    }

    /// `value` moved by `delta`, clamped to `range`.
    static func stepped(_ value: Int, by delta: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value + delta, range.lowerBound), range.upperBound)
    }

    public var body: some View {
        HStack(spacing: 0) {
            glyphButton(.minus, isEnabled: value > range.lowerBound, delta: -1)
            Text("\(value)")
                .fcFont(.numeralLarge)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 40)
            glyphButton(.plus, isEnabled: value < range.upperBound, delta: 1)
        }
        .frame(minHeight: 36)
        .background(Capsule().fill(FCSemanticColors.surfaceCanvas))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = Self.stepped(value, by: 1, in: range)
            case .decrement: value = Self.stepped(value, by: -1, in: range)
            @unknown default: break
            }
        }
    }

    private func glyphButton(_ kind: FCSymbol.Kind, isEnabled: Bool, delta: Int) -> some View {
        Button {
            value = Self.stepped(value, by: delta, in: range)
        } label: {
            FCSymbol(kind, color: isEnabled ? FCSemanticColors.textPrimary : FCSemanticColors.textDisabled)
                .frame(width: Self.glyphColumnWidth, height: 36)
                .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
