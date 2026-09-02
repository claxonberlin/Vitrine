import SwiftCrossUI

/// Shared visual constants.
///
/// Colours are expressed as translucent neutrals layered over whatever the
/// backend paints behind them, so a single definition reads correctly in both
/// light and dark on AppKit and GTK alike — SwiftCrossUI has no semantic
/// system-colour palette to defer to.
enum Theme {
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)

    static let rowBackground = Color(white: 0.5, opacity: 0.12)
    static let rowBorder = Color(white: 0.5, opacity: 0.20)
    static let badgeBackground = Color(white: 0.5, opacity: 0.22)

    static let secondaryText = Color(white: 0.5, opacity: 0.95)
    static let tertiaryText = Color(white: 0.5, opacity: 0.70)

    enum Metrics {
        static let rowHeight = 56
        static let compactRowHeight = 48
        static let actionWidth = 76
        static let actionHeight = 26
        static let corner = 8
        static let windowMinWidth = 460
        static let windowMinHeight = 380
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
    }
}
