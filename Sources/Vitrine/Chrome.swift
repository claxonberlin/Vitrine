import SwiftCrossUI
import VitrineKit

/// Pieces shared by both windows. Each window builds its own layout — they
/// differ enough that a single generic shell would obscure more than it saved
/// — but the parts below stay identical.

/// The top band. On macOS this sits *inside* the transparent title bar, so it
/// leaves room for the traffic lights and renders the title itself; on GNOME
/// the system header bar already shows the title and only the actions appear.
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
            HStack(spacing: 10) {
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

/// Groups the window actions into one rounded container, the way a macOS
/// unified toolbar does — individually bordered buttons read as loose and
/// unfinished.
struct ToolbarCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 3) {
            content()
        }
        .padding(4)
        .background(Theme.controlBackground.cornerRadius(Theme.Metrics.corner))
    }
}

/// Icon button used inside a `ToolbarCluster`. Carries no chrome of its own
/// beyond a hover fill — the cluster supplies the container.
struct IconButton: View {
    let icon: Icon
    let help: String
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
                .background(
                    (hovered ? Theme.hoverFill : Color.clear)
                        .cornerRadius(Theme.Metrics.buttonCorner)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = icon.url(for: colorScheme) {
            Image(url)
                .resizable()
                .frame(
                    width: Double(Theme.Metrics.iconSize),
                    height: Double(Theme.Metrics.iconSize)
                )
        } else {
            // Resource bundle missing: leave the space, don't crash.
            Color.clear
                .frame(
                    width: Double(Theme.Metrics.iconSize),
                    height: Double(Theme.Metrics.iconSize)
                )
        }
    }
}

/// Branch selector, drawn rather than delegated to the backend's segmented
/// control: the native one always paints the *system* accent, which put a blue
/// pill inside the orange Catalogue window. Drawing it also means the two
/// platforms look identical.
///
/// Each window owns its own selection, so browsing daily builds in the
/// catalogue doesn't disturb the library window.
struct BranchPicker: View {
    @Binding var branch: BuildBranch
    let accent: Color

    private static let padding = 3
    private static let spacing = 3

    var body: some View {
        // Segment widths are computed rather than expressed as
        // `.frame(maxWidth: .infinity)`: inside a Button label that traps in
        // SwiftCrossUI's layout ("Double value cannot be converted to Int").
        // The frame has to be inside the label for the whole capsule to be
        // clickable, so an explicit width is the way to get both.
        GeometryReader { proxy in
            let options = BuildBranch.allCases
            let inner = proxy.size.width - Double(Self.padding * 2)
            let gaps = Double(Self.spacing * (options.count - 1))
            let segment = max(40, (inner - gaps) / Double(options.count))

            HStack(spacing: Self.spacing) {
                ForEach(options, id: \.id) { option in
                    BranchSegment(
                        title: option.title,
                        selected: option == branch,
                        accent: accent,
                        width: segment
                    ) {
                        branch = option
                    }
                }
            }
            .padding(Self.padding)
            .background(
                Theme.controlBackground.cornerRadius(Theme.Metrics.tabContainerCorner)
            )
        }
        .frame(
            minHeight: Double(Theme.Metrics.tabHeight + Self.padding * 2),
            maxHeight: Double(Theme.Metrics.tabHeight + Self.padding * 2)
        )
    }
}

private struct BranchSegment: View {
    let title: String
    let selected: Bool
    let accent: Color
    let width: Double
    let action: @MainActor @Sendable () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? .white : Theme.secondaryText)
                .frame(
                    minWidth: width,
                    maxWidth: width,
                    minHeight: Double(Theme.Metrics.tabHeight),
                    maxHeight: Double(Theme.Metrics.tabHeight)
                )
                .background(fill.cornerRadius(Theme.Metrics.tabCorner))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var fill: Color {
        if selected { return accent }
        return hovered ? Theme.hoverFill : Color.clear
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
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
