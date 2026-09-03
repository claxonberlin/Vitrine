import Foundation
import SwiftCrossUI

/// The bundled icon set.
///
/// SwiftCrossUI's `Image` reads png/jpeg/webp only and cannot recolour an image
/// at render time, so each icon ships pre-tinted in two tones and the view
/// picks one from `\.colorScheme`. The SVG originals live in `Resources/Icons`
/// at the repo root; `Tools/rasterize-icons.swift` regenerates the PNGs.
enum Icon: String {
    case addBuild = "folder-add"
    case library = "apps"
    case catalogue = "book-open"
    case settings = "settings"
    case download = "download"

    /// Resolves to the pre-tinted variant that reads against the current
    /// background. Returns nil only if the resource bundle is missing, which
    /// the caller renders as empty space rather than crashing.
    /// Icons that only ever sit on a filled accent button ship in white only,
    /// so the colour scheme doesn't apply to them.
    private var isAccentOnly: Bool { self == .download }

    /// - Parameter onAccent: request the white variant, for an icon drawn on a
    ///   filled accent surface such as the selected half of the page toggle.
    func url(for colorScheme: ColorScheme, onAccent: Bool = false) -> URL? {
        let tone = (isAccentOnly || onAccent)
            ? "onaccent"
            : (colorScheme == .dark ? "ondark" : "onlight")
        guard let resources = Bundle.module.resourceURL else { return nil }
        let url = resources.appendingPathComponent("Icons/\(rawValue)-\(tone).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
