import Foundation
import SwiftCrossUI
import VitrineKit

/// The app's single view model.
///
/// `ObservableObject` and `Published` are spelled out with their module: on
/// macOS, Foundation re-exports Combine's same-named types, and the bare
/// names are ambiguous. Owns catalogue state, the installed list, and
/// in-flight downloads, and is the only place that talks to `VitrineKit`.
@MainActor
final class BuildStore: SwiftCrossUI.ObservableObject {
    // Remote (Catalogue tab)
    @SwiftCrossUI.Published private(set) var stable: [RemoteBuild] = []
    @SwiftCrossUI.Published private(set) var daily: [RemoteBuild] = []
    @SwiftCrossUI.Published private(set) var experimental: [RemoteBuild] = []

    // Local (Vitrine tab)
    @SwiftCrossUI.Published private(set) var installed: [InstalledBuild] = []

    // UI state
    @SwiftCrossUI.Published var topTab: TopTab = .installed
    @SwiftCrossUI.Published var subTab: BuildBranch = .stable
    @SwiftCrossUI.Published private(set) var fetchingStable = false
    @SwiftCrossUI.Published private(set) var fetchingDaily = false
    @SwiftCrossUI.Published private(set) var fetchingExperimental = false
    @SwiftCrossUI.Published var lastError: String?

    @SwiftCrossUI.Published private(set) var downloads: [String: DownloadState] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    /// Catalogue group expansion state, keyed by minorKey (e.g. "4.5").
    /// Outlives sub-tab switches so re-visiting a tab keeps the user's
    /// previously expanded sections open.
    @SwiftCrossUI.Published var expandedMinorKeys: Set<String> = []

    /// installed.id → remote id of the build currently downloading as an
    /// in-place upgrade. Drives the per-row spinner in InstalledRow.
    @SwiftCrossUI.Published private(set) var updatingTargets: [UUID: String] = [:]

    @SwiftCrossUI.Published var libraryPath: String {
        didSet {
            guard oldValue != libraryPath else { return }
            settings.libraryPath = libraryPath
            config.save(settings)
            reloadInstalled()
        }
    }

    @SwiftCrossUI.Published var minVersionString: String {
        didSet {
            guard oldValue != minVersionString else { return }
            settings.minVersion = minVersionString
            config.save(settings)
            // Re-fetch the stable archive against the new threshold; daily and
            // experimental are short lists, so filtering in memory is enough.
            Task { await refreshStable() }
        }
    }

    private let platform = Platform.current
    private let config = ConfigStore()
    private var settings: VitrineSettings
    private let downloadManager = DownloadManager()

    /// Rebuilt per access so a library-path change takes effect immediately;
    /// Installer holds no state beyond its roots.
    private var installer: Installer {
        Installer(libraryRoot: libraryURL, downloads: downloadManager, platform: platform)
    }

    var minVersion: Version { Version(minVersionString) ?? Version("2.80")! }
    var libraryURL: URL { URL(fileURLWithPath: libraryPath) }
    var isFetching: Bool { fetchingStable || fetchingDaily || fetchingExperimental }
    var fileManagerName: String { platform.fileManagerName }

    init() {
        let config = ConfigStore()
        let loaded = config.load()
        self.settings = loaded
        self.libraryPath = loaded.libraryPath ?? Platform.current.defaultLibraryRoot.path
        self.minVersionString = loaded.minVersion
        reloadInstalled()
        // Re-assert the star wiring after a relaunch so it survives an OS
        // update or cleanup elsewhere. Only when something is actually
        // starred: applyStarred(nil) actively unwires, and would tear down a
        // `blender` symlink the user created without Vitrine.
        if let starred = installed.first(where: { $0.pinned }) {
            Task { await platform.applyStarred(starred) }
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        async let s: Void = refreshStable()
        async let d: Void = refreshDaily()
        async let e: Void = refreshExperimental()
        _ = await (s, d, e)
    }

    func refreshStable() async {
        fetchingStable = true
        defer { fetchingStable = false }
        do {
            let builds = try await BlenderAPI.fetchStableArchive(
                minVersion: minVersion, platform: platform.buildPlatform
            )
            stable = builds.sorted { $0.parsedVersion > $1.parsedVersion }
        } catch {
            lastError = "Stable archive: \(error.localizedDescription)"
        }
    }

    func refreshDaily() async {
        fetchingDaily = true
        defer { fetchingDaily = false }
        do {
            let builds = try await BlenderAPI.fetchBuilderBuilds(
                .daily, platform: platform.buildPlatform
            )
            // Keep alpha/candidate/beta out of stable, and drop the "stable"
            // risk_id — those land in the dedicated stable archive instead.
            daily = builds.filter { $0.riskId != "stable" }.sorted { $0.date > $1.date }
        } catch {
            lastError = "Daily builds: \(error.localizedDescription)"
        }
    }

    func refreshExperimental() async {
        fetchingExperimental = true
        defer { fetchingExperimental = false }
        do {
            let builds = try await BlenderAPI.fetchBuilderBuilds(
                .experimental, platform: platform.buildPlatform
            )
            experimental = builds.sorted { $0.date > $1.date }
        } catch {
            lastError = "Experimental: \(error.localizedDescription)"
        }
    }

    // MARK: - Filtered views

    func currentInstalled() -> [InstalledBuild] {
        installed
            .filter { $0.branch == subTab }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                let lv = Version(lhs.version) ?? .zero
                let rv = Version(rhs.version) ?? .zero
                if lv != rv { return lv > rv }
                return lhs.installedAt > rhs.installedAt
            }
    }

