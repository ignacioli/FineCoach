#if DEBUG
    import Foundation

    public enum FaultInjectionPoint: String, CaseIterable, Codable, Sendable {
        case recoverySnapshotReplace
        case persistenceWriterSave
        case postCommitProtectionAudit
        case generationMetadataWrite
        case currentPointerReplace
        case archiveStoreAfterGenerationWritten = "archive.store.afterGenerationWritten"
        case archiveStoreAfterPointerRemoved = "archive.store.afterPointerRemoved"
    }

    public enum FaultInjectionError: Error, Equatable, LocalizedError, Sendable {
        case injected(FaultInjectionPoint)

        public var errorDescription: String? {
            "测试故障已注入。"
        }
    }

    public protocol FaultInjector: Sendable {
        func check(_ point: FaultInjectionPoint) throws
    }

    public struct NoFaultInjector: FaultInjector, Sendable {
        public init() {}

        public func check(_ point: FaultInjectionPoint) throws {}
    }

    public struct FaultInjectionBoundary: Sendable {
        private let injector: any FaultInjector

        public init(injector: any FaultInjector = NoFaultInjector()) {
            self.injector = injector
        }

        public func check(_ point: FaultInjectionPoint) throws {
            try injector.check(point)
        }
    }
#endif
