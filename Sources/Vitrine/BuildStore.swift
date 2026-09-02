import Foundation
import SwiftUI

@MainActor
final class BuildStore: ObservableObject {
    // Remote (Catalogue tab)
    @Published private(set) var stable: [RemoteBuild] = []
    @Published private(set) var daily: [RemoteBuild] = []
    @Published private(set) var experimental: [RemoteBuild] = []

    // Local (Vitrine tab)
    @Published private(set) var installed: [InstalledBuild] = []

    // UI state
    @Published var topTab: TopTab = .installed
    @Published var subTab: BuildBranch = .stable
    @Published private(set) var fetchingStable = false
    @Published private(set) var fetchingDaily = false
    @Published private(set) var fetchingExperimental = false
    @Published var lastError: String?

    @Published private(set) var downloads: [String: DownloadState] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    /// Catalogue group expansion state, keyed by minorKey (e.g. "4.5").
    /// Outlives sub-tab switches so re-visiting a tab keeps the user's
    /// previously expanded sections open.
    @Published var expandedMinorKeys: Set<String> = []

    /// installed.id → remote.url-id of the build currently being downloaded
    /// as an in-place upgrade. Drives the per-row spinner in InstalledRow.
    @Published private(set) var updatingTargets: [UUID: String] = [:]

    // Settings are backed by UserDefaults manually rather than @AppStorage:
    // wrappers other than @Published don't feed objectWillChange inside an
    // ObservableObject, so @AppStorage changes only repainted views by
    // coincidence (whenever some other @Published write happened to follow).

    @Published var libraryPath: String {
        didSet {
            guard oldValue != libraryPath else { return }
            UserDefaults.standard.set(libraryPath, forKey: Keys.libraryPath)
            reloadInstalled()
        }
    }

    @Published var minVersionString: String {
        didSet {
            guard oldValue != minVersionString else { return }
            UserDefaults.standard.set(minVersionString, forKey: Keys.minVersion)
            // Re-fetch the stable archive against the new threshold; daily/exp
            // are short lists, applying the filter in memory is enough.
            Task { await refreshStable() }
        }
    }

    private enum Keys {
        static let libraryPath = "libraryPath"
        static let minVersion = "minVersion"
        static let customBuilds = "customBuilds"
    }

    var minVersion: Version { Version(minVersionString) ?? Version("2.80")! }

    static var defaultLibrary: URL {
        URL(fileURLWithPath: "/Applications/Vitrine", isDirectory: true)
    }

    var libraryURL: URL { URL(fileURLWithPath: libraryPath) }

    private let downloadManager = DownloadManager()
    /// Rebuilt per access so a library-path change in Settings takes effect
    /// immediately; Installer holds no state beyond its two roots.
    private var installer: Installer { Installer(libraryRoot: libraryURL, downloads: downloadManager) }

    var isFetching: Bool { fetchingStable || fetchingDaily || fetchingExperimental }

    init() {
        let defaults = UserDefaults.standard
        _libraryPath = Published(initialValue: defaults.string(forKey: Keys.libraryPath) ?? Self.defaultLibrary.path)
        _minVersionString = Published(initialValue: defaults.string(forKey: Keys.minVersion) ?? "2.80")
        reloadInstalled()
        // Re-assert star wiring after a relaunch so the symlink survives an
        // OS update or accidental cleanup elsewhere. Only when a build is
        // actually starred: apply(nil) actively unwires, and would tear down
        // a `blender` symlink the user created without Vitrine.
        if let starred = installed.first(where: { $0.pinned }) {
            SystemIntegration.apply(starred: starred)
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
            let builds = try await BlenderAPI.fetchStableArchive(minVersion: minVersion)
            self.stable = builds.sorted { $0.parsedVersion > $1.parsedVersion }
        } catch {
            self.lastError = "Stable archive: \(error.localizedDescription)"
        }
    }

    func refreshDaily() async {
        fetchingDaily = true
        defer { fetchingDaily = false }
        do {
            let builds = try await BlenderAPI.fetchBuilderBuilds(.daily)
            // Keep alpha/candidate/beta out of stable, drop "stable" risk_id
            // (those land in the dedicated stable archive instead).
            self.daily = builds.filter { $0.riskId != "stable" }.sorted { $0.date > $1.date }
        } catch {
            self.lastError = "Daily builds: \(error.localizedDescription)"
        }
    }

