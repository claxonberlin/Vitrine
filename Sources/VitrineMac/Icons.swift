import SwiftUI
import AppKit

/// The bundled line-icon set.
///
/// AppKit reads SVG into a vector image rep, so the shipped file is the
/// designer's original and it stays crisp at any size. Marking it a template
/// hands the ink colour to SwiftUI, which is why there is one file per icon
/// instead of a pre-tinted variant per appearance.
enum Icon: String {
    case addBuild = "folder-add"
    case library = "apps"
    case catalogue = "book-open"
    case download
    case update = "circle-arrow-up"
    case trash = "delete"
    case more = "options-horizontal"

    /// Rendered in the current foreground style. Missing artwork yields nil so
    /// a broken resource bundle leaves a gap rather than taking the app down.
    @MainActor
    var image: Image? {
        guard let nsImage = Self.cache.image(for: rawValue) else { return nil }
        return Image(nsImage: nsImage)
    }

    private static let cache = IconCache()
}

/// Loading an SVG goes through Core Graphics, so each icon is read once and
/// kept — the toolbar and every catalogue row ask for the same few files.
@MainActor
private final class IconCache {
    private var images: [String: NSImage] = [:]

    func image(for name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        guard let url = Bundle.module.resourceURL?
                .appendingPathComponent("Icons/\(name).svg"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        images[name] = image
        return image
    }
}

/// An icon sized for a toolbar or a button label.
struct IconView: View {
    let icon: Icon
    var size: CGFloat = Theme.Metrics.iconSize

    var body: some View {
        Group {
            if let image = icon.image {
                image.resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}
