import SwiftUI
import Sparkle
import Combine

/// A tiny bridge so a "Check for Updates..." menu item can disable itself
/// while a check is already running or unavailable. Sparkle's `SPUUpdater`
/// isn't itself an ObservableObject -- this wraps its KVO-published
/// `canCheckForUpdates` property in a `@Published` value SwiftUI can
/// observe. This is Sparkle's own documented SwiftUI integration recipe,
/// not anything specific to Omnibus.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
}

/// Drop-in menu item for the app's Commands -- see OmnibusApp.swift, where
/// it's placed alongside the usual "About Omnibus" item.
struct CheckForUpdatesView: View {
    private let updater: SPUUpdater
    @ObservedObject private var viewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
