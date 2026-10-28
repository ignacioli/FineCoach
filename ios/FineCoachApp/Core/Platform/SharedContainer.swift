import Foundation

/// Shared by the host and its extension; an unavailable group has no fallback.
enum SharedContainer {
    static let appGroupIdentifier = "group.com.finecoach.app"
    static let widgetSnapshotFilename = "widget-today.json"

    static var widgetSnapshotURL: URL? {
        snapshotURL(in: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier))
    }

    static func snapshotURL(in containerURL: URL?) -> URL? {
        containerURL?.appendingPathComponent(widgetSnapshotFilename, isDirectory: false)
    }
}
