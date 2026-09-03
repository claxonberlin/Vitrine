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

    /// The sidebar floats over the library, so its fill has to be opaque —
    /// the translucent greys used elsewhere would let rows show through.
    /// SwiftCrossUI has no material or blur to defer to.
    static func sidebarSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.17) : Color(white: 0.97)
    }

    /// Stands in for the drop shadow that would normally separate a floating
    /// panel from what is behind it.
    static func sidebarBorder(_ scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 1.0 : 0.0, opacity: 0.12)
    }

    static let secondaryText = Color(white: 0.5, opacity: 0.95)
    static let tertiaryText = Color(white: 0.5, opacity: 0.70)

    enum Metrics {
        /// The spacing unit that sets the row rhythm: a row's action button
        /// sits this far from the leading edge and from the top and bottom, so
        /// a row is simply the button plus an even margin all round.
        static let rowInset = 6
        /// The single margin used everywhere content meets the window: the
        /// header buttons, the list edges, the gap between the library and the
        /// catalogue sidebar. One value keeps all of it visually even.
        static let windowMargin = 12
        static let sidebarWidth = 236
        static let sidebarCorner = 14

        /// Measured from a screencapture of the window's own rounded corner
        /// (best-fit circle through the alpha boundary, 40.5px at 2x). The
        /// toolbar buttons are centred on this so each sits concentric with
        /// the corner it tucks into.
        static let windowCornerRadius = 20
        /// Inset from the window edge that puts a button's *centre* on the
        /// corner's centre, rather than merely matching its radius.
        static var cornerButtonInset: Int { windowCornerRadius - iconButtonSize / 2 }

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

        /// Twice the corner radius, so a vertically centred toolbar button
        /// sits at exactly `windowCornerRadius` from the top edge.
        static var headerHeight: Int { windowCornerRadius * 2 }

        static let windowMinWidth = 380
        static let windowMinHeight = 430

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
