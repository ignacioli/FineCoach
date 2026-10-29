import ActivityKit
import SwiftUI
import WidgetKit

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionActivityLockView(content: context.state, now: displayDate(context))
                .activityBackgroundTint(FCSemanticColors.actionPrimary)
                .activitySystemActionForegroundColor(FCSemanticColors.actionOn)
                .widgetURL(SessionActivityContent.url(sessionID: context.attributes.sessionID))
        } dynamicIsland: { context in
            let now = displayDate(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(SessionActivityContent.title(context.state))
                        .modifier(ActivityTextStyle(.headline))
                        .foregroundStyle(FCSemanticColors.actionOn)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionActivityTimer(content: context.state, now: now, compact: false)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SessionActivitySecondary(content: context.state, now: now)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(FCSemanticColors.actionOn)
            } compactTrailing: {
                SessionActivityTimer(content: context.state, now: now, compact: true)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(FCSemanticColors.actionOn)
            }
            .widgetURL(SessionActivityContent.url(sessionID: context.attributes.sessionID))
            .keylineTint(FCSemanticColors.actionPrimary)
        }
    }

    private func displayDate(_ context: ActivityViewContext<SessionActivityAttributes>) -> Date {
        // ActivityContent's staleDate supplies the system-driven transition at rest end.
        if context.isStale, let end = context.state.restEndsAt { return max(.now, end) }
        return .now
    }
}

private struct SessionActivityLockView: View {
    let content: SessionActivityAttributes.ContentState
    let now: Date

    var body: some View {
        HStack(spacing: FCPrimitives.space4) {
            VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                Text(SessionActivityContent.title(content)).modifier(ActivityTextStyle(.headline))
                    .foregroundStyle(FCSemanticColors.actionOn)
                SessionActivitySecondary(content: content, now: now)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SessionActivityTimer(content: content, now: now, compact: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FCPrimitives.space4)
        .background(FCSemanticColors.actionPrimary)
    }
}

private struct SessionActivitySecondary: View {
    let content: SessionActivityAttributes.ContentState
    let now: Date

    var body: some View {
        if let text = SessionActivityContent.secondaryText(content, now: now) {
            Text(text).modifier(ActivityTextStyle(.caption))
                .foregroundStyle(FCSemanticColors.textOnActionSecondary)
        }
    }
}

private struct SessionActivityTimer: View {
    let content: SessionActivityAttributes.ContentState
    let now: Date
    let compact: Bool

    var body: some View {
        Group {
            if let end = content.restEndsAt {
                if SessionActivityContent.isOverdue(content, now: now) {
                    // Counts down to `end`, then keeps counting up on its own, so the number
                    // never freezes at 0:00 while the system delays the stale re-render.
                    let countUp = Text(end, style: .timer)
                    if compact {
                        SessionActivityTimerSlot(
                            timer: Text(verbatim: "+") + countUp, template: "+00:00", style: .caption)
                    } else {
                        VStack(alignment: .trailing, spacing: FCPrimitives.space1) {
                            Text(SessionActivityContent.overdueLabel).modifier(ActivityTextStyle(.caption))
                                .foregroundStyle(FCSemanticColors.textOnActionSecondary)
                            SessionActivityTimerSlot(timer: countUp, template: "00:00", style: .numeralLarge)
                        }
                    }
                } else {
                    SessionActivityTimerSlot(
                        timer: Text(end, style: .timer),
                        template: "00:00", style: compact ? .caption : .numeralLarge)
                }
            } else if compact {
                Text(SessionActivityContent.compactTrailingText(content, now: now))
                    .modifier(ActivityTextStyle(.caption))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(FCSemanticColors.actionOn)
    }
}

/// A system timer text greedily takes all offered width inside a Live Activity,
/// pushing its neighbours out of view; a hidden template fixes the slot instead.
private struct SessionActivityTimerSlot: View {
    let timer: Text
    let template: String
    let style: ActivityTextStyle.Style

    var body: some View {
        Text(verbatim: template)
            .modifier(ActivityTextStyle(style))
            .monospacedDigit()
            .hidden()
            .overlay(alignment: .trailing) {
                timer
                    .modifier(ActivityTextStyle(style))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
    }
}

private struct ActivityTextStyle: ViewModifier {
    enum Style { case headline, caption, numeralLarge }
    let style: Style
    @ScaledMetric(relativeTo: .headline) private var headline: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var caption: CGFloat = 13
    @ScaledMetric(relativeTo: .title2) private var numeral: CGFloat = 24

    init(_ style: Style) { self.style = style }

    func body(content: Content) -> some View {
        switch style {
        case .headline: content.font(.system(size: headline, weight: .semibold))
        case .caption: content.font(.system(size: caption, weight: .regular))
        case .numeralLarge: content.font(.system(size: numeral, weight: .semibold))
        }
    }
}
