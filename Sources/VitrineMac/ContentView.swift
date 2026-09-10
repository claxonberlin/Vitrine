import SwiftUI
import VitrineKit

/// The whole app in one window: the installed library fills it, and the
/// catalogue slides in from the trailing edge as a second page, the width
/// of the window itself rather than a strip along its side.
///
/// It isn't a real split — the window never resizes, and the library never
/// gives up any of its own width — but it reads like one: opening the
/// catalogue pushes the library most of the way out of its path rather than
/// merely covering it, so the two feel like adjacent pages rather than a
/// panel laid on top. Both travel by exactly the same distance,
/// `catalogueTravel` — 85% of the window's own current width, not the
/// catalogue's, so at rest the library still shows a sliver of itself down
/// the leading 15%, the same small overlap a real page transition leaves
/// behind, and the catalogue is that same 85% wide rather than some
/// separately-chosen sidebar width.
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
    private static let catalogueTravelFraction: CGFloat = 0.70

    var body: some View {
        GeometryReader { geometry in
            let travel = geometry.size.width * Self.catalogueTravelFraction

            ZStack(alignment: .topTrailing) {
                Theme.windowBackground.ignoresSafeArea()

                LibraryPane(showCatalogue: $menu.catalogueShown, addBuild: $menu.addingBuild)
                // Slides left to make room for the incoming page rather than
                // staying put underneath it — see the type's own doc comment.
                .offset(x: showingCatalogue ? -travel : 0)
                // The sliver left showing down the leading edge is scenery,
                // not a second copy of the library: its buttons belong to
                // rows you can no longer read, so they stop taking clicks and
                // drop out of the keyboard and VoiceOver order — the same
                // deal the catalogue gets while it is the one parked off the
                // other edge. Dimming it as well would read nicely and cost
                // a full-window offscreen composite of every material card on
                // every frame of the slide, which is not a trade worth making.
                .allowsHitTesting(!showingCatalogue)
                .accessibilityHidden(showingCatalogue)

                // The page stays mounted and slides in and out on its
                // offset. A conditional view with a `move` transition only
                // animated the way in: SwiftUI tore the pane down on the way
                // out before the slide could play, so hiding the catalogue
                // snapped.
                // Parked, it sits exactly its own width past the trailing
                // edge, so the window already clips it away and it needs no
                // fade to hide behind — which matters, because animating one
                // would composite the whole page offscreen on every frame of
                // a slide that is otherwise a plain transform.
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
        .frame(minWidth: Theme.Metrics.windowMinWidth,
               minHeight: Theme.Metrics.windowMinHeight)
        .toolbar {
            titleItem
            addBuildAction
            catalogueToggle
        }
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

    // MARK: - Toolbar

    /// Centres the title over the content rather than letting AppKit pin it to
    /// the leading edge, which is how the window has always looked. The system
    /// title is off — see `windowToolbarStyle` on the scene.
    @ToolbarContentBuilder
    private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) { titleLabel }
            .sharedBackgroundHidden()
    }

    /// Stands in for the catalogue's own title now that it doesn't have
    /// one — the same way a real second page would rename the window
    /// rather than relabel itself. See `CataloguePane`'s doc comment.
    private var titleLabel: some View {
        Text(showingCatalogue ? "Catalogue" : "Vitrine")
            .font(.system(size: 13, weight: .semibold))
            .contentTransition(.opacity)
            .animation(.smooth(duration: 0.2), value: showingCatalogue)
            .accessibilityAddTraits(.isHeader)
    }

    @ToolbarContentBuilder
    private var addBuildAction: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ToolbarIconButton(icon: .addBuild,
                              label: "Add a Blender build you already have") {
                menu.addingBuild = true
            }
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
            ToolbarIconButton(icon: .catalogue,
                              label: showingCatalogue ? "Hide the catalogue" : "Show the catalogue",
                              toggledOn: showingCatalogue) {
                menu.catalogueShown.toggle()
            }
        }
        .sharedBackgroundHidden()
    }
}


/// The catalogue toggle and the add-build button: `CircleIconButton` at the
/// smaller size the title bar wants, with the toggle's resting state left
/// unfilled so plain glass reads as "off" and the tinted fill as "on" — the
/// system's own vocabulary for a toggle sitting in a glass toolbar.
private struct ToolbarIconButton: View {
    let icon: Icon
    let label: String
    /// Set only by a control that has an on and an off state, so a plain
    /// action button isn't announced as a toggle.
    var toggledOn: Bool? = nil
    let action: () -> Void

    private static let diameter = Theme.Metrics.actionHeight
    private static let iconSize = Theme.Metrics.actionIconSize

    var body: some View {
        CircleIconButton(icon: icon, label: label, filled: toggledOn == true,
                         diameter: Self.diameter, iconSize: Self.iconSize,
                         action: action)
            .accessibilityAddTraits(traits)
    }

    private var traits: AccessibilityTraits {
        switch toggledOn {
        case .none: []
        case .some(true): [.isToggle, .isSelected]
        case .some(false): .isToggle
        }
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

    /// No scroll-edge effect at this edge — for a scroll view that doesn't
    /// span the window, where the system falls back to a hairline rather than
    /// a blur. Also a no-op below macOS 26, which draws neither.
    @ViewBuilder
    func scrollEdgeEffectHiddenCompat(for edges: Edge.Set) -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: edges)
        } else {
            self
        }
    }
}

/// The installed library.
struct LibraryPane: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    @Binding var showCatalogue: Bool
    @Binding var addBuild: Bool

    var body: some View {
        if store.installed.isEmpty {
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
            }
            .scrollContentBackground(.hidden)
            // The system's own soft scroll-edge dissolve, blurring rows as
            // they pass under the toolbar.
            .softScrollEdgeCompat(for: .top)
        }
    }

    /// Nothing installed yet, and both ways out of that offered here rather
    /// than left to be found in the toolbar.
    ///
    /// On its own card, like everything else in this window: the splash
    /// artwork behind it is a full-colour painting, and plain text laid
    /// straight on one is a coin toss between legible and invisible depending
    /// on which release is current.
    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No Builds Installed")
            } icon: {
                IconView(icon: .library, size: 34)
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text("Download one from the catalogue, or add a Blender you already have.")
                .frame(maxWidth: 240)
        } actions: {
            HStack(spacing: 10) {
                // Stock system buttons, which bring their own hover and
                // pressed states — nothing to add by hand here.
                Button("Show Catalogue") { showCatalogue = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.catalogueAccent)
                Button("Add Build…") { addBuild = true }
            }
            // The placeholder sizes its actions row to the description above
            // it, which clips a two-button row's labels.
            .fixedSize()
        }
        .fixedSize()
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(RowCard())
        .padding(Theme.Metrics.windowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A branch contributes a heading and its rows, or nothing at all — an
    /// empty heading would just be noise.
    @ViewBuilder
    private func section(_ branch: BuildBranch) -> some View {
        let items = store.installed(in: branch)
        if !items.isEmpty {
            SectionHeader(title: branch.title, indent: Theme.Metrics.libraryCorner)
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
