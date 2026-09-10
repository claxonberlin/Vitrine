import SwiftUI
import VitrineKit

/// A row for a build already in the library.
struct InstalledRow: View {
    @EnvironmentObject private var bridge: StoreBridge
    @EnvironmentObject private var splash: RowSplashCatalog
    /// `.key` while this is the frontmost window, `.inactive` when the app is
    /// in the background — the splash art desaturates and dims in step with
    /// it, the way the OS greys its own chrome.
    @Environment(\.controlActiveState) private var activeState
    private var store: BuildStore { bridge.store }
    let build: InstalledBuild

    @State private var confirmingUninstall = false

    var body: some View {
        content
            .padding(.horizontal, Theme.Metrics.libraryRowInset)
            // Pin the row — and therefore its card — to exactly the width the
            // list offers, so the background always keeps the window margin.
            // Without this a row whose controls don't fit at the minimum
            // window size (the Update button is the one that tips it over)
            // lets its HStack overflow, and the card grew with it.
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metrics.libraryRowHeight)
            // Purely the release's own splash painting, cropped to the card —
            // no glass, material or colour over it. Legibility comes later.
            .background(rowBackground)
            // The card's own hit region, now that its background declines
            // every click: this is what still gives right-click somewhere to
            // land across the whole row. It doesn't clip the buttons inside.
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.libraryCorner,
                                           style: .continuous))
            .contextMenu { rowActions }
            .uninstallConfirmation(for: build, isPresented: $confirmingUninstall)
            // The one place the artwork is fetched. Never from `body` — see
            // `RowSplashCatalog`.
            // A daily's backdrop ships with the app, so only a release has
            // anything to load.
            .task(id: build.version) {
                guard build.branch != .daily else { return }
                await splash.load(for: build.version)
            }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.libraryCorner, style: .continuous)
        // A mid-light grey until (and unless) the painting is in hand — a
        // release's art may still be loading. The solid base also takes
        // exactly the row's frame, so the painting on top is clipped to the
        // card and never spills into the rows above and below.
        Theme.cardPlaceholder
            .overlay {
                if let art = splash.image(for: build) {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(shape)
            .saturation(inactive ? 0 : 1)
            .opacity(inactive ? 0.6 : 1)
            .animation(.smooth(duration: 0.2), value: inactive)
            // Decoration, and it must never take a click. `scaledToFill` sizes
            // a 16:9 painting to ~450×253 inside a 450×70 row, so it hangs
            // ~90pt past the card top and bottom; `clipShape` above hides that
            // but does not reliably clip hit testing, and a `VStack` draws
            // later siblings over earlier ones — so each row's artwork was
            // swallowing the clicks meant for the row above it. Only the
            // bottom row, and any row under one with no splash of its own,
            // still worked.
            .allowsHitTesting(false)
    }

    /// The app is in the background — no window of it is key.
    private var inactive: Bool { activeState == .inactive }

    private var content: some View {
        HStack(spacing: Theme.Metrics.libraryRowSpacing) {
            // The version *is* the label — no separate "Launch" word and no
            // plain version text beside it.
            LaunchButton(version: build.version) { store.launch(build) }

            // Two stacked rows beside it, same chip styling on both: tags on
            // top, when the build was made on the bottom. The gap between the rows,
            // the gap from the top chip to the top of the Launch button, and
            // the gap from the bottom chip to its bottom are all the same
            // `cardChipGap` — 2·chipHeight + 3·gap == the button's height.
            VStack(alignment: .leading, spacing: Theme.Metrics.cardChipGap) {
                ChipLine(chips: tagChips)
                ChipLine(chips: [.text(dateChip, label: dateDescription)])
            }
            .padding(.vertical, Theme.Metrics.cardChipGap)
            .frame(height: Theme.Metrics.launchButtonSize.height, alignment: .leading)
            // Lowest priority in the row: at the minimum window size the
            // chips give way before the fixed-size controls do.
            .layoutPriority(-1)

            Spacer(minLength: Theme.Metrics.libraryRowSpacing)

            // The two round controls sit together at the trailing edge, Update
            // immediately left of the "···" menu — in their own HStack so
            // their gap is `rowTrailingSpacing`, not the row-wide spacing.
            HStack(spacing: Theme.Metrics.rowTrailingSpacing) {
                if let target = store.updateAvailable(for: build) {
                    UpdateButton(build: build, target: target)
                        .transition(.scale.combined(with: .opacity))
                }

                RowMenu(buildName: build.version) { rowActions }
            }
        }
    }

    /// The card's top line: what this build is, most important first — the
    /// star, then how finished it is, then which build it actually is, then
    /// whether its series is supported. Dropped from the end when the row
    /// runs out of width, so the star is the last thing to go.
    private var tagChips: [ChipSpec] {
        let isLTS = store.isLTS(build.version)
        var chips: [ChipSpec] = []
        if build.pinned {
            chips.append(.icon(.star, id: "star", help: Self.starMeaning,
                               label: "Starred", hint: Self.starMeaning))
        }
        if let risk = build.riskLabel(besideLTS: isLTS) { chips.append(.text(risk)) }
        // Only a daily needs the hash, and it belongs beside the risk it
        // qualifies: it is what tells two builds of one version apart, not a
        // second date.
        if build.branch == .daily, let hash = build.sourceHash {
            chips.append(.text(hash, label: "Build \(hash)"))
        }
        if isLTS { chips.append(BadgeRow.ltsChip) }
        return chips
    }

    private static let starMeaning =
        "Starred — opens .blend files, and puts `blender` on your PATH"

    /// A daily is a position on a moving track, so the recent ones read as
    /// the day they came from. Everything else is a dated release, and says
    /// which date — as does a daily old enough that "Today" and "Yesterday"
    /// have nothing left to say about it.
    private var dateChip: String {
        build.branch == .daily
            ? DateFormat.recentDay(build.buildDate)
            : DateFormat.day(build.buildDate)
    }

    private var dateDescription: String {
        let day = DateFormat.day(build.buildDate)
        return build.hasBuildDate ? "Built \(day)" : "Added \(day)"
    }

    @ViewBuilder
    private var rowActions: some View {
        Button(build.pinned ? "Unstar" : "Star") {
            withAnimation(.smooth(duration: 0.3)) { store.toggleStar(build) }
        }
        .help(build.pinned
              ? "Stop treating this build as the system Blender"
              : "Star — opens .blend files, and puts `blender` on your PATH")
        Button("Reveal in \(store.fileManagerName)") { store.reveal(build) }
        Divider()
        // A custom build is the user's own copy — Vitrine only forgets the
        // reference, so don't call it "Uninstall", and don't ask before
        // forgetting something that stays on disk either way.
        if build.isCustom {
            Button("Remove from Vitrine", role: .destructive) {
                withAnimation(.smooth(duration: 0.25)) { store.uninstall(build) }
            }
        } else {
            Button("Uninstall…", role: .destructive) { confirmingUninstall = true }
        }
    }
}

