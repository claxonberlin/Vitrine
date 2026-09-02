import Foundation
import SwiftCrossUI
import DefaultBackend
import VitrineKit

/// Entry point. `DefaultBackend` resolves to AppKit on macOS and GTK 4 on
/// Linux, so this file is the whole of the platform-specific app setup.
@main
@MainActor
struct VitrineApp: App {
    var body: some Scene {
        WindowGroup("Vitrine") {
            ContentView()
        }
        .defaultSize(
            width: Theme.Metrics.windowMinWidth + 60,
            height: Theme.Metrics.windowMinHeight + 80
        )
        .commands {
            // The sites Vitrine draws its catalogue from.
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
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        Task { await Platform.current.openURL(url) }
    }
}
