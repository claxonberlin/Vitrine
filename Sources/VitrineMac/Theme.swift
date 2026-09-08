import SwiftUI

/// Shared visual constants.
///
/// Only the two accents are fixed colours; everything else defers to the
/// system palette so the window follows the user's appearance, accent and
/// increase-contrast settings without a second definition for dark mode.
enum Theme {
    /// The library's blue.
    static let vitrineAccent = Color(red: 0.0, green: 0.48, blue: 1.0)
    /// Blender's brand orange (#EA7600), so the catalogue reads as the other
    /// half of the app at a glance.
    static let catalogueAccent = Color(red: 0.918, green: 0.463, blue: 0.0)
    /// The blue half of the Blender logo (#265787). Launch is the one button
    /// that starts Blender itself, so it wears Blender's own colour.
    static let blenderBlue = Color(red: 0.149, green: 0.341, blue: 0.529)

    enum Metrics {
        /// The spacing unit that sets the row rhythm: a row's action button
        /// sits this far from the leading edge and from the top and bottom, so
        /// a row is simply the button plus an even margin all round.
        static let rowInset: CGFloat = 6
        /// The single margin used everywhere content meets the window.
        static let windowMargin: CGFloat = 12

        static let actionHeight: CGFloat = 32
        static let pillWidth: CGFloat = 78     // text-only actions (Launch, Put Back, Stop, Retry)

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

        /// A floor only: what a library row needs (see `RowMinWidthKey`)
        /// almost always sets the real minimum higher than this. It only
        /// governs an empty library, which has no row to measure.
        static let windowMinWidth: CGFloat = 380
        static let windowMinHeight: CGFloat = 430
        /// The width the Scene asks for before the window exists to measure
        /// anything — `FrameKeeper` replaces it within the same launch with
        /// whatever the content actually turned out to need, so this value
        /// itself is never what the user sees.
        static let windowDefaultWidth: CGFloat = windowMinWidth
        static let windowDefaultHeight: CGFloat = 560

        /// Every button in the app is a pill, so its radius is half its
        /// height and it stays fully round at any size.
        static func pill(_ height: CGFloat) -> CGFloat { height / 2 }
    }

    static let rowStroke = Color.primary.opacity(0.07)
}

extension View {
    /// Shows the pointing-hand cursor while the pointer is over the receiver.
    ///
    /// An AppKit cursor rect rather than `NSCursor.push`/`pop`: cursor rects
    /// are managed by the window and can't leak a stuck cursor when SwiftUI
    /// tears the view down mid-hover.
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
