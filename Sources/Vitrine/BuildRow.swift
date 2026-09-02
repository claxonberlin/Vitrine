import SwiftCrossUI
import VitrineKit

/// A row for a build already in the library.
struct InstalledRow: View {
    let store: BuildStore
    let build: InstalledBuild
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            PillButton(title: "Launch", tint: build.pinned ? .yellow : .green) {
                store.launch(build)
            }

            if let target = store.updateAvailable(for: build) {
                UpdateButton(store: store, build: build, target: target, accent: accent)
            }

            StarButton(starred: build.pinned) { store.toggleStar(build) }

            Text(build.version)
                .font(.system(size: 13, weight: .medium))
                .fontDesign(.monospaced)

            BadgeRow(
                riskLabel: (build.branch == .stable && build.riskId == "stable")
                    ? nil : build.riskLabel,
                isLTS: store.isLTS(build.version),
                accent: accent
            )

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(DateFormat.day(build.installedAt))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                if let last = build.lastLaunchedAt {
                    Text("Opened \(DateFormat.relative(last))")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.tertiaryText)
                }
            }

            // Stands in for the right-click context menu the macOS build had:
            // SwiftCrossUI has no `contextMenu`, and an always-visible
            // affordance is more discoverable on GNOME anyway.
            Menu(Theme.Glyph.more) {
                Button("Reveal in \(store.fileManagerName)") { store.reveal(build) }
                Button(build.pinned ? "Unstar" : "Star") { store.toggleStar(build) }
                Divider()
                // A custom build is the user's own copy — Vitrine only forgets
                // the reference, so don't call it "Uninstall".
                Button(build.isCustom ? "Remove from Vitrine" : "Uninstall") {
                    store.uninstall(build)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.rowHeight)
        .background(RowBackground())
    }
}

/// A row for a build in the remote catalogue. The version lives inside the
/// download button rather than beside it — the button is what you aim at, and
/// naming the version on it says exactly what the click will fetch.
struct RemoteRow: View {
    let store: BuildStore
    let build: RemoteBuild
    let branch: BuildBranch
    let accent: Color
    var compact: Bool = false

    private var state: DownloadState { store.downloadState(build.id) }
    private var suppressRiskBadge: Bool { branch == .stable && build.riskId == "stable" }

    var body: some View {
        HStack(spacing: 10) {
            CatalogueActionColumn(
                store: store,
                build: build,
                branch: branch,
                accent: accent,
                installedBuild: store.installedMatch(for: build),
                state: state,
                compact: compact
            )

            BadgeRow(
                riskLabel: suppressRiskBadge ? nil : build.riskLabel,
                isLTS: store.isLTS(build.version),
                accent: accent
            )

            Spacer(minLength: 8)

            rightColumn
        }
        .padding(.horizontal, 12)
        .frame(height: compact ? Theme.Metrics.compactRowHeight : Theme.Metrics.rowHeight)
        .background(RowBackground())
    }

    @ViewBuilder
    private var rightColumn: some View {
        switch state {
        case .downloading(let received, let total, let bps):
            let fraction = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
            let etaSeconds = bps > 0 && total > received ? Double(total - received) / bps : -1
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: fraction)
                    .frame(width: 130)
                Text("\(speedString(bps)) · ETA \(DurationFormat.eta(seconds: etaSeconds))")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.secondaryText)
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.red)
                .lineLimit(2)
                .frame(maxWidth: 170, alignment: .trailing)
        default:
            VStack(alignment: .trailing, spacing: 1) {
                Text(DateFormat.day(build.date))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                if build.fileSize > 0 {
                    Text(ByteFormat.string(build.fileSize))
                        .font(.system(size: 9))
                        .foregroundColor(Theme.tertiaryText)
                }
            }
        }
    }

    private func speedString(_ bps: Double) -> String {
        bps > 0 ? "\(ByteFormat.string(Int64(bps)))/s" : "—"
    }
}

/// Header row summarising a minor-version group. The button fetches the
/// group's newest patch and names it; the label beside it is the series.
/// Tapping elsewhere folds or unfolds the children.
struct RemoteGroupHeaderRow: View {
    let store: BuildStore
    let group: RemoteBuildGroup
    let branch: BuildBranch
    let accent: Color

    private var isExpanded: Bool { store.expandedMinorKeys.contains(group.minorKey) }

    var body: some View {
        HStack(spacing: 10) {
            CatalogueActionColumn(
                store: store,
                build: group.latest,
                branch: branch,
                accent: accent,
                installedBuild: store.installedMatch(for: group.latest),
                state: store.downloadState(group.latest.id),
                compact: false,
                label: group.minorKey
            )

            BadgeRow(
                riskLabel: (branch == .stable && group.latest.riskId == "stable")
                    ? nil : group.latest.riskLabel,
                isLTS: store.isLTS(group.latest.version),
                accent: accent
            )

            Spacer(minLength: 8)

            Text("\(group.builds.count) versions")
                .font(.system(size: 10))
                .foregroundColor(Theme.tertiaryText)

            Text(isExpanded ? Theme.Glyph.expanded : Theme.Glyph.collapsed)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.tertiaryText)
                .frame(minWidth: 12, maxWidth: 12)
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.rowHeight)
        .background(RowBackground())
        .onTapGesture { store.toggleExpansion(group.minorKey) }
    }
}