/// Deleting an installed build takes a gigabyte or two off the disk and
/// nothing puts it back, so both ways in — the library row's menu and the
/// catalogue's remove button — ask first. Custom builds never come here:
/// forgetting a reference leaves the files exactly where they were.
extension View {
    func uninstallConfirmation(for build: InstalledBuild,
                               isPresented: Binding<Bool>) -> some View {
        modifier(UninstallConfirmation(build: build, isPresented: isPresented))
    }
}

private struct UninstallConfirmation: ViewModifier {
    @EnvironmentObject private var bridge: StoreBridge
    let build: InstalledBuild
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Uninstall Blender \(build.version)?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                withAnimation(.smooth(duration: 0.25)) { bridge.store.uninstall(build) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its folder is deleted from the library. Your Blender preferences and "
                 + "add-ons are kept.")
        }
    }
}

/// A row for a build in the remote catalogue.
struct RemoteRow: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: RemoteBuild
    let branch: BuildBranch
    /// False inside an expanded group, which paints one continuous card behind
    /// the header and all of its children.
    var drawsCard: Bool = true

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            CatalogueAction(build: build, branch: branch)

            CatalogueChips(build: build, branch: branch)

            Spacer(minLength: 4)

            trailing
        }
        .padding(.horizontal, Theme.Metrics.rowInset)
        // Every row the same height as the group header above it — a build
        // inside an expanded group used to render smaller, which read as a
        // different, lesser kind of row rather than simply more of the same.
        .frame(height: Theme.Metrics.rowHeight)
        .background {
            if drawsCard {
                RowCard(hovered: hovered, progress: progress)
            } else {
                RowHoverHighlight(hovered: hovered, progress: progress)
            }
        }
        .onHover { hovered = $0 }
        .help(build.fileName)
    }

    /// What the row's own card is drawing behind all of this — see
    /// `RowProgressFill`.
    private var progress: RowProgress? {
        switch store.downloadState(build.id) {
        case .downloading(let received, let total):
            return .downloading(total > 0 ? Double(received) / Double(total) : 0)
        case .installing(let fraction):
            return .installing(fraction)
        case .queued:
            return .queued
        case .idle, .failed:
            return nil
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch store.downloadState(build.id) {
        case .downloading(let received, let total):
            let fraction = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
            // Just the word. The card behind this is the progress bar now, and
            // how far along it is is the one thing it already says.
            Text("Downloading")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Downloading Blender \(build.version)")
                .accessibilityValue("\(Int(fraction * 100)) percent")
                .transition(.opacity)
        case .queued:
            Text("Queued")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        case .installing:
            Text("Installing")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        case .failed(let message):
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .lineLimit(2)
                .frame(maxWidth: 88, alignment: .trailing)
                .help(message)
        default:
            // Only the size: the release date doesn't fit in here, and it is
            // the less useful of the two when picking a build to download.
            if build.fileSize > 0 {
                Text(ByteFormat.string(build.fileSize))
                    .font(Theme.openDigits(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Download size \(ByteFormat.string(build.fileSize))")
            }
        }
    }
}

/// What a catalogue row wears beside its version: the same chips a library
/// card does, in the same order — the risk, a daily's hash, LTS — with the
/// build's own date under them. Two rows spread evenly over the catalogue
/// row's height, the way the card's chips are spread over the height of its
/// Launch button.
struct CatalogueChips: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: RemoteBuild
    let branch: BuildBranch

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowChipGap) {
            if !tagChips.isEmpty {
                ChipLine(chips: tagChips)
            }
            if !secondLine.isEmpty {
                ChipLine(chips: secondLine)
            }
        }
        .padding(.vertical, Theme.Metrics.rowChipGap)
        .frame(height: Theme.Metrics.rowHeight, alignment: .leading)
        // The chips give way before the row's fixed-size controls do, exactly
        // as they do on a library row.
        .layoutPriority(-1)
    }

    private var tagChips: [ChipSpec] {
        var chips: [ChipSpec] = []
        let isLTS = store.isLTS(build.version)
        // Every catalogue row says how finished its build is, "Stable"
        // included — the heading it sits under is scrolled away half the
        // time. Only an LTS row goes without, since its own chip says it.
        if let risk = build.riskLabel(besideLTS: isLTS) { chips.append(.text(risk)) }
        if isLTS { chips.append(BadgeRow.ltsChip) }
        return chips
    }

    /// Under the row's tags: which build this actually is.
    ///
    /// For a daily that is the hash, and only the hash — the catalogue lists
    /// one daily per series, tonight's, so a date under it would say what
    /// the heading already does. Every other row says the date it was
    /// released, which is how one release is told from another.
    private var secondLine: [ChipSpec] {
        if branch == .daily {
            guard let hash = build.hash else { return [] }
            return [.text(hash, label: "Build \(hash)")]
        }
        guard build.date != .distantPast else { return [] }
        return [.text(DateFormat.day(build.date), label: dateDescription)]
    }

    private var dateDescription: String { "Built \(DateFormat.day(build.date))" }
}

