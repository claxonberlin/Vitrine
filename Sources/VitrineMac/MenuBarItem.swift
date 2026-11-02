import SwiftUI
import AppKit
import VitrineKit
import ServiceManagement

/// Where the app lives: an item in the menu bar that outlasts the window.
///
/// Left-click brings the window up; right-click (or Control-click) opens a
/// short menu of the things worth doing without it — bringing the starred
/// build up to date, and opening any build in the library.
///
/// An `NSStatusItem` rather than SwiftUI's `MenuBarExtra`, because a
/// `MenuBarExtra` is one thing — a menu or a window — for every click, and
/// this item is two. Telling the buttons apart needs the status button's own
/// event, which only AppKit hands over.
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {
    static let shared = MenuBarItem()

    /// Supplied by the app as it starts, before the item is installed. The
    /// store is the app's own; this only reads it and asks it to do things.
    var store: BuildStore?

    private var item: NSStatusItem?
    private let menu = NSMenu()
    private var refreshTimer: Timer?

    /// How often the catalogue is fetched while the app sits in the menu bar
    /// with no window to trigger it. Dailies land once a day; an hour behind
    /// is as stale as an update offer gets.
    private static let refreshInterval: TimeInterval = 60 * 60

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // The artwork is 44 px: two pixels per point at 22 pt. It ships
            // loose in the bundle's Resources (see bundle.sh), so a bare
            // `swift run` falls back to a symbol.
            let image = Bundle.main.image(forResource: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "cube", accessibilityDescription: nil)
            image?.size = NSSize(width: 22, height: 22)
            image?.accessibilityDescription = "Vitrine"
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Saved under a fixed name so the position a user drags it to with
        // ⌘ held is kept across launches.
        item.autosaveName = "Vitrine"
        menu.delegate = self
        self.item = item

        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval,
                                            repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let store = self?.store else { return }
                Task { await store.refreshAll() }
            }
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        // No event at all when VoiceOver or another assistive app presses
        // the item; that is a primary click, and opens the window.
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else {
            MainWindow.shared.show()
        }
    }

    /// Hands the menu to the item only for the length of one click, so the
    /// button highlights and the menu hangs from it as a status menu should,
    /// while a left-click still reaches `clicked(_:)` instead of opening it.
    private func showMenu() {
        guard let item, let button = item.button else { return }
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    // MARK: - Menu

    /// Built fresh each time it opens: everything on it — the starred build,
    /// whether it has an update, what the library holds — can have changed
    /// since the last time.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let store else { return }

        if let update = starredUpdateItem(store) {
            menu.addItem(update)
            menu.addItem(.separator())
        }

        menu.addItem(openInstanceItem(store))
        menu.addItem(.separator())

        menu.addItem(loginItem())
        menu.addItem(.separator())

        let open = NSMenuItem(title: NSLocalizedString("Open Vitrine", comment: ""),
                              action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: NSLocalizedString("Quit Vitrine", comment: ""),
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// Always there while a build is starred, so the menu keeps its shape:
    /// an update when one exists, progress while it comes down, and a
    /// greyed-out all-clear otherwise.
    private func starredUpdateItem(_ store: BuildStore) -> NSMenuItem? {
        guard let starred = store.installed.first(where: { $0.pinned }) else { return nil }

        if store.isUpdating(starred) {
            let item = NSMenuItem(
                title: NSLocalizedString("Updating Starred Build…", comment: ""),
                action: nil, keyEquivalent: "")
            item.isEnabled = false
            if case .downloading(let received, let total) = store.updateState(for: starred),
               total > 0 {
                item.title += " \(Int(Double(received) / Double(total) * 100))%"
            }
            return item
        }

        guard let target = store.updateAvailable(for: starred) else {
            let item = NSMenuItem(title: NSLocalizedString("You're Up to Date", comment: ""),
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        let item = NSMenuItem(
            title: String(format: NSLocalizedString("Update Starred Build to %@", comment: ""),
                          target.version),
            action: #selector(updateStarred(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil)
        item.representedObject = UpdateRequest(build: starred, target: target)
        return item
    }

    /// Every build in the library, grouped the way the window groups them —
    /// by branch, starred first within each. Each opens a new instance, so
    /// picking a build that is already running gets you a second one rather
    /// than a jump to the first.
    private func openInstanceItem(_ store: BuildStore) -> NSMenuItem {
        let parent = NSMenuItem(title: NSLocalizedString("Open New Instance", comment: ""),
                                action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let branches = BuildBranch.allCases.filter { !store.installed(in: $0).isEmpty }

        for branch in branches {
            // A heading only earns its line when there is more than one.
            if branches.count > 1 {
                submenu.addItem(.sectionHeader(
                    title: NSLocalizedString(branch.title, comment: "")))
            }
            for build in store.installed(in: branch) {
                let item = NSMenuItem(
                    title: String(format: NSLocalizedString("Blender %@", comment: ""),
                                  build.version),
                    action: #selector(launch(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = build
                // Two dailies of one version are told apart by their hash,
                // the same as on their cards.
                if build.branch == .daily, let hash = build.sourceHash {
                    item.subtitle = hash
                }
                // In the state column, where a checkmark would stand: the
                // menu keeps that column for every item, so the star lines
                // up and the titles beside it stay put.
                if build.pinned {
                    item.state = .on
                    item.onStateImage = NSImage(systemSymbolName: "star.fill",
                                                accessibilityDescription: "Starred")
                }
                submenu.addItem(item)
            }
        }

        parent.submenu = submenu
        parent.isEnabled = !branches.isEmpty
        return parent
    }

    /// The app's own entry in System Settings › General › Login Items,
    /// through `SMAppService` — the same switch that list shows, so the two
    /// never disagree. Read fresh each time: the user can flip it there.
    private func loginItem() -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString("Open at Login", comment: ""),
                              action: #selector(toggleLogin), keyEquivalent: "")
        item.target = self
        switch SMAppService.mainApp.status {
        case .enabled: item.state = .on
        // Registered, but switched off in System Settings: only the user can
        // turn it back on, so the item says so and takes them there.
        case .requiresApproval: item.state = .mixed
        default: item.state = .off
        }
        return item
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try service.register()
            }
        } catch {
            store?.lastError = error.localizedDescription
        }
    }

    private struct UpdateRequest {
        let build: InstalledBuild
        let target: RemoteBuild
    }

    @objc private func updateStarred(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? UpdateRequest else { return }
        store?.updateInstall(from: request.build, to: request.target)
    }

    @objc private func launch(_ sender: NSMenuItem) {
        guard let build = sender.representedObject as? InstalledBuild else { return }
        store?.launch(build, newInstance: true)
    }

    @objc private func openWindow() {
        MainWindow.shared.show()
    }
}

/// The one window, and the app's place in the Dock that comes and goes with
/// it.
///
/// While the window is open, Vitrine is an ordinary app — Dock icon, menu
/// bar, ⌘-Tab — because a window without those is hard to get back to. Once
/// it closes, the app steps down to the menu bar item alone: nothing is left
/// on screen for a Dock icon to lead to.
@MainActor
final class MainWindow {
    static let shared = MainWindow()

    /// SwiftUI's way to open a scene, captured from inside it the first time
    /// it appears. Needed once the window has closed, when there is no view
    /// left to ask.
    var openAction: OpenWindowAction?

    static let sceneID = "library"

    /// The app always comes up in the menu bar alone: the window opens from
    /// the menu bar item, or when the app is reopened.
    static let startsInMenuBar = true

    private weak var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    /// Called each time the scene makes a window — at launch, and again each
    /// time it is reopened after being closed.
    func adopt(_ window: NSWindow) {
        guard window !== self.window else { return }
        self.window = window
        if pendingFront {
            pendingFront = false
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NSApp.setActivationPolicy(.accessory) }
        }
    }

    func show() {
        // Asked for before the window exists, and with the older, insistent
        // call: an app that has just stopped being menu-bar-only is refused
        // the cooperative `activate()` often enough to leave the window
        // opening behind whatever was in front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            pendingFront = true
            openAction?(id: Self.sceneID)
        }
    }

    /// Set while a window asked for by `show()` is still being made, so the
    /// new one is brought forward once it exists.
    private var pendingFront = false
}

/// Hands the scene's `openWindow` action to `MainWindow`, which outlives
/// every view that could otherwise supply it.
struct OpenWindowCapture: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear { MainWindow.shared.openAction = openWindow }
    }
}