/// The leading control shared by catalogue rows and group headers: download,
/// cancel, retry, or "Put Back" when the build is already installed.
struct CatalogueActionColumn: View {
    let store: BuildStore
    let build: RemoteBuild
    let branch: BuildBranch
    let accent: Color
    let installedBuild: InstalledBuild?
    let state: DownloadState
    let compact: Bool
    /// Defaults to the full version; group headers pass the series instead.
    var label: String? = nil

    private var height: Int {
        compact ? Theme.Metrics.compactActionHeight : Theme.Metrics.actionHeight
    }

    var body: some View {
        if let installed = installedBuild {
            PillButton(title: "Put Back", tint: .red, height: height) {
                store.uninstall(installed)
            }
        } else {
            switch state {
            case .idle:
                DownloadButton(
                    label: label ?? build.version,
                    version: build.version,
                    tint: accent,
                    height: height
                ) {
                    store.install(build, into: branch)
                }
            case .queued, .installing:
                ProgressView()
                    .frame(
                        minWidth: Double(Theme.Metrics.actionWidth),
                        maxWidth: Double(Theme.Metrics.actionWidth),
                        minHeight: Double(height), maxHeight: Double(height)
                    )
            case .downloading:
                PillButton(title: Theme.Glyph.stop, tint: .red, height: height) {
                    store.cancelDownload(build)
                }
            case .failed:
                PillButton(title: "Retry", tint: .orange, height: height) {
                    store.install(build, into: branch)
                }
            }
        }
    }
}

/// The catalogue's primary action. The icon is pinned to the leading edge and
/// the label centred across the full button, so labels of different lengths
/// ("5.2" against "4.5.13") still line up down the column.
struct DownloadButton: View {
    /// What the button says — the series on a group header, the exact build on
    /// an individual row.
    let label: String
    /// The build actually fetched, used for the tooltip.
    let version: String
    let tint: Color
    let height: Int
    let action: @MainActor @Sendable () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .fontDesign(.monospaced)
                    .foregroundColor(.white)

                HStack(spacing: 0) {
                    artwork
                    Spacer(minLength: 0)
                }
                .padding(.leading, 9)
            }
            .frame(
                minWidth: Double(Theme.Metrics.actionWidth),
                maxWidth: Double(Theme.Metrics.actionWidth),
                minHeight: Double(height),
                maxHeight: Double(height)
            )
            .background(
                tint.opacity(hovered ? 1.0 : 0.88)
                    .cornerRadius(Theme.Metrics.buttonCorner)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Download Blender \(version)")
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = Icon.download.url(for: colorScheme) {
            Image(url).resizable().frame(width: 15, height: 15)
        } else {
            Color.clear.frame(width: 15, height: 15)
        }
    }
}

/// Text-only action button. Hover swaps the fill rather than scaling it —
/// SwiftCrossUI has no animation or transform modifiers, so state changes read
/// as instant colour steps.
struct PillButton: View {
    let title: String
    let tint: Color
    var height: Int = Theme.Metrics.actionHeight
    let action: @MainActor @Sendable () -> Void

    @State private var hovered = false

    var body: some View {
        // Frame and fill sit inside the label so the whole pill is clickable,
        // not just the text.
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint == .yellow ? .black : .white)
                .frame(
                    minWidth: Double(Theme.Metrics.pillWidth),
                    maxWidth: Double(Theme.Metrics.pillWidth),
                    minHeight: Double(height),
                    maxHeight: Double(height)
                )
                .background(
                    tint.opacity(hovered ? 1.0 : 0.88)
                        .cornerRadius(Theme.Metrics.buttonCorner)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// In-place update for an installed build.
struct UpdateButton: View {
    let store: BuildStore
    let build: InstalledBuild
    let target: RemoteBuild
    let accent: Color

    private var inProgress: Bool {
        guard let remoteID = store.updatingTargets[build.id] else { return false }
        return store.downloadState(remoteID).isActive
    }

    var body: some View {
        if inProgress {
            ProgressView().frame(width: 22, height: 22)
        } else {
            Button(action: { store.updateInstall(from: build, to: target) }) {
                Text(Theme.Glyph.update)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(accent)
                    .frame(minWidth: 22, maxWidth: 22, minHeight: 22, maxHeight: 22)
            }
            .buttonStyle(.plain)
            .help("Update to \(target.version) (keeps preferences)")
        }
    }
}

/// Single-star toggle.
struct StarButton: View {
    let starred: Bool
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: action) {
            Text(starred ? Theme.Glyph.starFilled : Theme.Glyph.starEmpty)
                .font(.system(size: 15))
                .foregroundColor(starred ? .yellow : Theme.secondaryText)
                .frame(minWidth: 22, maxWidth: 22, minHeight: 22, maxHeight: 22)
        }
        .buttonStyle(.plain)
        .help(starred ? "Unstar" : "Star (sets default .blend app and adds to PATH)")
    }
}

struct BadgeRow: View {
    let riskLabel: String?
    let isLTS: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            if let riskLabel {
                Badge(text: riskLabel, tint: nil)
            }
            if isLTS {
                Badge(text: "LTS", tint: accent)
            }
        }
    }
}

struct Badge: View {
    let text: String
    /// nil renders the neutral variant.
    let tint: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(tint ?? Theme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (tint ?? Theme.badgeBackground)
                    .opacity(tint == nil ? 1.0 : 0.18)
                    .cornerRadius(Theme.Metrics.badgeCorner)
            )
    }
}

struct RowBackground: View {
    var body: some View {
        Theme.rowBackground.cornerRadius(Theme.Metrics.corner)
    }
}
