import Combine
import Foundation

@MainActor
public final class ScenePrivacyCoordinator: ObservableObject {
    @Published public private(set) var isCovered = false

    public init() {}

    public func sceneWillResignActive() {
        isCovered = true
    }

    public func sceneDidBecomeActive() {
        isCovered = false
    }
}
