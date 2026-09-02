import SwiftCrossUI
import VitrineKit

struct SettingsView: View {
    let store: BuildStore
    /// Tints the sheet to match whichever window opened it.
    let accent: Color
    @Binding var isPresented: Bool

    @State private var minVersionDraft = ""
    @State private var minVersionError: String?
    @Environment(\.chooseFile) private var chooseFile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Preferences")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                Spacer(minLength: 8)
                Button("Done") { isPresented = false }
            }

            librarySection
            catalogueSection

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 520, height: 340)
        .onAppear { minVersionDraft = store.minVersionString }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Library").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Text(store.libraryPath)
                    .font(.system(size: 11))
                    .fontDesign(.monospaced)
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Choose…") { pickFolder() }
                Button("Reveal") { store.revealLibrary() }
            }
            Text("""
                Builds are organised as <folder>/<branch>/<build-id>/. \
                Switching folders re-scans for installed builds.
                """)
                .font(.system(size: 10))
                .foregroundColor(Theme.tertiaryText)
        }
    }

    private var catalogueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Catalogue filter").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Text("Minimum version").font(.system(size: 11))
                TextField("e.g. 2.80", text: $minVersionDraft)
                    .frame(width: 120)
                Button("Apply") { commitMinVersion() }
                Spacer(minLength: 8)
            }
            if let minVersionError {
                Text(minVersionError)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            } else {
                Text("Hides every release older than this. Default 2.80.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
    }

    private func pickFolder() {
        Task {
            let url = await chooseFile(
                title: "Choose a library folder",
                initialDirectory: store.libraryURL.deletingLastPathComponent(),
                allowSelectingFiles: false,
                allowSelectingDirectories: true
            )
            if let url { store.libraryPath = url.path }
        }
    }

    private func commitMinVersion() {
        let trimmed = minVersionDraft.trimmingCharacters(in: .whitespaces)
        guard Version(trimmed) != nil else {
            minVersionError = "Not a version (try 2.80, 3.6, 4.2)."
            return
        }
        minVersionError = nil
        minVersionDraft = trimmed
        store.minVersionString = trimmed
    }
}
