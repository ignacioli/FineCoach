import SwiftUI

/// The switch appearance (§8 "开关": 44×26 capsule track, 18×18 white knob,
/// left-off/right-on per iOS convention; on: `action.primary` track; off:
/// `surface.divider` fill + 1.5pt `border.control` inner stroke, §7/O7).
///
/// Implemented as a `ToggleStyle`, not a hand-rolled `Button`, specifically
/// so the native `Toggle`'s built-in accessibility semantics (switch trait,
/// on/off value announcement, double-tap-to-toggle) are preserved untouched
/// — this type intentionally adds no `.accessibility*` modifiers of its own
/// that could shadow or duplicate them (§8's own instruction: "保留系统开关的
/// 无障碍语义").
public struct FCToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
            Capsule()
                .fill(configuration.isOn ? FCSemanticColors.actionPrimary : FCSemanticColors.surfaceDivider)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            FCSemanticColors.borderControl,
                            lineWidth: configuration.isOn ? 0 : 1.5
                        )
                )
                .frame(width: 44, height: 26)
            Circle()
                .fill(FCSemanticColors.actionOn)
                .frame(width: 18, height: 18)
                .padding(4)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}

extension ToggleStyle where Self == FCToggleStyle {
    public static var fc: FCToggleStyle { FCToggleStyle() }
}
