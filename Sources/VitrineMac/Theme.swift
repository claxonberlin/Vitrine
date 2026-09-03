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

    enum Metrics {
        /// The spacing unit that sets the row rhythm: a row's action button
        /// sits this far from the leading edge and from the top and bottom, so
        /// a row is simply the button plus an even margin all round.
        static let rowInset: CGFloat = 6
        /// The single margin used everywhere content meets the window.
        static let windowMargin: CGFloat = 12

        static let actionHeight: CGFloat = 32
        static let compactActionHeight: CGFloat = 28
        static let actionWidth: CGFloat = 84   // download button: icon + version
        static let pillWidth: CGFloat = 78     // text-only actions (Launch, Put Back)

        static var rowHeight: CGFloat { actionHeight + rowInset * 2 }
        static var compactRowHeight: CGFloat { compactActionHeight + rowInset * 2 }

        static let corner: CGFloat = 12          // row / group cards
        static let iconSize: CGFloat = 16

        static let windowMinWidth: CGFloat = 380
        static let windowMinHeight: CGFloat = 430

        /// The catalogue inspector: wide enough for a download button, a
        /// badge and a file size on one line.
        static let inspectorMin: CGFloat = 250
        static let inspectorIdeal: CGFloat = 268
        static let inspectorMax: CGFloat = 380

        /// Every button in the app is a pill, so its radius is half its
        /// height and it stays fully round at any size.
        static func pill(_ height: CGFloat) -> CGFloat { height / 2 }
    }

    /// Card fill behind a row. Layered over whatever the window paints, so one
    /// definition reads correctly in both appearances and inside the
    /// inspector, where the pane background is already a shade off.
    static func rowFill(hovered: Bool) -> some ShapeStyle {
        Color.primary.opacity(hovered ? 0.11 : 0.06)
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
