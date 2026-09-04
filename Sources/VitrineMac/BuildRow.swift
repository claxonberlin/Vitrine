import SwiftUI
import VitrineKit

/// A row for a build already in the library.
struct InstalledRow: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: InstalledBuild

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            PillButton(title: "Launch", tint: build.pinned ? .yellow : .green) {
                store.launch(build)
            }
            .help("Open Blender \(build.version)")

            if let target = store.updateAvailable(for: build) {
                UpdateButton(build: build, target: target)
                    .transition(.scale.combined(with: .opacity))
            }

            StarButton(starred: build.pinned) {
                withAnimation(.smooth(duration: 0.3)) { store.toggleStar(build) }
            }

            Text(build.version)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()

            BadgeRow(
                riskLabel: (build.branch == .stable && build.riskId == "stable")
                    ? nil : build.riskLabel,
                isLTS: store.isLTS(build.version),
                accent: Theme.vitrineAccent
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

            // The same actions as the context menu, in a control you can see.
            // Right-click is the macOS way to reach them; not everyone knows
            // there is anything there to right-click.
            Menu {
                rowActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            .foregroundStyle(hovered ? .secondary : .tertiary)
            .handCursor()
        }
        .padding(.horizontal, Theme.Metrics.rowInset)
        .frame(height: Theme.Metrics.rowHeight)
        .background(RowCard(hovered: hovered))
        .onHover { hovered = $0 }
        .contextMenu { rowActions }
    }

    @ViewBuilder
    private var rowActions: some View {
        Button("Reveal in \(store.fileManagerName)") { store.reveal(build) }
        Button(build.pinned ? "Unstar" : "Star") {
            withAnimation(.smooth(duration: 0.3)) { store.toggleStar(build) }
        }
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
    var compact: Bool = false
    /// False inside an expanded group, which paints one continuous card behind
    /// the header and all of its children.
    var drawsCard: Bool = true

    @State private var hovered = false

    private var state: DownloadState { store.downloadState(build.id) }
    private var suppressRiskBadge: Bool { branch == .stable && build.riskId == "stable" }

    var body: some View {
        HStack(spacing: 8) {
            CatalogueAction(build: build, branch: branch, compact: compact)

            BadgeRow(
                riskLabel: suppressRiskBadge ? nil : build.riskLabel,
                isLTS: store.isLTS(build.version),
                accent: Theme.catalogueAccent
            )

            Spacer(minLength: 4)

            trailing
        }
        .padding(.horizontal, Theme.Metrics.rowInset)
        .frame(height: compact ? Theme.Metrics.compactRowHeight : Theme.Metrics.rowHeight)
        .background {
            if drawsCard { RowCard(hovered: hovered, tinted: true) }
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
    var compact: Bool = false
    /// Defaults to the full version; a group header passes its series instead.
    var label: String? = nil

    private var height: CGFloat {
        compact ? Theme.Metrics.compactActionHeight : Theme.Metrics.actionHeight
    }

    var body: some View {
        if let installed = store.installedMatch(for: build) {
            PillButton(title: "Put Back", tint: .red, height: height) {
                withAnimation(.smooth(duration: 0.25)) { store.uninstall(installed) }
            }
            .help("Remove Blender \(build.version) from the library")
        } else {
            switch store.downloadState(build.id) {
            case .idle:
                DownloadButton(
                    label: label ?? build.version,
                    version: build.version,
                    height: height
                ) {
                    store.install(build, into: branch)
                }
            case .queued, .installing:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Theme.Metrics.actionWidth, height: height)
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
