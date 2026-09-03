import SwiftUI
import VitrineKit

/// The process's single store. Held here rather than passed through the
/// environment because `BuildStore` belongs to `VitrineKit` and knows nothing
/// about SwiftUI — including how to be an `EnvironmentKey`.
@MainActor
enum Shared {
    static let store = BuildStore()
}

/// Turns the core store's change notifications into SwiftUI invalidations.
///
/// Every view that reads the store observes this instead. That matters for
/// rows: a catalogue row's own inputs don't change while its download
/// progresses, so without an observed object in the view SwiftUI would be
/// entitled to skip re-running its body and the progress bar would sit still.
@MainActor
final class StoreBridge: ObservableObject {
    let store: BuildStore
    private var token: ObservationToken?

    init(store: BuildStore = Shared.store) {
        self.store = store
        token = store.observeChanges { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
