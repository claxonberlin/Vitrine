import Adwaita
import Foundation
import VitrineKit

/// Fedora entry point.
///
/// The window is a stock libadwaita one: a header bar, an overlay split view,
/// preferences in their own window, and a primary menu where GNOME users go
/// looking for it. Everything below the pixels is `VitrineKit`, shared with
/// the macOS build.
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

        Window(id: "preferences", open: 0) { _ in
            PreferencesView()
        }
        .closeShortcut()
        .defaultSize(width: 560, height: 340)
        .title("Preferences")
        .resizable(false)
    }
}
