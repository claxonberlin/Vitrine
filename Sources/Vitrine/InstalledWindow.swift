import SwiftCrossUI
import VitrineKit

/// The "Vitrine" window: builds already in the library. Accented blue.
struct InstalledWindow: View {
    let store: BuildStore

    @State private var branch: BuildBranch = .stable
    @State private var showingSettings = false
    @Environment(\.chooseFile) private var chooseFile
    @Environment(\.openWindow) private var openWindow

    private let accent = Theme.vitrineAccent

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            ErrorBanner(store: store)
            BranchPicker(branch: $branch)
            list
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(
            minWidth: Theme.Metrics.windowMinWidth,
            minHeight: Theme.Metrics.windowMinHeight
        )
        .onAppear {
            Task { await store.refreshAll() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, accent: accent, isPresented: $showingSettings)
        }
    }

    /// The window title now lives in the title bar, so this row carries only
    /// actions and sits right-aligned.
    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            IconButton(glyph: Theme.Glyph.add,
                       help: "Add a Blender build you already have",
                       accent: accent) {
                pickExistingBuild()
            }
            IconButton(glyph: Theme.Glyph.settings, help: "Preferences", accent: accent) {
                showingSettings = true
            }
            IconButton(glyph: Theme.Glyph.otherWindow,
                       help: "Show the Catalogue window",
                       accent: accent) {
                openWindow(id: Theme.WindowID.catalogue)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let items = store.installed(in: branch)
        if items.isEmpty {
            EmptyState(message: """
                No \(branch.title.lowercased()) builds installed.
                Open the Catalogue to download one, or use + to add a build you already have.
                """)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(items, id: \.id) { item in
                        InstalledRow(store: store, build: item, accent: accent)
                    }
                }
            }
        }
    }

    /// Adds a build the user already has. macOS offers `.app` bundles as
    /// selectable files; on Linux the build is a plain directory, so the
    /// dialog is configured from the platform layer rather than hardcoded.
    private func pickExistingBuild() {
        let wantsDirectory = Platform.current.buildIsDirectory
        let target = branch
        Task {
            let url = await chooseFile(
                title: wantsDirectory ? "Choose a Blender build folder" : "Choose Blender.app",
                allowSelectingFiles: !wantsDirectory,
                allowSelectingDirectories: wantsDirectory
            )
            if let url { store.addCustomBuild(at: url, into: target) }
        }
    }
}
