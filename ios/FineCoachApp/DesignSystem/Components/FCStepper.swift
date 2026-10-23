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

/// The editable weight/reps stepper (P0-a / P0-b, approved 2026-10-14).
/// A full-width `surface.canvas` capsule, 48pt tall, holding "−" value "+".
/// The value is a `numeralLarge` field the coach can type into; "−" / "+"
/// stay available while the keyboard is up. Focus draws a 1.5pt inner
/// `action.primary` stroke. Step size and the lower bound stay with the
/// caller (`SetValueStepping`, P0-D4 / P0-D6) — this view only shows the
/// disabled "−" the caller reports. The integer `FCStepper` is unchanged.
public struct FCStepperField: View {
    private let title: String
    private let text: Binding<String>
    private let canDecrement: Bool
    private let keyboardType: UIKeyboardType
    private let fieldIdentifier: String
    private let decrementIdentifier: String
    private let incrementIdentifier: String
    private let onDecrement: () -> Void
    private let onIncrement: () -> Void

    @FocusState private var isEditing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionTick = 0

    /// Leading inset that lines a caption up with this field inside an
    /// `FCLabelValueRow` (the P0 step hint sits under the value column).
    public static var valueColumnInset: CGFloat { FCLabelValueRow<Never>.labelColumnWidth }

    public init(
        _ title: String,
        text: Binding<String>,
        canDecrement: Bool,
        keyboardType: UIKeyboardType,
        fieldIdentifier: String,
        decrementIdentifier: String,
        incrementIdentifier: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) {
        self.title = title
        self.text = text
        self.canDecrement = canDecrement
        self.keyboardType = keyboardType
        self.fieldIdentifier = fieldIdentifier
        self.decrementIdentifier = decrementIdentifier
        self.incrementIdentifier = incrementIdentifier
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
    }

    public var body: some View {
        HStack(spacing: 0) {
            glyphButton(
                .minus,
                isEnabled: canDecrement,
                identifier: decrementIdentifier,
                label: String(format: String(localized: "session.stepper.decrementFormat"), title),
                action: {
                    selectionTick += 1
                    onDecrement()
                }
            )
            ZStack {
                Text(text.wrappedValue)
                    .fcFont(.numeralLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .default, value: selectionTick)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .opacity(isEditing ? 0 : 1)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                TextField("", text: text)
                    .keyboardType(keyboardType)
                    .fcFont(.numeralLarge)
                    .foregroundStyle(isEditing ? FCSemanticColors.textPrimary : Color.clear)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .focused($isEditing)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel(Text(title))
                    .accessibilityIdentifier(fieldIdentifier)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            glyphButton(
                .plus,
                isEnabled: true,
                identifier: incrementIdentifier,
                label: String(format: String(localized: "session.stepper.incrementFormat"), title),
                action: {
                    selectionTick += 1
                    onIncrement()
                }
            )
        }
        .sensoryFeedback(FCHaptic.selection, trigger: selectionTick)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Capsule().fill(FCSemanticColors.surfaceCanvas))
        .overlay {
            if isEditing {
                Capsule()
                    .strokeBorder(FCSemanticColors.actionPrimary, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private func glyphButton(
        _ kind: FCSymbol.Kind,
        isEnabled: Bool,
        identifier: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            FCSymbol(kind, color: isEnabled ? FCSemanticColors.textPrimary : FCSemanticColors.textDisabled)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }
}
