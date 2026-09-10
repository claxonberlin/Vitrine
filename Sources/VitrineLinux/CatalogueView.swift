import Adwaita
import Foundation
import VitrineKit

/// The remote catalogue. Fetched once when the window opens; the spinner in
/// the sidebar's header bar is the only progress that needs showing.
struct CatalogueView: View {
    private var store: BuildStore { Shared.store }

    var view: Body {
        if store.isFetching && store.stable.isEmpty {
            StatusPage(
                "Loading Builds…",
                icon: .default(icon: .contentLoading),
                description: "Fetching the catalogue from blender.org."
            ) {}
        } else {
            ScrollView {
                VStack {
                    ForEach(BuildBranch.allCases) { branch in
                        CatalogueGroup(branch: branch)
                    }
                }
                .padding()
            }
            .vexpand()
        }
    }
}

/// One branch of the catalogue.
struct CatalogueGroup: View {
    let branch: BuildBranch

    private var store: BuildStore { Shared.store }

    var view: Body {
        let groups = store.remoteGrouped(in: branch)
        if !groups.isEmpty {
            PreferencesGroup()
                .title(branch.groupTitle)
                .child {
                    ForEach(groups) { group in
                        if group.builds.count == 1 {
                            RemoteRow(build: group.builds[0], branch: branch)
                        } else {
                            SeriesRow(group: group, branch: branch)
                        }
                    }
                }
        }
    }
}

/// A minor series and the releases under it. `ExpanderRow` is libadwaita's own
/// disclosure row, so the fold-out behaves exactly as it does everywhere else
/// on the desktop.
struct SeriesRow: View {
    let group: RemoteBuildGroup
    let branch: BuildBranch

    private var store: BuildStore { Shared.store }

    var view: Body {
        ExpanderRow()
            .title("Blender \(group.minorKey)")
            .subtitle(subtitle)
            .expanded(Binding(
                get: { store.isExpanded(group.minorKey) },
                set: { _ in store.toggleExpansion(group.minorKey) }
            ))
            .prefix {
                CatalogueAction(build: group.latest, branch: branch,
                                label: group.minorKey)
            }
            .rows {
                ForEach(group.builds) { build in
                    RemoteRow(build: build, branch: branch)
                }
            }
    }

    private var subtitle: String {
        var parts = ["\(group.builds.count) releases"]
        let isLTS = store.isLTS(group.latest.version)
        if let risk = group.latest.riskLabel(besideLTS: isLTS) { parts.append(risk) }
        if isLTS { parts.append("LTS") }
        return parts.joined(separator: " · ")
    }
}

/// A single remote build.
struct RemoteRow: View {
    let build: RemoteBuild
    let branch: BuildBranch

    private var store: BuildStore { Shared.store }

    var view: Body {
        ActionRow("Blender \(build.version)")
            .subtitle(subtitle)
            .prefix {
                CatalogueAction(build: build, branch: branch)
            }
            .suffix {
                if case .downloading(let received, let total) = store.downloadState(build.id) {
                    let fraction = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
                    VStack {
                        ProgressBar(value: fraction, total: 1)
                            .frame(minWidth: 120)
                        // The bar says how far along it is; the label only has
                        // to say which half of the job this is.
                        Text("Downloading")
                            .caption()
                            .dimLabel()
                    }
                    .valign(.center)
                } else if case .installing = store.downloadState(build.id) {
                    Text("Installing")
                        .caption()
                        .dimLabel()
                        .valign(.center)
                }
            }
    }

    private var subtitle: String {
        var parts: [String] = []
        let isLTS = store.isLTS(build.version)
        // Every catalogue row says how finished its build is, "Stable"
        // included: the heading it sits under is scrolled away half the time.
        // Only an LTS row goes without, since its own tag says it.
        if let risk = build.riskLabel(besideLTS: isLTS) { parts.append(risk) }
        // The hash rides beside the risk it qualifies — it is what tells the
        // daily on offer from the one already installed.
        if branch == .daily, let hash = build.hash { parts.append(hash) }
        if isLTS { parts.append("LTS") }
        if build.fileSize > 0 { parts.append(ByteFormat.string(build.fileSize)) }
        // A daily reads as an age; a release says its date. Some old archive
        // entries carry neither.
        if build.date != .distantPast {
            parts.append(branch == .daily
                         ? DateFormat.recentDay(build.date)
                         : DateFormat.day(build.date))
        }
        if case .failed(let message) = store.downloadState(build.id) {
            parts.append(message)
        }
        return parts.joined(separator: " · ")
    }
}

/// The action shared by catalogue rows and series rows: download, cancel,
/// retry, or "Put Back" when the build is already installed.
struct CatalogueAction: View {
    let build: RemoteBuild
    let branch: BuildBranch
    /// Defaults to the exact version; a series row passes its minor key.
    var label: String?

    private var store: BuildStore { Shared.store }

    var view: Body {
        if let installed = store.installedMatch(for: build) {
            Button("Put Back") { store.uninstall(installed) }
                .pill()
                .destructive()
                .valign(.center)
                .tooltip("Remove Blender \(build.version) from the library")
        } else {
            switch store.downloadState(build.id) {
            case .idle:
                Button(label ?? build.version, icon: .default(icon: .folderDownload)) {
                    store.install(build, into: branch)
                }
                .pill()
                .suggested()
                .valign(.center)
                .tooltip("Download Blender \(build.version)")
            case .queued, .installing:
                Spinner().valign(.center)
            case .downloading:
                Button(icon: .default(icon: .processStop)) {
                    store.cancelDownload(build)
                }
                .circular()
                .destructive()
                .valign(.center)
                .tooltip("Cancel this download")
            case .failed:
                Button("Retry") { store.install(build, into: branch) }
                    .pill()
                    .valign(.center)
            }
        }
    }
}

/// How far back the stable archive is scraped.
///
/// This is the only setting the app has, and it belongs to the catalogue —
/// which is why it sits in the catalogue's own header bar rather than behind a
/// preferences window.
///
/// The entries are written out rather than looped over
/// `BuildStore.minVersionChoices`: a GMenu is built from a static model, and
/// spelling the items out keeps this to constructs the menu builder is known
/// to accept. Keep the two lists in step.
struct MinimumVersionMenu: View {
    private var store: BuildStore { Shared.store }

    var view: Body {
        Menu("from \(store.minVersionString)") {
            MenuButton("2.80") { store.setMinVersion("2.80") }
            MenuButton("2.93") { store.setMinVersion("2.93") }
            MenuButton("3.0") { store.setMinVersion("3.0") }
            MenuButton("3.3") { store.setMinVersion("3.3") }
            MenuButton("3.6") { store.setMinVersion("3.6") }
            MenuButton("4.0") { store.setMinVersion("4.0") }
            MenuButton("4.2") { store.setMinVersion("4.2") }
            MenuButton("4.5") { store.setMinVersion("4.5") }
            MenuButton("5.0") { store.setMinVersion("5.0") }
        }
        .tooltip("Hide every release older than this")
    }
}
