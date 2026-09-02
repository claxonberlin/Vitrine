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
        HStack(spacing: 10) {
            if WindowChrome.drawsOwnTitle {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer(minLength: 8)
            actions()
        }
        .padding(.leading, WindowChrome.trafficLightInset)
        .frame(minHeight: 38, maxHeight: 38)
    }
}

/// Groups the window actions into one rounded container, the way a macOS
/// unified toolbar does — individually bordered buttons read as loose and
/// unfinished.
struct ToolbarCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(3)
        .background(Theme.controlBackground.cornerRadius(9))
    }
}

/// Glyph button used inside a `ToolbarCluster`. Carries no chrome of its own
/// beyond a hover fill — the cluster supplies the container.
struct IconButton: View {
    let glyph: String
    let help: String
    let accent: Color
    let action: @MainActor @Sendable () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 13))
                .foregroundColor(hovered ? accent : Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 26, maxWidth: 26, minHeight: 24, maxHeight: 24)
        .background((hovered ? Theme.hoverFill : Color.clear).cornerRadius(6))
        .onHover { hovered = $0 }
        .help(help)
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

    var body: some View {
        HStack(spacing: 3) {
            ForEach(BuildBranch.allCases, id: \.id) { option in
                BranchSegment(
                    title: option.title,
                    selected: option == branch,
                    accent: accent
                ) {
                    branch = option
                }
            }
        }
        .padding(3)
        .background(Theme.controlBackground.cornerRadius(10))
    }
}

private struct BranchSegment: View {
    let title: String
    let selected: Bool
    let accent: Color
    let action: @MainActor @Sendable () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? .white : Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .background(fill.cornerRadius(7))
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
            .background(Color.red.opacity(0.12).cornerRadius(8))
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
