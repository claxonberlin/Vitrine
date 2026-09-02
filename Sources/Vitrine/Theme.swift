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
    /// Container fill behind grouped controls (segmented picker).
    static let controlBackground = Color(white: 0.5, opacity: 0.14)
    static let hoverFill = Color(white: 0.5, opacity: 0.18)
    /// Finder gives each toolbar button its own soft fill rather than merging
    /// them into one bar; these are the resting and pressed-in tones.
    static let toolbarFill = Color(white: 0.5, opacity: 0.13)
    static let toolbarFillHover = Color(white: 0.5, opacity: 0.26)

    static let secondaryText = Color(white: 0.5, opacity: 0.95)
    static let tertiaryText = Color(white: 0.5, opacity: 0.70)

    enum Metrics {
        /// The spacing unit that sets the row rhythm: a row's action button
        /// sits this far from the leading edge and from the top and bottom, so
        /// a row is simply the button plus an even margin all round.
        static let rowInset = 6
        /// The branch switcher's own inset — deliberately a touch larger than
        /// `rowInset` so it reads as the outer container it is.
        static let switcherInset = 8

        static let actionHeight = 32
        static let compactActionHeight = 28
        static let actionWidth = 84   // download button: icon + version
        static let pillWidth = 78     // text-only actions (Launch, Put Back)

        static var rowHeight: Int { actionHeight + rowInset * 2 }
        static var compactRowHeight: Int { compactActionHeight + rowInset * 2 }

        static let corner = 12          // row / group cards
        static let badgeCorner = 8

        static let iconButtonSize = 30
        static let iconSize = 18
        static let tabHeight = 28
        /// Toggle segments are wider than they are tall to fit comfortably.
        static let toggleSegmentWidth = 36
        static let toggleHeight = 30

        /// Matches the compact unified title bar so the header lines up with
        /// the traffic lights.
        static let headerHeight = 38

        static let windowMinWidth = 470
        static let windowMinHeight = 400

        /// Every button in the app is a pill: the radius is simply half the
        /// control's height, so it stays fully round at any size.
        static func pill(_ height: Int) -> Int { height / 2 }
    }

    /// Text stand-ins for what were SF Symbols on macOS. SwiftCrossUI's
    /// `Image` loads from a URL or a pixel buffer only, so shipping glyphs as
    /// characters avoids an icon-asset pipeline and renders identically under
    /// AppKit and GTK.
    enum Glyph {
        static let starFilled = "★"
        static let starEmpty = "☆"
        static let update = "↑"
        static let stop = "■"
        static let expanded = "⌄"
        static let collapsed = "›"
        static let more = "⋯"
        /// Plain U+2193 rather than a fancier download arrow: it is present in
        /// every system font on both platforms, including GNOME's Cantarell.
        static let download = "↓"
    }

}
