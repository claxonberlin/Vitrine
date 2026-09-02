import SwiftCrossUI
import VitrineKit

/// Small pieces shared by both windows. Each window builds its own layout —
/// they differ enough that a single generic shell would obscure more than it
/// saved — but the parts below stay identical.

/// Square glyph button used for window actions.
struct IconButton: View {
    let glyph: String
    let help: String
    let accent: Color
    let action: @MainActor @Sendable () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 14))
                .foregroundColor(hovered ? accent : Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .background(Theme.rowBackground.opacity(hovered ? 1.0 : 0.5))
        .cornerRadius(6)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// The stable / daily / experimental selector. Each window owns its own
/// selection, so browsing daily builds in the catalogue doesn't disturb the
/// library window.
struct BranchPicker: View {
    @Binding var branch: BuildBranch

    var body: some View {
        Picker(
            of: BuildBranch.allCases,
            selection: Binding(
                get: { branch },
                set: { if let new = $0 { branch = new } }
            )
        )
        .pickerStyle(SegmentedPickerStyle())
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
            .background(Color.red.opacity(0.12))
            .cornerRadius(6)
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
