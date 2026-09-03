import SwiftCrossUI
import VitrineKit

/// Pieces shared by the library list and the catalogue sidebar.

/// The top band. On macOS this sits *inside* the transparent title bar, so the
/// title is drawn here alongside the actions; on GNOME the system header bar
/// already shows the title and only the actions appear.
struct HeaderBar<Actions: View>: View {
    let title: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        // The title is centred across the full width and the actions are laid
        // over it on the trailing side, so the title stays optically centred
        // in the window rather than in the space left over beside the actions.
        ZStack {
            if WindowChrome.drawsOwnTitle {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                actions()
            }
        }
        .frame(
            minHeight: Double(Theme.Metrics.headerHeight),
            maxHeight: Double(Theme.Metrics.headerHeight)
        )
    }
}

/// Spaces the window actions the way Finder's toolbar does: each button
/// carries its own soft rounded fill with space between, rather than being
/// merged into a single bar.
struct ToolbarCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
        }
    }
}

/// Round icon button. `active` fills it with the accent — used by the
/// catalogue button to show the sidebar is open.
struct IconButton: View {
    let icon: Icon
    let help: String
    var active: Bool = false
    var activeTint: Color = Theme.vitrineAccent
    let action: @MainActor @Sendable () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        // Sizing and fill live *inside* the label: applied outside the Button
        // they decorate the frame but leave the clickable area the size of the
        // artwork, so only the icon itself responds.
        Button(action: action) {
            artwork
                .frame(
                    minWidth: Double(Theme.Metrics.iconButtonSize),
                    maxWidth: Double(Theme.Metrics.iconButtonSize),
                    minHeight: Double(Theme.Metrics.iconButtonSize),
                    maxHeight: Double(Theme.Metrics.iconButtonSize)
                )
                .background(fill.cornerRadius(Theme.Metrics.pill(Theme.Metrics.iconButtonSize)))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }

    private var fill: Color {
        if active { return activeTint }
        return hovered ? Theme.toolbarFillHover : Theme.toolbarFill
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = icon.url(for: colorScheme, onAccent: active) {
            Image(url)
                .resizable()
                .frame(
                    width: Double(Theme.Metrics.iconSize),
                    height: Double(Theme.Metrics.iconSize)
                )
        } else {
            // Resource bundle missing: leave the space, don't crash.
            Color.clear.frame(
                width: Double(Theme.Metrics.iconSize),
                height: Double(Theme.Metrics.iconSize)
            )
        }
    }
}

/// Separates the branches within a single scrolling list, in place of the
/// segmented tabs. Everything is visible at once and the headers just mark
/// where one branch ends and the next begins.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.tertiaryText)
            .padding(.leading, 4)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Replaces the modal alert the macOS build used. A dismissible banner doesn't
/// interrupt an in-progress download, which matters when a single flaky
/// catalogue fetch would otherwise block the whole window.
struct ErrorBanner: View {
    let store: BuildStore

    var body: some View {
        if let message = store.lastError {
            HStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Dismiss") { store.lastError = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.12).cornerRadius(Theme.Metrics.corner))
        }
    }
}

struct EmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundColor(Theme.secondaryText)
            .multilineTextAlignment(.center)
            // Capped so a long sentence wraps instead of reporting its full
            // unwrapped length as an ideal width and widening the window.
            .frame(maxWidth: 240)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
