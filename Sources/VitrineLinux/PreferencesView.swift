import Adwaita
import Foundation
import VitrineKit

/// The preferences window. `PreferencesPage` is what GNOME Settings itself is
/// built from, so this needs no explaining to anyone on the desktop.
struct PreferencesView: View {
    @State private var minVersionDraft = ""
    @State private var minVersionRejected = false
    @State private var openFolderChooser: Signal = .init()
    @State private var revision = 0

    private var store: BuildStore { Shared.store }

    var view: Body {
        PreferencesPage().child {
            PreferencesGroup()
                .title("Library")
                .description("Builds are filed as ⟨folder⟩/⟨branch⟩/⟨build⟩. Switching folders re-scans for installed builds.")
                .child {
                    ActionRow("Location")
                        .subtitle(store.libraryPath)
                        .suffix {
                            Button("Choose…") { openFolderChooser.signal() }
                                .valign(.center)
                            Button("Reveal") { store.revealLibrary() }
                                .flat()
                                .valign(.center)
                        }
                }

            PreferencesGroup()
                .title("Catalogue")
                .description(minVersionRejected
                             ? "Not a version — try 2.80, 3.6 or 4.2."
                             : "Hides every release older than this.")
                .child {
                    // libadwaita's own apply affordance: a checkmark that
                    // appears once the text differs from what was committed.
                    EntryRow("Minimum version", text: $minVersionDraft)
                        .showApplyButton()
                        .apply(commit)
                        .onSubmit(commit)
                }
        }
        .onAppear {
            Shared.connect(revision: $revision)
            minVersionDraft = store.minVersionString
        }
        .fileImporter(open: openFolderChooser) { url in
            store.setLibraryPath(url.path)
        } onClose: {}
    }

    private func commit() {
        minVersionRejected = !store.setMinVersion(minVersionDraft)
        if !minVersionRejected {
            minVersionDraft = store.minVersionString
        }
    }
}
