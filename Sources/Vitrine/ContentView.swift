import SwiftCrossUI
import VitrineKit

struct ContentView: View {
    @State private var store = BuildStore()
    @State private var showingSettings = false
    @Environment(\.chooseFile) private var chooseFile

    var body: some View {
        VStack(spacing: 8) {
            header
            errorBanner
            topTabPicker
            subTabPicker
            content
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
            SettingsView(store: store, isPresented: $showingSettings)
        }
    }

    // MARK: - Chrome
    //
    // SwiftCrossUI has no toolbar abstraction, so the window actions live in an
    // ordinary header row. That also keeps the layout identical on GNOME, where
    // a macOS-style unified toolbar would be out of place anyway.

    private var header: some View {
        HStack(spacing: 8) {
            Text("Vitrine")
                .font(.system(size: 15, weight: .semibold))

            Spacer(minLength: 8)

            if store.isFetching {
                ProgressView().frame(width: 16, height: 16)
            }

            IconButton(glyph: Theme.Glyph.add,
                       help: "Add an existing Blender build") {
                pickExistingBuild()
            }
            IconButton(glyph: Theme.Glyph.refresh,
                       help: "Refresh the catalogue") {
                Task { await store.refreshAll() }
            }
            .disabled(store.isFetching)
            IconButton(glyph: Theme.Glyph.settings, help: "Preferences") {
                showingSettings = true
            }
        }
    }

    /// Replaces the modal alert the macOS build used. A dismissible banner
    /// doesn't interrupt an in-progress download, which matters when a single
    /// flaky catalogue fetch would otherwise block the whole window.
    @ViewBuilder
    private var errorBanner: some View {
        if let message = store.lastError {
            HStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Dismiss") { store.lastError = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.12))
            .cornerRadius(6)
        }
    }

    private var topTabPicker: some View {
        Picker(
            of: TopTab.allCases,
            selection: Binding(
                get: { store.topTab },
                set: { if let new = $0 { store.topTab = new } }
            )
        )
        .pickerStyle(SegmentedPickerStyle())
    }

    private var subTabPicker: some View {
        Picker(
            of: BuildBranch.allCases,
            selection: Binding(
                get: { store.subTab },
                set: { if let new = $0 { store.subTab = new } }
            )
        )
        .pickerStyle(SegmentedPickerStyle())
    }

    @ViewBuilder
    private var content: some View {
        switch store.topTab {
        case .installed: installedList
        case .library: catalogueList
        }
    }

    // MARK: - Lists

    @ViewBuilder
    private var installedList: some View {
        let items = store.currentInstalled()
        if items.isEmpty {
            emptyState("""
                No \(store.subTab.title.lowercased()) builds installed.
                Switch to Catalogue to download one, or use + to add a build you already have.
                """)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(items, id: \.id) { item in
                        InstalledRow(store: store, build: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var catalogueList: some View {
        let groups = store.currentRemoteGrouped()
        if groups.isEmpty && store.isCurrentlyFetching(store.subTab) {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading builds…")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if groups.isEmpty {
            emptyState(
                "No \(store.subTab.title.lowercased()) builds available for "
                + "\(Platform.hostArchitecture) right now."
            )
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(groups, id: \.id) { group in
                        if group.builds.count == 1 {
                            RemoteRow(store: store, build: group.builds[0])
                        } else {
                            RemoteGroupHeaderRow(store: store, group: group)
                            if store.expandedMinorKeys.contains(group.minorKey) {
                                ForEach(group.builds, id: \.id) { build in
                                    RemoteRow(store: store, build: build, compact: true)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundColor(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let url { store.addCustomBuild(at: url) }
        }
    }
}

/// Square glyph button used for the header actions.
struct IconButton: View {
    let glyph: String
    let help: String
    let action: @MainActor @Sendable () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 14))
                .foregroundColor(hovered ? Theme.accent : Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .background(Theme.rowBackground.opacity(hovered ? 1.0 : 0.5))
        .cornerRadius(6)
        .onHover { hovered = $0 }
        .help(help)
    }
}
