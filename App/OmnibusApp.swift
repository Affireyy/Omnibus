import SwiftUI
import AppKit
import Sparkle

/// The app's appearance setting -- independent of, and overriding, the
/// macOS system appearance so light mode is available even when the Mac
/// itself is set to dark (or vice versa). Stored under the same key both
/// OmnibusApp and SettingsView bind to via @AppStorage, so a change in
/// Settings takes effect immediately everywhere. `.system` (the default)
/// passes `nil` to `.preferredColorScheme`, which is SwiftUI's own signal
/// to fall back to whatever macOS is set to.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct OmnibusApp: App {
    @StateObject private var store = OmnibusStore.shared
    @StateObject private var auth = GoogleAuthManager.shared
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    /// Owns Sparkle's background update-check timer for the app's whole
    /// lifetime, same as `store`/`auth` above. `startingUpdater: true`
    /// means it begins checking on its own schedule (SUEnableAutomaticChecks
    /// / SUScheduledCheckInterval in Info.plist) right away, not only when
    /// "Check for Updates..." is used -- see AUTOUPDATE.md for the one-time
    /// setup (signing key + feed URL) this needs before it finds anything.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private var preferredColorScheme: ColorScheme? {
        (AppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(auth)
                .preferredColorScheme(preferredColorScheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh All") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            // The default Edit menu's Paste just forwards Cmd+V straight
            // to whatever's focused. A compose bar's plain NSTextField
            // only knows how to paste text, so with a file/image (no
            // text) on the clipboard that's just a system beep -- nothing
            // attaches. Replacing the whole pasteboard group (and putting
            // Cut/Copy right back exactly as the default behaves, since
            // replacing it drops them otherwise) lets PasteCoordinator
            // offer the paste to whichever ComposeBar's message field is
            // currently focused first; it falls back to the normal paste
            // when nothing's registered (or the clipboard's just text).
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    if !PasteCoordinator.shared.tryHandle() {
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("v", modifiers: .command)
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(store)
                .environmentObject(auth)
                .preferredColorScheme(preferredColorScheme)
        }
        .windowResizability(.contentSize)
    }
}
