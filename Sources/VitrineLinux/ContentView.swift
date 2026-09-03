import Adwaita
import Foundation
import VitrineKit

/// The window: the installed library fills it, and the catalogue slides in
/// from the leading edge as an overlay sidebar — the shape GNOME uses for a
/// panel you dip into and dismiss.
struct ContentView: WindowView {
    var app: AdwaitaApp!
    var window: AdwaitaWindow

    /// Bumped whenever the store changes; see `Shared.connect`.
    @State private var revision = 0
    @State("catalogue-visible") private var catalogueVisible = false
    @State private var openBuildChooser: Signal = .init()
    @State private var about = false

    private var store: BuildStore { Shared.store }

    var view: Body {
        OverlaySplitView(visible: $catalogueVisible) {
            CatalogueView()
                .topToolbar {
                    HeaderBar.end {
                        if store.isFetching {
                            Spinner()
                                .valign(.center)
                                .transition(.crossfade)
                        }
                    }
                    .headerBarTitle {
                        WindowTitle(subtitle: "", title: "Catalogue")
                    }
                }
        } content: {
            library
                .topToolbar {
                    HeaderBar {
                        Toggle(icon: .default(icon: .sidebarShow), isOn: $catalogueVisible)
                            .tooltip("Show the catalogue")
                        Button(icon: .default(icon: .folderNew)) {
                            openBuildChooser.signal()
                        }
                        .tooltip("Add a Blender build you already have")
                    } end: {
                        menu
                    }
                    .headerBarTitle {
                        WindowTitle(subtitle: libraryCount, title: "Vitrine")
                    }
                }
        }
        .onAppear {
            Shared.connect(revision: $revision)
            Task { await store.refreshAll() }
        }
        .fileImporter(open: openBuildChooser) { url in
            // A Linux build is a plain directory, so this is a folder picker.
            store.addCustomBuild(at: url, into: .stable)
        } onClose: {}
        .aboutDialog(
            visible: $about,
            app: "Vitrine",
            developer: "Claxon",
            version: "1.0",
            icon: .default(icon: .applicationsGraphics),
            website: .init(string: "https://www.blender.org/download/"),
            issues: nil
        )
    }

    /// The store owns the window's own state too, so a change to it has to
    /// reach the title as well as the list.
    private var libraryCount: String {
        let count = store.installed.count
        _ = revision
        return count == 1 ? "1 build" : "\(count) builds"
    }

    @ViewBuilder
    private var library: Body {
        if store.installed.isEmpty {
            StatusPage(
                "No Builds Installed",
                icon: .default(icon: .systemSoftwareInstall),
                description: "Open the catalogue to download one, or add a Blender you already have."
            ) {
                Button("Open the Catalogue") {
                    catalogueVisible = true
                }
                .pill()
                .suggested()
                .halign(.center)
            }
        } else {
            ScrollView {
                VStack {
                    ErrorBanner()
                    ForEach(BuildBranch.allCases) { branch in
                        LibraryGroup(branch: branch)
                    }
                }
                .padding()
            }
            .vexpand()
        }
    }

    private var menu: AnyView {
        Menu(icon: .default(icon: .openMenu)) {
            MenuButton("Reload Catalogue") {
                Task { await store.refreshAll() }
            }
            .keyboardShortcut("r".ctrl())
            MenuButton("Reveal Library") { store.revealLibrary() }
            MenuSection {
                MenuButton("Blender Downloads") {
                    store.openInBrowser("https://www.blender.org/download/")
                }
                MenuButton("Daily Builds") {
                    store.openInBrowser("https://builder.blender.org/download/daily/")
                }
                MenuButton("LTS Releases") {
                    store.openInBrowser("https://www.blender.org/download/lts/")
                }
            }
            MenuSection {
                MenuButton("Preferences", window: false) {
                    app.addWindow("preferences")
                }
                .keyboardShortcut("comma".ctrl())
                MenuButton("About Vitrine") { about = true }
                MenuButton("Quit", window: false) { app.quit() }
                    .keyboardShortcut("q".ctrl())
            }
        }
        .primary()
        .tooltip("Main Menu")
    }

    func window(_ window: Window) -> Window {
        window
    }
}

/// GNOME's own idiom for a recoverable failure: an inline strip with one
/// action, not a dialog that interrupts a download already in flight.
struct ErrorBanner: View {
    private var store: BuildStore { Shared.store }

    var view: Body {
        Banner(store.lastError ?? "", visible: store.lastError != nil)
            .button("Dismiss") {
                store.lastError = nil
            }
    }
}
