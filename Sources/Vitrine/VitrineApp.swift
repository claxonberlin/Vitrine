import SwiftUI
import AppKit

@main
struct VitrineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = BuildStore()

    init() {
        Self.sanitizeAppLanguages()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .background(WindowConfigurator { window in
                    window.titleVisibility = .hidden
                    window.titlebarAppearsTransparent = true
                    // Persist window frame across launches. First launch has no
                    // saved frame, so the window opens at .defaultSize (which
                    // matches the content min size — see below).
                    window.setFrameAutosaveName("app.vitrine.main")
                })
        }
        .defaultSize(width: 380, height: 340)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            // The two sites Vitrine draws its catalogue from.
            CommandGroup(replacing: .help) {
                Button("Blender Downloads") {
                    NSWorkspace.shared.open(URL(string: "https://www.blender.org/download/")!)
                }
                Button("Blender Daily Builds") {
                    NSWorkspace.shared.open(URL(string: "https://builder.blender.org/download/daily/")!)
                }
            }
        }

        Settings {
            SettingsView().environmentObject(store)
        }
    }

    /// macOS 15+ ships GenerativeModelsAvailability (Apple Intelligence),
    /// which is wired into SwiftUI text input. It only accepts two-letter
    /// ISO 639 codes for AppleLanguages; a regional variant like `nl-BE`
    /// triggers a console warning and a silent fallback. We strip regional
    /// suffixes for this process so the framework sees `nl` directly. Locale
    /// region (date/number formatting via AppleLocale) is unaffected.
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

/// Forces the process into a regular GUI app at launch — menu bar and dock
/// entry. Without this, Xcode-launched SPM executables default to a no-UI
/// activation policy because `Bundle.main` doesn't see a real .app wrapper,
/// even with an Info.plist embedded in the binary's __TEXT,__info_plist
/// section. The bundled Vitrine.app from bundle.sh wouldn't need this, but
/// it's harmless there.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Reaches into the underlying NSWindow once it exists so we can apply
/// configuration that has no SwiftUI equivalent (title visibility,
/// transparent titlebar).
///
/// IMPORTANT: configuration is applied exactly once in makeNSView.
/// updateNSView is intentionally a no-op. Re-applying titlebarAppearsTransparent
/// or titleVisibility on every SwiftUI render (e.g. when isFetching flips)
/// resets the toolbar's internal state mid-cycle, producing the focus-flicker
/// the user sees when the window is unfocused or a toolbar button is pressed.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
