import SwiftUI
import VitrineKit

extension View {
    /// The one glass treatment every button on a library row shares — Launch,
    /// Update and the "···" menu. `.glassProminent` can't be dialled for
    /// translucency, so the row's buttons are hand-built from `.glassEffect`
    /// with a semi-transparent tint (`Theme.cardGlassOpacity`) instead; only
    /// the tint colour changes between them. Below macOS 26 it falls back to a
    /// near-solid fill, matching the rest of the pre-glass UI.
    ///
    /// Deliberately *not* `.interactive()`. That modifier gives the glass its
    /// own press-and-hover lensing, which sounds right for a button — but the
    /// glass here is applied outside the `Button`, and an interactive glass
    /// layer takes the pointer for itself: every control wearing one stopped
    /// reporting hover to the button underneath it at all, measured as a
    /// pixel-identical control at rest and under the pointer. `Hover` and
    /// `InteractiveButtonStyle` supply the response instead, from inside the
    /// button where the events actually are.
    @ViewBuilder
    func cardGlass<S: Shape>(tint: Color, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(Theme.cardGlassOpacity)), in: shape)
        } else {
            self.background(shape.fill(tint.opacity(0.88)))
        }
    }
}

/// The card behind a row. Lifts slightly under the pointer so a long list
/// still tells you which row you are on.
///
/// Flat rather than any material. Liquid Glass was tried here first and
/// dropped: `.glassEffect()` adapts its tint to whatever sits behind each
/// shape, and a card this wide spans both a bright and a shadowed patch at
/// once, so one card came out looking like two materials stitched together.
/// A frosted material fixed that but frosts nothing — the catalogue rows
/// stand on the window's plain ground — so the card now simply states its
/// own light grey, on every macOS version and both appearances.
struct RowCard: View {
    var hovered: Bool = false
    /// Set while this row's build is coming down: the card itself is the
    /// progress bar, so nothing else in the row has to carry one.
    var progress: RowProgress? = nil

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.corner, style: .continuous)
    }

    var body: some View {
        shape
            .fill(Theme.catalogueCard)
            .overlay { if let progress { RowProgressFill(progress: progress, shape: shape) } }
            .overlay { if hovered { shape.fill(Theme.rowHoverFill) } }
            .overlay { shape.strokeBorder(Theme.rowStroke, lineWidth: 0.5) }
            .animation(.smooth(duration: 0.15), value: hovered)
    }
}

/// What a catalogue row's card is showing about its own build.
enum RowProgress: Equatable {
    /// Bytes are arriving — the bar fills from the leading edge to that
    /// fraction of the row.
    case downloading(Double)
    /// Unpacking. Carries a fraction wherever the platform can measure the
    /// copy, and nil where it can't — then a band sweeps the row instead,
    /// which is the honest thing to draw when there is no number.
    case installing(Double?)
    /// Waiting for a download slot: nothing has moved yet, so nothing fills.
    case queued
}

/// A row's card doing duty as its own progress bar.
///
/// The whole card, not a small bar tucked into a corner: a catalogue row is
/// only 36pt tall and already carries a version, its tags and a size, so a
/// separate track was the smallest thing in the busiest part of the window.
/// Colour says which half of the job is running — Blender's orange while the
/// file is arriving, its blue while the build is being unpacked — and both
/// stay under the row's own text rather than washing over it.
struct RowProgressFill<S: Shape>: View {
    let progress: RowProgress
    let shape: S

