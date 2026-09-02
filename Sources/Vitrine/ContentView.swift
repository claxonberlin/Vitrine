import SwiftCrossUI
import VitrineKit

/// The whole app in one window. The library and the catalogue are two pages of
/// it, swapped by the toggle in the header, each keeping its own accent.
struct ContentView: View {
    @State private var store = BuildStore()
    @State private var page: Page = .vitrine
    @State private var branch: BuildBranch = .stable
    @State private var showingSettings = false
    @Environment(\.chooseFile) private var chooseFile

    private var accent: Color { page.accent }

    var body: some View {
        VStack(spacing: 10) {
            header
            ErrorBanner(store: store)
            BranchPicker(branch: $branch, accent: accent)
            content
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(
            minWidth: Double(Theme.Metrics.windowMinWidth),
            minHeight: Double(Theme.Metrics.windowMinHeight)
        )
        .onAppear {
            Task { await store.refreshAll() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, accent: accent, isPresented: $showingSettings)
        }
        .unifiedTitleBar()
    }

    // MARK: - Chrome

    private var header: some View {
        HeaderBar(title: page.title) {
            ToolbarCluster {
                pageAction
                IconButton(icon: .settings, help: "Preferences") {
                    showingSettings = true
                }
            }
            PageToggle(page: $page)
        }
    }

    /// The leading action belongs to whichever page is showing: adding a build
    /// only makes sense in the library, refreshing only in the catalogue.
    @ViewBuilder
    private var pageAction: some View {
        switch page {
        case .vitrine:
            IconButton(icon: .addBuild, help: "Add a Blender build you already have") {
                pickExistingBuild()
            }
        case .catalogue:
            // Deliberately a spinner rather than a disabled button: AppKit
            // draws a disabled plain button as a filled blue box.
            if store.isFetching {
                ProgressView()
                    .frame(
                        minWidth: Double(Theme.Metrics.iconButtonSize),
                        maxWidth: Double(Theme.Metrics.iconButtonSize),
                        minHeight: Double(Theme.Metrics.iconButtonSize),
                        maxHeight: Double(Theme.Metrics.iconButtonSize)
                    )
            } else {
                IconButton(icon: .refresh, help: "Refresh the catalogue") {
                    Task { await store.refreshAll() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .vitrine: installedList
        case .catalogue: catalogueList
        }
    }

    // MARK: - Library

    @ViewBuilder
    private var installedList: some View {
        let items = store.installed(in: branch)
        if items.isEmpty {
            EmptyState(message: """
                No \(branch.title.lowercased()) builds installed.
                Open the Catalogue to download one, or add a build you already have.
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

    // MARK: - Catalogue

    @ViewBuilder
    private var catalogueList: some View {
        let groups = store.remoteGrouped(in: branch)
        if groups.isEmpty && store.isCurrentlyFetching(branch) {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading builds…")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if groups.isEmpty {
            EmptyState(
                message: "No \(branch.title.lowercased()) builds available for "
                    + "\(Platform.hostArchitecture) right now."
            )
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(groups, id: \.id) { group in
                        if group.builds.count == 1 {
                            RemoteRow(store: store, build: group.builds[0],
                                      branch: branch, accent: accent)
                        } else {
                            groupCard(group)
                        }
                    }
                }
            }
        }
    }

    /// A series and its individual builds share one card, so an expanded group
    /// reads as a single object rather than a header followed by loose rows.
    /// The children aren't indented — the card already scopes them.
    private func groupCard(_ group: RemoteBuildGroup) -> some View {
        VStack(spacing: 0) {
            RemoteGroupHeaderRow(store: store, group: group, branch: branch, accent: accent)
            if store.expandedMinorKeys.contains(group.minorKey) {
                ForEach(group.builds, id: \.id) { build in
                    RemoteRow(store: store, build: build, branch: branch,
                              accent: accent, compact: true, drawsBackground: false)
                }
            }
        }
        .background(RowBackground())
    }

    // MARK: - Actions

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
