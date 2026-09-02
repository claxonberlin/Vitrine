import Foundation
import AppKit
import UniformTypeIdentifiers

/// Wires the starred build into macOS so that:
///
///   1. Double-clicking a `.blend` file opens that version (default app).
///   2. Running `blender` in Terminal launches that version (PATH symlink).
///   3. `/Applications/Blender` resolves to the starred build.
///   4. The starred build itself is pinned to the Dock.
///
/// All operations are best-effort — if the user's environment doesn't permit
/// writing into a system bin directory, we fall back to `~/.local/bin`. The
/// `/Applications/Blender` alias is only touched if it doesn't already exist
/// or is a symlink we previously installed (we never overwrite a real Blender
/// install the user may have placed there).
enum SystemIntegration {
    /// Locations probed for the PATH symlink, in order of preference.
    /// `/opt/homebrew/bin` is the Apple Silicon Homebrew default and is
    /// usually writable by an admin user; `/usr/local/bin` is the Intel
    /// equivalent. `~/.local/bin` is the universal user-writable fallback,
    /// though it requires the user to add it to `PATH` themselves.
    static let symlinkCandidates: [String] = [
        "/opt/homebrew/bin/blender",
        "/usr/local/bin/blender",
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/blender")
    ]

    static let applicationsAliasPath = "/Applications/Blender"
    /// Older builds created `/Applications/Blender.app`. Cleared on apply.
    private static let legacyApplicationsAliasPath = "/Applications/Blender.app"

    static func apply(starred: InstalledBuild?) {
        registerDefaultBlendHandler(for: starred)
        updateSymlink(for: starred)
        updateApplicationsAlias(for: starred)
        updateDockPin(for: starred)
    }

    private static func registerDefaultBlendHandler(for build: InstalledBuild?) {
        guard let build else { return }
        guard let blendType = blendUTType() else { return }
        Task.detached {
            try? await NSWorkspace.shared.setDefaultApplication(
                at: build.appPath,
                toOpen: blendType
            )
        }
    }

    private static func blendUTType() -> UTType? {
        if let declared = UTType("org.blender.blend") { return declared }
        return UTType.types(tag: "blend",
                            tagClass: .filenameExtension,
                            conformingTo: nil).first
    }

    private static func updateSymlink(for build: InstalledBuild?) {
        // Remove any existing symlinks we own (i.e. links pointing into a
        // Blender.app bundle) before placing a new one — keeps things clean
        // when un-starring or moving installs around.
        clearOwnedSymlinks()
        guard let build else { return }

        let target = build.appPath
            .appendingPathComponent("Contents/MacOS/Blender")
        guard FileManager.default.fileExists(atPath: target.path) else { return }

        for path in symlinkCandidates {
            let url = URL(fileURLWithPath: path)
            let dir = url.deletingLastPathComponent()

            if !FileManager.default.fileExists(atPath: dir.path) {
                // Only auto-create user-owned directories; never try to mkdir
                // /opt/homebrew/bin or /usr/local/bin if they don't exist.
                guard path.hasPrefix(NSHomeDirectory()) else { continue }
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            do {
                try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
                return
            } catch {
                continue
            }
        }
    }

    private static func clearOwnedSymlinks() {
        for path in symlinkCandidates {
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                continue
            }
            // Only delete if the link points into a Blender.app — otherwise
            // we might wipe a Homebrew or user-installed `blender` binary.
            if dest.contains("Blender.app/Contents/MacOS/") {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    /// Maintains `/Applications/Blender` as a symlink to the starred build.
    /// Dropping the `.app` extension keeps the entry tidy in /Applications;
    /// LaunchServices resolves the symlink before deciding it's a bundle,
    /// so double-clicking the link still launches Blender. If a real (non-
    /// symlink) file sits at the path — e.g. a hand-managed install — we
    /// leave it untouched.
    private static func updateApplicationsAlias(for build: InstalledBuild?) {
        let fm = FileManager.default

        // Clear any prior Vitrine-owned link at either the current path or
        // the legacy `.app` path created by earlier builds. Preserve anything
        // that isn't a symlink into a Blender.app bundle.
        for path in [applicationsAliasPath, legacyApplicationsAliasPath] {
            if let dest = try? fm.destinationOfSymbolicLink(atPath: path),
               dest.contains("Blender.app") {
                try? fm.removeItem(atPath: path)
            }
        }

        guard let build else { return }
        let target = URL(fileURLWithPath: applicationsAliasPath)
        if fm.fileExists(atPath: target.path) { return }  // real file in the way
        try? fm.createSymbolicLink(at: target, withDestinationURL: build.appPath)
    }

    /// Pins (or unpins) the starred build in the user's Dock. We rewrite
    /// `com.apple.dock`'s `persistent-apps` list with a tile pointing at the
    /// real .app bundle (not the /Applications symlink), strip any prior
    /// Blender entry, then bounce the Dock. macOS doesn't expose a public
    /// API for adding Dock items without restarting Dock — Dock only reads
    /// its plist at startup, so `defaults write` + `killall Dock` is the
    /// canonical approach used by `dockutil` and Apple's own preference
    /// panes. `CFPreferencesAppSynchronize` first to make sure the write is
    /// flushed before Dock relaunches and reads its prefs.
    private static func updateDockPin(for build: InstalledBuild?) {
        guard let dock = UserDefaults(suiteName: "com.apple.dock") else { return }
        var apps = (dock.array(forKey: "persistent-apps") as? [[String: Any]]) ?? []
        let initialApps = apps

        apps.removeAll { tile in
            guard let s = tileURLString(tile) else { return false }
            // Strip prior Vitrine-managed pins: the legacy /Applications
            // alias and any tile pointing into a Blender.app bundle.
            return s.contains(legacyApplicationsAliasPath)
                || s.hasSuffix("/Blender.app/")
                || s.hasSuffix("/Blender.app")
        }

        if let build {
            var urlString = build.appPath.absoluteString
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

        // Nothing actually changed — skip the synchronize + restart entirely.
        guard !persistentAppsEqual(apps, initialApps) else { return }

        dock.set(apps, forKey: "persistent-apps")
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = ["Dock"]
        try? proc.run()
    }

    private static func tileURLString(_ tile: [String: Any]) -> String? {
        guard let tileData = tile["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any] else { return nil }
        return fileData["_CFURLString"] as? String
    }

    /// Cheap equality check on the persistent-apps array — compares each
    /// tile's URL string, which is all we touch. Lets us skip the dock
    /// restart when star state lines up with the existing pin.
    private static func persistentAppsEqual(_ a: [[String: Any]], _ b: [[String: Any]]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where tileURLString(x) != tileURLString(y) { return false }
        return true
    }
}
