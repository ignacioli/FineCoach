#if DEBUG
    import Foundation
    import FineCoach

    public final class TestFaultInjector: FaultInjector, @unchecked Sendable {
        private let lock = NSLock()
        private var failingPoints: Set<FaultInjectionPoint>

        public init(failingPoints: Set<FaultInjectionPoint> = []) {
            self.failingPoints = failingPoints
        }

        public func check(_ point: FaultInjectionPoint) throws {
            lock.lock()
            let shouldFail = failingPoints.contains(point)
            lock.unlock()
            if shouldFail {
                throw FaultInjectionError.injected(point)
            }
        }

        public func setFailure(at point: FaultInjectionPoint, enabled: Bool) {
            lock.lock()
            if enabled {
                failingPoints.insert(point)
            } else {
                failingPoints.remove(point)
            }
            lock.unlock()
        }
    }
#endif
