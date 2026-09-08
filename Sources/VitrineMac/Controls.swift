import SwiftUI
import VitrineKit

/// The card behind a row. Lifts slightly under the pointer so a long list
/// still tells you which row you are on.
///
/// Real Liquid Glass was tried here and dropped again: `.glassEffect()`
/// samples the content directly behind each glass shape and adapts its own
/// tint to it, which is the point of the material for something compact
/// like a button, but a row card is wide enough to span both a bright and a
/// shadowed patch of the splash artwork in one shot — the same card comes
/// out looking like two different materials stitched together rather than
/// one continuous surface. `ultraThinMaterial` doesn't adapt to what's
/// behind it at all, so every row reads as the same frosted sheet no matter
/// how busy the artwork gets there, on every macOS version.
struct RowCard: View {
    var hovered: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.corner, style: .continuous)
            .fill(.ultraThinMaterial)
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
}

/// The row's overflow menu: the same actions as the context menu, in a
/// control you can see. Right-click is the macOS way to reach them; not
/// everyone knows there is anything there to right-click.
///
/// It sits in a well sunk into the row rather than floating loose on it, so
/// it reads as a control at rest instead of only on hover — which is what
/// the library rows used to rely on.
struct RowMenu<Actions: View>: View {
    @ViewBuilder let actions: () -> Actions

    @State private var hovered = false

    // As tall as the Launch button beside it, so the two read as one row of
    // controls at the same height rather than a large button and a small one.
    private static var diameter: CGFloat { Theme.Metrics.actionHeight }

    var body: some View {
        Menu(content: actions) {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(.secondary)
        .frame(width: Self.diameter, height: Self.diameter)
        .background {
            // Black rather than `primary`, which would lighten the well in
            // dark mode instead of deepening it.
            Circle().fill(Color.black.opacity(hovered ? 0.20 : 0.13))
        }
        .overlay {
            Circle().strokeBorder(Color.white.opacity(hovered ? 0.10 : 0), lineWidth: 0.5)
        }
        .animation(.smooth(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }
        .handCursor()
        .help("More actions")
    }
}

/// Text-only action button. Hover brightens the fill, pressing sinks it.
struct PillButton: View {
    let title: String
    let tint: Color
    var height: CGFloat = Theme.Metrics.actionHeight
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            // Real glass, filled with the action's own colour — the system
            // picks a legible label colour for whatever tint it's given,
            // which is the entire point of reaching for `.glassProminent`
            // instead of hand-mixing a foreground colour ourselves.
            //
            // Sizing a glass button is measured, not declared: a `.frame`
            // *outside* the button only proposes a box the button centres
            // itself within — it does not make the visible glass that
            // size — while a `.frame` on the label gets padded back out by
            // the style's own chrome. `Theme.Metrics.glassPillPadding` is
            // that padding, measured directly, so the label is sized to
            // land on exactly `pillWidth`×`height` once the chrome is added
            // back on top of it.
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: Theme.Metrics.pillWidth - Theme.Metrics.glassPillPadding.width,
                           height: height - Theme.Metrics.glassPillPadding.height)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .buttonBorderShape(.capsule)
            .buttonSizing(.fitted)
            .handCursor()
        } else {
            LegacyPillButton(title: title, tint: tint, height: height, action: action)
        }
    }
}

/// The pre-26 pill: a hand-filled capsule, since there's no real glass to
/// reach for below macOS 26.
private struct LegacyPillButton: View {
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

/// A round, icon-only action button — the shape every "do this to the row"
/// control uses now: Update, Download and Remove all read as the same kind
/// of control at a glance, distinguished only by their icon and colour.
struct CircleIconButton: View {
    let icon: Icon
    let tint: Color
    var diameter: CGFloat = Theme.Metrics.actionHeight
    var iconSize: CGFloat = 17
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            // Sizing a glass button is measured, not declared — see the note
            // on `PillButton`. `Theme.Metrics.glassCirclePadding` is the
            // chrome's own padding, measured directly, so the icon is sized
            // to land back on exactly `diameter` once that padding is added
            // on top of it.
            Button(action: action) {
                IconView(icon: icon, size: iconSize)
                    .frame(width: diameter - Theme.Metrics.glassCirclePadding,
                           height: diameter - Theme.Metrics.glassCirclePadding)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .buttonBorderShape(.circle)
            .buttonSizing(.fitted)
            .handCursor()
        } else {
            LegacyCircleIconButton(icon: icon, tint: tint, diameter: diameter,
                                   iconSize: iconSize, action: action)
        }
    }
}

/// The pre-26 circle: a hand-filled disc, since there's no real glass to
/// reach for below macOS 26.
private struct LegacyCircleIconButton: View {
    let icon: Icon
    let tint: Color
    var diameter: CGFloat = Theme.Metrics.actionHeight
    var iconSize: CGFloat = 17
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(tint.opacity(hovered ? 1.0 : 0.88))
                .overlay {
                    // White, same as every other icon on a filled circle in
                    // the app — Update set the precedent, this just follows it.
                    IconView(icon: icon, size: iconSize)
                        .foregroundStyle(.white)
                }
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.smooth(duration: 0.12), value: hovered)
        .handCursor()
    }
}

/// In-place update for an installed build. Swaps to a spinner while the
/// replacement downloads.
struct UpdateButton: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let build: InstalledBuild
    let target: RemoteBuild

    var body: some View {
        if store.isUpdating(build) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: Theme.Metrics.actionHeight, height: Theme.Metrics.actionHeight)
        } else {
            CircleIconButton(icon: .update, tint: Theme.catalogueAccent) {
                store.updateInstall(from: build, to: target)
            }
            .help("Update to \(target.version) — keeps your preferences")
        }
    }
}

/// Single-star toggle. The starred build is the one wired into the desktop.
struct StarButton: View {
    let starred: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.system(size: 13))
                .foregroundStyle(starred ? Color.yellow : Color.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(starred
              ? "Unstar"
              : "Star — opens .blend files, and puts `blender` on your PATH")
        .handCursor()
    }
}

struct BadgeRow: View {
    let riskLabel: String?
    let isLTS: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let riskLabel {
                Badge(text: riskLabel, tint: nil)
            }
            if isLTS {
                // Fixed rather than tinted to the library's blue or the
                // catalogue's orange — the same chip either place, so LTS
                // reads as one consistent label rather than picking up
                // whichever accent colour the row around it happens to use.
                Badge(text: "LTS", tint: nil, dark: true)
                    .help("Long-term support — two years of bug-fix releases")
            }
        }
    }
}

struct Badge: View {
    let text: String
    /// nil renders the neutral variant. Ignored when `dark` is set.
    let tint: Color?
    /// Dark text on a medium-dark chip, fixed regardless of appearance or
    /// accent — the LTS badge's own look, not derived from `tint`.
    var dark: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(dark ? Color.black.opacity(0.75) : (tint ?? Color.secondary))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(fill)
            }
            .fixedSize()
    }

    private var fill: AnyShapeStyle {
        if dark {
            AnyShapeStyle(Color(white: 0.55))
        } else {
            AnyShapeStyle(tint?.opacity(0.16) ?? Color.primary.opacity(0.08))
        }
    }
}
