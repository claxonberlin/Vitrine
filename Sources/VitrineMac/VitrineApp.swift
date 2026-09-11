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
                .fullScreenDisabled()
                .environmentObject(bridge)
                .environmentObject(menu)
                .environmentObject(rowSplash)
                .background(WindowConfigurator { window in
                    // Asked again every time the window is fitted, so the
                    // answer follows the library as builds come and go.
                    FrameKeeper.shared.attach(to: window) {
                        Theme.Metrics.libraryHeight(
                            sections: bridge.store.installedBranchCount,
                            rows: bridge.store.installed.count
                        )
                    }
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
            // The Window menu's sizing section, with Minimize and Zoom —
            // where an item that sets the window's size belongs. AppKit fills
            // the rest of that section in itself as the menu opens, and puts
            // its own items above this one; where they land is its business,
            // not something to reach in and rearrange.
            CommandGroup(after: .windowSize) {
                Button("Size to Content") { FrameKeeper.shared.sizeToContent() }
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
                // Built by hand rather than left to SwiftUI's interpolation:
                // the file manager's name is a runtime value, and the key
                // that reaches the strings table has to be the format string
                // itself.
                Button(String(format: NSLocalizedString("Reveal Library in %@", comment: ""),
                              store.fileManagerName)) {
                    store.revealLibrary()
                }
            }
            #if DEBUG
            CommandMenu("Developer") {
                // A specimen sheet for glass treatments, over the picture a
                // daily card wears — see `GlassLab`. Debug builds only.
                Button("Glass Lab") { GlassLabWindow.show() }
                    .disabled(!GlassLabWindow.isAvailable)
                    .keyboardShortcut("g", modifiers: [.command, .control])
            }
            #endif
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
                Divider()
                // Blender is free because people pay for it. A build manager
                // that does nothing but hand out those builds can at least
                // point at the tin.
                Button("Support the Blender Foundation") {
                    store.openInBrowser("https://www.blender.org/foundation/donation-program/")
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
        // SwiftUI rebuilds the whole menu bar whenever its commands
        // re-evaluate, and puts Edit back every time, so this can't be done
        // once at launch. The app tells us when it is about to update; the
        // handler is a pair of integer comparisons unless the bar has
        // actually changed shape.
        menuTidyObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willUpdateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Self.tidyMenuBar() }
        }
    }

    /// Kept for the lifetime of the app — see the comment where it is made.
    private var menuTidyObserver: NSObjectProtocol?

    /// Runs on every app update, because SwiftUI rebuilds the menu bar
    /// whenever its commands re-evaluate — it re-adds Edit, and it puts
    /// Developer back where it declared it. Each step below is a scan of a
    /// handful of menu items and does nothing when there is nothing to do.

    /// Drops the separators taking up space around nothing: a menu can't
    /// open or close on one, and two in a row are one line too many. Removing
    /// items leaves all three behind.
    @MainActor
    private static func tidySeparators(in menu: NSMenu) {
        var previousWasSeparator = true   // treat the top edge as one
        for item in menu.items {
            guard item.isSeparatorItem else {
                previousWasSeparator = false
                continue
            }
            if previousWasSeparator { menu.removeItem(item) }
            previousWasSeparator = true
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }

    /// A top-level menu carries its name on the item, on the submenu, or on
    /// both, depending on who made it — SwiftUI's own menus leave the item
    /// blank.
    @MainActor
    private static func isNamed(_ item: NSMenuItem, _ name: String) -> Bool {
        item.title == name || item.submenu?.title == name
    }

    /// Trims the menu bar down to what this app can actually do, and puts the
    /// debug menu where a debug menu goes.
    ///
    /// Everything here is matched on selectors rather than on titles, because
    /// AppKit's own items arrive in the user's language.
    @MainActor
    private static func tidyMenuBar() {
        guard let main = NSApp.mainMenu else { return }

        // Edit: nothing in this window takes text — no field, no editor, no
        // undo stack. A menu of items that can never fire is worse than no
        // menu. Found by the one selector every Edit menu has.
        if let edit = main.items.first(where: { item in
            item.submenu?.items.contains { $0.action == #selector(NSText.paste(_:)) } == true
        }) {
            main.removeItem(edit)
        }

        // Close, and Close All with it: there is one window, closing it
        // quits, and the app already has Quit for that. `closeAll:` has no
        // symbol to name — it is AppKit's own, reachable only as a string.
        let closing: Set<Selector> = [
            #selector(NSWindow.performClose(_:)), Selector(("closeAll:"))
        ]
        for item in main.items {
            guard let submenu = item.submenu else { continue }
            for child in submenu.items
            where child.action.map(closing.contains) == true {
                submenu.removeItem(child)
            }
            tidySeparators(in: submenu)
        }

        // Developer belongs at the end of the bar, beside Help, not in the
        // middle of the menus a user reads. Its title is ours, so matching on
        // it is safe: it is never translated.
        guard let developer = main.items.firstIndex(where: { Self.isNamed($0, "Developer") })
        else { return }
        let help = main.items.firstIndex { $0.submenu === NSApp.helpMenu } ?? main.items.count
        guard help > developer else { return }
        let item = main.items[developer]
        main.removeItem(at: developer)
        main.insertItem(item, at: help - 1)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

extension View {
    /// Takes full screen off the window: out of the View menu, off the green
    /// button, which goes back to being a zoom button, and away from the
    /// keyboard and the Dock's menu.
    ///
    /// Nothing here is worth a whole screen. The window is a list of
    /// installed builds standing exactly as tall as that list, and full
    /// screen would stretch it over a display with nothing to put in the
    /// space. The tiling commands are a separate mechanism and still work.
    ///
    /// SwiftUI has owned this since macOS 15. Setting the window's own
    /// `collectionBehavior` is the older way and no longer holds: SwiftUI
    /// asserts `fullScreenPrimary` over anything set on the window, whenever
    /// the scene updates.
    func fullScreenDisabled() -> some View {
        windowFullScreenBehavior(.disabled)
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
///
/// The height is not among what it remembers: the window opens at the height
/// its content needs — see `attach`.
@MainActor
final class FrameKeeper {
    static let shared = FrameKeeper()

    private static let key = "MainWindowFrame"
    private var attached = false

    /// How tall the content wants to be, asked fresh each time the window is
    /// fitted rather than measured once at launch.
    private var contentHeight: (() -> CGFloat)?

    /// The window itself, so the Window menu has something to act on. Weak
    /// because the window outlives nothing here — it is the app.
    private weak var window: NSWindow?

    func attach(to window: NSWindow, contentHeight: @escaping () -> CGFloat) {
        guard !attached else { return }
        attached = true
        self.contentHeight = contentHeight
        self.window = window

        // The width and the position are the window's own, carried over from
        // last time. The height isn't: a window whose whole content is a list
        // of installed builds has one right height, and it is whatever that
        // list measures today — the same window reopening around a build
        // added or removed since should stand as tall as the library it is
        // showing, not as tall as it happened to be left.
        let remembered = savedFrame()
        if let frame = remembered {
            // Opened at the size it was left and fitted a moment later, in
            // front of whoever opened it, rather than corrected before the
            // window is on screen. A window that settles says what it did;
            // one that was already the right size says nothing.
            window.setFrame(frame, display: false)
            DispatchQueue.main.async { self.sizeToContent() }
        } else {
            // First launch has nothing to settle from, and no width to carry
            // over. The scene's `defaultSize` doesn't survive contact with a
            // content view this flexible — SwiftUI sizes the window from the
            // content and lands on the minimum width — so the opening size is
            // set here instead, where it sticks.
            var frame = window.frame
            frame.size.width = Theme.Metrics.windowMinWidth
            window.setFrame(fitted(frame, in: window), display: false)
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

    /// Fits the window to its content on demand — the Window menu's own
    /// item, doing at any moment what opening the window does once.
    ///
    /// Animated, because unlike the silent resize at launch this one happens
    /// while somebody is looking at it, and a window that jumps doesn't say
    /// what moved. AppKit's own resize animations are timed by
    /// `animationResizeTime(_:)`, which is documented as a fifth of a second
    /// for every 150 points of the longest edge — a fitted library usually
    /// moves further than that, and long enough to drag. 300ms is the whole
    /// move, however far it goes.
    func sizeToContent() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(fitted(window.frame, in: window), display: true)
        }
    }

    private static let resizeDuration: TimeInterval = 0.3

    /// A frame at the height its content asks for, hung from its own top
    /// edge so the window grows and shrinks downward.
    ///
    /// Clamped both ways — never shorter than a single library card, never
    /// taller than the screen it is opening on.
    private func fitted(_ frame: NSRect, in window: NSWindow) -> NSRect {
        var frame = frame
        guard let contentHeight = contentHeight?() else { return frame }
        let chrome = window.frame.height - window.contentLayoutRect.height
        let ceiling = window.screen?.visibleFrame.height ?? frame.height
        let height = min(max(contentHeight, Theme.Metrics.windowMinHeight) + chrome,
                         ceiling)
        frame.origin.y += frame.height - height   // hold the top edge
        frame.size.height = height
        return frame
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

#if DEBUG
/// Opens the glass specimen sheet in a window of its own.
///
/// An AppKit window rather than a second SwiftUI `Window` scene: the sheet is
/// a debug tool, and a scene would put its state, its restoration and its
/// menu items into the shipping app's scene graph for the sake of something
/// no user ever opens.
@MainActor
enum GlassLabWindow {
    private static var window: NSWindow?

    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }

    static func show() {
        guard #available(macOS 26.0, *) else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosted = NSHostingController(rootView: GlassLab())
        let window = NSWindow(contentViewController: hosted)
        window.title = "Glass Lab"
        window.setContentSize(NSSize(width: 900, height: 620))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        Self.window = window
    }
}
#endif
