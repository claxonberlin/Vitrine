import SwiftUI
import VitrineKit

/// The ⌘, window. A grouped `Form` is what every other macOS app puts here,
/// so it needs no explanation.
struct SettingsView: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    @State private var minVersionDraft = ""
    @State private var minVersionRejected = false
    @State private var choosingFolder = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    HStack(spacing: 6) {
                        Text(displayPath)
                            .font(.system(size: 11))
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(store.libraryPath)
                        Spacer(minLength: 8)
                        Button("Choose…") { choosingFolder = true }
                        Button("Reveal") { store.revealLibrary() }
                    }
                }
            } header: {
                Text("Library")
            } footer: {
                Text("Builds are filed as ⟨folder⟩/⟨branch⟩/⟨build⟩. Switching folders re-scans for installed builds.")
            }

            Section {
                LabeledContent("Minimum version") {
                    HStack(spacing: 6) {
                        // The label is carried by LabeledContent, so the
                        // field's own is hidden and "2.80" stays a prompt
                        // rather than becoming a second label beside it.
                        TextField("Minimum version",
                                  text: $minVersionDraft,
                                  prompt: Text("2.80"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .monospaced()
                            .frame(width: 84)
                            .onSubmit(commitMinVersion)
                        Button("Apply", action: commitMinVersion)
                            .disabled(minVersionDraft == store.minVersionString)
                        Spacer(minLength: 0)
                    }
                }
            } header: {
                Text("Catalogue")
            } footer: {
                Text(minVersionRejected
                     ? "Not a version — try 2.80, 3.6 or 4.2."
                     : "Hides every release older than this.")
                    .foregroundStyle(minVersionRejected ? Color.red : Color.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { minVersionDraft = store.minVersionString }
        .fileImporter(
            isPresented: $choosingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                store.setLibraryPath(url.path)
            }
        }
    }

    /// The full path is long enough to blow the window out, so the row shows
    /// the tail and keeps the whole thing in a tooltip.
    private var displayPath: String {
        let home = NSHomeDirectory()
        return store.libraryPath.hasPrefix(home)
            ? "~" + store.libraryPath.dropFirst(home.count)
            : store.libraryPath
    }

    private func commitMinVersion() {
        minVersionRejected = !store.setMinVersion(minVersionDraft)
        if !minVersionRejected {
            minVersionDraft = store.minVersionString
        }
    }
}
