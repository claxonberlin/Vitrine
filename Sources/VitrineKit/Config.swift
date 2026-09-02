import Foundation

/// User settings and the list of externally-managed builds the user pointed
/// Vitrine at.
///
/// Persisted as JSON rather than through `UserDefaults`: the Linux shim in
/// swift-corelibs-foundation writes to a location no other tool reads, and a
/// plain file keeps the two platforms behaving identically (and makes the
/// settings hand-editable, which suits a developer tool).
public struct VitrineSettings: Codable, Sendable {
    /// nil means "use the platform default library root".
    public var libraryPath: String?
    public var minVersion: String
    /// Builds outside the library folder can't be rediscovered by walking it,
    /// so they are carried here.
    public var customBuilds: [InstalledBuild]
    /// Last list fetched from blender.org, so a cold start without a network
    /// still badges LTS releases correctly.
    public var ltsBranches: LTSBranches

    public static let `default` = VitrineSettings(
        libraryPath: nil,
        minVersion: "2.80",
        customBuilds: [],
        ltsBranches: .fallback
    )

    public init(libraryPath: String?, minVersion: String,
                customBuilds: [InstalledBuild], ltsBranches: LTSBranches) {
        self.libraryPath = libraryPath
        self.minVersion = minVersion
        self.customBuilds = customBuilds
        self.ltsBranches = ltsBranches
    }

    // Hand-written so a settings file from an older version — or one the user
    // edited and got slightly wrong — degrades to defaults per key instead of
    // failing to decode wholesale.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        libraryPath = try c.decodeIfPresent(String.self, forKey: .libraryPath)
        minVersion = try c.decodeIfPresent(String.self, forKey: .minVersion)
            ?? Self.default.minVersion
        customBuilds = try c.decodeIfPresent([InstalledBuild].self, forKey: .customBuilds) ?? []
        ltsBranches = try c.decodeIfPresent(LTSBranches.self, forKey: .ltsBranches) ?? .fallback
    }
}

public final class ConfigStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(platform: any PlatformIntegration = Platform.current) {
        self.fileURL = platform.configDirectory.appendingPathComponent("settings.json")
    }

    public func load() -> VitrineSettings {
        lock.lock(); defer { lock.unlock() }
        if let data = try? Data(contentsOf: fileURL),
           let settings = try? JSONDecoder().decode(VitrineSettings.self, from: data) {
            return settings
        }
        // No settings file yet. Before falling back to defaults, rescue
        // anything the pre-cross-platform build left in UserDefaults, so an
        // upgrade doesn't silently reset the user's library folder and
        // minimum-version filter.
        if let migrated = legacySettings() {
            write(migrated)
            return migrated
        }
        return .default
    }

    /// Best-effort: a settings write that fails must not take the app down,
    /// so callers get no error back. The in-memory state stays authoritative
    /// for the session either way.
    public func save(_ settings: VitrineSettings) {
        lock.lock(); defer { lock.unlock() }
        write(settings)
    }

    /// Assumes `lock` is already held — `load` writes through this during
    /// migration, and re-entering a non-recursive NSLock would deadlock.
    private func write(_ settings: VitrineSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    /// One-time carry-over from the UserDefaults-backed store used before
    /// settings moved to JSON. Only ever populated on macOS, and returns nil
    /// when there is nothing to rescue so a genuinely fresh install still gets
    /// `.default`.
    private func legacySettings() -> VitrineSettings? {
        let defaults = UserDefaults.standard
        let libraryPath = defaults.string(forKey: "libraryPath")
        let minVersion = defaults.string(forKey: "minVersion")
        // Custom builds were stored with the old `appPath` key, so this decode
        // fails for entries written before the rename. Losing a tracked
        // reference is recoverable — the user re-adds the build — whereas
        // failing the whole migration would also drop their settings.
        let customBuilds = defaults.data(forKey: "customBuilds").flatMap {
            try? JSONDecoder().decode([InstalledBuild].self, from: $0)
        }
        guard libraryPath != nil || minVersion != nil || customBuilds != nil else {
            return nil
        }
        var settings = VitrineSettings.default
        settings.libraryPath = libraryPath
        if let minVersion { settings.minVersion = minVersion }
        if let customBuilds { settings.customBuilds = customBuilds }
        return settings
    }
}