    /// How much of the row the sweeping band covers, and how long one pass
    /// across it takes.
    private static var bandWidth: CGFloat { 0.35 }
    private static var sweepSeconds: Double { 1.4 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            switch progress {
            case .downloading(let fraction):
                bar(Theme.catalogueAccent, width: width, to: fraction)
            case .installing(.some(let fraction)):
                // A wash across the whole row under the bar. Unpacking opens
                // with a beat of mounting the disk image, where nothing has
                // been copied yet and a bar alone would leave the row blank
                // between the full download bar and the first bytes of this
                // one. The wash says "installing" the moment the state
                // changes; the bar says how far along it is.
                ZStack(alignment: .leading) {
                    Theme.blenderBlue.opacity(Self.washOpacity)
                    bar(Theme.blenderBlue, width: width, to: fraction)
                }
            case .queued:
                Color.clear
            case .installing(.none):
                // Driven off the clock rather than a repeating animation on
                // a piece of state: the row is rebuilt whenever the store
                // publishes, and a `repeatForever` that starts on `onAppear`
                // was landing before layout and finishing the whole sweep in
                // one frame — leaving the band parked off the trailing edge,
                // which looked exactly like no progress at all.
                TimelineView(.animation) { context in
                    let cycle = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Self.sweepSeconds) / Self.sweepSeconds
                    // Enters a band-width off the leading edge and leaves at
                    // the trailing one, so it crosses rather than blinks.
                    let travel = CGFloat(cycle) * (1 + Self.bandWidth) - Self.bandWidth
                    Theme.blenderBlue.opacity(Self.inkOpacity)
                        .frame(width: width * Self.bandWidth)
                        .offset(x: travel * width)
                }
            }
        }
        .clipShape(shape)
        // Decoration under the row's controls, and it must never take a click.
        .allowsHitTesting(false)
    }

    /// One flat colour, filled to `fraction` of the row.
    ///
    /// The bar is deliberately slow to follow: bytes land in bursts and an
    /// unpack jumps whenever a big file lands, and a bar that tracked either
    /// exactly would twitch its way across the row.
    private func bar(_ tint: Color, width: CGFloat, to fraction: Double) -> some View {
        tint.opacity(Self.inkOpacity)
            .frame(width: width * CGFloat(max(0, min(1, fraction))))
            .animation(.smooth(duration: 0.8), value: fraction)
    }

    /// Strong enough to read as the row's own colour, light enough to leave
    /// the version and its tags legible on top.
    private static var inkOpacity: Double { 0.55 }

    /// The ground the install bar fills over — enough to colour the row,
    /// not enough to be mistaken for progress.
    private static var washOpacity: Double { 0.16 }
}

