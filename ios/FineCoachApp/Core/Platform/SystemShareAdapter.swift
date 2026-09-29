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
        #if DEBUG
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
        #endif
        return await UIKitSystemSharePresenter().present(fileURLs: fileURLs)
    }
}

public struct UIKitDocumentExportPresenter: Sendable {
    public init() {}

    public func export(fileURL: URL) async -> SystemShareOutcome {
        await UIKitDocumentExportSession.shared.export(fileURL: fileURL)
    }
}

@MainActor
final class UIKitDocumentExportSession: NSObject, UIDocumentPickerDelegate {
    static let shared = UIKitDocumentExportSession()
    private var continuation: CheckedContinuation<SystemShareOutcome, Never>?

    func export(fileURL: URL) async -> SystemShareOutcome {
        await withCheckedContinuation { continuation in
            if let pending = self.continuation {
                pending.resume(returning: .failed)
            }
            self.continuation = continuation
            let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
            picker.delegate = self
            guard let root = UIKitSystemSharePresenter.topViewController() else {
                self.continuation = nil
                continuation.resume(returning: .failed)
                return
            }
            root.present(picker, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(.completed)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(.cancelled)
    }

    private func finish(_ outcome: SystemShareOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
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

    fileprivate static func topViewController() -> UIViewController? {
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
