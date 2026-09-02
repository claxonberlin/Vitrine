import Foundation
import SwiftCrossUI
import DefaultBackend
import VitrineKit

/// Entry point. `DefaultBackend` resolves to AppKit on macOS and GTK 4 on
/// Linux, so this file is the whole of the platform-specific app setup.
///
/// Two windows rather than two tabs: the library and the catalogue are
/// independent surfaces, each with its own branch selection and accent
/// colour, and both are usually wanted side by side. `Window` (not
/// `WindowGroup`) keeps each one single-instance, so the reopen buttons
/// activate the existing window instead of spawning duplicates — but it also
/// means launch behaviour has to be requested explicitly, since a plain
/// `Window` is suppressed at startup.
@main
@MainActor
struct VitrineApp: App {
    @State private var store = BuildStore()

    var body: some Scene {
        Window("Vitrine", id: Theme.WindowID.vitrine) {
            InstalledWindow(store: store)
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(
            width: Theme.Metrics.windowMinWidth,
            height: Theme.Metrics.windowMinHeight
        )
        .commands {
            // The two sites Vitrine draws its catalogue from.
            CommandMenu("Blender") {
                Button("Blender Downloads") {
                    open("https://www.blender.org/download/")
                }
                Button("Blender Daily Builds") {
                    open("https://builder.blender.org/download/daily/")
                }
                Button("Blender LTS Releases") {
                    open("https://www.blender.org/download/lts/")
                }
            }
        }

        Window("Catalogue", id: Theme.WindowID.catalogue) {
            CatalogueWindow(store: store)
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(
            width: Theme.Metrics.windowMinWidth + 60,
            height: Theme.Metrics.windowMinHeight + 80
        )
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        Task { await Platform.current.openURL(url) }
    }
}
