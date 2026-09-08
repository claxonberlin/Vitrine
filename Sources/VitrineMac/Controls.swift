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
/// one continuous surface. `thinMaterial` doesn't adapt to what's
/// behind it at all, so every row reads as the same frosted sheet no matter
/// how busy the artwork gets there, on every macOS version.
struct RowCard: View {
    var hovered: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.corner, style: .continuous)
    }

    var body: some View {
        shape
            .fill(.thinMaterial)
            .overlay { if hovered { shape.fill(Theme.rowHoverFill) } }
            .overlay { shape.strokeBorder(Theme.rowStroke, lineWidth: 0.5) }
            .animation(.smooth(duration: 0.15), value: hovered)
    }
}

/// The hover highlight a row inside an expanded group gets: the group paints
/// one continuous card behind all of its children, so a child can't lift its
/// own card the way a standalone row does — it tints the patch it occupies
/// instead, which lands on the same colour either way.
struct RowHoverHighlight: View {
    var hovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.corner - Theme.Metrics.rowInset,
                         style: .continuous)
            .fill(hovered ? Theme.rowHoverFill : .clear)
            .padding(.horizontal, 3)
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
    let buildName: String
    @ViewBuilder let actions: () -> Actions

    @State private var hovered = false

    // As tall as the Launch button beside it, so the two read as one row of
    // controls at the same height rather than a large button and a small one.
    private static var diameter: CGFloat { Theme.Metrics.actionHeight }

    var body: some View {
        Menu(content: actions) {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                // On the glyph rather than on the Menu: a menu button takes
                // its name from its own label, and the symbol's built-in one
                // ("More", localised) says nothing about which row it opens.
                .accessibilityLabel(Self.label(for: buildName))
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
        .help(Self.label(for: buildName))
    }

    private static func label(for buildName: String) -> String {
        "More actions for Blender \(buildName)"
    }
}

/// Text-only action button. Hover brightens the fill, pressing sinks it.
struct PillButton: View {
    let title: String
    let tint: Color
    /// Tooltip and VoiceOver label, where the visible title alone doesn't say
    /// which build the button acts on.
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        core
            .handCursor()
            .help(help ?? title)
            .accessibilityLabel(help ?? title)
    }

    @ViewBuilder
    private var core: some View {
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
            // that padding, measured directly, so the label is sized to land
            // on exactly `pillWidth`×`actionHeight` once the chrome is added
            // back on top of it.
            Button(action: action) {
                label(width: Theme.Metrics.pillWidth - Theme.Metrics.glassPillPadding.width,
                      height: Theme.Metrics.actionHeight - Theme.Metrics.glassPillPadding.height)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .buttonBorderShape(.capsule)
            .buttonSizing(.fitted)
        } else {
            LegacyPillButton(tint: tint, action: action) {
                label(width: Theme.Metrics.pillWidth, height: Theme.Metrics.actionHeight)
            }
        }
    }

    private func label(width: CGFloat, height: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: width, height: height)
    }
}

/// The pre-26 pill: a hand-filled capsule, since there's no real glass to
/// reach for below macOS 26.
private struct LegacyPillButton<Label: View>: View {
    let tint: Color
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovered = false

    var body: some View {
        Button(action: action) { label() }
            .buttonStyle(FilledPillStyle(tint: tint, hovered: hovered))
            .onHover { hovered = $0 }
    }
}

/// One filled-pill look for every action button, so hover and press feel the
/// same wherever you click.
private struct FilledPillStyle: ButtonStyle {
    let tint: Color
    let hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
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

/// A round, icon-only button — the shape every "do this" control in the app
/// uses, on a row and in the toolbar alike, so Update, Download, Remove and
/// the catalogue toggle read as the same kind of control at a glance,
/// distinguished only by their icon and colour.
///
/// `filled` carries the action's own colour and is what a row's buttons use;
/// unfilled is the resting state of a toggle, which has to stay legible
/// against whatever the splash artwork put behind it and so keeps a light
/// disc of its own.
struct CircleIconButton: View {
    let icon: Icon
    /// Names the control for the tooltip and for VoiceOver — icon-only
    /// buttons have nothing else to go on.
    let label: String
    /// A second clause the tooltip spells out and VoiceOver offers as a hint,
    /// for anything the name alone leaves unsaid.
    var hint: String? = nil
    var tint: Color = Theme.catalogueAccent
    var filled: Bool = true
    var diameter: CGFloat = Theme.Metrics.actionHeight
    var iconSize: CGFloat = 17
    let action: () -> Void