    func currentRemote() -> [RemoteBuild] {
        let raw: [RemoteBuild]
        switch subTab {
        case .stable: raw = stable
        case .daily: raw = daily
        case .experimental: raw = experimental
        }
        return raw.filter { $0.parsedVersion >= minVersion }
    }

    /// Groups the current remote list by X.Y minor key for the catalogue view.
    /// Builds without a parseable minor key fall into single-element groups
    /// keyed by their raw version string. Groups are returned newest minor
    /// first; within a group, builds are sorted newest version first.
    func currentRemoteGrouped() -> [RemoteBuildGroup] {
        var buckets: [String: [RemoteBuild]] = [:]
        var order: [String] = []
        for b in currentRemote() {
            let key = b.parsedVersion.minorKey ?? b.version
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(b)
        }
        return order.map { key in
            RemoteBuildGroup(
                minorKey: key,
                builds: buckets[key]!.sorted { $0.parsedVersion > $1.parsedVersion }
            )
        }
        .sorted { $0.latest.parsedVersion > $1.latest.parsedVersion }
    }

    func toggleExpansion(_ key: String) {
        if expandedMinorKeys.contains(key) {
            expandedMinorKeys.remove(key)
        } else {
            expandedMinorKeys.insert(key)
        }
    }

    /// The installed build corresponding to a remote listing, if any. Matched
    /// primarily by source URL — exact, and immune to the builder API
    /// reporting git branches ("main", feature branches) that never map onto a
    /// BuildBranch. Version+branch remains as a fallback for library folders
    /// whose metadata predates URL tracking. Custom builds never match: their
    /// version strings are user-controlled and they aren't Vitrine's to remove.
    func installedMatch(for remote: RemoteBuild) -> InstalledBuild? {
        let candidates = installed.filter { !$0.isCustom }
        if let exact = candidates.first(where: { $0.sourceURL == remote.url }) { return exact }
        guard let remoteBranch = BuildBranch(rawValue: remote.branch) else { return nil }
        return candidates.first {
            $0.sourceURL == nil && $0.version == remote.version && $0.branch == remoteBranch
        }
    }

    func isCurrentlyFetching(_ branch: BuildBranch) -> Bool {
        switch branch {
        case .stable: return fetchingStable
        case .daily: return fetchingDaily
        case .experimental: return fetchingExperimental
        }
    }

    func downloadState(_ id: String) -> DownloadState { downloads[id] ?? .idle }

    // MARK: - Install / cancel / launch

    func install(_ build: RemoteBuild) {
        startInstall(of: build, branch: subTab)
    }

    /// Downloads `target` and replaces `old` with the result. Star status
    /// transfers across. Blender stores prefs under a per-X.Y folder, so a
    /// within-minor patch picks up existing settings automatically — we just
    /// don't touch that folder.
    func updateInstall(from old: InstalledBuild, to target: RemoteBuild) {
        startInstall(of: target, branch: old.branch, replacing: old)
    }

