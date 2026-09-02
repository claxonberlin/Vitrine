import SwiftCrossUI
import VitrineKit

/// The "Catalogue" window: builds available upstream. Accented Blender orange.
struct CatalogueWindow: View {
    let store: BuildStore

    @State private var branch: BuildBranch = .stable
    @State private var showingSettings = false
    @Environment(\.openWindow) private var openWindow

    private let accent = Theme.catalogueAccent

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
            minWidth: Double(Theme.Metrics.windowMinWidth),
            minHeight: Double(Theme.Metrics.windowMinHeight)
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, accent: accent, isPresented: $showingSettings)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if store.isFetching {
                ProgressView().frame(width: 16, height: 16)
            }

            IconButton(glyph: Theme.Glyph.refresh,
                       help: "Refresh the catalogue",
                       accent: accent) {
                Task { await store.refreshAll() }
            }
            .disabled(store.isFetching)
            IconButton(glyph: Theme.Glyph.settings, help: "Preferences", accent: accent) {
                showingSettings = true
            }
            IconButton(glyph: Theme.Glyph.otherWindow,
                       help: "Show the Vitrine window",
                       accent: accent) {
                openWindow(id: Theme.WindowID.vitrine)
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
