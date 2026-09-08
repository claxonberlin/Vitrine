import SwiftUI
import VitrineKit

/// A row for a build already in the library.
struct InstalledRow: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: InstalledBuild

    @State private var confirmingUninstall = false

    var body: some View {
        content
            .padding(.horizontal, Theme.Metrics.rowInset)
            .frame(height: Theme.Metrics.rowHeight)
            // No hover fill. A library row isn't clickable as a row, so
            // lighting it up under the pointer promised something that never
            // happened — the buttons on it do their own hover instead.
            .background(RowCard())
            .contextMenu { rowActions }
            .uninstallConfirmation(for: build, isPresented: $confirmingUninstall)
    }

    private var content: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            PillButton(title: "Launch", tint: Theme.blenderBlue,
                       help: "Open Blender \(build.version)") {
                store.launch(build)
            }

            // LTS grouped right against the version it qualifies — the two
            // read as one identity, not a version followed by a separate
            // status chip.
            HStack(spacing: 4) {
                // A build the user added by hand is named after whatever is
                // on disk, so this is the one label on a row with no bound on
                // its length. It truncates rather than pushing the row wider
                // than the window; everything beside it is a short, fixed
                // string or a fixed-size control.
                Text(build.version)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                if store.isLTS(build.version) { LTSBadge() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(store.isLTS(build.version)
                                ? "Blender \(build.version), long-term support"
                                : "Blender \(build.version)")

            if let target = store.updateAvailable(for: build) {
                UpdateButton(build: build, target: target)
                    .transition(.scale.combined(with: .opacity))
            }

            if let riskLabel = build.displayRiskLabel {
                Badge(text: riskLabel)
            }

            Spacer(minLength: Theme.Metrics.rowSpacing)

            dates

            RowMenu(buildName: build.version) { rowActions }
        }
    }

    private var dates: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(DateFormat.day(build.installedAt))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let last = build.lastLaunchedAt {
                Text("Opened \(DateFormat.relative(last))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .monospacedDigit()
        // A date is a fixed, short string; wrapping it onto two lines to
        // save four points is never the right trade.
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(build.lastLaunchedAt.map {
            "Installed \(DateFormat.day(build.installedAt)), last opened \(DateFormat.relative($0))"
        } ?? "Installed \(DateFormat.day(build.installedAt))")
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
                    .font(.system(size: 9))
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
                    .font(.system(size: 10))
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
                .font(.system(size: 13, weight: .medium))
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
