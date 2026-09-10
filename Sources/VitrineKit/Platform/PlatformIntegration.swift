import Foundation

/// Describes how this OS's Blender builds are published upstream, so the
/// catalogue code stays free of `#if os(...)`.
public struct BuildPlatform: Sendable {
    /// Value of the `platform` field in builder.blender.org's JSON.
    public let builderToken: String
    /// Archive extensions this OS installs from, longest-first so that
    /// ".tar.xz" is tested before ".xz".
    public let archiveSuffixes: [String]
    /// Substrings that mark a filename in the stable archive as belonging to
    /// this OS (`blender-4.2.1-linux-x64.tar.xz`).
    public let nameMarkers: [String]
    /// Architecture tokens accepted for the current host. Upstream has used
    /// "arm64", "aarch64", "x86_64", "x64" and bare "intel" over the years.
    public let architectures: [String]

    public func matchesArchive(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        guard archiveSuffixes.contains(where: lower.hasSuffix) else { return false }
        return nameMarkers.contains(where: lower.contains)
    }

    public func matchesArchitecture(_ arch: String?) -> Bool {
        guard let arch else { return false }
        let lower = arch.lowercased()
        return architectures.contains(where: lower.contains)
    }
}

/// The per-OS half of Vitrine: unpacking builds, launching them, and wiring
/// the starred build into the desktop. Everything else lives in `VitrineKit`
/// proper and is shared verbatim between macOS and Fedora.
public protocol PlatformIntegration: Sendable {
    /// Where builds land when the user hasn't chosen a library folder.
    var defaultLibraryRoot: URL { get }
    /// Where `settings.json` lives, following each platform's convention.
    var configDirectory: URL { get }
    var buildPlatform: BuildPlatform { get }
    /// Name of the OS file manager, for menu labels ("Finder" / "Files").
    var fileManagerName: String { get }
    /// Whether `applyStarred` can pin to a dock or favourites bar here.
    var supportsLauncherPin: Bool { get }
    /// Whether adding an existing build means picking a *directory*. macOS
    /// bundles are selected as files; a Linux build is a plain folder, and the
    /// open dialog has to be configured differently for each.
    var buildIsDirectory: Bool { get }

    /// Unpacks a downloaded archive into `destination`, returning the path of
    /// the runnable build — a `.app` bundle on macOS, a build directory on
    /// Linux.
    /// `progress` is called with the share of the build already written,
    /// as often as the platform can measure it, and never called at all where
    /// it can't.
    func extract(archive: URL, into destination: URL,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL
    /// Finds an installed build inside one of the library's per-build folders.
    func findBuild(in folder: URL) -> URL?
    /// Best-effort version string for a build the user added by hand.
    func version(ofBuildAt url: URL) async -> String?

    func launch(_ buildPath: URL) throws
    func reveal(_ url: URL) async
    /// Opens a web link in the user's browser.
    func openURL(_ url: URL) async
    /// Wires the starred build into the desktop, or unwires everything when
    /// passed nil. Best-effort throughout: a read-only `/usr/local/bin` or a
    /// non-GNOME session must degrade, never fail the app.
    func applyStarred(_ build: InstalledBuild?) async
}

public extension PlatformIntegration {
    /// For callers that don't watch the unpack — the tests, and any code that
    /// only wants the resulting path.
    func extract(archive: URL, into destination: URL) async throws -> URL {
        try await extract(archive: archive, into: destination, progress: { _ in })
    }
}

public enum Platform {
    /// The integration for the OS this binary was built for.
    public static let current: any PlatformIntegration = {
        #if os(macOS)
        return MacOSIntegration()
        #elseif os(Linux)
        return LinuxIntegration()
        #else
        #error("Vitrine supports macOS and Linux")
        #endif
    }()

    /// Host CPU architecture, reported honestly. Blender publishes no
    /// linux-arm64 builds today, so an aarch64 Fedora host legitimately sees
    /// an empty catalogue rather than builds it cannot run.
    public static let hostArchitecture: String = {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }()

    static var architectureAliases: [String] {
        hostArchitecture == "arm64" ? ["arm64", "aarch64"] : ["x86_64", "x64", "intel"]
    }

    /// `$XDG_*_HOME` with the spec-mandated fallback, used by the Linux layer
    /// and by the shared config store.
    static func xdgDirectory(_ variable: String, fallback: String) -> URL {
        if let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(fallback, isDirectory: true)
    }
}
