import SwiftUI
import VitrineKit

/// Turns the core store's change notifications into SwiftUI invalidations,
/// and owns the one store the process has.
///
/// `BuildStore` belongs to `VitrineKit` and knows nothing about SwiftUI —
/// including how to be observable — so every view that reads it observes this
/// instead. That matters for rows: a catalogue row's own inputs don't change
/// while its download progresses, so without an observed object in the view
/// SwiftUI would be entitled to skip re-running its body and the progress bar
/// would sit still.
@MainActor
final class StoreBridge: ObservableObject {
    let store = BuildStore()
    private var token: ObservationToken?

    init() {
        token = store.observeChanges { [weak self] in
            self?.objectWillChange.send()
        }
    }
}

/// The handful of values the menu bar shows or drives, and the only thing the
/// `App` observes.
///
/// Menus are expensive to rebuild, and SwiftUI rebuilds all of them whenever
/// the Scene's body re-runs. Two obvious ways to feed them both make that
/// happen constantly: observing `StoreBridge` from the `App` re-runs it on
/// every change the store publishes, download progress included, and
/// `focusedSceneValue` re-runs it on every render of the view that publishes
/// it — a focused value is a preference, so it climbs the whole view tree and
/// pushes a window-focus update out the top each time. Measured against the
/// catalogue's slide, that second one nearly tripled the app's main-thread
/// work.
///
/// So the menus read this instead. The two mirrored properties are assigned
/// only when they actually differ, so a value that hasn't changed publishes
/// nothing and the menu bar stands still.
@MainActor
final class MenuState: ObservableObject {
    /// Which page the window is showing, remembered across launches.
    @Published var catalogueShown: Bool {
        didSet { UserDefaults.standard.set(catalogueShown, forKey: Self.catalogueKey) }
    }
    /// Raised to put the window's "add a build you already have" dialog up.
    @Published var addingBuild = false

    @Published private(set) var reloading = false
    @Published private(set) var minVersion: String

    private let store: BuildStore
    private var token: ObservationToken?

    private static let catalogueKey = "showingCatalogue"

    init(store: BuildStore) {
        self.store = store
        self.catalogueShown = UserDefaults.standard.bool(forKey: Self.catalogueKey)
        self.minVersion = store.minVersionString
        token = store.observeChanges { [weak self] in self?.mirrorStore() }
    }

    func setMinVersion(_ version: String) {
        store.setMinVersion(version)
    }

    private func mirrorStore() {
        if reloading != store.isFetching { reloading = store.isFetching }
        if minVersion != store.minVersionString { minVersion = store.minVersionString }
    }
}
