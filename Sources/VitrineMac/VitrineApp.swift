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
/// back to scrape the stable archive — and one item in the View menu is a
/// smaller thing to carry than a window built to hold it.
@main
@MainActor
struct VitrineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The store is held, not observed: it publishes on every change it
    /// makes, and re-running this body rebuilds the whole menu bar. What the
    /// menus read and write lives on `MenuState`, which publishes only when
    /// one of those few values actually moves.
    private let bridge: StoreBridge
    private let rowSplash = RowSplashCatalog()
    @ObservedObject private var menu: MenuState
    private var store: BuildStore { bridge.store }

    init() {
        Self.sanitizeAppLanguages()
        let bridge = StoreBridge()
        self.bridge = bridge
        self.menu = MenuState(store: bridge.store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bridge)
                .environmentObject(menu)
                .environmentObject(rowSplash)
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
        .defaultSize(width: Theme.Metrics.windowMinWidth,
                     height: Theme.Metrics.windowDefaultHeight)
        .windowResizability(.contentMinSize)
        // The title is drawn as a principal toolbar item so it stays centred
        // over the content, which is how the window has always looked.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // No documents to make, but there is one thing to open.
            CommandGroup(replacing: .newItem) {
                Button("Add Build…") { menu.addingBuild = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button(menu.catalogueShown ? "Hide Catalogue" : "Show Catalogue") {
                    menu.catalogueShown.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Reload Catalogue") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(menu.reloading)

                // The app's one setting: how far back to scrape the stable
                // archive. There is no settings window, and the menu bar is
                // where a Mac app puts a setting with nowhere else to live —
                // same reasoning as the library folder below it.
                Picker("Oldest Version Listed", selection: Binding(
                    get: { menu.minVersion },
                    set: { menu.setMinVersion($0) }
                )) {
                    ForEach(minVersionOptions, id: \.self) { version in
                        Text(version).tag(version)
                    }
                }

                Divider()

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

    /// The offered floors, plus whatever is currently set if a hand-edited
    /// settings file named something off the list — the menu has to be able
    /// to show the value it is bound to.
    private var minVersionOptions: [String] {
        var all = BuildStore.minVersionChoices
        if !all.contains(menu.minVersion) { all.append(menu.minVersion) }
        return all.sorted { (Version($0) ?? .zero) < (Version($1) ?? .zero) }
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
        // One window, and nothing sensible to put in a second tab of it —
        // without this AppKit still offers "Show Tab Bar" and "Merge All
        // Windows" in the View and Window menus.
        NSWindow.allowsAutomaticWindowTabbing = false
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
            window.setContentSize(NSSize(width: Theme.Metrics.windowMinWidth,
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
