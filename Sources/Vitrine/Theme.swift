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
        // Rows are tighter and buttons taller than before: the action is the
        // thing you aim at, the row is just its container.
        static let rowHeight = 44
        static let compactRowHeight = 38
        static let actionWidth = 96   // download button: glyph + version
        static let pillWidth = 78     // text-only actions (Launch, Put Back)
        static let actionHeight = 32
        static let compactActionHeight = 28

        static let corner = 12          // rows, cluster
        static let buttonCorner = 10
        static let badgeCorner = 6
        /// Half the control height, i.e. a full capsule.
        static let tabCorner = 14
        static let tabHeight = 28
        /// The capsule radius plus the container's own padding, so the outer
        /// and inner curves stay concentric.
        static let tabContainerCorner = 17

        /// Hit area for a toolbar icon, and the artwork inside it. The
        /// generous difference is the whitespace that keeps the cluster from
        /// looking cramped.
        static let iconButtonSize = 30
        static let iconSize = 18
        /// Text glyphs still used for marks with no SVG (star, chevrons, ⋯).
        static let iconGlyphSize = 16
        /// Matches the compact unified title bar so the header lines up with
        /// the traffic lights.
        static let headerHeight = 38

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
        static let stop = "■"
        static let expanded = "⌄"
        static let collapsed = "›"
        static let more = "⋯"
        /// Plain U+2193 rather than a fancier download arrow: it is present in
        /// every system font on both platforms, including GNOME's Cantarell.
        static let download = "↓"
    }

    /// Window identifiers, shared between the scene declarations and the
    /// buttons that reopen a closed window.
    enum WindowID {
        static let vitrine = "vitrine"
        static let catalogue = "catalogue"
    }
}
