import SwiftUI
import WidgetKit

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FineCoachToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(URL(string: "finecoach://today"))
        }
        .configurationDisplayName(String(localized: "widget.today.title"))
        .description(String(localized: "widget.today.description"))
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetTodaySnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: WidgetSnapshotReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let snapshot = WidgetSnapshotReader.read()
        let dates = WidgetTodaySnapshot.timelineDates(snapshot: snapshot, now: now, calendar: calendar)
        let entries = dates.map { TodayEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(dates.last!.addingTimeInterval(1))))
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                InlineTodayView(entry: entry)
            case .accessoryRectangular:
                RectangularTodayView(entry: entry)
            case .systemMedium:
                HomeTodayView(entry: entry, medium: true)
            default:
                HomeTodayView(entry: entry, medium: false)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                FCSemanticColors.actionPrimary
            } else {
                AccessoryWidgetBackground()
            }
        }
    }
}

extension TodayEntry {
    fileprivate var state: WidgetTodaySnapshot.DisplayState {
        snapshot?.displayState(at: date, calendar: .current) ?? .placeholder
    }
    fileprivate var next: WidgetTodaySnapshot.Entry? { snapshot?.nextEntry(at: date, calendar: .current) }
    fileprivate var remainingText: String {
        String(
            format: String(localized: "widget.today.remaining"),
            snapshot?.remainingCount(at: date, calendar: .current) ?? 0)
    }
    fileprivate var emptyText: String {
        switch state {
        case .noClasses: String(localized: "widget.today.empty")
        case .allFinished: String(localized: "widget.today.finished")
        default: String(localized: "widget.today.placeholder")
        }
    }
    fileprivate func time(_ start: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    fileprivate var nextText: String {
        String(format: String(localized: "widget.today.nextTime"), next.map { time($0.startAtUTC) } ?? "")
    }
}

private struct InlineTodayView: View {
    let entry: TodayEntry
    var body: some View {
        Text(
            entry.state == .classes
                ? entry.nextText
                : (entry.state == .placeholder ? String(localized: "widget.today.inlinePlaceholder") : entry.emptyText))
    }
}

private struct RectangularTodayView: View {
    let entry: TodayEntry
    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space1) {
            // The system did not redact privacy-sensitive text here on a locked
            // device (R1, 2026-10-28), so this family omits the name (spec T-03).
            if entry.next != nil {
                Text(entry.nextText).modifier(WidgetTextStyle(.calloutStrong))
                Text(entry.remainingText).modifier(WidgetTextStyle(.caption)).foregroundStyle(.secondary)
            } else {
                Text(entry.emptyText).modifier(WidgetTextStyle(.calloutStrong))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct HomeTodayView: View {
    /// False in StandBy, where the phone can be locked and the system did not
    /// redact privacy-sensitive text (R1, 2026-10-28): names stay off there
    /// (spec T-03). The home screen itself is only visible when unlocked.
    @Environment(\.showsWidgetContainerBackground) private var showsNames
    let entry: TodayEntry
    let medium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            if entry.state == .classes {
                Text(medium ? entry.remainingText : String(localized: "widget.today.nextClass"))
                    .modifier(WidgetTextStyle(.sectionLabel))
                    .foregroundStyle(FCSemanticColors.textOnActionSecondary)
                if medium {
                    let rows = entry.snapshot?.mediumEntries(at: entry.date, calendar: .current) ?? []
                    ForEach(Array(rows.enumerated()), id: \.element.appointmentID) { index, row in
                        if index > 0 {
                            Rectangle().fill(FCSemanticColors.surfaceDividerOnAction).frame(height: 1)
                        }
                        HStack(spacing: FCPrimitives.space3) {
                            Text(entry.time(row.startAtUTC)).monospacedDigit().modifier(WidgetTextStyle(.calloutStrong))
                                .fixedSize(horizontal: true, vertical: false)
                            if showsNames {
                                Text(row.studentDisplayName).privacySensitive().modifier(WidgetTextStyle(.body))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let next = entry.next {
                    Text(entry.time(next.startAtUTC)).monospacedDigit().modifier(WidgetTextStyle(.title))
                        .fixedSize(horizontal: true, vertical: false)
                    if showsNames {
                        Text(next.studentDisplayName).privacySensitive().modifier(WidgetTextStyle(.body))
                    }
                    Spacer(minLength: 0)
                    Text(entry.remainingText).modifier(WidgetTextStyle(.caption))
                        .foregroundStyle(FCSemanticColors.textOnActionSecondary)
                }
            } else {
                Text(entry.emptyText).modifier(WidgetTextStyle(.headline))
            }
        }
        .foregroundStyle(FCSemanticColors.actionOn)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(FCPrimitives.space4)
    }
}

/// System-font counterparts of the approved typography styles; no bundled font dependency.
private struct WidgetTextStyle: ViewModifier {
    enum Style { case title, headline, body, callout, calloutStrong, caption, sectionLabel }
    let style: Style
    @ScaledMetric(relativeTo: .title2) private var title: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var body: CGFloat = 17
    @ScaledMetric(relativeTo: .callout) private var callout: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var caption: CGFloat = 13

    init(_ style: Style) { self.style = style }

    func body(content: Content) -> some View {
        switch style {
        case .title: content.font(.system(size: title, weight: .semibold))
        case .headline: content.font(.system(size: body, weight: .semibold))
        case .body: content.font(.system(size: body, weight: .regular))
        case .callout: content.font(.system(size: callout, weight: .regular))
        case .calloutStrong: content.font(.system(size: callout, weight: .semibold))
        case .caption: content.font(.system(size: caption, weight: .regular))
        case .sectionLabel: content.font(.system(size: caption, weight: .semibold))
        }
    }
}
