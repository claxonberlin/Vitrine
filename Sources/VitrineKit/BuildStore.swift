import Foundation

/// The app's single view model: catalogue state, the installed library, and
/// in-flight downloads. It is the only thing the front ends talk to, and it
/// talks to nothing above itself — no UI framework is imported here, so the
/// same object drives SwiftUI on macOS and Adwaita on Fedora.
///
/// Change notification is hand-rolled rather than left to the `@Observable`
/// macro: a macro plugin has to run on the build host, and the one Linux
/// toolchains ship has known trouble expanding `@Observable`. A `didSet` on
/// each property costs a line and works the same everywhere. Front ends
/// subscribe with `observeChanges(_:)`.
///
/// There is deliberately no window state here — which pane is open, what is
/// selected — because that belongs to whichever shell is presenting it.
@MainActor
public final class BuildStore {

    // MARK: - Remote catalogue

    public private(set) var stable: [RemoteBuild] = [] { didSet { republish() } }
    public private(set) var daily: [RemoteBuild] = [] { didSet { republish() } }
    public private(set) var experimental: [RemoteBuild] = [] { didSet { republish() } }

    public private(set) var fetchingStable = false { didSet { notify() } }
    public private(set) var fetchingDaily = false { didSet { notify() } }
    public private(set) var fetchingExperimental = false { didSet { notify() } }

    /// Which X.Y branches carry the LTS badge. Seeded from the cached list and
    /// refreshed from blender.org on launch.
    public private(set) var ltsBranches: LTSBranches { didSet { notify() } }

    // MARK: - Local library

    public private(set) var installed: [InstalledBuild] = [] { didSet { republish() } }

    public private(set) var downloads: [String: DownloadState] = [:] { didSet { notify() } }

    /// installed.id → remote id of the build currently downloading as an
    /// in-place upgrade. Drives the progress the card itself paints while its
    /// replacement comes down.
    public private(set) var updatingTargets: [UUID: String] = [:] { didSet { notify() } }

    /// Builds being installed for the first time, in the order they were
    /// asked for. The library lists a card for each straight away, so a new
    /// install is visible where it will live rather than only in the
    /// catalogue. An in-place update adds nothing here — see `updatingTargets`.
    public private(set) var pendingInstalls: [PendingInstall] = [] { didSet { republish() } }

    /// Catalogue group expansion, keyed by minor key (e.g. "4.5"). Lives here
    /// rather than in a view so both front ends fold groups the same way and
    /// the state survives a re-render.
    public var expandedMinorKeys: Set<String> = [] { didSet { notify() } }

    /// Last failure worth showing. Settable so the UI can dismiss it.
    public var lastError: String? { didSet { notify() } }

    /// Local file holding the splash artwork of the newest stable release, or
    /// nil until it has been fetched — or for good, if blender.org couldn't
    /// be reached. Front ends paint it behind the window.
    public private(set) var splashArtwork: URL? { didSet { notify() } }

    // MARK: - Settings

    public private(set) var libraryPath: String { didSet { notify() } }
    public private(set) var minVersionString: String { didSet { republish() } }

    // MARK: - Internals

    private let platform = Platform.current
    private let config: ConfigStore
    private var settings: VitrineSettings
    private let downloadManager = DownloadManager()
    private let splashLibrary = SplashLibrary()
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    /// Front ends subscribed through `observeChanges`. See StoreObservation.
    var observers: [Observer] = []

    /// `remoteGrouped(in:)` and `installed(in:)` are pure functions of the
    /// stored lists, and both front ends call them once per branch on every
    /// render — while a download is running that is ten times a second, for
    /// work that only changes when a fetch lands. Computed once per change
    /// instead, and dropped by `republish()` when their inputs move.
    private var groupedRemote: [BuildBranch: [RemoteBuildGroup]] = [:]
    private var installedByBranch: [BuildBranch: [InstalledBuild]] = [:]
    private var libraryRowsByBranch: [BuildBranch: [LibraryRow]] = [:]

    /// The `didSet` for a property the derived lists are built from.
    private func republish() {
        groupedRemote.removeAll(keepingCapacity: true)
        installedByBranch.removeAll(keepingCapacity: true)
        libraryRowsByBranch.removeAll(keepingCapacity: true)
        notify()
    }

