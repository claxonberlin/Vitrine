import SwiftCrossUI

/// Shared visual constants.
///
/// Colours are expressed as translucent neutrals layered over whatever the
/// backend paints behind them, so a single definition reads correctly in both
/// light and dark on AppKit and GTK alike — SwiftCrossUI has no semantic
/// system-colour palette to defer to.
enum Theme {
    /// The library window keeps the original blue.
    static let vitrineAccent = Color(red: 0.0, green: 0.48, blue: 1.0)
    /// The catalogue window takes Blender's brand orange (#EA7600), so the two
    /// windows are distinguishable at a glance when both are open.
    static let catalogueAccent = Color(red: 0.918, green: 0.463, blue: 0.0)

    static let rowBackground = Color(white: 0.5, opacity: 0.12)
    static let badgeBackground = Color(white: 0.5, opacity: 0.22)
    /// Container fill behind grouped controls (toolbar cluster, segmented picker).
    static let controlBackground = Color(white: 0.5, opacity: 0.14)
    static let hoverFill = Color(white: 0.5, opacity: 0.18)

    static let secondaryText = Color(white: 0.5, opacity: 0.95)
    static let tertiaryText = Color(white: 0.5, opacity: 0.70)

    enum Metrics {
        static let rowHeight = 56
        static let compactRowHeight = 48
        static let actionWidth = 76
        static let actionHeight = 26
        static let corner = 8
        static let windowMinWidth = 470
        static let windowMinHeight = 400
    }

    /// Text stand-ins for what were SF Symbols on macOS. SwiftCrossUI's
    /// `Image` loads from a URL or a pixel buffer only, so shipping glyphs as
    /// characters avoids an icon-asset pipeline and renders identically under
    /// AppKit and GTK.
    enum Glyph {
        static let starFilled = "★"
        static let starEmpty = "☆"
        static let update = "↑"
        static let refresh = "⟳"
        static let add = "+"
        static let settings = "⚙"
        static let stop = "■"
        static let expanded = "⌄"
        static let collapsed = "›"
        static let more = "⋯"
        static let otherWindow = "⧉"
    }

    /// Window identifiers, shared between the scene declarations and the
    /// buttons that reopen a closed window.
    enum WindowID {
        static let vitrine = "vitrine"
        static let catalogue = "catalogue"
    }
}
