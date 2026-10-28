import Foundation
import WidgetKit

public protocol WidgetSnapshotPublishing: Sendable {
    func refresh() async
}

public struct NoopWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    public init() {}
    public func refresh() async {}
}

/// Serializes rebuilds off the caller's executor without delaying business results.
public actor WidgetSnapshotPublisher: WidgetSnapshotPublishing {
    private let rebuild: @Sendable () async throws -> WidgetTodaySnapshot
    private let snapshotURL: @Sendable () -> URL?
    private let reload: @Sendable () -> Void
    private let files: ProtectedFileStore
    private let logger: any AppLogging
    private var pending: Task<Void, Never>?

    public init(
        rebuild: @escaping @Sendable () async throws -> WidgetTodaySnapshot,
        snapshotURL: (@Sendable () -> URL?)? = nil,
        files: ProtectedFileStore = ProtectedFileStore(), logger: any AppLogging = AppLogger.standard,
        reload: @escaping @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.rebuild = rebuild
        self.snapshotURL = snapshotURL ?? { SharedContainer.widgetSnapshotURL }
        self.files = files
        self.logger = logger
        self.reload = reload
    }

    public func refresh() async {
        let previous = pending
        pending = Task {
            await previous?.value
            await self.publish()
        }
    }

    /// Allows callers that require file evidence to wait for already requested rebuilds.
    public func flush() async { await pending?.value }

    private func publish() async {
        do {
            let snapshot = try await rebuild()
            guard let url = snapshotURL() else { throw CocoaError(.fileNoSuchFile) }
            let data = try JSONEncoder().encode(snapshot)
            // Do not apply a directory policy to the shared App Group root.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try files.apply(policy: .widgetSnapshot, to: url)
            _ = try files.audit(url: url)
            reload()
            logger.info(.systemEntrySnapshotWritten, operation: .systemEntry)
        } catch {
            logger.failure(.systemEntrySnapshotFailed, operation: .systemEntry, category: .persistenceFailed)
        }
    }
}

#if DEBUG
    public actor FakeWidgetSnapshotPublisher: WidgetSnapshotPublishing {
        public private(set) var refreshCount = 0
        public init() {}
        public func refresh() async { refreshCount += 1 }
    }
#endif
