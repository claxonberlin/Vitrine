import SwiftCrossUI

/// The two halves of the app, now sharing one window.
///
/// Each keeps the accent it had when they were separate windows, so the colour
/// still says which side you are on — it just changes in place rather than
/// distinguishing two windows.
enum Page: String, CaseIterable, Identifiable, Equatable {
    case vitrine
    case catalogue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vitrine: return "Vitrine"
        case .catalogue: return "Catalogue"
        }
    }

    var icon: Icon {
        switch self {
        case .vitrine: return .library
        case .catalogue: return .catalogue
        }
    }

    var accent: Color {
        switch self {
        case .vitrine: return Theme.vitrineAccent
        case .catalogue: return Theme.catalogueAccent
        }
    }
}
