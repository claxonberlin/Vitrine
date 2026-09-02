import SwiftCrossUI
import VitrineKit

/// The "Catalogue" window: builds available upstream. Accented Blender orange.
struct CatalogueWindow: View {
    let store: BuildStore

    @State private var branch: BuildBranch = .stable
    @Environment(\.openWindow) private var openWindow

    private let accent = Theme.catalogueAccent

    var body: some View {
        VStack(spacing: 10) {
            header
            ErrorBanner(store: store)
            BranchPicker(branch: $branch, accent: accent)
            list
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(
            minWidth: Double(Theme.Metrics.windowMinWidth),
            minHeight: Double(Theme.Metrics.windowMinHeight)
        )
        .unifiedTitleBar()
    }

    private var header: some View {
        HeaderBar(title: "Catalogue") {
            ToolbarCluster {
                // Deliberately not `.disabled(store.isFetching)`: AppKit draws
                // a disabled plain button as a filled blue box, which flashed
                // on every refresh — and in the orange window, no less. The
                // spinner both replaces the control and reports progress.
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
                IconButton(icon: .library, help: "Show the Vitrine window") {
                    openWindow(id: Theme.WindowID.vitrine)
                }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
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
                            RemoteGroupHeaderRow(store: store, group: group,
                                                 branch: branch, accent: accent)
                            if store.expandedMinorKeys.contains(group.minorKey) {
                                ForEach(group.builds, id: \.id) { build in
                                    RemoteRow(store: store, build: build, branch: branch,
                                              accent: accent, compact: true)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
