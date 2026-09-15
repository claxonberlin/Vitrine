import SwiftUI
import VitrineKit

/// The whole app in one window: the installed library fills it, and the
/// catalogue slides in from the trailing edge as a second page.
///
/// It isn't a real split — the window never resizes, and the library never
/// gives up any of its own width — but it reads like one: opening the
/// catalogue pushes the library most of the way out of its path rather than
/// merely covering it, so the two feel like adjacent pages rather than a
/// panel laid on top. Both travel by exactly the same distance, a fixed
/// fraction of the window's own current width, so at rest the library still
/// shows a sliver of itself down the leading edge, and the catalogue is that
/// same width rather than some separately-chosen sidebar width.
///
/// Branches are not tabs. Both lists show every branch at once under a plain
/// heading, so nothing is hidden behind a control you have to discover first.
struct ContentView: View {
    @EnvironmentObject private var bridge: StoreBridge
    @EnvironmentObject private var menu: MenuState
    private var store: BuildStore { bridge.store }

    /// Both live on `MenuState` rather than in `@State`, because the menu bar
    /// drives them too and a menu cannot reach a view's own state.
    private var showingCatalogue: Bool { menu.catalogueShown }

    /// Builds the user adds by hand have no branch of their own to infer, and
    /// there is no selector to read one from.
    private static let customBuildBranch: BuildBranch = .stable

    /// How far the catalogue travels sliding in, how far the library
    /// travels getting out of its way, and how wide the catalogue itself
    /// is — all the same fraction of whatever the window measures itself
    /// at, so the page keeps reading as "almost the whole window" at any
    /// size instead of a fixed-width strip that a wide window would dwarf.
    private static let catalogueTravelFraction: CGFloat = 0.72

    var body: some View {
        // A navigation stack at the root, the structure Apple's Landmarks
        // sample uses for a titled page.
        NavigationStack {
            pages
                // The catalogue renames the window rather than carrying a
                // heading of its own, the way a second page would.
                .navigationTitle(showingCatalogue ? "Catalogue" : "Vitrine")
                .toolbar {
                    addBuildAction
                    catalogueToggle
                }
        }
        .frame(minWidth: Theme.Metrics.windowMinWidth,
               minHeight: Theme.Metrics.windowMinHeight)
        .task { await store.refreshAll() }
        .fileImporter(
            isPresented: $menu.addingBuild,
            allowedContentTypes: [.application]
        ) { result in
            if case .success(let url) = result {
                store.addCustomBuild(at: url, into: Self.customBuildBranch)
            }
        }
        .animation(.smooth(duration: 0.3), value: showingCatalogue)
    }

    /// The library, with the catalogue sliding in over its trailing edge.
    private var pages: some View {
        GeometryReader { geometry in
            let travel = geometry.size.width * Self.catalogueTravelFraction

            // No ground of its own: the window's background shows through.
            ZStack(alignment: .topTrailing) {
                LibraryPane()
                // Slides left to make room for the incoming page rather than
                // staying put underneath it — see the type's own doc comment.
                .offset(x: showingCatalogue ? -travel : 0)
                // The sliver left showing down the leading edge is scenery,
                // not a second copy of the library: its buttons belong to
                // rows you can no longer read, so they stop taking clicks and
                // drop out of the keyboard and VoiceOver order — the same
                // deal the catalogue gets while it is the one parked off the
                // other edge.
                .allowsHitTesting(!showingCatalogue)
                .accessibilityHidden(showingCatalogue)

                // The page stays mounted and slides in and out on its
                // offset. A conditional view with a `move` transition only
                // animated the way in: SwiftUI tore the pane down on the way
                // out before the slide could play, so hiding the catalogue
                // snapped. Parked, it sits exactly its own width past the
                // trailing edge, so the window already clips it away.
                CataloguePane()
                    .frame(width: travel)
                    .frame(maxHeight: .infinity)
                    .offset(x: showingCatalogue ? 0 : travel)
                    .allowsHitTesting(showingCatalogue)
                    .accessibilityHidden(!showingCatalogue)
            }
            // Above both pages rather than on top of the library: a catalogue
            // fetch is the likeliest thing to fail, and its error used to
            // travel off the edge with the library the moment you opened the
            // page it was about.
            .overlay(alignment: .top) { ErrorBanner() }
        }
    }

    // MARK: - Toolbar

    // Plain buttons labelled with a symbol image, declared the way Landmarks
    // declares its own, so the system draws them on its toolbar glass.

    @ToolbarContentBuilder
    private var addBuildAction: some ToolbarContent {
        ToolbarItem {
            Button {
                menu.addingBuild = true
            } label: {
                Label("Add Build", systemImage: "folder.badge.plus")
            }
            .help("Add a Blender build you already have")
        }
    }

