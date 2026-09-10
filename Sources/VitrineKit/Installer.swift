import Foundation

/// Library layout, identical on both platforms:
///
///   <libraryRoot>/
///     stable/<build-id>/Blender.app          (macOS)
///     stable/<build-id>/blender-4.2.1-linux-x64/   (Linux)
///                       .vitrine.json        ← per-build metadata
///     daily/...
///     experimental/...
///
/// `<build-id>` is the archive basename without extension. Per-build JSON
/// makes the layout self-describing — a fresh launch rediscovers everything
/// by walking the folder, with no central manifest to fall out of sync.
public struct BuildMetadata: Codable, Sendable {
    public var buildID: UUID
    public var version: String
    public var riskId: String
    public var branch: BuildBranch
    public var installedAt: Date
    public var lastLaunchedAt: Date?
    public var sourceURL: URL?
    public var pinned: Bool

    public static let fileName = ".vitrine.json"
}

public enum InstallError: LocalizedError {
    case noBuildInArchive
    case extractionFailed(String)
    case outsideLibrary(String)

    public var errorDescription: String? {
        switch self {
        case .noBuildInArchive:
            return "No Blender build found inside the downloaded archive"
        case .extractionFailed(let detail):
            return "Could not unpack the archive: \(detail)"
        case .outsideLibrary(let path):
            return "Refusing to remove \(path) — it is outside the build library"
        }
    }
}

/// Download-and-unpack pipeline plus library bookkeeping. Everything here is
/// platform-neutral; the two steps that differ per OS — unpacking an archive
/// and recognising an installed build — are delegated to `PlatformIntegration`.
public final class Installer: Sendable {
    let libraryRoot: URL
    let downloads: DownloadManager
    let platform: any PlatformIntegration

    public init(libraryRoot: URL,
                downloads: DownloadManager,
                platform: any PlatformIntegration = Platform.current) {
        self.libraryRoot = libraryRoot
        self.downloads = downloads
        self.platform = platform
    }

