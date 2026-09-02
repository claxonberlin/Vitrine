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

    public static let `default` = VitrineSettings(
        libraryPath: nil,
        minVersion: "2.80",
        customBuilds: []
    )

    public init(libraryPath: String?, minVersion: String, customBuilds: [InstalledBuild]) {
        self.libraryPath = libraryPath
        self.minVersion = minVersion
        self.customBuilds = customBuilds
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
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(VitrineSettings.self, from: data)
        else { return .default }
        return settings
    }

    /// Best-effort: a settings write that fails must not take the app down,
    /// so callers get no error back. The in-memory state stays authoritative
    /// for the session either way.
    public func save(_ settings: VitrineSettings) {
        lock.lock(); defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
