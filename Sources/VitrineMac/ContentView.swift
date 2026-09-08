import SwiftUI
import VitrineKit

/// The whole app in one window: the installed library fills it, and the
/// catalogue floats in over the trailing edge.
///
/// The catalogue is an overlay, not a split. It lies on top of the library
/// rather than taking space from it, so opening it never resizes the window
/// or shoves the list sideways.
///
/// Branches are not tabs. Both lists show every branch at once under a plain
/// heading, so nothing is hidden behind a control you have to discover first.
struct ContentView: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    @AppStorage("showingCatalogue") private var showingCatalogue = false
    @State private var choosingBuild = false
    /// The narrowest a library row's content can be without wrapping or
    /// clipping, gathered from every row on screen — see `RowMinWidthKey`.
    /// Floored at the old fixed minimum, which still has to hold when the
    /// library is empty and has no row to measure.
    @State private var measuredRowWidth: CGFloat = 0

    /// Builds the user adds by hand have no branch of their own to infer, and
    /// there is no selector to read one from.
    private static let customBuildBranch: BuildBranch = .stable

    /// Far enough right to clear the pane, its margin and its shadow.
    private static var catalogueHiddenOffset: CGFloat {
        Theme.Metrics.sidebarWidth + Theme.Metrics.windowMargin * 2 + 24
    }

    /// The window can never be narrower than the widest row actually needs —
    /// the row's own measured width plus the margin either side of it — with
    /// the old fixed constant as a floor for when the library is empty and
    /// there's no row to measure yet.
    private var windowMinWidth: CGFloat {
        max(measuredRowWidth + Theme.Metrics.windowMargin * 2, Theme.Metrics.windowMinWidth)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SplashBackground()

            VStack(spacing: 0) {
                ErrorBanner()
                LibraryPane()
            }

            // The pane stays mounted and slides in and out on its offset.
            // A conditional view with a `move` transition only animated the
            // way in: SwiftUI tore the pane down on the way out before the
            // slide could play, so hiding the catalogue snapped.
            CataloguePane()
                .frame(width: Theme.Metrics.sidebarWidth)
                .padding(Theme.Metrics.windowMargin)
                .offset(x: showingCatalogue ? 0 : Self.catalogueHiddenOffset)
                .opacity(showingCatalogue ? 1 : 0)
                .allowsHitTesting(showingCatalogue)
                .accessibilityHidden(!showingCatalogue)
        }
        .frame(minWidth: windowMinWidth,
               minHeight: Theme.Metrics.windowMinHeight)
        .onPreferenceChange(RowMinWidthKey.self) { measuredRowWidth = $0 }
        .toolbar {
            titleItem
            addBuildAction
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
    @ToolbarContentBuilder
    private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) { titleLabel }
            .sharedBackgroundHidden()
    }

    private var titleLabel: some View {
        Text("Vitrine")
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(TitlePillBackground())
    }

    @ToolbarContentBuilder
    private var addBuildAction: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ToolbarIconButton(icon: .addBuild) {
                choosingBuild = true
            }
            .help("Add a Blender build you already have")
        }
        .sharedBackgroundHidden()
    }

    /// This one sits a few points closer to the window's trailing edge than
    /// to its top — confirmed, not assumed: a running build measures 0pt to
    /// the top and 4pt to the trailing edge, and that gap holds regardless
    /// of anything this file adds to the item's own content. NSToolbar
    /// lays each item out inside its own fixed, opaque margins; padding
    /// added here doesn't reach it. Moving the buttons out of the toolbar
    /// entirely and drawing them as ordinary window content *does* get
    /// pixel-exact concentric placement — measured at exactly 12pt both
    /// ways — but that band of the window is native title-bar chrome, and
    /// AppKit routes every click there to window dragging before SwiftUI's
    /// content ever sees it, whether or not something is visually drawn
    /// over it. A button that looks right but can't be clicked is worse
    /// than one that's four points off, so this stays a toolbar item.
    /// Fixing the asymmetry for real means giving up the native unified
    /// title bar in favour of a fully custom one — a bigger change than
    /// this one warrants on its own.
    @ToolbarContentBuilder
    private var catalogueToggle: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ToolbarIconButton(icon: .catalogue, active: showingCatalogue, tint: Theme.catalogueAccent) {
                showingCatalogue.toggle()
            }
            .help(showingCatalogue ? "Hide the catalogue" : "Show the catalogue")
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        .sharedBackgroundHidden()
    }
}

/// The title's own glass pill, the same material a library row's card
/// wears — so "Vitrine" stays legible over whatever the splash artwork put
/// behind it without needing the artwork itself to dim or dissolve. Same
/// split as `RowCard`: real glass on macOS 26, a plain thin material below
/// it, and the identical hairline stroke either way so the two chrome
/// pieces (row and title) read as the same material at a glance.
private struct TitlePillBackground: View {
    @ViewBuilder
    var body: some View {
        let capsule = Capsule()
        Group {
            if #available(macOS 26.0, *) {
                capsule.fill(.clear).glassEffect(.regular, in: capsule)
            } else {
                capsule.fill(.ultraThinMaterial)
            }
        }
        .overlay { capsule.strokeBorder(Theme.rowStroke, lineWidth: 0.5) }
    }
}

