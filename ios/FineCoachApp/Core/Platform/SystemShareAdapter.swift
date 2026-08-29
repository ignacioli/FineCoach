import Foundation
import UIKit

public protocol SystemSharePresenting: Sendable {
    func present(fileURLs: [URL]) async -> SystemShareOutcome
}

public struct SystemShareAdapter: Sendable {
    private let presenter: any SystemSharePresenting

    public init(presenter: any SystemSharePresenting) {
        self.presenter = presenter
    }

    public func share(fileURLs: [URL]) async -> SystemShareOutcome {
        await presenter.present(fileURLs: fileURLs)
    }
}

public struct LaunchArgumentSharePresenter: SystemSharePresenting {
    public init() {}

    public func present(fileURLs: [URL]) async -> SystemShareOutcome {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-FineCoachSimulateShareCompletion") {
            return .completed
        }
        if arguments.contains("-FineCoachSimulateShareCancel") {
            return .cancelled
        }
        if arguments.contains("-FineCoachSimulateShareFailure") {
            return .failed
        }
        return await UIKitSystemSharePresenter().present(fileURLs: fileURLs)
    }
}

public struct UIKitSystemSharePresenter: SystemSharePresenting {
    public init() {}

    public func present(fileURLs: [URL]) async -> SystemShareOutcome {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let activity = UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
                activity.completionWithItemsHandler = { _, completed, _, error in
                    if error != nil {
                        continuation.resume(returning: .failed)
                    } else if completed {
                        continuation.resume(returning: .completed)
                    } else {
                        continuation.resume(returning: .cancelled)
                    }
                }
                guard let root = Self.topViewController() else {
                    continuation.resume(returning: .failed)
                    return
                }
                root.present(activity, animated: true)
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var presenter = window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        return presenter
    }
}
