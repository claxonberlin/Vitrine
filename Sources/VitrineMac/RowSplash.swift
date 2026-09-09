import SwiftUI
import AppKit
import VitrineKit

/// Loads and caches the splash painting for each Blender X.Y series, so a
/// library row can paint its own release's artwork behind it. Shared across
/// every row through the environment.
///
/// Reading and loading are deliberately separate calls. `image(for:)` is pure,
/// so a row's `body` may call it freely; `load(for:)` is driven from a `.task`.
/// Fetching lazily from `body` instead — which is what this did first — meant
/// every re-render of a row whose series has no splash page (every daily build)
/// fired another request at blender.org, because nothing recorded the miss.
/// Rows re-render on window focus, on hover, and on every store notification,
/// so that ran away into a stream of 30-second network calls that starved the
/// main thread and made the buttons drop clicks.
@MainActor
final class RowSplashCatalog: ObservableObject {
    private enum Entry {
        case loading
        /// Asked, and blender.org has nothing for this series — never ask again.
        case missing
        case loaded(NSImage)
    }

    @Published private var entries: [String: Entry] = [:]
    private let library = SplashLibrary()

    /// The artwork for a version's X.Y series, if it is already in hand.
    /// Pure: no fetching, no state change, safe to call from `body`.
    func image(for version: String) -> NSImage? {
        guard let series = Self.series(of: version),
              case .loaded(let image) = entries[series]
        else { return nil }
        return image
    }

    /// Fetches a series' artwork, at most once per run whatever the outcome.
    /// Drive from `.task`, never from `body`.
    func load(for version: String) async {
        guard let series = Self.series(of: version), entries[series] == nil else { return }
        entries[series] = .loading

        let url = await library.artwork(forSeries: series)
        // A row scrolled out of the list cancels its task mid-flight. Leave no
        // verdict behind in that case, so the next row to ask starts over
        // rather than waiting forever on a `.loading` that never resolves.
        guard !Task.isCancelled else {
            entries[series] = nil
            return
        }
        guard let url else {
            entries[series] = .missing
            return
        }

        // Read the file off the main actor — a splash painting is megabytes.
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        entries[series] = data.flatMap(NSImage.init(data:)).map(Entry.loaded) ?? .missing
    }

    private static func series(of version: String) -> String? {
        Version(version)?.minorKey
    }
}
