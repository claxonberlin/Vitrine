#if os(Linux)
import Foundation

/// Linux (Fedora Workstation / GNOME) half of `PlatformIntegration`.
///
/// The four macOS integrations map onto freedesktop equivalents:
///
///   | macOS                          | Linux                                    |
///   |--------------------------------|------------------------------------------|
///   | LaunchServices .blend handler  | `.desktop` file + `xdg-mime default`     |
///   | PATH symlink                   | `~/.local/bin/blender` (same idea)       |
///   | `/Applications/Blender` alias  | no equivalent — dropped                  |
///   | Dock pin                       | `org.gnome.shell favorite-apps`          |
///
/// Everything is best-effort and degrades quietly: a non-GNOME session simply
/// has no `gsettings` schema, which must not be an error.
struct LinuxIntegration: PlatformIntegration {
    var defaultLibraryRoot: URL {
        Platform.xdgDirectory("XDG_DATA_HOME", fallback: ".local/share")
            .appendingPathComponent("vitrine/builds", isDirectory: true)
    }

    var configDirectory: URL {
        Platform.xdgDirectory("XDG_CONFIG_HOME", fallback: ".config")
            .appendingPathComponent("vitrine", isDirectory: true)
    }

    var buildPlatform: BuildPlatform {
        BuildPlatform(
            builderToken: "linux",
            // Longest-first: ".tar.xz" must win over a bare ".xz" test.
            archiveSuffixes: [".tar.xz", ".tar.bz2", ".tar.gz"],
            nameMarkers: ["linux"],
            architectures: Platform.architectureAliases
        )
    }

    var fileManagerName: String { "Files" }
    /// Only meaningful under GNOME Shell; `applyStarred` re-checks at runtime.
    var supportsLauncherPin: Bool { true }
    /// A Linux build is an ordinary directory holding the `blender` binary.
    var buildIsDirectory: Bool { true }

    private static let desktopFileName = "vitrine-blender.desktop"
    private static let blendMimeType = "application/x-blender"

    private var applicationsDir: URL {
        Platform.xdgDirectory("XDG_DATA_HOME", fallback: ".local/share")
            .appendingPathComponent("applications", isDirectory: true)
    }

    private var desktopFileURL: URL {
        applicationsDir.appendingPathComponent(Self.desktopFileName)
    }

