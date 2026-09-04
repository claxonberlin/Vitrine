import SwiftUI
import VitrineKit

/// The card behind a row. Lifts slightly under the pointer so a long list
/// still tells you which row you are on.
struct RowCard: View {
    var hovered: Bool = false
    /// Rows in the library sit straight on the splash artwork and need to
    /// frost it to stay readable. Rows in the catalogue pane are already on a
    /// sheet of material, and a second sheet over the first goes muddy, so
    /// they tint instead.
    var tinted: Bool = false

    var body: some View {
        shape
            .overlay {
                if hovered {
                    RoundedRectangle(cornerRadius: Theme.Metrics.corner, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.corner, style: .continuous)
                    .strokeBorder(Theme.rowStroke, lineWidth: 0.5)
            }
            .animation(.smooth(duration: 0.15), value: hovered)
    }

    @ViewBuilder
    private var shape: some View {
        let rect = RoundedRectangle(cornerRadius: Theme.Metrics.corner, style: .continuous)
        if tinted {
            rect.fill(Theme.rowTint(hovered: false))
        } else {
            rect.fill(.regularMaterial)
        }
    }
}

/// Text-only action button. Hover brightens the fill, pressing sinks it.
struct PillButton: View {
    let title: String
    let tint: Color
    var height: CGFloat = Theme.Metrics.actionHeight
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: Theme.Metrics.pillWidth, height: height)
        }
        .buttonStyle(FilledPillStyle(tint: tint, height: height, hovered: hovered))
        .onHover { hovered = $0 }
        .handCursor()
    }
}

/// The catalogue's primary action: download glyph on the leading edge, the
/// version it will fetch on the trailing edge.
struct DownloadButton: View {
    /// What the button says — a series on a group header, the exact build on
    /// an individual row.
    let label: String
    /// The build actually fetched, named in the tooltip.
    let version: String
    var height: CGFloat = Theme.Metrics.actionHeight
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                IconView(icon: .download, size: 14)
                Spacer(minLength: 0)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .frame(width: Theme.Metrics.actionWidth, height: height)
        }
        .buttonStyle(FilledPillStyle(tint: Theme.catalogueAccent,
                                     height: height, hovered: hovered))
        .onHover { hovered = $0 }
        .handCursor()
        .help("Download Blender \(version)")
    }
}

/// One filled-pill look for every action button, so hover and press feel the
/// same wherever you click.
private struct FilledPillStyle: ButtonStyle {
    let tint: Color
    let height: CGFloat
    let hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint == .yellow ? Color.black : Color.white)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.7 : (hovered ? 1.0 : 0.88)))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(hovered ? 0.2 : 0), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.smooth(duration: 0.12), value: hovered)
            .animation(.smooth(duration: 0.08), value: configuration.isPressed)
    }
}

/// In-place update for an installed build. Swaps to a spinner while the
/// replacement downloads.
struct UpdateButton: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: InstalledBuild
    let target: RemoteBuild

    @State private var hovered = false

    var body: some View {
        Group {
            if store.isUpdating(build) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Button {
                    store.updateInstall(from: build, to: target)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.vitrineAccent)
                        .scaleEffect(hovered ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 }
                .animation(.smooth(duration: 0.12), value: hovered)
                .help("Update to \(target.version) — keeps your preferences")
                .handCursor()
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// Single-star toggle. The starred build is the one wired into the desktop.
struct StarButton: View {
    let starred: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.system(size: 13))
                .foregroundStyle(starred ? Color.yellow : Color.secondary)
                .scaleEffect(hovered ? 1.15 : 1.0)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.smooth(duration: 0.12), value: hovered)
        .help(starred
              ? "Unstar"
              : "Star — opens .blend files, and puts `blender` on your PATH")
        .handCursor()
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
                    .help("Long-term support — two years of bug-fix releases")
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
            .tracking(0.3)
            .foregroundStyle(tint ?? Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint?.opacity(0.16) ?? Color.primary.opacity(0.08))
            }
            .fixedSize()
    }
}
