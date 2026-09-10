import SwiftUI

/// How a control in this window says "you can click me".
///
/// macOS does not change the pointer over a button. The pointing hand means
/// *link*, and Finder, Mail and the rest of the system leave the arrow alone
/// over their own controls — so the affordance has to live in the control
/// itself: a highlight that comes up under the pointer, and a sink while it
/// is held. That pair is exactly what the toolbar's `.glass` buttons get from
/// the system on macOS 26, and this is the same pair for the controls that
/// are drawn by hand or that run on an older system.
enum Hover {
    /// Lifted over a control that carries a colour of its own — a filled
    /// pill, a tinted disc. White reads as "brighter" on any tint, in either
    /// appearance, which a semantic colour would not.
    static let onTint = Color.white.opacity(0.16)

    /// Lifted over a control with no fill of its own — a bare glyph, a
    /// disclosure, the banner's dismiss. Semantic, so it darkens in light
    /// appearance and lightens in dark, and it has to be the visible edge of
    /// the control as well as its highlight: at rest there is nothing there.
    static let onSurface = Color.primary.opacity(0.12)

    /// The same lift, for a control that sits inside a glass shape.
    ///
    /// Flat numbers picked by the window's scheme, because `onSurface` is
    /// `Color.primary` and every dynamic colour inside glass is resolved
    /// under the material's own vibrant appearance — which over a dark card
    /// comes back light. That put a white veil on a white disc: a hover state
    /// that was simply invisible on the two rows with the darkest paintings.
    /// See `Theme.cardButtonFill(_:)` for the same trap in the disc itself.
    static func onGlass(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 1).opacity(0.16) : Color(white: 0).opacity(0.10)
    }

    /// Lifted while the control is held down, over whichever hover ink it
    /// uses. Dark either way, so a press reads as sinking rather than as more
    /// hover.
    static let pressed = Color.black.opacity(0.14)

    /// Pressing shrinks the control very slightly, the way AppKit's own
    /// controls do.
    static let pressedScale: CGFloat = 0.97

    /// Short enough to feel like a response to the pointer rather than an
    /// animation of its own.
    static let response = Animation.smooth(duration: 0.12)
}

/// The one hover-and-press treatment every hand-drawn button in the app
/// shares.
///
/// `shape` is the control's own outline, so the highlight lands on the disc
/// or the capsule the button actually draws rather than on its bounding box —
/// and it doubles as the hit region, which a `.plain` button otherwise takes
/// from the glyph alone.
///
/// The ink goes on as an overlay rather than a background because these
/// buttons draw their own fill in wildly different ways: some behind the
/// label, some as real glass applied outside the button entirely. An overlay
/// composites over all of it the same way, which is also what an AppKit cell
/// does when it highlights.
struct InteractiveButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    var hoverInk: Color = Hover.onTint
    var pressInk: Color = Hover.pressed

    func makeBody(configuration: Configuration) -> some View {
        Surface(shape: shape, hoverInk: hoverInk, pressInk: pressInk,
                configuration: configuration)
    }

    /// A `ButtonStyle`'s `makeBody` is not itself a `View`, so `@State` on the
    /// style would never be installed and the hover would never arrive. It
    /// lives here instead, which is a view.
    private struct Surface: View {
        let shape: S
        let hoverInk: Color
        let pressInk: Color
        let configuration: Configuration

        @State private var hovered = false

        var body: some View {
            configuration.label
                .overlay { shape.fill(ink) }
                .contentShape(shape)
                .scaleEffect(configuration.isPressed ? Hover.pressedScale : 1)
                .onHover { hovered = $0 }
                .animation(Hover.response, value: hovered)
                .animation(Hover.response, value: configuration.isPressed)
        }

        private var ink: Color {
            if configuration.isPressed { return pressInk }
            return hovered ? hoverInk : .clear
        }
    }
}

extension ButtonStyle where Self == InteractiveButtonStyle<Circle> {
    /// A round control: the row's Update and "···" buttons, the catalogue's
    /// download and remove.
    static func disc(hoverInk: Color = Hover.onTint) -> Self {
        InteractiveButtonStyle(shape: Circle(), hoverInk: hoverInk)
    }
}

extension ButtonStyle where Self == InteractiveButtonStyle<Capsule> {
    /// A pill: Launch, Stop, Retry.
    static func pill(hoverInk: Color = Hover.onTint) -> Self {
        InteractiveButtonStyle(shape: Capsule(style: .continuous), hoverInk: hoverInk)
    }
}

extension ButtonStyle where Self == InteractiveButtonStyle<RoundedRectangle> {
    /// A control with no fill of its own, which needs the highlight to be its
    /// whole visible edge — the group's disclosure, the error banner's
    /// dismiss.
    static func bare(cornerRadius: CGFloat = 6) -> Self {
        InteractiveButtonStyle(shape: RoundedRectangle(cornerRadius: cornerRadius,
                                                       style: .continuous),
                               hoverInk: Hover.onSurface)
    }
}

extension View {
    /// Hover feedback for a control whose own style doesn't provide any
    /// visible one.
    ///
    /// `.buttonStyle(.glass)` does light up under the pointer, but its filled
    /// sibling `.glassProminent` barely moves — measured against a running
    /// macOS 26 build, a hovered prominent glass button lifts its own
    /// luminance by about 0.003, against 0.06 for the plain one, which is
    /// invisible on a coloured disc. Those buttons are the app's whole
    /// catalogue vocabulary — download, remove, stop, retry — so they get the
    /// same ink every hand-drawn control uses, laid over the system's style
    /// rather than replacing it: the press response, the label colour and the
    /// glass itself all stay the system's own.
    func hoverHighlight<S: Shape>(in shape: S, ink: Color = Hover.onTint) -> some View {
        modifier(HoverHighlight(shape: shape, ink: ink))
    }
}

private struct HoverHighlight<S: Shape>: ViewModifier {
    let shape: S
    let ink: Color

    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                // Decoration only: the button underneath still takes every
                // click, and its own style still owns the hit region.
                shape.fill(hovered ? ink : .clear)
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
            .animation(Hover.response, value: hovered)
    }
}
