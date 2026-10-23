import SwiftUI

/// Motion tokens (`design/design-system/README.md` §14.2, §10 C17). The
/// Penpot token set has no duration or curve type, so §14 and this file are
/// the single source of truth; a view never writes its own duration or curve.
///
/// Internal rather than `public`: `ComponentCatalogTests` requires every
/// public `FC*` type under `DesignSystem/` to be indexed in
/// `design/design-system/components.md` §3, and that document is not part of
/// this round. Same module, so every feature view can still use it.
enum FCMotion {
    // MARK: §14.2 — durations (seconds)

    /// `motion.duration.instant`: a small local toggle.
    static let durationInstant: Double = 0.15
    /// `motion.duration.fast`: a state flip (set circle outline → fill).
    static let durationFast: Double = 0.2
    /// `motion.duration.standard`: sheets and bars (rest bar slide/fade).
    static let durationStandard: Double = 0.25
    /// `motion.duration.gentle`: page-content arrival.
    static let durationGentle: Double = 0.35
    /// `motion.duration.emphasis`: one-shot emphasis; the new-record value
    /// float (D-a3). 1.5 s: candidate D, picked on device by the product
    /// owner 2026-10-23.
    static let durationEmphasis: Double = 1.5

    // MARK: §14.2 — curves

    /// `motion.curve.standard` (`easeOut`): the default for appear, leave and
    /// one-shot feedback.
    static func curveStandard(duration: Double) -> Animation {
        .easeOut(duration: duration)
    }

    /// `motion.curve.symmetric` (`easeInOut`): state that toggles back and
    /// forth (set circle, rest-bar show/hide).
    static func curveSymmetric(duration: Double) -> Animation {
        .easeInOut(duration: duration)
    }

    // MARK: §14.2 — distance (a spacing token, never a new number)

    /// 新纪录数值浮起 distance: §14.2 fixes it at `space.6` (24pt, candidate
    /// D), so the float cannot invent a distance of its own.
    static let recordFloatDistance: CGFloat = FCPrimitives.space6

    /// `motion.spring.toggle` parameters: `spring(response: 0.25,
    /// dampingFraction: 0.55)`.
    static let springToggleResponse: Double = 0.25
    static let springToggleDampingFraction: Double = 0.55
    static var springToggle: Animation {
        .spring(response: springToggleResponse, dampingFraction: springToggleDampingFraction)
    }
}

/// Haptic tokens (§14.3, §10 C17). Three meanings only — confirm a set,
/// selection, attention — and never a fourth "record" haptic: a record uses
/// the same `confirm` impact and is told apart by the value float (§14.4).
enum FCHaptic {
    /// `haptic.confirm`: every confirmed set, record or not, exactly once.
    static let confirm: SensoryFeedback = .impact(weight: .light)
    /// `haptic.selection`: − / + steps, share settings switches and marks.
    static let selection: SensoryFeedback = .selection
    /// `haptic.attention`: the rest timer finished.
    static let attention: SensoryFeedback = .warning
}
