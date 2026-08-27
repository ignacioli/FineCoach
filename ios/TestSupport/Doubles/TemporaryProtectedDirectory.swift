import FineCoach
import Foundation

public final class TemporaryProtectedDirectory: @unchecked Sendable {
    public let url: URL

    public init() throws {
        let base = FileManager.default.temporaryDirectory
        let name = "FineCoachTests-\(UUID().uuidString)"
        let directory = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        _ = try ProtectedFileStore().prepareDirectory(at: directory, policy: .business)
        self.url = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
