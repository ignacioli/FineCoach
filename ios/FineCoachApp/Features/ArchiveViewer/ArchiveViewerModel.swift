import Foundation
import SwiftUI

/// Loads the installed archive once and holds the local display settings. The loaded content
/// is a plain value; every page is a function of it. The only write this model can do is the
/// display-settings file (M2-FR-032), never the archive.
@MainActor
final class ArchiveViewerModel: ObservableObject {
    enum Phase {
        case loading
        case loaded(ArchiveViewerContent)
        case unreadable
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var settings: ArchiveDisplaySettings
    @Published private(set) var settingsSaveFailed = false

    private let useCases: ArchiveViewerUseCases

    init(useCases: ArchiveViewerUseCases) {
        self.useCases = useCases
        self.settings = useCases.displaySettings()
    }

    var converter: ArchiveDisplayConverter {
        ArchiveDisplayConverter(settings: settings)
    }

    func load() async {
        phase = .loading
        do {
            phase = .loaded(try await useCases.load())
        } catch {
            phase = .unreadable
        }
    }

    /// A failed save leaves the previous setting in force and says so.
    func update(_ change: (inout ArchiveDisplaySettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        do {
            try useCases.updateDisplaySettings(updated)
            settings = updated
            settingsSaveFailed = false
        } catch {
            settingsSaveFailed = true
        }
    }
}
