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
        if store.isLTS(group.latest.version) { parts.append("LTS") }
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
                if case .downloading(let received, let total, let bps) = store.downloadState(build.id) {
                    let fraction = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
                    let eta = bps > 0 && total > received
                        ? Double(total - received) / bps
                        : -1
                    VStack {
                        ProgressBar(value: fraction, total: 1)
                            .frame(minWidth: 120)
                        Text(DurationFormat.eta(seconds: eta))
                            .caption()
                            .dimLabel()
                    }
                    .valign(.center)
                }
            }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !(branch == .stable && build.riskId == "stable") {
            parts.append(build.riskLabel)
        }
        if store.isLTS(build.version) { parts.append("LTS") }
        if build.fileSize > 0 { parts.append(ByteFormat.string(build.fileSize)) }
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