/// The hover highlight a row inside an expanded group gets: the group paints
/// one continuous card behind all of its children, so a child can't lift its
/// own card the way a standalone row does — it tints the patch it occupies
/// instead, which lands on the same colour either way.
struct RowHoverHighlight: View {
    var hovered: Bool
    /// The same progress fill a standalone row's card takes, kept inside the
    /// patch this child occupies.
    var progress: RowProgress? = nil

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.corner - Theme.Metrics.rowInset,
                         style: .continuous)
    }

    var body: some View {
        shape
            .fill(hovered ? Theme.rowHoverFill : .clear)
            .overlay { if let progress { RowProgressFill(progress: progress, shape: shape) } }
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
    /// The window's own appearance, read out here where it is still the
    /// window's — inside the glass it would be the material's. See
    /// `Theme.cardButtonFill(_:)`.
    @Environment(\.colorScheme) private var scheme
    let buildName: String
    @ViewBuilder let actions: () -> Actions

    // The same diameter as every other action control in the window.
    private static var diameter: CGFloat { Theme.Metrics.actionHeight }

    var body: some View {
        core
            .help(Self.label(for: buildName))
    }

    @ViewBuilder
    private var core: some View {
        // `.button` rather than `.borderlessButton`, which sizes its control
        // to the glyph and ignores any frame on the label: that left a 32pt
        // disc of which only the middle 20×14 actually opened anything, and
        // the rest of the visible circle swallowed the click. The button menu
        // style hands the label to the ambient `buttonStyle`, so the disc
        // style below keeps the frame and sets the hit region to the whole
        // circle. Verified against the accessibility frame, not by eye.
        //
        // The glass still goes on the `Menu` itself — applied to the label it
        // doesn't render at all.
        Menu(content: actions) {
            glyph
                // A flat colour, chosen by the window's scheme rather than
                // left to be resolved inside the glass — see
                // `Theme.cardButtonGlyph(_:)` for what that costs.
                .foregroundStyle(Theme.cardButtonGlyph(scheme))
                .frame(width: Self.diameter, height: Self.diameter)
        }
        .menuStyle(.button)
        // The disc is light in light appearance and dark in dark, so the
        // highlight turns with it — as flat numbers, for the same reason the
        // disc and glyph are flat. See `Hover.onGlass(_:)`.
        .buttonStyle(.disc(hoverInk: Hover.onGlass(scheme)))
        .menuIndicator(.hidden)
        .fixedSize()
        .cardGlass(tint: Theme.cardButtonFill(scheme), in: Circle())
    }

    private var glyph: some View {
        // The bundled line icon rather than SF Symbols' `ellipsis`, so the
        // dots are drawn from the same set as every other icon in the window
        // and carry that set's weight instead of the system font's.
        IconView(icon: .more, size: Theme.Metrics.actionIconSize)
            // On the glyph rather than on the Menu: a menu button takes its
            // name from its own label, and a drawn icon has no name of its
            // own to say which row it opens.
            .accessibilityLabel(Self.label(for: buildName))
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
            .controlSize(.regular)
            .buttonBorderShape(.capsule)
            .buttonSizing(.fitted)
            // Prominent glass barely moves under the pointer on its own —
            // see `hoverHighlight`.
            .hoverHighlight(in: Capsule(style: .continuous))
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
/// reach for below macOS 26. Hover and press come from the same shared style
/// the rest of the app's hand-drawn controls use, so the two eras of the UI
/// respond identically.
private struct LegacyPillButton<Label: View>: View {
    let tint: Color
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(.white)
                .background(Capsule(style: .continuous).fill(tint))
        }
        .buttonStyle(.pill())
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
    var iconSize: CGFloat = Theme.Metrics.actionIconSize
    let action: () -> Void

    var body: some View {
        core
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
            //
            // `.controlSize(.regular)` is what makes that padding a constant
            // rather than a guess. A toolbar hands its items a larger control
            // size than window content uses, and the glass chrome scales with
            // it: the same button that pads its label by 8pt in the catalogue
            // pads it by 20pt in the title bar. Without this the toolbar's
            // buttons came out 40pt from a `diameter` of 28 — bigger than the
            // 32pt controls on a row they are meant to sit below. Measured
            // both ways, and confirmed by driving `diameter` to 60 and
            // watching the toolbar render 72.
            glass
                .controlSize(.regular)
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
                // Prominent glass has no hover response worth the name of its
                // own — see `hoverHighlight`. The plain glass below does, so
                // it is left alone.
                .hoverHighlight(in: Circle())
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

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: iconSize)
                // White on a filled circle; ink on the light resting disc.
                .foregroundStyle(filled ? .white : Color.black.opacity(0.72))
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(filled ? tint : Color.white.opacity(0.92))
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
        // White brightens the tinted disc; the resting one is already near
        // white, so it takes the semantic ink instead.
        .buttonStyle(.disc(hoverInk: filled ? Hover.onTint : Hover.onSurface))
        .animation(Hover.response, value: filled)
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
                .frame(width: Theme.Metrics.actionHeight,
                       height: Theme.Metrics.actionHeight)
                .accessibilityLabel("Updating Blender \(build.version) to \(target.version)")
        } else {
            let label = "Update Blender \(build.version) to \(target.version)"
            Button {
                store.updateInstall(from: build, to: target)
            } label: {
                IconView(icon: .update, size: Theme.Metrics.actionIconSize)
                    .foregroundStyle(.white)
                    .frame(width: Theme.Metrics.actionHeight,
                           height: Theme.Metrics.actionHeight)
            }
            // Carries the hover highlight, and sets the hit region to the
            // whole disc: a `.plain` button is only clickable where the glyph
            // itself is drawn.
            .buttonStyle(.disc())
            // Same glass as Launch and the "···" menu; only the tint differs.
            .cardGlass(tint: Theme.catalogueAccent, in: Circle())
            .help("\(label) — your preferences and add-ons are kept")
            .accessibilityLabel(label)
            .accessibilityHint("your preferences and add-ons are kept")
        }
    }
}

