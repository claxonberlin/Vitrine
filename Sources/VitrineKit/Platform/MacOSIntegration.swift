#if os(macOS)
import Foundation
import AppKit
import UniformTypeIdentifiers

/// macOS half of `PlatformIntegration`.
///
/// Starring a build wires it into the system four ways:
///   1. Double-clicking a `.blend` opens that version (LaunchServices).
///   2. `blender` in Terminal launches it (PATH symlink).
///   3. `/Applications/Blender` resolves to it.
///   4. It is pinned to the Dock.
///
/// All of it is best-effort. If the environment doesn't permit writing into a
/// system bin directory we fall back to `~/.local/bin`, and the
/// `/Applications/Blender` alias is only touched when it is absent or is a
/// symlink we installed — a real Blender the user put there is never removed.
struct MacOSIntegration: PlatformIntegration {
    var defaultLibraryRoot: URL {
        URL(fileURLWithPath: "/Applications/Vitrine", isDirectory: true)
    }

    var configDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Vitrine", isDirectory: true)
    }

    var buildPlatform: BuildPlatform {
        BuildPlatform(
            builderToken: "darwin",
            archiveSuffixes: [".dmg"],
            nameMarkers: ["darwin", "macos", "osx"],
            architectures: Platform.architectureAliases
        )
    }

    var fileManagerName: String { "Finder" }
    var supportsLauncherPin: Bool { true }
    /// A `.app` is a bundle: the open panel offers it as a selectable file.
    var buildIsDirectory: Bool { false }

    /// Locations probed for the PATH symlink, in order of preference.
    /// `/opt/homebrew/bin` is the Apple Silicon Homebrew default and is
    /// usually writable by an admin user; `/usr/local/bin` is the Intel
    /// equivalent. `~/.local/bin` is the universal user-writable fallback,
    /// though it requires the user to put it on PATH themselves.
    static let symlinkCandidates: [String] = [
        "/opt/homebrew/bin/blender",
        "/usr/local/bin/blender",
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/blender")
    ]

    static let applicationsAliasPath = "/Applications/Blender"
    /// Older Vitrine builds created `/Applications/Blender.app`. Cleared on apply.
    private static let legacyApplicationsAliasPath = "/Applications/Blender.app"

    // MARK: - Install

    func extract(archive: URL, into destination: URL) async throws -> URL {
        let mountPoint = try await attach(archive)
        do {
            let appPath = try copyApp(from: mountPoint, into: destination)
            await detach(mountPoint)
            return appPath
        } catch {
            await detach(mountPoint)
            throw error
        }
    }

    func findBuild(in folder: URL) -> URL? {
        let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )
        return entries?.first { $0.pathExtension == "app" }
    }

    func version(ofBuildAt url: URL) async -> String? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String,
              !version.isEmpty
        else { return nil }
        return version
    }

    func launch(_ buildPath: URL) throws {
        NSWorkspace.shared.open(buildPath)
    }

    func reveal(_ url: URL) async {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openURL(_ url: URL) async {
        NSWorkspace.shared.open(url)
    }

    // MARK: - System wiring

    func applyStarred(_ build: InstalledBuild?) async {
        registerDefaultBlendHandler(for: build)
        updateSymlink(for: build)
        updateApplicationsAlias(for: build)
        await updateDockPin(for: build)
    }

    private func registerDefaultBlendHandler(for build: InstalledBuild?) {
        guard let build, let blendType = blendUTType() else { return }
        Task.detached {
            try? await NSWorkspace.shared.setDefaultApplication(
                at: build.buildPath, toOpen: blendType
            )
        }
    }

    private func blendUTType() -> UTType? {
        if let declared = UTType("org.blender.blend") { return declared }
        return UTType.types(tag: "blend", tagClass: .filenameExtension, conformingTo: nil).first
    }

    private func updateSymlink(for build: InstalledBuild?) {
        // Remove any symlink we own (i.e. one pointing into a Blender.app)
        // before placing a new one — keeps things clean when un-starring or
        // moving installs around.
        clearOwnedSymlinks()
        guard let build else { return }

        let target = build.buildPath.appendingPathComponent("Contents/MacOS/Blender")
        guard FileManager.default.fileExists(atPath: target.path) else { return }

        for path in Self.symlinkCandidates {
            let url = URL(fileURLWithPath: path)
            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                // Only auto-create user-owned directories; never try to mkdir
                // /opt/homebrew/bin or /usr/local/bin if they don't exist.
                guard path.hasPrefix(NSHomeDirectory()) else { continue }
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            if (try? FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)) != nil {
                return
            }
        }
    }

    private func clearOwnedSymlinks() {
        for path in Self.symlinkCandidates {
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                continue
            }
            // Only delete links into a Blender.app — otherwise we might wipe a
            // Homebrew or user-installed `blender` binary.
            if dest.contains("Blender.app/Contents/MacOS/") {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    /// Maintains `/Applications/Blender` as a symlink to the starred build.
    /// Dropping the `.app` extension keeps the entry tidy in /Applications;
    /// LaunchServices resolves the symlink before deciding it's a bundle, so
    /// double-clicking the link still launches Blender. A real (non-symlink)
    /// file at that path is left untouched.
    private func updateApplicationsAlias(for build: InstalledBuild?) {
        let fm = FileManager.default
        for path in [Self.applicationsAliasPath, Self.legacyApplicationsAliasPath] {
            if let dest = try? fm.destinationOfSymbolicLink(atPath: path),
               dest.contains("Blender.app") {
                try? fm.removeItem(atPath: path)
            }
        }
        guard let build else { return }
        let target = URL(fileURLWithPath: Self.applicationsAliasPath)
        if fm.fileExists(atPath: target.path) { return }  // real file in the way
        try? fm.createSymbolicLink(at: target, withDestinationURL: build.buildPath)
    }

    /// Pins (or unpins) the starred build in the Dock by rewriting
    /// `com.apple.dock`'s `persistent-apps` list and bouncing the Dock. macOS
    /// exposes no public API for this: Dock only reads its plist at startup,
    /// so `defaults write` + `killall Dock` is the canonical approach used by
    /// `dockutil` and Apple's own preference panes.
    private func updateDockPin(for build: InstalledBuild?) async {
        guard let dock = UserDefaults(suiteName: "com.apple.dock") else { return }
        var apps = (dock.array(forKey: "persistent-apps") as? [[String: Any]]) ?? []
        let initialApps = apps

        apps.removeAll { tile in
            guard let s = tileURLString(tile) else { return false }
            return s.contains(Self.legacyApplicationsAliasPath)
                || s.hasSuffix("/Blender.app/")
                || s.hasSuffix("/Blender.app")
        }

        if let build {
            var urlString = build.buildPath.absoluteString
            if !urlString.hasSuffix("/") { urlString += "/" }
            apps.append([
                "tile-type": "file-tile",
                "tile-data": [
                    "file-label": "Blender",
                    "file-type": 41,
                    "file-data": [
                        "_CFURLString": urlString,
                        "_CFURLStringType": 15
                    ] as [String: Any]
                ] as [String: Any]
            ])
        }

        // Nothing changed — skip the synchronize and the Dock restart.
        guard !persistentAppsEqual(apps, initialApps) else { return }

        dock.set(apps, forKey: "persistent-apps")
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        try? await Shell.run("killall", ["Dock"])
    }

    private func tileURLString(_ tile: [String: Any]) -> String? {
        guard let tileData = tile["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any] else { return nil }
        return fileData["_CFURLString"] as? String
    }

    /// Cheap equality on persistent-apps — compares each tile's URL string,
    /// which is all we touch. Lets us skip the Dock restart when the star
    /// state already lines up with the existing pin.
    private func persistentAppsEqual(_ a: [[String: Any]], _ b: [[String: Any]]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where tileURLString(x) != tileURLString(y) { return false }
        return true
    }

    // MARK: - DMG

    private func copyApp(from mountPoint: String, into destFolder: URL) throws -> URL {
        let mountDir = URL(fileURLWithPath: mountPoint, isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(
            at: mountDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        guard let appOnDMG = entries.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.noBuildInArchive
        }
        let dest = destFolder.appendingPathComponent(appOnDMG.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: appOnDMG, to: dest)
        return dest
    }

    private func attach(_ dmg: URL) async throws -> String {
        let result = try await Shell.run(
            "hdiutil",
            ["attach", "-nobrowse", "-noverify", "-noautoopen", "-plist", dmg.path]
        )
        guard result.ok else {
            throw InstallError.extractionFailed(result.stderrText)
        }
        guard let plist = try PropertyListSerialization.propertyList(
                  from: result.stdout, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw InstallError.extractionFailed("could not parse hdiutil output")
        }
        return mount
    }

    private func detach(_ mountPoint: String) async {
        // Best-effort; -force covers files the copy may still hold open.
        try? await Shell.run("hdiutil", ["detach", mountPoint, "-force"])
    }
}
#endif
