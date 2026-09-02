import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: BuildStore
    @Environment(\.openSettings) private var openSettings

    /// Drives the content's transition for the next change. Recomputed
    /// inside the picker bindings so the inserting view picks up the right
    /// asymmetric transition before SwiftUI runs the diff.
    @State private var contentTransition: AnyTransition = TransitionLib.subTabSlide

    var body: some View {
        VStack(spacing: 8) {
            topTabPicker
            subTabPicker
            content
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(minWidth: 380, minHeight: 340)
        .toolbar {
            // Empty principal item forces the toolbar's title-area slot to
            // exist; without this, primaryAction items collapse leftward.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { pickCustomApp() } label: {
                    Image(systemName: "plus.app")
                }
                .help("Add Blender.app… (file under the current sub-tab)")
                .handCursor()

                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isFetching)
                .handCursor()

                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .help("Preferences (⌘,)")
                .keyboardShortcut(",", modifiers: .command)
                .handCursor()
            }
        }
        .task { await store.refreshAll() }
        // AppKit doesn't automatically redraw toolbar items when SwiftUI state
        // changes programmatically (e.g. isFetching toggling .disabled) or when
        // the window regains key status — items stay visually stale until the
        // user hovers over them. validateVisibleItems() forces an immediate
        // re-validate + redraw of all visible toolbar items.
        .onChange(of: store.isFetching) {
            NSApp.mainWindow?.toolbar?.validateVisibleItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            NSApp.mainWindow?.toolbar?.validateVisibleItems()
        }
        .alert("Error",
               isPresented: Binding(get: { store.lastError != nil },
                                    set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private func refresh() {
        Task { await store.refreshAll() }
    }

    private var topTabPicker: some View {
        Picker("", selection: Binding(
            get: { store.topTab },
            set: { newValue in
                let forward = newValue == .library
                contentTransition = forward
                    ? TransitionLib.slideLeftward
                    : TransitionLib.slideRightward
                withAnimation(.smooth(duration: 0.32)) {
                    store.topTab = newValue
                }
            }
        )) {
            ForEach(TopTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .focusable(false)
        .focusEffectDisabled()
        .handCursor()
    }

    private var subTabPicker: some View {
        Picker("", selection: Binding(
            get: { store.subTab },
            set: { newValue in
                contentTransition = TransitionLib.subTabSlide
                withAnimation(.smooth(duration: 0.22)) {
                    store.subTab = newValue
                }
            }
        )) {
            ForEach(BuildBranch.allCases) { b in
                Text(b.title).tag(b)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .focusable(false)
        .focusEffectDisabled()
        .handCursor()
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch store.topTab {
            case .installed: installedList
            case .library: libraryList
            }
        }
        .id("\(store.topTab.rawValue)/\(store.subTab.rawValue)")
        .transition(contentTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var installedList: some View {
        Group {
            let items = store.currentInstalled()
            if items.isEmpty {
                emptyState("No \(store.subTab.title.lowercased()) builds installed.\nSwitch to Catalogue to download one, or use + to add an existing Blender.app.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            InstalledRow(build: item)
                        }
                    }
                    .padding(.vertical, 2)
                    // Animate reorders (starring moves a row to the top).
                    .animation(.smooth(duration: 0.32), value: items.map(\.id))
                }
            }
        }
    }

    private var libraryList: some View {
        Group {
            let groups = store.currentRemoteGrouped()
            if store.isCurrentlyFetching(store.subTab) && groups.isEmpty {
                ProgressView("Loading builds…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                emptyState("No \(store.subTab.title.lowercased()) builds available right now.")
            } else {
                groupedRemoteList(groups)
            }
        }
    }

    @ViewBuilder
    private func groupedRemoteList(_ groups: [RemoteBuildGroup]) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(groups) { group in
                    if group.builds.count == 1 {
                        RemoteRow(build: group.builds[0])
                    } else {
                        VStack(spacing: 4) {
                            RemoteGroupHeaderRow(group: group)
                            if store.expandedMinorKeys.contains(group.minorKey) {
                                ForEach(group.builds) { build in
                                    RemoteRow(build: build, compact: true)
                                        .padding(.leading, 16)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .animation(.smooth(duration: 0.32), value: store.expandedMinorKeys)
        }
    }

    private func pickCustomApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.addCustomBuild(at: url)
            withAnimation(.smooth(duration: 0.32)) {
                store.topTab = .installed
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .font(.callout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
    }
}

/// Centralized transition catalog so individual views don't redefine the
/// same asymmetric pairs.
private enum TransitionLib {
    /// Going forward in the page stack (e.g. Vitrine → Catalogue): the new
    /// view slides in from the trailing edge; the outgoing view exits left.
    static let slideLeftward = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )

    /// Reverse (Catalogue → Vitrine).
    static let slideRightward = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )

    /// Sub-tab change — exaggerated slide-up combined with fade.
    static let subTabSlide = AnyTransition.opacity.combined(with: .offset(y: 50))
}
