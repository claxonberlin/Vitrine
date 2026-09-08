import SwiftUI

/// Shared visual constants.
///
/// Only the two brand colours are fixed; everything else defers to the system
/// palette so the window follows the user's appearance, accent and
/// increase-contrast settings without a second definition for dark mode.
enum Theme {
    /// Blender's brand orange (#EA7600), so the catalogue reads as the other
    /// half of the app at a glance.
    static let catalogueAccent = Color(red: 0.918, green: 0.463, blue: 0.0)
    /// The blue half of the Blender logo (#265787). Launch is the one button
    /// that starts Blender itself, so it wears Blender's own colour.
    static let blenderBlue = Color(red: 0.149, green: 0.341, blue: 0.529)

    /// The hairline around every card, and the fill a card takes on under the
    /// pointer.
    static let rowStroke = Color.primary.opacity(0.07)
    static let rowHoverFill = Color.primary.opacity(0.06)

    enum Metrics {
        /// The spacing unit that sets the row rhythm: a row's action button
        /// sits this far from the leading edge and from the top and bottom, so
        /// a row is simply the button plus an even margin all round.
        static let rowInset: CGFloat = 6
        /// The single margin used everywhere content meets the window.
        static let windowMargin: CGFloat = 12
        /// The gap between a row's own controls.
        static let rowSpacing: CGFloat = 8

        static let actionHeight: CGFloat = 32
        static let pillWidth: CGFloat = 78     // text-only actions (Launch, Stop, Retry)

        /// How much bigger a real Liquid Glass button renders than the
        /// frame given to its own label — measured directly against a
        /// running macOS 26 build, since neither the label's frame nor an
        /// outer `.frame` around the whole button controls this: the label
        /// gets padded back out by the glass chrome, and an outer frame is
        /// only a layout box the button centres itself within, not a size
        /// it actually takes on. `PillButton`/`CircleIconButton` size their
        /// label down by exactly this much so the finished glass button
        /// lands back on `pillWidth`/`actionHeight`.
        static let glassPillPadding = CGSize(width: 24, height: 8)
        static let glassCirclePadding: CGFloat = 8

        static var rowHeight: CGFloat { actionHeight + rowInset * 2 }

        static let corner: CGFloat = 12          // row / group cards
        static let iconSize: CGFloat = 16

        /// Wide enough for a library row at its usual shape: the Launch
        /// pill, a version with its LTS chip, an update button, both dates
        /// and the overflow menu, with the margins either side. Rows used to
        /// measure this for themselves, which meant drawing a second hidden
        /// copy of every one of them; the number that produced was 359, and
        /// only an unusually long custom build name beats it. That one
        /// truncates.
        static let windowMinWidth: CGFloat = 380
        static let windowMinHeight: CGFloat = 430
        static let windowDefaultHeight: CGFloat = 560
    }
}

extension View {
    /// Shows the pointing-hand cursor while the pointer is over the receiver.
    ///
    /// An AppKit cursor rect rather than `NSCursor.push`/`pop`: cursor rects
    /// are managed by the window and can't leak a stuck cursor when SwiftUI
    /// tears the view down mid-hover. SwiftUI's own `pointerStyle` was tried
    /// here and reverted — its regions came and went unreliably in the
    /// toolbar, leaving the pointing hand behind after the pointer had moved
    /// on, which is the very thing cursor rects are here to avoid.
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
