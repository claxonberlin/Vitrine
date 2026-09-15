import SwiftUI

/// The glyphs the window draws, all SF Symbols — the same set the toolbar
/// uses, so every icon carries the system's own weight and rendering.
enum Icon {
    case catalogue
    case download
    case update
    case trash
    case more
    case star

    var systemName: String {
        switch self {
        case .catalogue: "book"
        case .download: "arrow.down.to.line"
        case .update: "arrow.up"
        case .trash: "trash"
        case .more: "ellipsis"
        case .star: "star.fill"
        }
    }
}

/// An icon sized for a toolbar or a button label.
struct IconView: View {
    let icon: Icon
    var size: CGFloat = Theme.Metrics.iconSize

    var body: some View {
        Image(systemName: icon.systemName)
            // Sized as text rather than stretched, so the symbol keeps its
            // designed stroke weight at every size.
            .font(.system(size: size * 0.8, weight: .medium))
            .frame(width: size, height: size)
    }
}
