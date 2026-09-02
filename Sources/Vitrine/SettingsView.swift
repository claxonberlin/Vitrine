import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: BuildStore
    @State private var minVersionDraft: String = ""
    @State private var minVersionError: String?

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Folder") {
                    HStack(spacing: 6) {
                        Text(store.libraryPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { pickFolder() }
                            .handCursor()
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.libraryURL])
                        }
                        .handCursor()
                    }
                }
                Text("Builds are organized as `<folder>/<branch>/<build-id>/Blender.app`. Switching folders re-scans for installed builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Catalogue filter") {
                LabeledContent("Minimum version") {
                    HStack {
                        TextField("e.g. 2.80", text: $minVersionDraft)
                            .frame(width: 120)
                            .onSubmit(commitMinVersion)
                            .onChange(of: minVersionDraft) { minVersionError = nil }
                        Button("Apply", action: commitMinVersion)
                            .disabled(minVersionDraft == store.minVersionString)
                            .handCursor()
                    }
                }
                if let err = minVersionError {
                    Text(err).font(.caption).foregroundStyle(.red)
                } else {
                    Text("Hides every release older than this. Default 2.80 — earlier builds don't run on modern macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
        .onAppear { minVersionDraft = store.minVersionString }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.libraryURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            store.libraryPath = url.path
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
