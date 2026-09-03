import SwiftUI
import VitrineKit

/// The whole app in one window: the installed library fills it, and the
/// catalogue opens as a trailing inspector.
///
/// Branches are not tabs. Both lists show every branch at once under a plain
/// heading, so nothing is hidden behind a control you have to discover first.
struct ContentView: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    @Environment(\.openSettings) private var openSettings

    @AppStorage("showingCatalogue") private var showingCatalogue = false
    @State private var choosingBuild = false

    /// Builds the user adds by hand have no branch of their own to infer, and
    /// there is no selector to read one from.
    private static let customBuildBranch: BuildBranch = .stable

    var body: some View {
        VStack(spacing: 0) {
            ErrorBanner()
            LibraryPane()
        }
        .frame(minWidth: Theme.Metrics.windowMinWidth,
               minHeight: Theme.Metrics.windowMinHeight)
        .inspector(isPresented: $showingCatalogue) {
            CataloguePane()
                .inspectorColumnWidth(
                    min: Theme.Metrics.inspectorMin,
                    ideal: Theme.Metrics.inspectorIdeal,
                    max: Theme.Metrics.inspectorMax
                )
        }
        .toolbar {
            titleItem
            libraryActions
            // A gap on macOS 26, so the catalogue toggle reads as belonging to
            // the pane below it rather than to the two library actions.
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }
            catalogueToggle
        }
        .task { await store.refreshAll() }
        .fileImporter(
            isPresented: $choosingBuild,
            allowedContentTypes: [.application]
        ) { result in
            if case .success(let url) = result {
                store.addCustomBuild(at: url, into: Self.customBuildBranch)
            }
        }
        .animation(.smooth(duration: 0.3), value: showingCatalogue)
    }

    // MARK: - Toolbar

    /// Centres the title over the content rather than letting AppKit pin it to
    /// the leading edge, which is how the window has always looked. The system
    /// title is off — see `windowToolbarStyle` on the scene.
    ///
    /// macOS 26 gives every toolbar item a glass backing, which around a plain
    /// title reads as a stray grey blob, so the title opts out of the shared
    /// background it never asked for.
    @ToolbarContentBuilder
    private var titleItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) { titleLabel }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { titleLabel }
        }
    }

    private var titleLabel: some View {
        Text("Vitrine")
            .font(.system(size: 13, weight: .semibold))
    }

    @ToolbarContentBuilder
    private var libraryActions: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                choosingBuild = true
            } label: {
                IconView(icon: .addBuild)
            }
            .help("Add a Blender build you already have")

            Button {
                openSettings()
            } label: {
                IconView(icon: .settings)
            }
            .help("Settings")
        }
    }

    @ToolbarContentBuilder
    private var catalogueToggle: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $showingCatalogue) {
                IconView(icon: .catalogue)
            }
            .toggleStyle(.button)
            .help(showingCatalogue ? "Hide the catalogue" : "Show the catalogue")
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

/// The installed library.
struct LibraryPane: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    var body: some View {
        if store.installed.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Builds Installed")
                } icon: {
                    IconView(icon: .library, size: 34)
                        .foregroundStyle(.secondary)
                }
            } description: {
                Text("Open the catalogue to download one, or add a Blender you already have.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(BuildBranch.allCases) { branch in
                        section(branch)
                    }
                }
                .padding(.horizontal, Theme.Metrics.windowMargin)
                .padding(.bottom, Theme.Metrics.windowMargin)
            }
        }
    }

    /// A branch contributes a heading and its rows, or nothing at all — an
    /// empty heading would just be noise.
    @ViewBuilder
    private func section(_ branch: BuildBranch) -> some View {
        let items = store.installed(in: branch)
        if !items.isEmpty {
            SectionHeader(title: branch.title)
            ForEach(items) { item in
                InstalledRow(build: item)
            }
        }
    }
}

/// Marks where one branch ends and the next begins, in place of the segmented
/// tabs the app used to have.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

/// A dismissible banner rather than a modal alert: a single flaky catalogue
/// fetch shouldn't interrupt a download that is already running.
struct ErrorBanner: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    var body: some View {
        if let message = store.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    store.lastError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .handCursor()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, Theme.Metrics.windowMargin)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