    func refreshExperimental() async {
        fetchingExperimental = true
        defer { fetchingExperimental = false }
        do {
            let builds = try await BlenderAPI.fetchBuilderBuilds(.experimental)
            self.experimental = builds.sorted { $0.date > $1.date }
        } catch {
            self.lastError = "Experimental: \(error.localizedDescription)"
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

    /// Groups the current remote list by X.Y minor key for the catalogue
    /// view. Builds without a parseable minor key fall into single-element
    /// groups keyed by their raw version string. Groups are returned newest
    /// minor first; within a group, builds are sorted newest version first.
    func currentRemoteGrouped() -> [RemoteBuildGroup] {
        let raw = currentRemote()
        var buckets: [String: [RemoteBuild]] = [:]
        var order: [String] = []
        for b in raw {
            let key = b.parsedVersion.minorKey ?? b.version
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(b)
        }
        let groups = order.map { key -> RemoteBuildGroup in
            let sorted = buckets[key]!.sorted { $0.parsedVersion > $1.parsedVersion }
            return RemoteBuildGroup(minorKey: key, builds: sorted)
        }
        return groups.sorted { $0.latest.parsedVersion > $1.latest.parsedVersion }
    }

    func toggleExpansion(_ key: String) {
        if expandedMinorKeys.contains(key) {
            expandedMinorKeys.remove(key)
        } else {
            expandedMinorKeys.insert(key)
        }
    }

    /// Returns the installed build that corresponds to a remote listing, if
    /// any. Matched primarily by source URL — exact, and immune to the
    /// builder API reporting git branches ("main", feature branches) that
    /// never map onto a BuildBranch. Version+branch remains as a fallback
    /// for library folders whose metadata predates URL tracking. Custom
    /// builds never match: their version strings are user-controlled and
    /// they aren't Vitrine's to put back.
    func installedMatch(for remote: RemoteBuild) -> InstalledBuild? {
        let candidates = installed.filter { !$0.isCustom }
        if let exact = candidates.first(where: { $0.sourceURL == remote.url }) {
            return exact
        }
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

    // MARK: - Install / cancel / launch

    func install(_ build: RemoteBuild) {
        startInstall(of: build, branch: subTab)
    }

    /// Download `target` and replace `old` with the result. Star status
    /// transfers across. Blender stores prefs under a per-X.Y folder in
    /// Application Support, so a within-minor patch picks up the existing
    /// settings automatically — we just don't touch that folder.
    func updateInstall(from old: InstalledBuild, to target: RemoteBuild) {
        startInstall(of: target, branch: old.branch, replacing: old)
    }

    /// Shared download-and-install pipeline. `old` marks the in-place-update
    /// case: the outgoing build is removed once the new one is in place, and
    /// its star carries over.
    private func startInstall(of target: RemoteBuild, branch: BuildBranch, replacing old: InstalledBuild? = nil) {
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
                    // toggleStar enforces single-star and re-applies system wiring.
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

    /// Clears the transient bookkeeping once an install completes, fails or
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
        installer.launch(build)
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
        installer.reveal(build)
    }

    /// Uninstalling a library build deletes its folder. A custom build —
    /// an app the user already had on disk — is only forgotten; the .app
    /// itself is never touched.
    func uninstall(_ build: InstalledBuild) {
        let removingStarred = build.pinned
        if !build.isCustom {
            try? installer.uninstall(build)
        }
        installed.removeAll { $0.id == build.id }
        if build.isCustom {
            persistCustomBuilds()
        }
        if removingStarred {
            SystemIntegration.apply(starred: nil)
        }
    }

    /// Single-star semantics: the targeted build becomes the *only* starred
    /// build (or unstarred if it was already starred). The starred build is
    /// also wired into macOS (default `.blend` handler + `blender` symlink).
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
        SystemIntegration.apply(starred: starred)
    }

    // MARK: - In-place update

    /// Returns the newest remote build sharing the same X.Y minor key as the
    /// installed build, where the remote version is strictly greater. Searches
    /// only the matching branch's pool, since cross-branch updates would mean
    /// switching tracks (e.g. stable → daily), which is not what "update"
    /// implies. Custom builds (loose Blender.apps) opt out — their version
    /// strings often aren't real Blender versions.
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

    /// Adds an externally-installed Blender.app to the Vitrine. The app stays
    /// where the user has it; we only track a reference. The build is filed
    /// under whichever sub-tab is currently visible, so the user controls
    /// where it lands by switching tabs first.
    func addCustomBuild(at appURL: URL) {
        // Re-picking an already-tracked app keeps the existing entry.
        guard !installed.contains(where: { $0.appPath == appURL }) else { return }
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let version: String = {
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let v = plist["CFBundleShortVersionString"] as? String, !v.isEmpty {
                return v
            }
            return appURL.deletingPathExtension().lastPathComponent
        }()
        let entry = InstalledBuild(
            id: UUID(),
            version: version,
            riskId: InstalledBuild.customRiskID,
            branch: subTab,
            installedAt: Date(),
            lastLaunchedAt: nil,
            sourceURL: nil,
            appPath: appURL,
            pinned: false
        )
        installed.append(entry)
        persistCustomBuilds()
    }

    /// Custom builds live outside the library folder, so walking it can't
    /// rediscover them — they're carried in UserDefaults instead.
    private func persistCustomBuilds() {
        let customs = installed.filter { $0.isCustom }
        UserDefaults.standard.set(try? JSONEncoder().encode(customs), forKey: Keys.customBuilds)
    }

    private static func loadCustomBuilds() -> [InstalledBuild] {
        guard let data = UserDefaults.standard.data(forKey: Keys.customBuilds),
              let customs = try? JSONDecoder().decode([InstalledBuild].self, from: data)
        else { return [] }
        // Drop entries whose .app vanished (moved or trashed outside Vitrine).
        return customs.filter { FileManager.default.fileExists(atPath: $0.appPath.path) }
    }

    func reloadInstalled() {
        installed = installer.discoverInstalled() + Self.loadCustomBuilds()
    }
}