/// The leading control shared by catalogue rows and group headers: download,
/// cancel, retry, or remove when the build is already installed.
struct CatalogueAction: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: RemoteBuild
    let branch: BuildBranch
    /// Defaults to the full version; a group header passes its series instead.
    var label: String? = nil

    @State private var confirmingUninstall = false

    /// The button plus the version beside it, laid out the same way as an
    /// installed row: a round action, then the version it acts on, instead
    /// of the version living inside the button's own label.
    var body: some View {
        // The library's gap, not the catalogue's own: this pair is the same
        // pair a library row opens with — a round action and the version it
        // acts on — so it stands the same distance apart on both pages.
        HStack(spacing: Theme.Metrics.libraryRowSpacing) {
            action
            // The same treatment the library gives a version on its Launch
            // button — bold, open digits — only smaller and at regular
            // width, since a catalogue row has the room the button hasn't.
            Text(label ?? build.version)
                .font(Theme.openDigits(size: 15, weight: .bold))
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel("Blender \(label ?? build.version)")
        }
    }

    @ViewBuilder
    private var action: some View {
        if let installed = store.installedMatch(for: build) {
            CircleIconButton(icon: .trash,
                             label: "Remove Blender \(build.version) from the library",
                             tint: .red) {
                confirmingUninstall = true
            }
            .uninstallConfirmation(for: installed, isPresented: $confirmingUninstall)
        } else {
            switch store.downloadState(build.id) {
            case .idle:
                // A group header stands for its whole series. If an older
                // patch of it is already installed, offer to bring that one
                // forward instead of installing the newest as a second,
                // separate copy — the individual rows inside the group keep
                // the plain download button regardless (`label` is only set
                // on the header).
                if label != nil, let outdated = store.installedInSameSeries(as: build) {
                    CircleIconButton(icon: .update,
                                     label: "Update Blender \(outdated.version) to \(build.version)") {
                        withAnimation(.smooth(duration: 0.25)) {
                            store.updateInstall(from: outdated, to: build)
                        }
                    }
                } else {
                    CircleIconButton(icon: .download,
                                     label: "Download Blender \(build.version)") {
                        store.install(build, into: branch)
                    }
                }
            case .queued, .installing:
                // No spinner: the card behind the row is already sweeping.
                // The space is held so the version doesn't jump leftward for
                // the few seconds an install takes.
                Color.clear
                    .frame(width: Theme.Metrics.actionHeight, height: Theme.Metrics.actionHeight)
                    .accessibilityLabel("Installing Blender \(build.version)")
            case .downloading:
                PillButton(title: "Stop", tint: .red,
                           help: "Cancel the Blender \(build.version) download") {
                    store.cancelDownload(build)
                }
            case .failed:
                PillButton(title: "Retry", tint: .orange,
                           help: "Try the Blender \(build.version) download again") {
                    store.install(build, into: branch)
                }
            }
        }
    }
}

