import Adwaita
import Foundation
import VitrineKit

/// The single `BuildStore` for the process, plus the wiring that turns its
/// changes into a redraw.
///
/// Adwaita re-renders when a `@State` value is *assigned*, so mutating a
/// reference type in place is invisible to it. The window keeps a revision
/// counter in its own state and hands the binding over here; every change the
/// store publishes bumps it, and the view tree diffs as usual.
@MainActor
enum Shared {
    static let store = BuildStore()

    private static var token: ObservationToken?

    /// Connects store changes to `revision`. Safe to call on every appearance:
    /// only the first one takes.
    static func connect(revision: Binding<Int>) {
        guard token == nil else { return }
        token = store.observeChanges {
            revision.wrappedValue &+= 1
        }
    }
}

extension BuildBranch {
    /// GNOME's list rows carry their own headings, so a branch names its
    /// group rather than a bare section label.
    var groupTitle: String { title }
}
