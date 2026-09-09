import SwiftUI
import AppKit
import CoreText

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

    /// The plain grey macOS puts behind a Finder window — the window's ground
    /// now that the splash artwork no longer fills it. The system's own
    /// semantic colour rather than a fixed value, so it is #ECECEC in light
    /// appearance and the matching deep grey in dark, with no second
    /// definition to keep in step.
    static let windowBackground = Color(nsColor: .windowBackgroundColor)

    /// The card behind a build whose splash artwork isn't available — a daily
    /// build, or a release whose painting hasn't downloaded yet.
    ///
    /// A designed value rather than a semantic one: no system colour means
    /// "placeholder artwork". `NSColor`'s dynamic provider is the framework's
    /// own mechanism for that — the same thing an asset-catalogue colour
    /// compiles down to — so it resolves per appearance on its own.
    static let cardPlaceholder = Color(nsColor: NSColor(name: "cardPlaceholder") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.26, alpha: 1)
            : NSColor(white: 0.72, alpha: 1)
    })

    /// How strongly a card button's tint sits on its glass. `.glassProminent`
    /// has no translucency knob of its own, so every button on a library row
    /// is hand-built from `.glassEffect(.regular.tint(colour.opacity(this)))`
    /// instead — lower this to let more of the splash art show through the
    /// buttons, raise it towards 1 for a near-solid fill.
    static let cardGlassOpacity: Double = 0.62

    /// SF Pro with the "open" digit stylistic sets switched on — open 4,
    /// open 6, open 9 — used for every number the app draws in its own chrome
    /// (the Launch version, the card's date and tags, catalogue sizes and
    /// counts), so digits read the same everywhere. Built from an `NSFont`
    /// descriptor because SwiftUI's `Font` exposes no API for OpenType
    /// stylistic sets. Width is left to `.fontWidth(.condensed)` on the
    /// `Text` itself.
    static func openDigits(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        // OpenType ssNN maps to AAT stylistic-alt selector 2·NN (the "on"
        // selector). ss02 / ss03 / ss04 are Open Four / Open Six / Open Nine
        // in SF Pro.
        let features = [2, 3, 4].map { n in
            [NSFontDescriptor.FeatureKey.typeIdentifier: kStylisticAlternativesType,
             NSFontDescriptor.FeatureKey.selectorIdentifier: n * 2]
        }
        let descriptor = base.fontDescriptor
            .addingAttributes([.featureSettings: features])
        return Font(NSFont(descriptor: descriptor, size: size) ?? base)
    }

    enum Metrics {
        /// The spacing unit that sets the row rhythm: a row's action button
        /// sits this far from the leading edge and from the top and bottom, so
        /// a row is simply the button plus an even margin all round.
        static let rowInset: CGFloat = 6
        /// The single margin used everywhere content meets the window.
        static let windowMargin: CGFloat = 12
        /// The gap between a row's own controls.
        static let rowSpacing: CGFloat = 8

        /// Every action control in the window stands this tall: the round
        /// icon-only buttons in the toolbar, at the trailing end of a library
        /// row and down the leading edge of the catalogue, and the text pills
        /// that take a catalogue button's place while a download runs.
        ///
        /// One number for all of them, because they trade places: a
        /// catalogue row's button becomes a "Stop" pill mid-download and a
        /// spinner while it installs, and a row that changed height each time
        /// would make the whole list jump. It sets the height of a catalogue
        /// row with it — a row is the button plus `rowInset` all round.
        static let actionHeight: CGFloat = 36
        /// The glyph inside an icon-only action button.
        static let actionIconSize: CGFloat = 20
        static let pillWidth: CGFloat = 78     // text-only actions (Stop, Retry)

        /// The library row's Launch button. Its height also sets how tall the
        /// date/tag chip stack beside it stands, so the two line up top and
        /// bottom.
        static let launchButtonSize = CGSize(width: 120, height: 46)

        /// One date/tag chip's height, and the gap repeated four ways around
        /// the two-chip stack: above the top chip, between the chips, below
        /// the bottom chip — chosen so `2·height + 3·gap` is exactly the
        /// Launch button's height.
        static let cardChipHeight: CGFloat = 16
        static var cardChipGap: CGFloat { (launchButtonSize.height - cardChipHeight * 2) / 3 }

        /// The gap between the two round controls at the trailing end of a
        /// library row — the Update button and the "···" menu. Its own knob,
        /// independent of `libraryRowSpacing` (which sets every other gap in
        /// the row), so the pair can be tightened without moving the tags off
        /// the Launch button.
        static let rowTrailingSpacing: CGFloat = 8

        /// How much bigger a real Liquid Glass button renders than the
        /// frame given to its own label — measured directly against a
        /// running macOS 26 build, since neither the label's frame nor an
        /// outer `.frame` around the whole button controls this: the label
        /// gets padded back out by the glass chrome, and an outer frame is
        /// only a layout box the button centres itself within, not a size
        /// it actually takes on. `PillButton`/`CircleIconButton` size their
        /// label down by exactly this much so the finished glass button
        /// lands back on `pillWidth`/`actionHeight`.
        ///
        /// Only true at `.controlSize(.regular)`, which is why both of those
        /// set it explicitly. The chrome scales with the control size, and a
        /// toolbar hands its items a larger one than window content uses —
        /// the circle's padding goes from 8pt to 20pt in the title bar. Left
        /// to the ambient value, one constant means two different sizes.
        static let glassPillPadding = CGSize(width: 24, height: 8)
        static let glassCirclePadding: CGFloat = 8

        static var rowHeight: CGFloat { actionHeight + rowInset * 2 }

        /// Library rows stand 60% larger than a catalogue row, so each has the
        /// room to carry its release's splash painting as its background. Every
        /// other measure of a library row — its inner margin, its corner
        /// radius, the gap to the next row — scales by the same factor so the
        /// bigger card keeps the catalogue's proportions rather than looking
        /// like a catalogue row with its content floating in slack space.
        static let libraryRowScale: CGFloat = 1.6
        static var libraryRowHeight: CGFloat { rowHeight * libraryRowScale }
        static var libraryRowInset: CGFloat { rowInset * libraryRowScale }
        static var libraryRowSpacing: CGFloat { rowSpacing * libraryRowScale }
        static var libraryCorner: CGFloat { corner * libraryRowScale }
        /// The gap between one library row and the next (catalogue uses 4).
        static var libraryRowGap: CGFloat { (4 * libraryRowScale).rounded() }

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