/// A standalone round toolbar button. On macOS 26 this is real Liquid
/// Glass — plain glass at rest, filled/tinted glass while active — the
/// system's own vocabulary for "a toggle sitting in a glass toolbar," the
/// same shape a real Tahoe app's sidebar or filter toggle uses. Below 26
/// there's no real glass to reach for, so it falls back to a hand-drawn
/// light circle: a fixed fill regardless of hover, since `Button`'s own
/// default styling there draws its own background no matter what
/// `sharedBackgroundVisibility` says, and only overriding the style
/// entirely (`.buttonStyle(.plain)`, drawing the circle ourselves) escapes
/// it.
private struct ToolbarIconButton: View {
    let icon: Icon
    var active: Bool = false
    var tint: Color = Theme.catalogueAccent
    let action: () -> Void

    private static let diameter: CGFloat = 28
    private static let iconSize: CGFloat = 18

    // Sizing a glass button is measured, not declared — see the note on
    // `PillButton`/`CircleIconButton` in Controls.swift. The icon is sized
    // down by the same measured chrome padding so the finished circle
    // lands back on exactly `diameter`.
    private var label: some View {
        IconView(icon: icon, size: Self.iconSize)
            .frame(width: Self.diameter - Theme.Metrics.glassCirclePadding,
                   height: Self.diameter - Theme.Metrics.glassCirclePadding)
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            Group {
                if active {
                    Button(action: action) { label }
                        .buttonStyle(.glassProminent)
                        .tint(tint)
                        .buttonBorderShape(.circle)
                } else {
                    Button(action: action) { label }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                }
            }
            .buttonSizing(.fitted)
            .animation(.smooth(duration: 0.12), value: active)
            .handCursor()
        } else {
            LegacyToolbarIconButton(icon: icon, active: active, tint: tint, action: action)
        }
    }
}

/// The pre-26 fallback: a fixed light circle, since there's no real glass to
/// reach for below macOS 26.
private struct LegacyToolbarIconButton: View {
    let icon: Icon
    var active: Bool = false
    var tint: Color = Theme.catalogueAccent
    let action: () -> Void

    @State private var hovered = false

    private static let diameter: CGFloat = 28

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: 18)
                .foregroundStyle(active ? .white : Color.black.opacity(0.72))
                .frame(width: Self.diameter, height: Self.diameter)
                .background {
                    Circle()
                        .fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(hovered ? 1.0 : 0.82)))
                }
                .overlay {
                    Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.smooth(duration: 0.12), value: hovered)
        .animation(.smooth(duration: 0.12), value: active)
        .handCursor()
    }
}

extension ToolbarContent {
    /// Opts a toolbar item out of macOS 26's automatic glass backing, which
    /// otherwise fuses adjacent items into one shared capsule — the two
    /// buttons here read as separate controls sitting close together, not as
    /// halves of a single pill. Title, add-build and the catalogue toggle all
    /// use this, so nothing in the toolbar ever merges by accident. A no-op
    /// before macOS 26, which has no shared backing to opt out of.
    @ToolbarContentBuilder
    func sharedBackgroundHidden() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension View {
    /// The soft scroll-edge dissolve where rows pass under a glass header —
    /// macOS 26+; a no-op below that, since there's no real scroll-edge
    /// glass to style on older systems. (`ScrollEdgeEffectStyle` itself is
    /// 26-only, so it can't appear in this method's own signature — the
    /// choice of style lives inside, not in a parameter.)
    @ViewBuilder
    func softScrollEdgeCompat(for edges: Edge.Set) -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
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
            .scrollContentBackground(.hidden)
            // The system's own soft scroll-edge dissolve, blurring rows as
            // they pass under the toolbar. It can't reach the splash artwork
            // behind them too — that effect only ever touches genuine
            // scrolling content, not a `.background()` decoration, and the
            // artwork has to stay a persistent backdrop rather than content
            // that scrolls away — so the title wears its own glass pill
            // instead of depending on the artwork dissolving under it. See
            // `TitlePillBackground`.
            .softScrollEdgeCompat(for: .top)
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
    /// Matches the surface of the rows it heads: real glass in the library
    /// on macOS 26 (nothing else translucent sits under it there), a flat
    /// tint in the catalogue, which already sits on its own sheet of glass
    /// and would go muddy under a second layer of it — the same split
    /// `RowCard` makes.
    var tinted: Bool = false

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            // The same shape as a badge, not a full-width bar — a heading is
            // a label, not a divider.
            .background(fill)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private var fill: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if tinted {
            shape.fill(Theme.rowTint(hovered: false))
        } else if #available(macOS 26.0, *) {
            shape.fill(.clear).glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
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
            .background(errorBannerFill)
            .padding(.horizontal, Theme.Metrics.windowMargin)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var errorBannerFill: some View {
        // Floating chrome over the library, straight on the artwork — a
        // genuine glass candidate on macOS 26, same reasoning as the row
        // cards it sits above.
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if #available(macOS 26.0, *) {
            shape.fill(.clear).glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}
