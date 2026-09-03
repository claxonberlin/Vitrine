import SwiftCrossUI
import VitrineKit

/// The whole app in one window: the installed library fills it, and the
/// catalogue folds out as a sidebar on the trailing edge.
///
/// Branches are no longer tabs. Both lists show every branch at once with a
/// plain text header marking where each begins, so nothing is hidden behind a
/// control you have to discover.
struct ContentView: View {
    @State private var store = BuildStore()
    @State private var showingSettings = false
    @Environment(\.chooseFile) private var chooseFile
    @Environment(\.colorScheme) private var colorScheme

    /// Builds the user adds by hand have no branch of their own to infer, and
    /// there is no longer a selector to read one from.
    private static let customBuildBranch: BuildBranch = .stable

    var body: some View {
        VStack(spacing: 6) {
            header
                .padding(.trailing, Theme.Metrics.cornerButtonInset)
            ErrorBanner(store: store)
                .padding(.horizontal, Theme.Metrics.windowMargin)
            // The sidebar floats over the library rather than displacing it,
            // so a 380pt window doesn't have to split itself in two.
            ZStack(alignment: .trailing) {
                libraryPane
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.Metrics.windowMargin)
                if store.showingCatalogue {
                    catalogueSidebar
                        .padding(.trailing, Theme.Metrics.windowMargin)
                }
            }
        }
        .padding(.bottom, Theme.Metrics.windowMargin)
        .frame(
            minWidth: Double(Theme.Metrics.windowMinWidth),
            minHeight: Double(Theme.Metrics.windowMinHeight)
        )
        .onAppear {
            Task { await store.refreshAll() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                store: store,
                accent: Theme.vitrineAccent,
                isPresented: $showingSettings
            )
        }
        .unifiedTitleBar()
    }

    // MARK: - Header

    private var header: some View {
        HeaderBar(title: "Vitrine") {
            ToolbarCluster {
                IconButton(icon: .addBuild,
                           help: "Add a Blender build you already have") {
                    pickExistingBuild()
                }
                IconButton(icon: .settings, help: "Preferences") {
                    showingSettings = true
                }
                IconButton(
                    icon: .catalogue,
                    help: store.showingCatalogue ? "Hide the catalogue" : "Show the catalogue",
                    active: store.showingCatalogue,
                    activeTint: Theme.catalogueAccent
                ) {
                    store.showingCatalogue = !store.showingCatalogue
                }
            }
        }
    }

    // MARK: - Library

    @ViewBuilder
    private var libraryPane: some View {
        if store.installed.isEmpty {
            EmptyState(message: "No builds installed.\nOpen the catalogue to download one.")
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(BuildBranch.allCases, id: \.id) { branch in
                        librarySection(branch)
                    }
                }
            }
        }
    }

    /// A branch contributes a header and its rows, or nothing at all — an
    /// empty heading would just be noise.
    @ViewBuilder
    private func librarySection(_ branch: BuildBranch) -> some View {
        let items = store.installed(in: branch)
        if !items.isEmpty {
            SectionHeader(title: branch.title)
            ForEach(items, id: \.id) { item in
                InstalledRow(store: store, build: item, accent: Theme.vitrineAccent)
            }
        }
    }

    // MARK: - Catalogue sidebar

    private var catalogueSidebar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("Catalogue")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
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
            catalogueList
        }
        .padding(Theme.Metrics.rowInset)
        .frame(
            minWidth: Double(Theme.Metrics.sidebarWidth),
            maxWidth: Double(Theme.Metrics.sidebarWidth)
        )
        .background(
            Theme.sidebarSurface(colorScheme)
                .cornerRadius(Theme.Metrics.sidebarCorner)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Double(Theme.Metrics.sidebarCorner))
                .stroke(Theme.sidebarBorder(colorScheme), style: StrokeStyle(width: 1))
        }
    }

    @ViewBuilder
    private var catalogueList: some View {
        if store.isFetching && store.stable.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading builds…")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(BuildBranch.allCases, id: \.id) { branch in
                        catalogueSection(branch)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func catalogueSection(_ branch: BuildBranch) -> some View {
        let groups = store.remoteGrouped(in: branch)
        if !groups.isEmpty {
            SectionHeader(title: branch.title)
            ForEach(groups, id: \.id) { group in
                if group.builds.count == 1 {
                    RemoteRow(store: store, build: group.builds[0],
                              branch: branch, accent: Theme.catalogueAccent)
                } else {
                    groupCard(group, branch: branch)
                }
            }
        }
    }

    /// A series and its individual builds share one card, so an expanded group
    /// reads as a single object. The children aren't indented — the card
    /// already scopes them.
    private func groupCard(_ group: RemoteBuildGroup, branch: BuildBranch) -> some View {
        VStack(spacing: 0) {
            RemoteGroupHeaderRow(store: store, group: group,
                                 branch: branch, accent: Theme.catalogueAccent)
            if store.expandedMinorKeys.contains(group.minorKey) {
                ForEach(group.builds, id: \.id) { build in
                    RemoteRow(store: store, build: build, branch: branch,
                              accent: Theme.catalogueAccent,
                              compact: true, drawsBackground: false)
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
        Task {
            let url = await chooseFile(
                title: wantsDirectory ? "Choose a Blender build folder" : "Choose Blender.app",
                allowSelectingFiles: !wantsDirectory,
                allowSelectingDirectories: wantsDirectory
            )
            if let url {
                store.addCustomBuild(at: url, into: Self.customBuildBranch)
            }
        }
    }
}
