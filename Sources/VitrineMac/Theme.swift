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

    /// The card behind a build whose splash artwork isn't available — a
    /// release newer than the app, whose painting is still being fetched.
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

    /// The flat ground behind a catalogue row. The catalogue sits on the
    /// window's own grey with nothing but artwork-free rows on it, so a
    /// material here had nothing to frost — it only made every card read as a
    /// slightly different sheet depending on what the window showed through.
    /// A plain light grey states the card instead.
    static let catalogueCard = Color(nsColor: NSColor(name: "catalogueCard") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.22, alpha: 1)
            : NSColor(white: 0.925, alpha: 1)
    })

    /// The disc under a row's "···", and the glyph on it.
    ///
    /// Flat numbers, picked by the *window's* light or dark scheme, which is
    /// read from the environment and passed in. Nothing here is a dynamic
    /// colour, and that is the whole point.
    ///
    /// A glass control installs a vibrant appearance over its contents, and
    /// whether that appearance is the light or the dark one is chosen from
    /// whatever the glass is lensing. Any dynamic colour inside — a system
    /// semantic like `secondaryLabelColor`, or a hand-rolled `NSColor(name:)`
    /// — is resolved again under it, so over a dark card it comes back as its
    /// dark-appearance value while the same colour used as the tint, resolved
    /// earlier and outside, stays light. That split is what put a white glyph
    /// on a white disc. A flat colour has nothing left to re-resolve.
    static func cardButtonFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.26) : Color(white: 1.0)
    }

    static func cardButtonGlyph(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.90) : Color(white: 0.34)
    }

    /// How strongly a card button's tint sits on its glass. `.glassProminent`
    /// has no translucency knob of its own, so every button on a library row
    /// is hand-built from `.glassEffect(.regular.tint(colour.opacity(this)))`
    /// instead — lower this to let more of the splash art show through the
    /// buttons, raise it towards 1 for a solid fill.
    ///
    /// Solid. A translucent tint let the painting decide how light each
    /// button came out, and a button whose lightness the artwork sets can't
    /// be given a glyph colour that reads on all of them. The glass keeps its
    /// edge and its specular sheen; only the fill underneath is stated.
    static let cardGlassOpacity: Double = 1.0

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
        static let launchButtonSize = CGSize(width: 110, height: 46)

        /// One date/tag chip's height, and the gap repeated four ways around
        /// the two-chip stack: above the top chip, between the chips, below
        /// the bottom chip — chosen so `2·height + 3·gap` is exactly the
        /// Launch button's height.
        static let cardChipHeight: CGFloat = 16
        static var cardChipGap: CGFloat { (launchButtonSize.height - cardChipHeight * 2) / 3 }

        /// The same idea as `cardChipGap`, for the catalogue's two-chip
        /// stack: a gap repeated above, between and below the chips — but
        /// measured against the catalogue row's own height, since there is no
        /// Launch button here to line up with.
        static var rowChipGap: CGFloat { (rowHeight - cardChipHeight * 2) / 3 }

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

        // MARK: - The library card
        //
        // Its own design, not a catalogue row at a larger scale. It used to
        // be exactly that: every measure below was the catalogue's own
        // multiplied by 1.6, which is why they used to land on odd fractions
        // of a point — 9.6, 12.8, 19.2 — and why a change to a catalogue
        // button moved the splash artwork. The two lists share a vocabulary,
        // not a geometry, so these are chosen rather than derived, and they
        // are whole points because a designed value has no reason not to be.

        /// The margin above and below the Launch pill. That pill is the
        /// tallest thing in the row and the one the card exists to carry, so
        /// the two together are the whole of the card's height.
        static let libraryRowPadding: CGFloat = 14
        static var libraryRowHeight: CGFloat {
            launchButtonSize.height + libraryRowPadding * 2
        }
        /// From the card's edge to the controls inside it.
        static let libraryRowInset: CGFloat = 10
        /// Between one control in a row and the next.
        static let libraryRowSpacing: CGFloat = 12
        /// The card's corner radius — and, since a branch heading lines up
        /// with where a card's flat edge begins, that heading's indent too.
        static let libraryCorner: CGFloat = 20
        /// Between one card and the next, on both pages: the catalogue used
        /// to sit its rows tighter, which made the same list read as two
        /// different rhythms depending on which page you were on.
        static let rowGap: CGFloat = 6

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

        /// A branch heading's own height: 10pt of air above the text, the
        /// 10pt uppercase line itself, 2pt below. Measured against the
        /// running app rather than derived, since the line's height is a font
        /// metric — see `SectionHeader`, which draws it.
        static let sectionHeaderHeight: CGFloat = 25

        /// The shortest the window may get: one library card, the heading
        /// that always stands above it, and the same margin beneath it that
        /// the cards keep from the window's sides. Anything less and a single
        /// build can't be seen whole, which is the least the window can
        /// usefully be.
        ///
        /// This measures the content under the title bar — the area
        /// `.windowResizability(.contentMinSize)` adds the chrome back onto —
        /// so the finished window's minimum is this plus the toolbar.
        static var windowMinHeight: CGFloat {
            sectionHeaderHeight + rowGap + libraryRowHeight + windowMargin
        }

        /// What the window opens at on a first launch, which is a different
        /// question from how small it may be dragged.
        static let windowDefaultHeight: CGFloat = 560
    }
}
