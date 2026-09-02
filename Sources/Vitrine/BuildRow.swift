import SwiftUI
import AppKit

private enum RowMetrics {
    static let height: CGFloat = 56
    static let compactHeight: CGFloat = 48
    static let actionWidth: CGFloat = 72
    static let cornerRadius: CGFloat = 10
}

struct InstalledRow: View {
    @EnvironmentObject var store: BuildStore
    let build: InstalledBuild

    var body: some View {
        HStack(spacing: 10) {
            HoverButton(tint: build.pinned ? .yellow : .green) {
                store.launch(build)
            } label: {
                Text("Launch")
                    .font(.system(size: 12, weight: .semibold))
            }

            if let target = store.updateAvailable(for: build) {
                UpdateButton(build: build, target: target)
                    .transition(.scale.combined(with: .opacity))
            }

            StarButton(starred: build.pinned) {
                withAnimation(.smooth(duration: 0.32)) {
                    store.toggleStar(build)
                }
            }

            Text(build.version)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()

            BadgeRow(
                riskLabel: (build.branch == .stable && build.riskId == "stable") ? nil : build.riskLabel,
                isLTS: LTS.contains(version: build.version)
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
        }
        .padding(.horizontal, 12)
        .frame(height: RowMetrics.height)
        .background(rowBackground())
        .contextMenu {
            Button("Reveal in Finder") { store.reveal(build) }
            Button(build.pinned ? "Unstar" : "Star") {
                withAnimation(.smooth(duration: 0.32)) {
                    store.toggleStar(build)
                }
            }
            Divider()
            // A custom build is the user's own app — Vitrine only forgets
            // the reference, so don't call it "Uninstall".
            Button(build.isCustom ? "Remove from Vitrine" : "Uninstall", role: .destructive) {
                withAnimation(.smooth(duration: 0.25)) {
                    store.uninstall(build)
                }
            }
        }
    }
}

struct RemoteRow: View {
    @EnvironmentObject var store: BuildStore
    let build: RemoteBuild
    var compact: Bool = false

    private var state: DownloadState { store.downloads[build.id] ?? .idle }
    private var installedBuild: InstalledBuild? { store.installedMatch(for: build) }
    private var suppressRiskBadge: Bool { store.subTab == .stable && build.riskId == "stable" }

    var body: some View {
        HStack(spacing: 10) {
            actionColumn

            Text(build.version)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()

            BadgeRow(
                riskLabel: suppressRiskBadge ? nil : build.riskLabel,
                isLTS: LTS.contains(version: build.version)
            )

            Spacer(minLength: 8)

            rightColumn
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: compact ? RowMetrics.compactHeight : RowMetrics.height)
        .background(rowBackground())
    }

    @ViewBuilder
    private var actionColumn: some View {
        if let installed = installedBuild {
            HoverButton(tint: .red) {
                withAnimation(.smooth(duration: 0.25)) {
                    store.uninstall(installed)
                }
            } label: {
                Text("Put Back").font(.system(size: 11, weight: .semibold))
            }
        } else {
            switch state {
            case .idle:
                HoverButton(tint: .accentColor) { store.install(build) } label: {
                    Text("Get").font(.system(size: 12, weight: .semibold))
                }
            case .queued, .installing:
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.15))
                    ProgressView().controlSize(.small)
                }
                .frame(width: RowMetrics.actionWidth, height: 26)
            case .downloading:
                HoverButton(tint: .red) { store.cancelDownload(build) } label: {
                    Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold))
                }
            case .failed:
                HoverButton(tint: .orange) { store.install(build) } label: {
                    Text("Retry").font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var rightColumn: some View {
        switch state {
        case .downloading(let received, let total, let bps):
            let frac = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
            let etaSec = bps > 0 && total > received ? Double(total - received) / bps : -1
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: frac)
                    .progressViewStyle(.linear)
                    .frame(width: 130)
                Text("\(speedString(bps)) · ETA \(DurationFormat.eta(seconds: etaSec))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160, alignment: .trailing)
        default:
            VStack(alignment: .trailing, spacing: 1) {
                Text(DateFormat.day(build.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if build.fileSize > 0 {
                    Text(ByteFormat.string(build.fileSize))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func speedString(_ bps: Double) -> String {
        guard bps > 0 else { return "—" }
        return "\(ByteFormat.string(Int64(bps)))/s"
    }
}

/// Header row that summarizes a minor-version group in the catalogue.
/// "Get" installs the latest patch in the group; tapping anywhere else on
/// the row toggles fold/unfold for the children.
struct RemoteGroupHeaderRow: View {
    @EnvironmentObject var store: BuildStore
    let group: RemoteBuildGroup

    private var isExpanded: Bool { store.expandedMinorKeys.contains(group.minorKey) }
    private var latestState: DownloadState { store.downloads[group.latest.id] ?? .idle }
    private var latestInstalled: InstalledBuild? { store.installedMatch(for: group.latest) }
    private var suppressRiskBadge: Bool { store.subTab == .stable && group.latest.riskId == "stable" }

    var body: some View {
        HStack(spacing: 10) {
            actionColumn

            HStack(spacing: 5) {
                Text(group.minorKey)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.smooth(duration: 0.28), value: isExpanded)
            }

            BadgeRow(
                riskLabel: suppressRiskBadge ? nil : group.latest.riskLabel,
                isLTS: LTS.contains(version: group.latest.version)
            )

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text("Latest \(group.latest.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(group.builds.count) versions")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: RowMetrics.height)
        .background(rowBackground())
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: 0.32)) {
                store.toggleExpansion(group.minorKey)
            }
        }
        .handCursor()
    }

    @ViewBuilder
    private var actionColumn: some View {
        if let installed = latestInstalled {
            HoverButton(tint: .red) {
                withAnimation(.smooth(duration: 0.25)) {
                    store.uninstall(installed)
                }
            } label: {
                Text("Put Back").font(.system(size: 11, weight: .semibold))
            }
        } else {
            switch latestState {
            case .idle:
                HoverButton(tint: .accentColor) { store.install(group.latest) } label: {
                    Text("Get").font(.system(size: 12, weight: .semibold))
                }
            case .queued, .installing:
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.15))
                    ProgressView().controlSize(.small)
                }
                .frame(width: RowMetrics.actionWidth, height: 26)
            case .downloading:
                HoverButton(tint: .red) { store.cancelDownload(group.latest) } label: {
                    Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold))
                }
            case .failed:
                HoverButton(tint: .orange) { store.install(group.latest) } label: {
                    Text("Retry").font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }
}