/// One chip's worth of content, so a line of them can be measured, kept or
/// dropped as a list instead of as hand-written view branches.
struct ChipSpec: Identifiable {
    enum Content {
        case text(String)
        case icon(Icon)
    }

    let id: String
    let content: Content
    var help: String? = nil
    var label: String? = nil
    var hint: String? = nil

    static func text(_ text: String, help: String? = nil,
                     label: String? = nil, hint: String? = nil) -> ChipSpec {
        ChipSpec(id: text, content: .text(text), help: help, label: label, hint: hint)
    }

    static func icon(_ icon: Icon, id: String, help: String? = nil,
                     label: String? = nil, hint: String? = nil) -> ChipSpec {
        ChipSpec(id: id, content: .icon(icon), help: help, label: label, hint: hint)
    }
}

/// A line of chips that never squeezes one to fit.
///
/// Chips are dropped from the end until the line fits the width it is given,
/// and a "…" chip stands where the dropped ones were. The old behaviour
/// scaled the text down instead, which turned a tag into a smudge at exactly
/// the width where the row was already tight — and said nothing about the
/// fact that something had been left out.
struct ChipLine: View {
    let chips: [ChipSpec]

    var body: some View {
        // Candidates are offered longest first and the first that fits wins;
        // `fixedSize` is what makes each one report the width it actually
        // wants rather than accepting a squeeze.
        ViewThatFits(in: .horizontal) {
            line(keeping: chips.count)
            line(keeping: chips.count - 1)
            line(keeping: chips.count - 2)
            line(keeping: chips.count - 3)
            line(keeping: 0)
        }
    }

    @ViewBuilder
    private func line(keeping count: Int) -> some View {
        let kept = Array(chips.prefix(max(0, count)))
        HStack(spacing: 4) {
            ForEach(kept) { Chip(spec: $0) }
            if kept.count < chips.count {
                CardChip(text: "…")
                    .accessibilityLabel("More tags than fit")
            }
        }
        .fixedSize()
    }
}

/// A chip drawn from its spec — the same box either way, a word or a glyph
/// inside it.
struct Chip: View {
    let spec: ChipSpec

    var body: some View {
        // Each modifier only where the spec asks for it: an empty string is
        // not "no label", it is a label of nothing, and it would silence the
        // chip's own text for VoiceOver.
        content
            .modifier(OptionalHelp(text: spec.help))
            .modifier(OptionalAccessibility(label: spec.label, hint: spec.hint))
    }

    @ViewBuilder
    private var content: some View {
        switch spec.content {
        case .text(let text): CardChip(text: text)
        case .icon(let icon): CardIconChip(icon: icon)
        }
    }
}

private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}

private struct OptionalAccessibility: ViewModifier {
    let label: String?
    let hint: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        switch (label, hint) {
        case (let label?, let hint?):
            content.accessibilityLabel(label).accessibilityHint(hint)
        case (let label?, nil):
            content.accessibilityLabel(label)
        case (nil, let hint?):
            content.accessibilityHint(hint)
        case (nil, nil):
            content
        }
    }
}

/// The chips beside a version in the catalogue: how finished the build is,
/// and whether its series is long-term support.
///
/// The library's own chips, in the library's own style — one row of them,
/// since a group header stands for a whole series rather than for the one
/// build a date or a hash would describe.
struct BadgeRow: View {
    let riskLabel: String?
    let isLTS: Bool

    static let ltsMeaning = "Long-term support — two years of bug-fix releases"

    /// The LTS chip, spelled once for every line that carries one.
    static var ltsChip: ChipSpec {
        .text("LTS", help: ltsMeaning, label: "Long-term support", hint: ltsMeaning)
    }

    var body: some View {
        ChipLine(chips: [riskLabel.map { ChipSpec.text($0) }, isLTS ? Self.ltsChip : nil]
            .compactMap { $0 })
        // The chips give way before the row's fixed-size controls do, exactly
        // as they do on a library row.
        .layoutPriority(-1)
    }
}