    @ToolbarContentBuilder
    private var catalogueToggle: some ToolbarContent {
        ToolbarItem {
            Button {
                menu.catalogueShown.toggle()
            } label: {
                Label(showingCatalogue ? "Hide Catalogue" : "Show Catalogue", systemImage: "book")
                    .symbolVariant(showingCatalogue ? .fill : .none)
            }
            .help(showingCatalogue ? "Hide the catalogue" : "Show the catalogue")
        }
    }
}

/// The installed library.
struct LibraryPane: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    var body: some View {
        if store.libraryIsEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Metrics.rowGap) {
                    ForEach(BuildBranch.allCases) { branch in
                        section(branch)
                    }
                }
                .padding(.horizontal, Theme.Metrics.windowMargin)
                .padding(.bottom, Theme.Metrics.windowMargin)
                // The card for a new install appears and leaves as a card,
                // rather than the list jumping by a row's height twice.
                .animation(.smooth(duration: 0.3), value: store.pendingInstalls)
            }
        }
    }

    /// Nothing installed yet, said in one line on the window's own
    /// background.
    ///
    /// It was a card with two buttons on it, and that was one thing too many:
    /// a filled panel reads as an object in its own right, and both of its
    /// buttons already sit in the title bar, a few points above where the card
    /// was pointing. All this moment has to do is send you to the toolbar, so
    /// it says that and draws nothing — the catalogue's own glyph above the
    /// line, so there is no hunting for which button is meant.
    private var emptyState: some View {
        // Wrapped in a scroll view it will never need to scroll, because the
        // hairline under the title bar is the *hard* scroll-edge effect the
        // system falls back to whenever the content below the toolbar isn't a
        // scroll view at all. The installed list never drew one; this puts the
        // empty library on exactly the same footing. Setting the window's own
        // `titlebarSeparatorStyle` doesn't reach it.
        // The geometry reader is what keeps the tip centred as the window
        // resizes: a scroll view sizes its content from the content itself, so
        // without a minimum height to fill it would sit at the top and stay
        // there. Measuring the space the scroll view was given and asking the
        // tip for at least that much hands the centring back to the frame.
        GeometryReader { proxy in
            ScrollView {
                tip.frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var tip: some View {
        VStack(spacing: 12) {
            IconView(icon: .catalogue, size: 26)
                .foregroundStyle(.tertiary)
            Text("Open the catalogue from the button at the top right to browse and install Blender versions.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
        }
        .padding(Theme.Metrics.windowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A branch contributes a heading and its rows, or nothing at all — an
    /// empty heading would just be noise.
    @ViewBuilder
    private func section(_ branch: BuildBranch) -> some View {
        let rows = store.libraryRows(in: branch)
        if !rows.isEmpty {
            SectionHeader(title: branch.title, indent: Theme.Metrics.libraryCorner)
            // Installed builds and arrivals in one list, so a download sits
            // where it will live from the start — see `libraryRows(in:)`.
            ForEach(rows) { row in
                switch row {
                case .installed(let build):
                    InstalledRow(build: build)
                case .pending(let pending):
                    PendingRow(pending: pending)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
        }
    }
}

/// Marks where one branch ends and the next begins, in place of the segmented
/// tabs the app used to have.
struct SectionHeader: View {
    let title: String
    /// How far in from the pane's margin the text starts.
    ///
    /// The cards below are rounded, so their leading edge only runs straight
    /// from the corner radius down. The heading lines up with that — where
    /// the card's flat edge actually begins — rather than with the corner's
    /// outermost point, which no edge of the card ever reaches. Each pane
    /// passes its own cards' radius, since a library card's is 1.6× a
    /// catalogue card's.
    var indent: CGFloat = Theme.Metrics.corner

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            // The window title's own colour. A branch heading is the window
            // naming its own contents, the same job the title above it does,
            // so it is drawn in the same ink rather than demoted to
            // secondary — which is also what lets it go without a background
            // and still hold its own against the artwork below it.
            .foregroundStyle(.primary)
            .fixedSize()
            .padding(.leading, indent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 2)
            // Spelled out, the uppercase is read one letter at a time.
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A dismissible banner rather than a modal alert: a single flaky catalogue
/// fetch shouldn't interrupt a download that is already running.
struct ErrorBanner: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    var body: some View {
        Group {
            if let message = store.lastError {
                banner(message)
            }
        }
        .animation(.smooth(duration: 0.25), value: store.lastError)
    }

    private func banner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 11))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                store.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    // A 9-point glyph is not a target; the frame around it is.
                    .frame(width: 20, height: 20)
            }
            // The glyph has no fill of its own, so the hover highlight is the
            // whole of what says this is a button rather than an icon.
            .buttonStyle(.bare(cornerRadius: 5))
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(fill)
        .padding(.horizontal, Theme.Metrics.windowMargin)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(message)")
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var fill: some View {
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