    var body: some View {
        core
            .handCursor()
            .help(hint.map { "\(label) — \($0)" } ?? label)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }

    @ViewBuilder
    private var core: some View {
        if #available(macOS 26.0, *) {
            // Sizing a glass button is measured, not declared — see the note
            // on `PillButton`. `Theme.Metrics.glassCirclePadding` is the
            // chrome's own padding, measured directly, so the icon is sized
            // to land back on exactly `diameter` once that padding is added
            // on top of it.
            glass
                .buttonBorderShape(.circle)
                .buttonSizing(.fitted)
                .animation(.smooth(duration: 0.12), value: filled)
        } else {
            LegacyCircleIconButton(icon: icon, tint: tint, filled: filled,
                                   diameter: diameter, iconSize: iconSize, action: action)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private var glass: some View {
        let label = IconView(icon: icon, size: iconSize)
            .frame(width: diameter - Theme.Metrics.glassCirclePadding,
                   height: diameter - Theme.Metrics.glassCirclePadding)
        if filled {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(tint)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
        }
    }
}

/// The pre-26 circle: a hand-filled disc, since there's no real glass to
/// reach for below macOS 26.
private struct LegacyCircleIconButton: View {
    let icon: Icon
    let tint: Color
    let filled: Bool
    let diameter: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: iconSize)
                // White on a filled circle; ink on the light resting disc.
                .foregroundStyle(filled ? .white : Color.black.opacity(0.72))
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(filled
                                  ? tint.opacity(hovered ? 1.0 : 0.88)
                                  : Color.white.opacity(hovered ? 1.0 : 0.82))
                }
                .overlay {
                    // Only the resting disc needs an edge: it has no colour of
                    // its own to separate it from the artwork behind it.
                    if !filled {
                        Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(filled ? 0 : 0.22), radius: 2.5, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.smooth(duration: 0.12), value: hovered)
        .animation(.smooth(duration: 0.12), value: filled)
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
                .accessibilityLabel("Updating Blender \(build.version) to \(target.version)")
        } else {
            CircleIconButton(icon: .update,
                             label: "Update Blender \(build.version) to \(target.version)",
                             hint: "your preferences and add-ons are kept") {
                store.updateInstall(from: build, to: target)
            }
        }
    }
}

/// The chips beside a version: how finished the build is, and whether its
/// series is long-term support.
struct BadgeRow: View {
    let riskLabel: String?
    let isLTS: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let riskLabel {
                Badge(text: riskLabel)
            }
            if isLTS {
                LTSBadge()
            }
        }
    }
}

/// Fixed rather than tinted to the library's blue or the catalogue's orange —
/// the same chip either place, so LTS reads as one consistent label rather
/// than picking up whichever accent colour the row around it happens to use.
struct LTSBadge: View {
    private static let meaning = "Long-term support — two years of bug-fix releases"

    var body: some View {
        Badge(text: "LTS", sunken: true)
            .help(Self.meaning)
            .accessibilityLabel("L T S")
            .accessibilityHint(Self.meaning)
    }
}

struct Badge: View {
    let text: String
    /// The same sunken well `RowMenu`'s "···" button sits in — the LTS
    /// badge's own look, so it reads as the same kind of chrome as the row's
    /// other fixed control rather than a coloured status label.
    var sunken: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    // Black rather than `primary`, which would lighten the
                    // well in dark mode instead of deepening it — same
                    // reasoning as `RowMenu`'s own well.
                    .fill(sunken ? Color.black.opacity(0.13) : Color.primary.opacity(0.08))
            }
            .fixedSize()
    }
}
