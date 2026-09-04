import Adwaita
import Foundation
import VitrineKit

/// Fedora entry point.
///
/// The window is a stock libadwaita one: a header bar, an overlay split view,
/// and a primary menu where GNOME users go looking for it. Everything below
/// the pixels is `VitrineKit`, shared with the macOS build.
///
/// There is no preferences window. The app has exactly one setting — how far
/// back to scrape the stable archive — and it sits at the top of the
/// catalogue, next to the list it governs.
@main
struct VitrineApp: App {
    let id = "app.vitrine.Vitrine"
    var app: AdwaitaApp!

    var scene: Scene {
        Window(id: "main") { window in
            ContentView(app: app, window: window)
        }
        .defaultSize(width: 760, height: 560)
        .title("Vitrine")
    }
}
