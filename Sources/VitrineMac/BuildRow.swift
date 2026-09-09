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
            .task(id: build.version) { await splash.load(for: build.version) }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.libraryCorner, style: .continuous)
        // A mid-light grey until (and unless) the release's painting is in
        // hand — a daily build has no splash of its own, and a release's art
        // may still be downloading. The solid base also takes exactly the
        // row's frame, so the painting on top is clipped to the card and
        // never spills into the rows above and below.
        Theme.cardPlaceholder
            .overlay {
                if let art = splash.image(for: build.version) {
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
            // top, the "added" date on the bottom. The gap between the rows,
            // the gap from the top chip to the top of the Launch button, and
            // the gap from the bottom chip to its bottom are all the same
            // `cardChipGap` — 2·chipHeight + 3·gap == the button's height.
            VStack(alignment: .leading, spacing: Theme.Metrics.cardChipGap) {
                HStack(spacing: 4) {
                    let isLTS = store.isLTS(build.version)
                    // "Stable" beside "LTS" says nothing "LTS" doesn't — an
                    // LTS build is always stable branch, stable risk.
                    if !(isLTS && build.riskId == "stable") {
                        CardChip(text: build.riskLabel)
                    }
                    if isLTS {
                        CardChip(text: "LTS")
                            .accessibilityLabel("Long-term support")
                    }
                }

                CardChip(text: DateFormat.day(build.installedAt))
                    .accessibilityLabel("Added \(DateFormat.day(build.installedAt))")
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

            BadgeRow(riskLabel: build.riskLabel(under: branch),
                     isLTS: store.isLTS(build.version))

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
                RowCard(hovered: hovered)
            } else {
                RowHoverHighlight(hovered: hovered)
            }
        }
        .onHover { hovered = $0 }
        .help(build.fileName)
    }

    @ViewBuilder
    private var trailing: some View {
        switch store.downloadState(build.id) {
        case .downloading(let received, let total, let bps):
            let fraction = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
            let etaSeconds = bps > 0 && total > received ? Double(total - received) / bps : -1
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(width: 74)
                Text(DurationFormat.eta(seconds: etaSeconds))
                    .font(Theme.openDigits(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Downloading Blender \(build.version)")
            .accessibilityValue("\(Int(fraction * 100)) percent")
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
        HStack(spacing: Theme.Metrics.rowSpacing) {
            action
            Text(label ?? build.version)
                .font(Theme.openDigits(size: 13, weight: .medium))
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
                ProgressView()
                    .controlSize(.small)
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
private struct CardChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.openDigits(size: 12, weight: .semibold).smallCaps())
            .fontWidth(.condensed)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // Semantic, so it inverts with the material behind it in dark
            // appearance instead of staying ink on a now-dark chip.
            .foregroundStyle(.secondary)
            // Optical centring. The frame below centres the *line box*, which
            // runs from ascender to descender — and small caps, digits and
            // capitals reach neither, so the ink lands a point low. Nudged
            // back up before the frame is applied, so this shifts what is
            // drawn without moving the chip or its material.
            .offset(y: -1)
            .padding(.horizontal, 5)
            .frame(height: Theme.Metrics.cardChipHeight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.thickMaterial)
            )
            .accessibilityLabel(text)
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
                // A `.plain` button takes its hit region from what the label
                // actually draws — without this only the glyphs of the version
                // are clickable and the rest of the pill is dead.
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .cardGlass(tint: Theme.blenderBlue, in: Capsule(style: .continuous))
        .handCursor()
        .help("Open Blender \(version)")
        .accessibilityLabel("Open Blender \(version)")
    }
}
