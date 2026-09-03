import SwiftUI
import AppKit
import VitrineKit

/// macOS entry point.
///
/// The window itself is stock SwiftUI: a unified title bar, a real toolbar,
/// and a `Settings` scene on ⌘, — the things AppKit already knows how to do
/// well, done its way rather than reimplemented.
@main
@MainActor
struct VitrineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// A plain stored property rather than `@StateObject`: the App value
    /// lives as long as the process does, and its initialiser is the one
    /// main-actor context available before any scene exists.
    private let bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    init() {
        Self.sanitizeAppLanguages()
        bridge = StoreBridge()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bridge)
                .background(WindowConfigurator { window in
                    // Restores the size and position from the last session.
                    // On a first launch there is nothing saved, so the window
                    // opens at `defaultSize` below.
                    window.setFrameAutosaveName("app.vitrine.main")
                    // AppKit hands first responder to the first control it
                    // finds, so the window opened with a focus ring around
                    // whichever build happened to sit at the top of the list.
                    // Clearing it only changes the starting point: tabbing to
                    // a control still rings it, as it should.
                    window.makeFirstResponder(nil)
                })
        }
        .defaultSize(width: Theme.Metrics.windowMinWidth,
                     height: Theme.Metrics.windowMinHeight)
        .windowResizability(.contentMinSize)
        // The title is drawn as a principal toolbar item so it stays centred
        // over the content, which is how the window has always looked.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Reload Catalogue") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isFetching)
            }
            CommandMenu("Blender") {
                Button("Blender Downloads") {
                    store.openInBrowser("https://www.blender.org/download/")
                }
                Button("Daily Builds") {
                    store.openInBrowser("https://builder.blender.org/download/daily/")
                }
                Button("LTS Releases") {
                    store.openInBrowser("https://www.blender.org/download/lts/")
                }
            }
        }

        Settings {
            SettingsView().environmentObject(bridge)
        }
    }

    /// macOS 15+ ships Apple Intelligence's model-availability check wired
    /// into SwiftUI text input. It only accepts two-letter ISO 639 codes for
    /// AppleLanguages; a regional variant like `nl-BE` triggers a console
    /// warning and a silent fallback. Stripping regional suffixes for this
    /// process alone lets the framework see `nl` directly. Locale region —
    /// date and number formatting, read from AppleLocale — is unaffected.
    private static func sanitizeAppLanguages() {
        let current = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
            ?? Locale.preferredLanguages
        var seen = Set<String>()
        let trimmed = current.compactMap { code -> String? in
            let base = String(code.split(separator: "-").first ?? Substring(code))
            return seen.insert(base).inserted ? base : nil
        }
        if trimmed != current {
            UserDefaults.standard.set(trimmed, forKey: "AppleLanguages")
        }
    }
}

/// Forces the process into a regular GUI app at launch — menu bar and Dock
/// entry. Without this, an SPM executable run straight from `swift run`
/// defaults to a no-UI activation policy because `Bundle.main` doesn't see a
/// real .app wrapper, even with an Info.plist embedded in the binary's
/// `__TEXT,__info_plist` section. Harmless inside the bundled app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Reaches the underlying `NSWindow` once it exists, for the handful of
/// settings SwiftUI has no modifier for.
///
/// Configuration is applied exactly once. Re-applying title-bar properties on
/// every render resets the toolbar's internal state mid-cycle, which showed up
/// as focus flicker whenever a fetch flipped a piece of state.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