/// In-place update for an installed build. Mirrors StarButton's plain icon
/// styling and hover scale. Swaps to a small spinner while the new version
/// is downloading.
struct UpdateButton: View {
    @EnvironmentObject var store: BuildStore
    let build: InstalledBuild
    let target: RemoteBuild

    @State private var hovered = false

    private var inProgress: Bool {
        guard let remoteID = store.updatingTargets[build.id] else { return false }
        return store.downloads[remoteID]?.isActive == true
    }

    var body: some View {
        Button {
            store.updateInstall(from: build, to: target)
        } label: {
            ZStack {
                if inProgress {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(hovered ? 1.15 : 1.0)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(inProgress)
        .onHover { hovered = $0 }
        .animation(.smooth(duration: 0.12), value: hovered)
        .help(inProgress ? "Updating to \(target.version)…" : "Update to \(target.version) (keeps preferences)")
        .handCursor()
    }
}

/// Single-star toggle with a subtle hover scale.
struct StarButton: View {
    let starred: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: starred ? "star.fill" : "star")
                .imageScale(.medium)
                .foregroundStyle(starred ? Color.yellow : Color.secondary)
                .scaleEffect(hovered ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .animation(.smooth(duration: 0.12), value: hovered)
        .help(starred ? "Unstar" : "Star (sets default app + adds to PATH)")
        .handCursor()
    }
}

struct BadgeRow: View {
    let riskLabel: String?
    let isLTS: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let riskLabel {
                Badge(text: riskLabel, style: .neutral)
            }
            if isLTS {
                Badge(text: "LTS", style: .accent)
            }
        }
    }
}

struct Badge: View {
    enum Style { case neutral, accent }
    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(background)
            )
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch style {
        case .neutral: return Color(nsColor: .quaternaryLabelColor)
        case .accent: return Color.accentColor.opacity(0.18)
        }
    }
    private var foreground: Color {
        switch style {
        case .neutral: return .secondary
        case .accent: return .accentColor
        }
    }
}

/// Pill-shaped action button with hover lift + press scale. Hover state is
/// scoped to the button only — the surrounding row stays static.
struct HoverButton<Label: View>: View {
    let tint: Color
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(textColor)
                .frame(width: RowMetrics.actionWidth, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(pressed ? 0.65 : (hovered ? 1.0 : 0.85)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(hovered ? 0.18 : 0), lineWidth: 1)
                )
                .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .pressAction(pressed: $pressed)
        .animation(.smooth(duration: 0.12), value: hovered)
        .animation(.smooth(duration: 0.08), value: pressed)
        .handCursor()
    }

    private var textColor: Color { tint == .yellow ? .black : .white }
}

private struct PressActionModifier: ViewModifier {
    @Binding var pressed: Bool
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in pressed = false }
        )
    }
}
private extension View {
    func pressAction(pressed: Binding<Bool>) -> some View {
        modifier(PressActionModifier(pressed: pressed))
    }
}

@ViewBuilder
private func rowBackground() -> some View {
    RoundedRectangle(cornerRadius: RowMetrics.cornerRadius, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: RowMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
}

extension View {
    /// Shows the system pointing-hand cursor while the pointer is over the
    /// receiver — the same affordance the web uses for clickable links.
    /// Implemented as an AppKit cursor rect rather than NSCursor.push/pop
    /// because cursor rects are managed by the window and never leak when
    /// SwiftUI tears the view down mid-hover.
    func handCursor() -> some View {
        overlay(HandCursorOverlay().allowsHitTesting(false))
    }
}

private struct HandCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HandCursorNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class HandCursorNSView: NSView {
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
