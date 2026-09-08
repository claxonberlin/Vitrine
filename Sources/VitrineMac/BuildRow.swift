import SwiftUI
import VitrineKit

/// The narrowest a library row's content can ever be laid out without
/// wrapping the date, truncating the version, or clipping the menu — reported
/// by every `InstalledRow` and reduced to the widest one. The window's
/// minimum width is built from this, so a row's content is what decides how
/// far the window can shrink, not a guessed constant that drifts out of date
/// the moment a version string or a date format changes shape.
struct RowMinWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A row for a build already in the library.
struct InstalledRow: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: InstalledBuild

    var body: some View {
        content
            .padding(.horizontal, Theme.Metrics.rowInset)
            .frame(height: Theme.Metrics.rowHeight)
            // No hover fill. A library row isn't clickable as a row, so
            // lighting it up under the pointer promised something that never
            // happened — the buttons on it do their own hover instead.
            .background(RowCard())
            .background(widthMeasurement)
            .contextMenu { rowActions }
    }

    // Eight points rather than ten: the menu's well is wider than the bare
    // glyph it replaced, and at the window's minimum width the row has no
    // slack to give it.
    @ViewBuilder
    private var content: some View {
        HStack(spacing: 8) {
            PillButton(title: "Launch", tint: Theme.blenderBlue) {
                store.launch(build)
            }
            .help("Open Blender \(build.version)")

            Text(build.version)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .fixedSize()

            if let target = store.updateAvailable(for: build) {
                UpdateButton(build: build, target: target)
                    .transition(.scale.combined(with: .opacity))
            }

            StarButton(starred: build.pinned) {
                withAnimation(.smooth(duration: 0.3)) { store.toggleStar(build) }
            }

            BadgeRow(
                riskLabel: (build.branch == .stable && build.riskId == "stable")
                    ? nil : build.riskLabel,
                isLTS: store.isLTS(build.version)
            )

            Spacer(minLength: 8)

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

            RowMenu { rowActions }
        }
    }

    /// An invisible copy of the row's content, laid out at its natural size
    /// instead of whatever width the real row was squeezed into, so it
    /// reports the true minimum rather than however far it already got
    /// compressed this frame.
    private var widthMeasurement: some View {
        content
            .padding(.horizontal, Theme.Metrics.rowInset)
            .fixedSize(horizontal: true, vertical: false)
            .hidden()
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: RowMinWidthKey.self, value: geometry.size.width)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var rowActions: some View {
        Button("Reveal in \(store.fileManagerName)") { store.reveal(build) }
        Divider()
        // A custom build is the user's own copy — Vitrine only forgets the
        // reference, so don't call it "Uninstall".
        Button(build.isCustom ? "Remove from Vitrine" : "Uninstall", role: .destructive) {
            withAnimation(.smooth(duration: 0.25)) { store.uninstall(build) }
        }
    }
}

/// A row for a build in the remote catalogue. The version lives inside the
/// download button rather than beside it — the button is what you aim at, and
/// naming the version on it says exactly what the click will fetch.
struct RemoteRow: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: RemoteBuild
    let branch: BuildBranch
    /// False inside an expanded group, which paints one continuous card behind
    /// the header and all of its children.
    var drawsCard: Bool = true

    @State private var hovered = false

    private var state: DownloadState { store.downloadState(build.id) }
    private var suppressRiskBadge: Bool { branch == .stable && build.riskId == "stable" }

    var body: some View {
        HStack(spacing: 8) {
            CatalogueAction(build: build, branch: branch)

            BadgeRow(
                riskLabel: suppressRiskBadge ? nil : build.riskLabel,
                isLTS: store.isLTS(build.version)
            )

            Spacer(minLength: 4)

            trailing
        }
        .padding(.horizontal, Theme.Metrics.rowInset)
        // Every row the same height as the group header above it — a build
        // inside an expanded group used to render smaller, which read as a
        // different, lesser kind of row rather than simply more of the same.
        .frame(height: Theme.Metrics.rowHeight)
        .background {
            if drawsCard { RowCard(hovered: hovered) }
        }
        .onHover { hovered = $0 }
        .help(build.fileName)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
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
            }
        }
    }
}

/// The leading control shared by catalogue rows and group headers: download,
/// cancel, retry, or "Put Back" when the build is already installed.
struct CatalogueAction: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: RemoteBuild
    let branch: BuildBranch
    /// Defaults to the full version; a group header passes its series instead.
    var label: String? = nil

    private let height = Theme.Metrics.actionHeight
    private let iconSize: CGFloat = 17

    /// The button plus the version beside it, laid out the same way as an
    /// installed row: a round action, then the version it acts on, instead
    /// of the version living inside the button's own label.
    var body: some View {
        HStack(spacing: 8) {
            action
            Text(label ?? build.version)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .fixedSize()
        }
    }

    @ViewBuilder
    private var action: some View {
        if let installed = store.installedMatch(for: build) {
            CircleIconButton(icon: .trash, tint: .red, diameter: height, iconSize: iconSize) {
                withAnimation(.smooth(duration: 0.25)) { store.uninstall(installed) }
            }
            .help("Remove Blender \(build.version) from the library")
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
                    CircleIconButton(icon: .update, tint: Theme.catalogueAccent,
                                     diameter: height, iconSize: iconSize) {
                        withAnimation(.smooth(duration: 0.25)) {
                            store.updateInstall(from: outdated, to: build)
                        }
                    }
                    .help("Update Blender \(outdated.version) to \(build.version)")
                } else {
                    CircleIconButton(icon: .download, tint: Theme.catalogueAccent,
                                     diameter: height, iconSize: iconSize) {
                        store.install(build, into: branch)
                    }
                    .help("Download Blender \(build.version)")
                }
            case .queued, .installing:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: height, height: height)
            case .downloading:
                PillButton(title: "Stop", tint: .red, height: height) {
                    store.cancelDownload(build)
                }
                .help("Cancel this download")
            case .failed:
                PillButton(title: "Retry", tint: .orange, height: height) {
                    store.install(build, into: branch)
                }
            }
        }
    }
}
