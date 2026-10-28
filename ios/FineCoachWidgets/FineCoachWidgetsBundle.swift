import SwiftUI
import WidgetKit

@main
struct FineCoachWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FineCoachPlaceholderWidget()
    }
}

private struct FineCoachPlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FineCoachPlaceholder", provider: PlaceholderProvider()) { _ in
            Text("精练教练")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("精练教练")
        .description("占位，后续版本替换")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

private struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}