    /// Rebuilt per access so a library-path change takes effect immediately;
    /// Installer holds no state beyond its roots.
    private var installer: Installer {
        Installer(libraryRoot: libraryURL, downloads: downloadManager, platform: platform)
    }

    public var minVersion: Version { Version(minVersionString) ?? Version("2.80")! }
    public var libraryURL: URL { URL(fileURLWithPath: libraryPath) }
    public var isFetching: Bool { fetchingStable || fetchingDaily || fetchingExperimental }
    public var fileManagerName: String { platform.fileManagerName }
    /// Whether "add an existing build" means picking a directory rather than a
    /// file, so each front end can configure its open dialog correctly.
    public var buildIsDirectory: Bool { platform.buildIsDirectory }

    public init() {
        // Built here rather than as a property initialiser: `self` isn't
        // usable until every stored property has a value, and loading the
        // settings is what supplies most of them.
        let config = ConfigStore()
        let loaded = config.load()
        self.config = config
        self.settings = loaded
        self.libraryPath = loaded.libraryPath ?? Platform.current.defaultLibraryRoot.path
        self.minVersionString = loaded.minVersion
        self.ltsBranches = loaded.ltsBranches
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

    public func refreshAll() async {
        guard !isFetching else { return }
        async let l: Void = refreshLTS()
        async let s: Void = refreshStable()
        async let d: Void = refreshDaily()
        async let e: Void = refreshExperimental()
        _ = await (l, s, d, e)
        // Last, because it needs the stable list to know which release is the
        // newest one to ask for artwork about.
        await refreshSplash()
    }

    /// Fetches the splash artwork of the newest stable release. Silent on
    /// failure: a window with no picture behind it is not an error worth
    /// interrupting anyone over.
    public func refreshSplash() async {
        guard let series = stable.first?.parsedVersion.minorKey else { return }
        guard let artwork = await splashLibrary.artwork(forSeries: series) else { return }
        splashArtwork = artwork
    }

    /// Failure here is deliberately silent: the cached list stays in place and
    /// a missing badge isn't worth an error banner over.
    public func refreshLTS() async {
        guard let fetched = try? await BlenderAPI.fetchLTSBranches() else { return }
        guard fetched != ltsBranches else { return }
        ltsBranches = fetched
        settings.ltsBranches = fetched
        config.save(settings)
    }

    public func refreshStable() async {
        fetchingStable = true
        defer { fetchingStable = false }
        do {
            let builds = try await BlenderAPI.fetchStableArchive(
                minVersion: minVersion, platform: platform.buildPlatform
            )
            stable = builds.sorted { $0.parsedVersion > $1.parsedVersion }
            backfillVintages(from: stable)
        } catch {
            lastError = "Stable archive: \(error.localizedDescription)"
        }
    }

    public func refreshDaily() async {
        fetchingDaily = true
        defer { fetchingDaily = false }
        do {
            let builds = try await BlenderAPI.fetchBuilderBuilds(
                .daily, platform: platform.buildPlatform
            )
            // Keep alpha/candidate/beta out of stable, and drop the "stable"
            // risk_id — those land in the dedicated stable archive instead.
            daily = builds.filter { $0.riskId != "stable" }.sorted { $0.date > $1.date }
            backfillVintages(from: daily)
        } catch {
            lastError = "Daily builds: \(error.localizedDescription)"
        }
    }

    public func refreshExperimental() async {
        fetchingExperimental = true
        defer { fetchingExperimental = false }
        do {
            let builds = try await BlenderAPI.fetchBuilderBuilds(
                .experimental, platform: platform.buildPlatform
            )
            experimental = builds.sorted { $0.date > $1.date }
            backfillVintages(from: experimental)
        } catch {
            lastError = "Experimental: \(error.localizedDescription)"
        }
    }

    /// Fills in the build date and hash for installs made before Vitrine
    /// recorded them, whenever a fetch turns up the exact file one came from.
    ///
    /// Matched on source URL, which is exact — no guessing from a version
    /// string. A library folder that predates URL tracking, or a build whose
    /// file the archive no longer lists, keeps showing the day it was
    /// installed, which is the only date anybody has for it.
    private func backfillVintages(from pool: [RemoteBuild]) {
        guard !installed.isEmpty else { return }
        let byURL = Dictionary(pool.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        for index in installed.indices {
            let build = installed[index]
            guard !build.isCustom, !build.hasBuildDate,
                  let source = build.sourceURL, let remote = byURL[source],
                  remote.date != .distantPast else { continue }
            installed[index].builtAt = remote.date
            installed[index].sourceHash = remote.hash
            installer.updateMetadata(for: build) {
                $0.builtAt = remote.date
                $0.sourceHash = remote.hash
            }
        }
    }

    // MARK: - Queries

    public func isLTS(_ version: String) -> Bool { ltsBranches.contains(version: version) }

    /// How many branches have anything installed in them — the number of
    /// headings the library draws.
    public var installedBranchCount: Int {
        BuildBranch.allCases.filter { branch in
            installed.contains { $0.branch == branch }
        }.count
    }

    /// The branch's builds, starred first, then newest version, then newest
    /// install.
    public func installed(in branch: BuildBranch) -> [InstalledBuild] {
        if let cached = installedByBranch[branch] { return cached }
        let items = installed
            .filter { $0.branch == branch }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                let lv = Version(lhs.version) ?? .zero
                let rv = Version(rhs.version) ?? .zero
                if lv != rv { return lv > rv }
                // Dailies share one version string for months, so the vintage
                // is what actually separates them.
                return lhs.buildDate > rhs.buildDate
            }
        installedByBranch[branch] = items
        return items
    }

    private func remote(in branch: BuildBranch) -> [RemoteBuild] {
        let raw: [RemoteBuild]
        switch branch {
        case .stable: raw = stable
        case .daily: raw = daily
        case .experimental: raw = experimental
        }
        return raw.filter { $0.parsedVersion >= minVersion }
    }

    /// Groups a branch's remote list by X.Y minor key for the catalogue view.
    /// Builds without a parseable minor key fall into single-element groups
    /// keyed by their raw version string. Groups are returned newest minor
    /// first; within a group, builds are sorted newest version first.
    public func remoteGrouped(in branch: BuildBranch) -> [RemoteBuildGroup] {
        if let cached = groupedRemote[branch] { return cached }
        let groups = groupRemote(in: branch)
        groupedRemote[branch] = groups
        return groups
    }

    /// True when no branch has anything to list — the catalogue's own empty
    /// state, asked once rather than re-grouping all three branches to find out.
    public var catalogueIsEmpty: Bool {
        BuildBranch.allCases.allSatisfy { remoteGrouped(in: $0).isEmpty }
    }

    private func groupRemote(in branch: BuildBranch) -> [RemoteBuildGroup] {
        var buckets: [String: [RemoteBuild]] = [:]
        var order: [String] = []
        for b in remote(in: branch) {
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

    public func isExpanded(_ key: String) -> Bool { expandedMinorKeys.contains(key) }

    public func toggleExpansion(_ key: String) {
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
    public func installedMatch(for remote: RemoteBuild) -> InstalledBuild? {
        let candidates = installed.filter { !$0.isCustom }
        if let exact = candidates.first(where: { $0.sourceURL == remote.url }) { return exact }
        guard let remoteBranch = BuildBranch(rawValue: remote.branch) else { return nil }
        return candidates.first {
            $0.sourceURL == nil && $0.version == remote.version && $0.branch == remoteBranch
        }
    }

    /// An installed build sharing `remote`'s branch and X.Y minor series,
    /// whether or not it's the exact version `remote` names — the catalogue's
    /// group header uses this to offer bringing that build up to the series'
    /// newest instead of installing the newest as a second, separate copy.
    /// `installedMatch` already covers the exact-version case, so callers
    /// should check that first.
    public func installedInSameSeries(as remote: RemoteBuild) -> InstalledBuild? {
        guard let remoteBranch = BuildBranch(rawValue: remote.branch),
              let key = remote.parsedVersion.minorKey else { return nil }
        return installed.first {
            !$0.isCustom && $0.branch == remoteBranch && Version($0.version)?.minorKey == key
        }
    }

    public func downloadState(_ id: String) -> DownloadState { downloads[id] ?? .idle }

    /// How far along the in-place update of this build is, or `.idle` when
    /// none is running — what the card paints over its own artwork.
    public func updateState(for build: InstalledBuild) -> DownloadState {
        guard let remoteID = updatingTargets[build.id] else { return .idle }
        return downloadState(remoteID)
    }

    /// The first-time installs filed under a branch.
    public func pending(in branch: BuildBranch) -> [PendingInstall] {
        pendingInstalls.filter { $0.branch == branch }
    }

    /// Everything a branch shows in the library, in one list: the builds
    /// installed there and the ones on their way, ordered together.
    ///
    /// A card that is downloading takes the place it will keep once it lands,
    /// rather than appearing at the head of the branch and then jumping to
    /// its real position on arrival — the version and vintage that decide
    /// where it belongs are both known before the first byte does.
    public func libraryRows(in branch: BuildBranch) -> [LibraryRow] {
        if let cached = libraryRowsByBranch[branch] { return cached }
        let rows = (installed(in: branch).map(LibraryRow.installed)
                    + pending(in: branch).map(LibraryRow.pending))
            .sorted { $0.sortsBefore($1) }
        libraryRowsByBranch[branch] = rows
        return rows
    }

    /// True when there is nothing to show in the library at all: nothing
    /// installed, and nothing on its way either.
    public var libraryIsEmpty: Bool { installed.isEmpty && pendingInstalls.isEmpty }

    // MARK: - Install / cancel / launch

    public func install(_ build: RemoteBuild, into branch: BuildBranch) {
        startInstall(of: build, branch: branch)
    }

    /// Downloads `target` and replaces `old` with the result. Star status
    /// transfers across. Blender stores prefs under a per-X.Y folder, so a
    /// within-minor patch picks up existing settings automatically — we just
    /// don't touch that folder.
    public func updateInstall(from old: InstalledBuild, to target: RemoteBuild) {
        startInstall(of: target, branch: old.branch, replacing: old)
    }

    /// Shared download-and-install pipeline. `old` marks the in-place-update
    /// case: the outgoing build is removed once the new one is in place, and
    /// its star carries over.
    private func startInstall(of target: RemoteBuild,
                              branch: BuildBranch,
                              replacing old: InstalledBuild? = nil) {
        guard downloads[target.id]?.isActive != true else { return }
        if let old {
            updatingTargets[old.id] = target.id
        } else if !pendingInstalls.contains(where: { $0.id == target.id }) {
            // The card goes into the library before the first byte does.
            pendingInstalls.append(PendingInstall(build: target, branch: branch))
        }
        downloads[target.id] = .queued
        downloadTasks[target.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let new = try await self.installer.install(target, branch: branch) { state in
                    self.downloads[target.id] = state
                }
                self.installed.append(new)
                // A daily's predecessor is kept as the rollback; every other
                // branch replaces outright.
                if let old, branch != .daily {
                    // The new build is in place either way. If the old one
                    // can't be removed it stays listed, because it is still
                    // on disk — see `uninstall(_:)`.
                    do {
                        try self.installer.uninstall(old)
                        self.installed.removeAll { $0.id == old.id }
                    } catch {
                        self.lastError = "Installed \(target.version), but could not remove "
                            + "\(old.version): \(error.localizedDescription)"
                    }
                }
                self.finishInstall(of: target, replacing: old)
                if old?.pinned == true {
                    // toggleStar enforces single-star and re-applies wiring.
                    self.toggleStar(new)
                }
                // After the star has moved, so the build that just landed is
                // the one the prune protects.
                if branch == .daily { self.pruneDailies(inSeriesOf: new) }
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
        pendingInstalls.removeAll { $0.id == target.id }
    }

    public func cancelDownload(_ build: RemoteBuild) {
        downloadManager.cancel(id: build.id)
        downloadTasks[build.id]?.cancel()
        downloadTasks[build.id] = nil
        downloads[build.id] = nil
        pendingInstalls.removeAll { $0.id == build.id }
    }

    public func launch(_ build: InstalledBuild) {
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

    public func reveal(_ build: InstalledBuild) {
        Task { await installer.reveal(build) }
    }

    public func revealLibrary() {
        Task { await platform.reveal(libraryURL) }
    }

    public func openInBrowser(_ string: String) {
        guard let url = URL(string: string) else { return }
        Task { await platform.openURL(url) }
    }

    /// Uninstalling a library build deletes its folder. A custom build — one
    /// the user already had on disk — is only forgotten; the files themselves
    /// are never touched.
    ///
    /// A delete that is refused leaves the build where it is and says so. The
    /// library folder defaults to `/Applications/Vitrine`, and macOS gates
    /// removing an app bundle there behind App Management, so this is a
    /// permission the user can actually be missing — dropping the row anyway
    /// would strand a gigabyte or two with nothing tracking it.
    public func uninstall(_ build: InstalledBuild) {
        if !build.isCustom {
            do {
                try installer.uninstall(build)
            } catch {
                lastError = "Could not uninstall Blender \(build.version): "
                    + error.localizedDescription
                return
            }
        }
        let removingStarred = build.pinned
        installed.removeAll { $0.id == build.id }
        if build.isCustom { persistCustomBuilds() }
        if removingStarred {
            Task { await platform.applyStarred(nil) }
        }
    }

    /// Single-star semantics: the targeted build becomes the *only* starred
    /// build (or is unstarred if it already was). The starred build is also
    /// wired into the desktop by the platform layer.
    public func toggleStar(_ build: InstalledBuild) {
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
    ///
    /// An older build also opts out once the update it would offer is already
    /// in the library under its own row: with 3.6.23 installed, 3.6.20 has
    /// nothing to update *to*, and 4.0.2 sitting under a 4.5.13 is a line
    /// somebody is keeping on purpose. So the button only appears when the
    /// target is newer than everything installed in that major.
    public func updateAvailable(for build: InstalledBuild) -> RemoteBuild? {
        guard !build.isCustom else { return nil }
        if build.branch == .daily { return dailyUpdate(for: build) }
        guard let installedV = Version(build.version),
              let key = installedV.minorKey,
              let major = installedV.major else { return nil }
        let pool: [RemoteBuild]
        switch build.branch {
        case .stable: pool = stable
        case .daily: pool = daily
        case .experimental: pool = experimental
        }
        guard let target = pool
            .filter({ $0.parsedVersion.minorKey == key && $0.parsedVersion > installedV })
            .max(by: { $0.parsedVersion < $1.parsedVersion })
        else { return nil }
        return alreadyInLibrary(atOrAbove: target.parsedVersion,
                                major: major,
                                branch: build.branch) ? nil : target
    }

    /// True when the same branch already holds a build of this major that is
    /// at least as new as `version`.
    private func alreadyInLibrary(atOrAbove version: Version,
                                  major: Int,
                                  branch: BuildBranch) -> Bool {
        installed.contains { other in
            guard !other.isCustom, other.branch == branch,
                  let v = Version(other.version), v.major == major else { return false }
            return !(v < version)
        }
    }

    /// A daily's update, which the version comparison above can never find:
    /// the builder rebuilds `main` every night under one version string —
    /// 5.3.0 alpha stays 5.3.0 alpha for months — and only the hash and the
    /// build date move. So a daily is compared by vintage instead, within its
    /// own X.Y series, and the newest listing wins whenever it is a different
    /// build than the one on disk.
    ///
    /// A build installed before Vitrine recorded hashes has no vintage to
    /// compare, so the newest daily is offered on the assumption that a
    /// months-old alpha is behind. Once it is taken, the question answers
    /// itself for good.
    private func dailyUpdate(for build: InstalledBuild) -> RemoteBuild? {
        guard let key = Version(build.version)?.minorKey,
              let target = daily
                .filter({ $0.parsedVersion.minorKey == key })
                .max(by: { $0.date < $1.date })
        else { return nil }
        // Same build by any identifier we hold: nothing to offer.
        if let installedHash = build.sourceHash, let remoteHash = target.hash {
            guard installedHash != remoteHash else { return nil }
        } else if let source = build.sourceURL, source == target.url {
            return nil
        }
        // The target is already here under its own row — which is exactly
        // what the kept rollback looks like right after an update. Offering
        // it again would download a build the library already holds.
        guard !dailyLibraryHolds(target, series: key, ignoring: build) else { return nil }
        guard build.hasBuildDate else { return target }
        return target.date > build.buildDate ? target : nil
    }

    /// True when some other daily of this series is already the target build,
    /// or newer than it.
    private func dailyLibraryHolds(_ target: RemoteBuild,
                                   series key: String,
                                   ignoring build: InstalledBuild) -> Bool {
        installed.contains { other in
            guard other.id != build.id, other.branch == .daily, !other.isCustom,
                  Version(other.version)?.minorKey == key else { return false }
            if let mine = other.sourceHash, let theirs = target.hash, mine == theirs {
                return true
            }
            return other.hasBuildDate && other.buildDate >= target.date
        }
    }

    /// How many builds a daily series keeps: tonight's, and the one it
    /// replaced. Alphas break, and the fix is almost always yesterday's build,
    /// so an update leaves that one standing instead of deleting it — but only
    /// that one, or the folder fills with copies of a single version number.
    public static let dailyKeepCount = 2

    /// Trims a daily series back to `dailyKeepCount`, newest vintage first.
    /// The starred build is never removed, however old it is: a star is a
    /// deliberate choice, and this runs without asking.
    private func pruneDailies(inSeriesOf build: InstalledBuild) {
        let key = Version(build.version)?.minorKey
        let ordered = installed
            .filter { $0.branch == .daily && !$0.isCustom
                && Version($0.version)?.minorKey == key }
            .sorted { $0.buildDate > $1.buildDate }
        for stale in ordered.dropFirst(Self.dailyKeepCount) where !stale.pinned {
            uninstall(stale)
        }
    }

    /// True while an in-place update for this build is downloading.
    public func isUpdating(_ build: InstalledBuild) -> Bool {
        guard let remoteID = updatingTargets[build.id] else { return false }
        return downloadState(remoteID).isActive
    }

    // MARK: - Custom (user-added local builds)

    /// Adds an externally-installed Blender to the Vitrine. It stays where the
    /// user has it; we only track a reference, filed under `branch`.
    public func addCustomBuild(at url: URL, into branch: BuildBranch) {
        guard !installed.contains(where: { $0.buildPath == url }) else { return }
        Task {
            let version = await platform.version(ofBuildAt: url)
                ?? url.deletingPathExtension().lastPathComponent
            installed.append(InstalledBuild(
                id: UUID(),
                version: version,
                riskId: InstalledBuild.customRiskID,
                branch: branch,
                installedAt: Date(),
                lastLaunchedAt: nil,
                sourceURL: nil,
                buildPath: url,
                pinned: false
            ))
            persistCustomBuilds()
        }
    }

    /// Custom builds live outside the library folder, so walking it can't
    /// rediscover them — they're carried in the config file instead.
    private func persistCustomBuilds() {
        settings.customBuilds = installed.filter { $0.isCustom }
        config.save(settings)
    }

    public func reloadInstalled() {
        // Drop entries whose build vanished (moved or deleted outside Vitrine).
        let customs = settings.customBuilds.filter {
            FileManager.default.fileExists(atPath: $0.buildPath.path)
        }
        installed = installer.discoverInstalled() + customs
    }

    // MARK: - Settings mutation
    //
    // Written as a method rather than a settable property: it persists to
    // disk and re-queries, which is more than a caller should trigger by
    // assigning to a field.

    /// The floors offered in the UI. Every entry opens a Blender series that
    /// people still reach back for; scraping below 2.80 means walking a
    /// decade of directories for builds nobody installs.
    public static let minVersionChoices = [
        "2.80", "2.93", "3.0", "3.3", "3.6", "4.0", "4.2", "4.5", "5.0"
    ]

    /// Rejects anything that isn't a version, leaving the current value in
    /// place, and reports whether it took.
    @discardableResult
    public func setMinVersion(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard Version(trimmed) != nil else { return false }
        guard trimmed != minVersionString else { return true }
        minVersionString = trimmed
        settings.minVersion = trimmed
        config.save(settings)
        // Re-fetch the stable archive against the new threshold; daily and
        // experimental are short lists, so filtering in memory is enough.
        // The newest stable release can change with it, so the artwork is
        // re-checked too.
        Task {
            await refreshStable()
            await refreshSplash()
        }
        return true
    }
}