    /// Runs off the main actor on purpose: unpacking is slow (Blender is
    /// 1–2 GB once expanded) and on the main actor it froze the UI for the
    /// whole "Installing…" phase. Only `progress` hops back to main.
    public func install(_ build: RemoteBuild,
                        branch: BuildBranch,
                        progress: @MainActor @escaping (DownloadState) -> Void) async throws -> InstalledBuild {
        try ensureLibraryExists()
        await progress(.queued)

        let archiveURL = try await downloads.download(build.url, id: build.id) { p in
            Task { @MainActor in
                progress(.downloading(received: p.received, total: p.total,
                                      bytesPerSecond: p.bytesPerSecond))
            }
        }
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        // Zero rather than "no idea" wherever the unpack can be watched: the
        // row has just finished filling its download bar, and a band sweeping
        // across it for the one beat before the first measurement arrives
        // reads as the work starting over.
        await progress(.installing(fraction: platform.reportsInstallProgress ? 0 : nil))

        let buildID = stripArchiveExtension(build.fileName)
        let destFolder = folder(for: branch).appendingPathComponent(buildID, isDirectory: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

        let buildPath = try await platform.extract(archive: archiveURL, into: destFolder) { fraction in
            Task { @MainActor in progress(.installing(fraction: fraction)) }
        }

        let metadata = BuildMetadata(
            buildID: UUID(),
            version: build.version,
            riskId: build.riskId,
            branch: branch,
            installedAt: Date(),
            lastLaunchedAt: nil,
            sourceURL: build.url,
            pinned: false
        )
        try writeMetadata(metadata, into: destFolder)

        return InstalledBuild(
            id: metadata.buildID,
            version: build.version,
            riskId: build.riskId,
            branch: branch,
            installedAt: metadata.installedAt,
            lastLaunchedAt: nil,
            sourceURL: build.url,
            buildPath: buildPath,
            pinned: false
        )
    }

    public func launch(_ build: InstalledBuild) throws {
        try platform.launch(build.buildPath)
    }

    public func reveal(_ build: InstalledBuild) async {
        await platform.reveal(build.buildPath)
    }

    /// Deletes the build's container folder. Guarded to paths inside the
    /// library so a mis-tracked entry — say a custom build whose parent is
    /// ~/Downloads — can never take an unrelated folder with it.
    public func uninstall(_ build: InstalledBuild) throws {
        let folder = build.buildPath.deletingLastPathComponent()
        guard isInsideLibrary(folder) else {
            throw InstallError.outsideLibrary(folder.path)
        }
        try FileManager.default.removeItem(at: folder)
    }

    public func updateMetadata(for build: InstalledBuild,
                               mutate: (inout BuildMetadata) -> Void) {
        let folder = build.buildPath.deletingLastPathComponent()
        // Never drop a .vitrine.json outside the library — a custom build's
        // folder belongs to the user, not to Vitrine.
        guard isInsideLibrary(folder) else { return }
        var meta = (try? readMetadata(from: folder)) ?? BuildMetadata(
            buildID: build.id,
            version: build.version,
            riskId: build.riskId,
            branch: build.branch,
            installedAt: build.installedAt,
            lastLaunchedAt: build.lastLaunchedAt,
            sourceURL: build.sourceURL,
            pinned: build.pinned
        )
        mutate(&meta)
        try? writeMetadata(meta, into: folder)
    }

    /// Walks the library to rediscover all installs. On-disk metadata is the
    /// single source of truth, not a separate manifest — so a user can move
    /// builds between branch folders by hand and Vitrine still sees them.
    public func discoverInstalled() -> [InstalledBuild] {
        var result: [InstalledBuild] = []
        for branch in BuildBranch.allCases {
            let branchURL = folder(for: branch)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: branchURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for buildDir in entries where buildDir.hasDirectoryPath {
                guard let buildPath = platform.findBuild(in: buildDir) else { continue }
                let meta = try? readMetadata(from: buildDir)
                result.append(InstalledBuild(
                    id: meta?.buildID ?? UUID(),
                    version: meta?.version ?? buildDir.lastPathComponent,
                    riskId: meta?.riskId ?? branch.rawValue,
                    branch: meta?.branch ?? branch,
                    installedAt: meta?.installedAt ?? Date(),
                    lastLaunchedAt: meta?.lastLaunchedAt,
                    sourceURL: meta?.sourceURL,
                    buildPath: buildPath,
                    pinned: meta?.pinned ?? false
                ))
            }
        }
        return result
    }

    // MARK: - Helpers

    private func folder(for branch: BuildBranch) -> URL {
        libraryRoot.appendingPathComponent(branch.rawValue, isDirectory: true)
    }

    /// Vitrine only ever owns `<libraryRoot>/<branch>/<build-id>/` folders.
    /// The root itself fails the check too — it is never deleted wholesale.
    private func isInsideLibrary(_ folder: URL) -> Bool {
        let root = libraryRoot.standardizedFileURL.path
        return folder.standardizedFileURL.path.hasPrefix(root + "/")
    }

    private func ensureLibraryExists() throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        for branch in BuildBranch.allCases {
            try? FileManager.default.createDirectory(at: folder(for: branch),
                                                     withIntermediateDirectories: true)
        }
    }

    /// "blender-4.2.1-linux-x64.tar.xz" → "blender-4.2.1-linux-x64".
    /// `deletingPathExtension` alone would leave the ".tar".
    private func stripArchiveExtension(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        for suffix in platform.buildPlatform.archiveSuffixes where lower.hasSuffix(suffix) {
            return String(fileName.dropLast(suffix.count))
        }
        return (fileName as NSString).deletingPathExtension
    }

    private func writeMetadata(_ meta: BuildMetadata, into folder: URL) throws {
        let url = folder.appendingPathComponent(BuildMetadata.fileName)
        try JSONEncoder().encode(meta).write(to: url, options: .atomic)
    }

    private func readMetadata(from folder: URL) throws -> BuildMetadata {
        let url = folder.appendingPathComponent(BuildMetadata.fileName)
        return try JSONDecoder().decode(BuildMetadata.self, from: Data(contentsOf: url))
    }
}
