import Foundation
import AppKit

/// Layout (Blender Launcher convention):
///
///   <libraryRoot>/
///     stable/<build-id>/Blender.app
///                       .vitrine.json    ← per-build metadata
///     daily/...
///     experimental/...
///
/// `<build-id>` is the dmg basename without extension, e.g.
/// `blender-4.2.20-stable+v42.6df22026265d-darwin.arm64-release`.
/// Per-build JSON makes the install layout self-describing — a fresh launch
/// of Vitrine can rediscover everything by walking the folder.
struct BuildMetadata: Codable, Sendable {
    var buildID: UUID
    var version: String
    var riskId: String
    var branch: BuildBranch
    var installedAt: Date
    var lastLaunchedAt: Date?
    var sourceURL: URL?
    var pinned: Bool

    static let fileName = ".vitrine.json"
}

enum InstallError: LocalizedError {
    case noAppInDMG
    case hdiutilAttach(String)
    case unreadableMountOutput
    case outsideLibrary(String)

    var errorDescription: String? {
        switch self {
        case .noAppInDMG:
            return "No .app found in mounted DMG"
        case .hdiutilAttach(let stderr):
            return "hdiutil attach failed: \(stderr)"
        case .unreadableMountOutput:
            return "Could not parse hdiutil output"
        case .outsideLibrary(let path):
            return "Refusing to remove \(path) — it is outside the build library"
        }
    }
}

final class Installer: Sendable {
    let libraryRoot: URL
    let downloads: DownloadManager

    init(libraryRoot: URL, downloads: DownloadManager) {
        self.libraryRoot = libraryRoot
        self.downloads = downloads
    }

    /// Runs off the main actor on purpose: mounting, copying (Blender.app is
    /// 1–2 GB) and detaching all block their thread, and on the main actor
    /// they froze the UI for the whole "Installing…" phase. Only `progress`
    /// hops back to main.
    func install(_ build: RemoteBuild,
                 branch: BuildBranch,
                 progress: @MainActor @escaping (DownloadState) -> Void) async throws -> InstalledBuild {
        try ensureLibraryExists()
        await progress(.queued)

        let dmgURL = try await downloads.download(build.url, id: build.id) { p in
            Task { @MainActor in
                progress(.downloading(received: p.received, total: p.total, bytesPerSecond: p.bytesPerSecond))
            }
        }
        defer { try? FileManager.default.removeItem(at: dmgURL) }
        await progress(.installing)

        let buildID = (build.fileName as NSString).deletingPathExtension
        let destFolder = folder(for: branch).appendingPathComponent(buildID, isDirectory: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

        let appPath = try await mountAndCopy(dmgURL: dmgURL, into: destFolder)

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
            appPath: appPath,
            pinned: false
        )
    }

    func launch(_ build: InstalledBuild) {
        NSWorkspace.shared.open(build.appPath)
    }

    func reveal(_ build: InstalledBuild) {
        NSWorkspace.shared.activateFileViewerSelecting([build.appPath])
    }

    /// Deletes the build's container folder. Guarded to paths inside the
    /// library so a mis-tracked entry — say a custom build whose parent is
    /// ~/Downloads — can never take an unrelated folder with it.
    func uninstall(_ build: InstalledBuild) throws {
        let folder = build.appPath.deletingLastPathComponent()
        guard isInsideLibrary(folder) else {
            throw InstallError.outsideLibrary(folder.path)
        }
        try FileManager.default.removeItem(at: folder)
    }

    func updateMetadata(for build: InstalledBuild,
                        mutate: (inout BuildMetadata) -> Void) {
        let folder = build.appPath.deletingLastPathComponent()
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

    /// Walk the library to rediscover all installs. The single source of truth
    /// is the on-disk metadata, not a separate manifest file — so a user could
    /// move builds between branch folders manually and the app would still see
    /// them.
    func discoverInstalled() -> [InstalledBuild] {
        var result: [InstalledBuild] = []
        for branch in BuildBranch.allCases {
            let branchURL = folder(for: branch)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: branchURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for buildDir in entries where buildDir.hasDirectoryPath {
                guard let app = findApp(in: buildDir) else { continue }
                let meta = try? readMetadata(from: buildDir)
                let installed = InstalledBuild(
                    id: meta?.buildID ?? UUID(),
                    version: meta?.version ?? buildDir.lastPathComponent,
                    riskId: meta?.riskId ?? branch.rawValue,
                    branch: meta?.branch ?? branch,
                    installedAt: meta?.installedAt ?? Date(),
                    lastLaunchedAt: meta?.lastLaunchedAt,
                    sourceURL: meta?.sourceURL,
                    appPath: app,
                    pinned: meta?.pinned ?? false
                )
                result.append(installed)
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
            try? FileManager.default.createDirectory(at: folder(for: branch), withIntermediateDirectories: true)
        }
    }

    private func findApp(in folder: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return nil }
        return entries.first { $0.pathExtension == "app" }
    }

    private func writeMetadata(_ meta: BuildMetadata, into folder: URL) throws {
        let url = folder.appendingPathComponent(BuildMetadata.fileName)
        let data = try JSONEncoder().encode(meta)
        try data.write(to: url, options: .atomic)
    }

    private func readMetadata(from folder: URL) throws -> BuildMetadata {
        let url = folder.appendingPathComponent(BuildMetadata.fileName)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BuildMetadata.self, from: data)
    }

    // MARK: - DMG

    private func mountAndCopy(dmgURL: URL, into destFolder: URL) async throws -> URL {
        let mountPoint = try await attach(dmgURL)
        do {
            let appPath = try copyApp(from: mountPoint, into: destFolder)
            await detach(mountPoint)
            return appPath
        } catch {
            await detach(mountPoint)
            throw error
        }
    }

    private func copyApp(from mountPoint: String, into destFolder: URL) throws -> URL {
        let mountDir = URL(fileURLWithPath: mountPoint, isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(
            at: mountDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard let appOnDMG = entries.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.noAppInDMG
        }
        let dest = destFolder.appendingPathComponent(appOnDMG.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: appOnDMG, to: dest)
        return dest
    }

    private func attach(_ dmg: URL) async throws -> String {
        let result = try await Self.run("/usr/bin/hdiutil",
                                        ["attach", "-nobrowse", "-noverify", "-noautoopen", "-plist", dmg.path])
        guard result.status == 0 else {
            throw InstallError.hdiutilAttach(String(data: result.stderr, encoding: .utf8) ?? "")
        }
        guard let plist = try PropertyListSerialization.propertyList(from: result.stdout, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw InstallError.unreadableMountOutput
        }
        return mount
    }

    private func detach(_ mountPoint: String) async {
        // Best-effort; -force covers files the copy may still hold open.
        _ = try? await Self.run("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
    }

    private struct ToolResult {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    /// Async wrapper around Process so callers never block on waitUntilExit.
    /// Output is read inside the termination handler, which is safe here:
    /// hdiutil's plist output stays far below the 64 KB pipe buffer, so the
    /// process can't stall on a full pipe before exiting.
    private static func run(_ tool: String, _ arguments: [String]) async throws -> ToolResult {
        try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: tool)
            proc.arguments = arguments
            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err
            proc.terminationHandler = { finished in
                cont.resume(returning: ToolResult(
                    status: finished.terminationStatus,
                    stdout: out.fileHandleForReading.readDataToEndOfFile(),
                    stderr: err.fileHandleForReading.readDataToEndOfFile()
                ))
            }
            do {
                try proc.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
