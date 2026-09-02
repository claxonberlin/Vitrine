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
    case refresh = "repeat-alt"

    /// Resolves to the pre-tinted variant that reads against the current
    /// background. Returns nil only if the resource bundle is missing, which
    /// the caller renders as empty space rather than crashing.
    func url(for colorScheme: ColorScheme) -> URL? {
        let tone = colorScheme == .dark ? "ondark" : "onlight"
        guard let resources = Bundle.module.resourceURL else { return nil }
        let url = resources.appendingPathComponent("Icons/\(rawValue)-\(tone).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
