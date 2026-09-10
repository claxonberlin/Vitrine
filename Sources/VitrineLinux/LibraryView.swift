import Adwaita
import Foundation
import VitrineKit

/// One branch of the installed library, as a preferences group. A branch with
/// nothing in it contributes no heading — an empty section would just be noise.
struct LibraryGroup: View {
    let branch: BuildBranch

    private var store: BuildStore { Shared.store }

    var view: Body {
        let builds = store.installed(in: branch)
        if !builds.isEmpty {
            PreferencesGroup()
                .title(branch.groupTitle)
                .child {
                    ForEach(builds) { build in
                        InstalledRow(build: build)
                    }
                }
        }
    }
}

/// A build already in the library.
struct InstalledRow: View {
    let build: InstalledBuild

    private var store: BuildStore { Shared.store }

    var view: Body {
        ActionRow(build.version)
            .subtitle(subtitle)
            .prefix {
                Button("Launch") { store.launch(build) }
                    .pill()
                    .suggested(build.pinned)
                    .valign(.center)
                    .tooltip("Open Blender \(build.version)")
            }
            .suffix {
                if store.isUpdating(build) {
                    Spinner().valign(.center)
                } else if let target = store.updateAvailable(for: build) {
                    Button(icon: .default(icon: .softwareUpdateAvailable)) {
                        store.updateInstall(from: build, to: target)
                    }
                    .flat()
                    .valign(.center)
                    .tooltip("Update to \(target.version) — keeps your preferences")
                }

                Button(icon: .default(icon: build.pinned ? .starred : .nonStarred)) {
                    store.toggleStar(build)
                }
                .flat()
                .valign(.center)
                .tooltip(build.pinned
                         ? "Unstar"
                         : "Star — opens .blend files, and puts `blender` on your PATH")

                Menu(icon: .default(icon: .viewMore)) {
                    MenuButton("Reveal in \(store.fileManagerName)") { store.reveal(build) }
                    MenuButton(build.pinned ? "Unstar" : "Star") { store.toggleStar(build) }
                    MenuSection {
                        // A custom build is the user's own copy — Vitrine only
                        // forgets the reference, so don't call it "Uninstall".
                        MenuButton(build.isCustom ? "Remove from Vitrine" : "Uninstall") {
                            store.uninstall(build)
                        }
                    }
                }
                .flat()
                .valign(.center)
            }
    }

    /// Badges have no libadwaita equivalent that fits a list row, so the same
    /// facts ride in the subtitle, which is where GNOME puts row detail.
    private var subtitle: String {
        var parts: [String] = []
        if !(build.branch == .stable && build.riskId == "stable") {
            parts.append(build.riskLabel)
        }
        // The hash rides beside the risk it qualifies: it is what tells two
        // dailies of one version apart.
        if build.branch == .daily, let hash = build.sourceHash { parts.append(hash) }
        if store.isLTS(build.version) { parts.append("LTS") }
        // A daily is a position on a track that moves nightly, so it reads as
        // an age; everything else is a dated release and says which date.
        parts.append(build.branch == .daily
                     ? DateFormat.recentDay(build.buildDate)
                     : DateFormat.day(build.buildDate))
        if let last = build.lastLaunchedAt {
            parts.append("opened \(DateFormat.relative(last))")
        }
        return parts.joined(separator: " · ")
    }
}
