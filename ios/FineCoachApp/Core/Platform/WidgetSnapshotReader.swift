import Foundation

/// The extension has one read-only data source and never falls back to business storage.
enum WidgetSnapshotReader {
    static func read(at url: URL? = SharedContainer.widgetSnapshotURL) -> WidgetTodaySnapshot? {
        guard let url, let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(WidgetTodaySnapshot.self, from: data),
            snapshot.formatVersion == WidgetTodaySnapshot.currentFormatVersion
        else { return nil }
        return snapshot
    }
}