/// A small text chip on a library card — the "added" date and each tag wear
/// it: Sequoia's `.thinMaterial` in a small-radius rectangle that hugs the
/// text, with dark text on top.
struct CardChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.openDigits(size: 12, weight: .semibold).smallCaps())
            .fontWidth(.condensed)
            // Never squeezed to fit: a chip that doesn't fit is dropped by
            // the line that holds it. See `ChipLine`.
            .lineLimit(1)
            .fixedSize()
            // Semantic, so it inverts with the material behind it in dark
            // appearance instead of staying ink on a now-dark chip.
            .foregroundStyle(.secondary)
            // Optical centring. The frame below centres the *line box*, which
            // runs from ascender to descender — and small caps, digits and
            // capitals reach neither, so the ink lands a point low. Nudged
            // back up before the frame is applied, so this shifts what is
            // drawn without moving the chip or its material.
            .offset(y: -1)
            .cardChipBackground()
            .accessibilityLabel(text)
    }
}

/// A chip with a glyph in place of a word — the starred build's is the one
/// that uses it. It leads the line rather than joining it, since it says
/// something about this build's standing in the library rather than about
/// the build itself.
struct CardIconChip: View {
    let icon: Icon

    var body: some View {
        IconView(icon: icon, size: 12)
            .foregroundStyle(.secondary)
            .cardChipBackground()
    }
}

extension View {
    /// The chip itself: a small-radius rectangle of `.thickMaterial` hugging
    /// whatever it holds, at the one chip height.
    func cardChipBackground() -> some View {
        self
            .padding(.horizontal, 5)
            .frame(height: Theme.Metrics.cardChipHeight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.thickMaterial)
            )
    }
}

/// The library row's primary action: opens the build. Its label is the
/// version number itself — heavy, condensed, with SF Pro's open-digit
/// stylistic sets — and it stands 50% taller than the row's round controls
/// so the number reads as the anchor of the row. Same glass material as the
/// Update and overflow buttons; only the tint (Blender blue) differs.
private struct LaunchButton: View {
    let version: String
    let action: () -> Void

    /// Every Launch button is this exact size, whatever its version string —
    /// a wall of same-shaped buttons down the leading edge, not a ragged one.
    private static let size = Theme.Metrics.launchButtonSize

    var body: some View {
        Button(action: action) {
            Text(version)
                .font(Theme.openDigits(size: 21, weight: .bold))
                .fontWidth(.condensed)
                .lineLimit(1)
                // A hand-added build can be named anything; shrink to fit
                // rather than clip or force the fixed-width button wider.
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .frame(width: Self.size.width, height: Self.size.height)
        }
        // Carries the hover highlight, and sets the hit region to the whole
        // capsule: a `.plain` button takes its region from what the label
        // actually draws, which left only the glyphs of the version clickable
        // and the rest of the pill dead.
        .buttonStyle(.pill())
        .cardGlass(tint: Theme.blenderBlue, in: Capsule(style: .continuous))
        .help("Open Blender \(version)")
        .accessibilityLabel("Open Blender \(version)")
    }
}