    /// Shared download-and-install pipeline. `old` marks the in-place-update
    /// case: the outgoing build is removed once the new one is in place, and
    /// its star carries over.
    private func startInstall(of target: RemoteBuild,
                              branch: BuildBranch,
                              replacing old: InstalledBuild? = nil) {
        guard downloads[target.id]?.isActive != true else { return }
        if let old { updatingTargets[old.id] = target.id }
        downloads[target.id] = .queued
        downloadTasks[target.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let new = try await self.installer.install(target, branch: branch) { state in
                    self.downloads[target.id] = state
                }
                self.installed.append(new)
                if let old {
                    try? self.installer.uninstall(old)
                    self.installed.removeAll { $0.id == old.id }
                }
                self.finishInstall(of: target, replacing: old)
                if old?.pinned == true {
                    // toggleStar enforces single-star and re-applies wiring.
                    self.toggleStar(new)
                }
                self.topTab = .installed
                self.subTab = branch
            } catch DownloadManager.Failure.canceled {
                self.finishInstall(of: target, replacing: old)
            } catch {
                self.finishInstall(of: target, replacing: old)
                self.downloads[target.id] = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Clears the transient bookkeeping once an install completes, fails, or
    /// is canceled.
    private func finishInstall(of target: RemoteBuild, replacing old: InstalledBuild?) {
        downloads[target.id] = nil
        downloadTasks[target.id] = nil
        if let old { updatingTargets[old.id] = nil }
    }

    func cancelDownload(_ build: RemoteBuild) {
        downloadManager.cancel(id: build.id)
        downloadTasks[build.id]?.cancel()
        downloadTasks[build.id] = nil
        downloads[build.id] = nil
    }

    func launch(_ build: InstalledBuild) {
        do {
            try installer.launch(build)
        } catch {
            lastError = error.localizedDescription
            return
        }
        let now = Date()
        if let idx = installed.firstIndex(where: { $0.id == build.id }) {
            installed[idx].lastLaunchedAt = now
        }
        if build.isCustom {
            persistCustomBuilds()
        } else {
            installer.updateMetadata(for: build) { $0.lastLaunchedAt = now }
        }
    }

    func reveal(_ build: InstalledBuild) {
        Task { await installer.reveal(build) }
    }

    func revealLibrary() {
        Task { await platform.reveal(libraryURL) }
    }

    func openInBrowser(_ string: String) {
        guard let url = URL(string: string) else { return }
        Task { await platform.openURL(url) }
    }

    /// Uninstalling a library build deletes its folder. A custom build — one
    /// the user already had on disk — is only forgotten; the files themselves
    /// are never touched.
    func uninstall(_ build: InstalledBuild) {
        let removingStarred = build.pinned
        if !build.isCustom {
            try? installer.uninstall(build)
        }
        installed.removeAll { $0.id == build.id }
        if build.isCustom { persistCustomBuilds() }
        if removingStarred {
            Task { await platform.applyStarred(nil) }
        }
    }

    /// Single-star semantics: the targeted build becomes the *only* starred
    /// build (or is unstarred if it already was). The starred build is also
    /// wired into the desktop by the platform layer.
    func toggleStar(_ build: InstalledBuild) {
        let wasStarred = installed.first(where: { $0.id == build.id })?.pinned ?? false
        let nowStarred = !wasStarred
        var customsChanged = false
        for i in installed.indices {
            let shouldBeStarred = (installed[i].id == build.id) && nowStarred
            guard installed[i].pinned != shouldBeStarred else { continue }
            installed[i].pinned = shouldBeStarred
            if installed[i].isCustom {
                customsChanged = true
            } else {
                installer.updateMetadata(for: installed[i]) { $0.pinned = shouldBeStarred }
            }
        }
        if customsChanged { persistCustomBuilds() }
        let starred = installed.first(where: { $0.pinned })
        Task { await platform.applyStarred(starred) }
    }

    // MARK: - In-place update

    /// The newest remote build sharing the same X.Y minor key as the installed
    /// build, where the remote version is strictly greater. Searches only the
    /// matching branch's pool, since a cross-branch update would mean
    /// switching tracks (stable → daily), which isn't what "update" implies.
    /// Custom builds opt out — their version strings often aren't real Blender
    /// versions.
    func updateAvailable(for build: InstalledBuild) -> RemoteBuild? {
        guard !build.isCustom,
              let installedV = Version(build.version),
              let key = installedV.minorKey else { return nil }
        let pool: [RemoteBuild]
        switch build.branch {
        case .stable: pool = stable
        case .daily: pool = daily
        case .experimental: pool = experimental
        }
        return pool
            .filter { $0.parsedVersion.minorKey == key && $0.parsedVersion > installedV }
            .max { $0.parsedVersion < $1.parsedVersion }
    }

    // MARK: - Custom (user-added local builds)

    /// Adds an externally-installed Blender to the Vitrine. It stays where the
    /// user has it; we only track a reference. The build is filed under
    /// whichever sub-tab is visible, so the user controls where it lands by
    /// switching tabs first.
    func addCustomBuild(at url: URL) {
        guard !installed.contains(where: { $0.buildPath == url }) else { return }
        let branch = subTab
        Task {
            let version = await platform.version(ofBuildAt: url)
                ?? url.deletingPathExtension().lastPathComponent
            let entry = InstalledBuild(
                id: UUID(),
                version: version,
                riskId: InstalledBuild.customRiskID,
                branch: branch,
                installedAt: Date(),
                lastLaunchedAt: nil,
                sourceURL: nil,
                buildPath: url,
                pinned: false
            )
            installed.append(entry)
            persistCustomBuilds()
            topTab = .installed
        }
    }

    /// Custom builds live outside the library folder, so walking it can't
    /// rediscover them — they're carried in the config file instead.
    private func persistCustomBuilds() {
        settings.customBuilds = installed.filter { $0.isCustom }
        config.save(settings)
    }

    func reloadInstalled() {
        // Drop entries whose build vanished (moved or deleted outside Vitrine).
        let customs = settings.customBuilds.filter {
            FileManager.default.fileExists(atPath: $0.buildPath.path)
        }
        installed = installer.discoverInstalled() + customs
    }
}