    /// `~/.local/bin` comes first here: on Fedora it is on PATH by default for
    /// login sessions, and unlike `/usr/local/bin` it needs no privilege.
    private static var symlinkCandidates: [URL] {
        [
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".local/bin/blender"),
            URL(fileURLWithPath: "/usr/local/bin/blender")
        ]
    }

    // MARK: - Install

    /// Blender's Linux tarballs hold a single top-level directory
    /// (`blender-4.2.1-linux-x64/`). We unpack into a staging folder so a
    /// malformed archive can't scatter files across the library, then move
    /// that one directory into place.
    func extract(archive: URL, into destination: URL) async throws -> URL {
        let fm = FileManager.default
        let staging = destination.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // `tar -xf` auto-detects xz/bzip2/gzip, so one call covers every
        // archive format Blender has shipped.
        let result = try await Shell.run("tar", ["-xf", archive.path, "-C", staging.path])
        guard result.ok else {
            throw InstallError.extractionFailed(result.stderrText)
        }

        let entries = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])
        // Normally one wrapper directory; tolerate an archive that unpacked
        // its contents flat by falling back to the staging folder itself.
        let unpacked = entries.first { $0.hasDirectoryPath && executable(in: $0) != nil }
            ?? (executable(in: staging) != nil ? staging : nil)
        guard let unpacked else { throw InstallError.noBuildInArchive }

        let dest = destination.appendingPathComponent(
            unpacked == staging ? archiveBaseName(archive) : unpacked.lastPathComponent,
            isDirectory: true
        )
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: unpacked, to: dest)
        return dest
    }

    func findBuild(in folder: URL) -> URL? {
        if executable(in: folder) != nil { return folder }
        let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        return entries?.first { $0.hasDirectoryPath && executable(in: $0) != nil }
    }

    func version(ofBuildAt url: URL) async -> String? {
        // The directory name is authoritative for builds we installed and
        // costs nothing to read.
        if let match = url.lastPathComponent.firstMatch(of: /blender-(\d+(?:\.\d+){1,2}[a-z]?)/) {
            return String(match.output.1)
        }
        // A build the user added by hand may live in an arbitrarily named
        // folder, so fall back to asking Blender itself.
        guard let exe = executable(in: url),
              let result = try? await Shell.run(exe.path, ["--version"]),
              result.ok
        else { return nil }
        // First line reads "Blender 4.2.1".
        guard let line = result.stdoutText.split(separator: "\n").first,
              let match = line.firstMatch(of: /Blender\s+(\d+(?:\.\d+){1,2}[a-z]?)/)
        else { return nil }
        return String(match.output.1)
    }

    func launch(_ buildPath: URL) throws {
        guard let exe = executable(in: buildPath) else {
            throw InstallError.noBuildInArchive
        }
        try Shell.spawnDetached(exe)
    }

    func reveal(_ url: URL) async {
        // Selects the item in the file manager rather than merely opening its
        // folder — the closest match to Finder's "Reveal".
        let shown = try? await Shell.run("dbus-send", [
            "--session", "--dest=org.freedesktop.FileManager1", "--type=method_call",
            "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems",
            "array:string:\(url.absoluteString)", "string:"
        ])
        if shown?.ok == true { return }
        try? await Shell.run("xdg-open", [url.deletingLastPathComponent().path])
    }

    func openURL(_ url: URL) async {
        try? await Shell.run("xdg-open", [url.absoluteString])
    }

    // MARK: - System wiring

    func applyStarred(_ build: InstalledBuild?) async {
        await updateDesktopEntry(for: build)
        updateSymlink(for: build)
        await updateMimeDefault(for: build)
        await updateShellFavorite(for: build)
    }

    /// The `.desktop` file is the linchpin on Linux: the MIME default and the
    /// GNOME favourite both reference it by name, so it is written first and
    /// removed last.
    private func updateDesktopEntry(for build: InstalledBuild?) async {
        let fm = FileManager.default
        guard let build, let exe = executable(in: build.buildPath) else {
            try? fm.removeItem(at: desktopFileURL)
            await refreshDesktopDatabase()
            return
        }
        try? fm.createDirectory(at: applicationsDir, withIntermediateDirectories: true)

        var entry = """
            [Desktop Entry]
            Type=Application
            Version=1.0
            Name=Blender
            GenericName=3D modeller
            Comment=Blender \(build.version) — managed by Vitrine
            Exec="\(exe.path)" %f
            Terminal=false
            Categories=Graphics;3DGraphics;
            MimeType=\(Self.blendMimeType);
            StartupWMClass=blender

            """
        // Icon= is omitted rather than pointed at a missing file: GNOME shows
        // a generic placeholder for a broken path, but falls back to the icon
        // theme when the key is absent.
        if let icon = iconPath(in: build.buildPath) {
            entry += "Icon=\(icon)\n"
        }
        try? entry.write(to: desktopFileURL, atomically: true, encoding: .utf8)
        await refreshDesktopDatabase()
    }

    private func refreshDesktopDatabase() async {
        guard await Shell.exists("update-desktop-database") else { return }
        try? await Shell.run("update-desktop-database", [applicationsDir.path])
    }

    private func updateMimeDefault(for build: InstalledBuild?) async {
        guard build != nil, await Shell.exists("xdg-mime") else { return }
        try? await Shell.run("xdg-mime", ["default", Self.desktopFileName, Self.blendMimeType])
    }

    private func updateSymlink(for build: InstalledBuild?) {
        clearOwnedSymlinks()
        guard let build, let exe = executable(in: build.buildPath) else { return }
        for link in Self.symlinkCandidates {
            let dir = link.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                // Only create directories under the user's home; never mkdir
                // /usr/local/bin.
                guard dir.path.hasPrefix(NSHomeDirectory()) else { continue }
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            if (try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: exe)) != nil {
                return
            }
        }
    }

    /// Only removes links that point into our own library, so a `blender`
    /// binary installed by dnf or placed there by the user survives.
    private func clearOwnedSymlinks() {
        for link in Self.symlinkCandidates {
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
            else { continue }
            if dest.hasSuffix("/blender") && dest.contains("blender-") {
                try? FileManager.default.removeItem(at: link)
            }
        }
    }

    /// GNOME Shell's dash. The equivalent of the macOS Dock pin, and equally
    /// unavailable through any public API — `gsettings` is the supported
    /// route. Absent on KDE and other desktops, which is not an error.
    private func updateShellFavorite(for build: InstalledBuild?) async {
        guard await Shell.exists("gsettings") else { return }
        guard let current = try? await Shell.run(
            "gsettings", ["get", "org.gnome.shell", "favorite-apps"]
        ), current.ok else { return }

        var favorites = parseGVariantList(current.stdoutText)
        favorites.removeAll { $0 == Self.desktopFileName }
        if build != nil { favorites.append(Self.desktopFileName) }

        let encoded = "[" + favorites.map { "'\($0)'" }.joined(separator: ", ") + "]"
        try? await Shell.run("gsettings", ["set", "org.gnome.shell", "favorite-apps", encoded])
    }

    /// `gsettings get` prints a GVariant array: `['a.desktop', 'b.desktop']`.
    private func parseGVariantList(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ",").compactMap {
            let item = $0.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return item.isEmpty ? nil : item
        }
    }

    // MARK: - Helpers

    /// The `blender` executable directly inside `folder`, if there is one.
    private func executable(in folder: URL) -> URL? {
        let candidate = folder.appendingPathComponent("blender")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    /// Blender ships its icon inside the versioned datafiles directory; the
    /// exact path moves between releases, so probe the known spellings.
    private func iconPath(in buildPath: URL) -> String? {
        let candidates = [
            "blender.svg",
            "blender.png",
            "blender-symbolic.svg"
        ].map { buildPath.appendingPathComponent($0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }

    /// "blender-4.2.1-linux-x64.tar.xz" → "blender-4.2.1-linux-x64"
    private func archiveBaseName(_ archive: URL) -> String {
        var name = archive.lastPathComponent
        for suffix in buildPlatform.archiveSuffixes where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return name
    }
}
#endif
