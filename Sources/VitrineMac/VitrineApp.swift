import SwiftUI
import AppKit
import VitrineKit

/// macOS entry point.
///
/// The window itself is stock SwiftUI: a unified title bar and a real
/// toolbar, the things AppKit already knows how to do well, done its way
/// rather than reimplemented.
///
/// There is no settings window. The app has exactly one setting — how far
/// back to scrape the stable archive — and it sits at the top of the
/// catalogue, next to the list it governs.
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
                    FrameKeeper.shared.attach(to: window)
                    // AppKit hands first responder to the first control it
                    // finds, so the window opened with a focus ring around
                    // whichever build happened to sit at the top of the list.
                    // Clearing it only changes the starting point: tabbing to
                    // a control still rings it, as it should.
                    window.makeFirstResponder(nil)
                })
        }
        .defaultSize(width: Theme.Metrics.windowDefaultWidth,
                     height: Theme.Metrics.windowDefaultHeight)
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

                // The library folder used to be reachable from the settings
                // window. It is worth keeping a way in, and the menu bar is
                // where a Mac app puts one.
                Button("Reveal Library in Finder") {
                    store.revealLibrary()
                }
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

/// Remembers the window's size and position across launches.
///
/// SwiftUI autosaves the frame already, but under a key derived from the
/// content view's *type*: change anything about the view hierarchy and the key
/// changes with it, so the window forgets where it was and reopens at its
/// minimum size. Setting `frameAutosaveName` ourselves doesn't hold — SwiftUI
/// assigns its own after the window is configured — so the frame is kept here
/// under a name that never moves.
@MainActor
final class FrameKeeper {
    static let shared = FrameKeeper()

    private static let key = "MainWindowFrame"
    private var attached = false

    func attach(to window: NSWindow) {
        guard !attached else { return }
        attached = true

        if let frame = savedFrame() {
            window.setFrame(frame, display: false)
        } else {
            // First launch. The scene's `defaultSize` doesn't survive contact
            // with a content view this flexible — SwiftUI sizes the window
            // from the content and lands on the minimum width — so the
            // opening size is set here instead, where it sticks.
            //
            // Width comes straight from the window's own `minSize`, which by
            // this point already reflects what the library's rows measured
            // themselves at (see `RowMinWidthKey`) — the window opens exactly
            // as narrow as its content allows, no separate default to keep in
            // sync with it. The old constant is only a floor, in case this
            // runs before that first measurement has landed.
            let width = max(window.minSize.width, Theme.Metrics.windowMinWidth)
            window.setContentSize(NSSize(width: width,
                                         height: Theme.Metrics.windowDefaultHeight))
            window.center()
        }

        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            // Recorded on every resize and move, so a crash or a force-quit
            // loses nothing.
            NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.key)
                }
            }
        }
    }

    /// The stored frame, unless it belongs to a display that is no longer
    /// attached — reopening a window somewhere the user cannot see it is
    /// worse than forgetting where it was.
    private func savedFrame() -> NSRect? {
        guard let saved = UserDefaults.standard.string(forKey: Self.key) else { return nil }
        let frame = NSRectFromString(saved)
        guard frame.width > 0, frame.height > 0,
              NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) })
        else { return nil }
        return frame
    }
}
