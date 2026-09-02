import Foundation

/// Two data sources merged behind one façade:
///   1. `builder.blender.org` JSON — fast, structured, current daily/exp builds.
///   2. `download.blender.org/release/` HTML index — every stable release ever.
struct BlenderAPI {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = ["User-Agent": "Vitrine/1.0"]
        return URLSession(configuration: cfg)
    }()

    private static let arch: String = {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }()

    // MARK: - Builder API (daily / experimental)

    static func fetchBuilderBuilds(_ kind: BuilderKind) async throws -> [RemoteBuild] {
        let (data, response) = try await session.data(from: kind.url)
        try ensure2xx(response, url: kind.url)
        let raw = try JSONDecoder().decode([RawBuilderBuild].self, from: data)
        return raw.compactMap { $0.toRemote() }.filter(macOSCompatible)
    }

    enum BuilderKind {
        case daily, experimental
        var url: URL {
            switch self {
            case .daily: return URL(string: "https://builder.blender.org/download/daily/?format=json&v=2")!
            case .experimental: return URL(string: "https://builder.blender.org/download/experimental/?format=json&v=2")!
            }
        }
    }

    // MARK: - Stable archive scraping

    /// Scrape the full `/release/` archive for every BlenderX.Y/ folder
    /// whose version is at or above `minVersion`. Each version directory
    /// contributes one `RemoteBuild` per (version, arch) pair.
    static func fetchStableArchive(minVersion: Version) async throws -> [RemoteBuild] {
        let topURL = URL(string: "https://download.blender.org/release/")!
        let (data, response) = try await session.data(from: topURL)
        try ensure2xx(response, url: topURL)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        let entries = parseIndex(html: html, baseURL: topURL)
        let directories = entries.filter { $0.href.hasSuffix("/") && $0.href.hasPrefix("Blender") }

        // Skip whole subdirs below the threshold to keep the request count
        // down. Directory keys are truncated ("Blender4.2/"), so compare only
        // the shared prefix: a floor of 4.2.1 must not discard the 4.2
        // folder, which may still hold 4.2.2.
        let candidate = directories.filter { dir in
            guard let v = Version(String(dir.href.dropFirst("Blender".count).dropLast())) else { return false }
            return v.couldContain(atLeast: minVersion)
        }

        return await withTaskGroup(of: [RemoteBuild].self) { group in
            for dir in candidate {
                group.addTask {
                    let url = topURL.appendingPathComponent(dir.href)
                    // Per-directory failures are tolerated — one bad folder
                    // shouldn't empty the whole catalogue.
                    return (try? await fetchVersionDir(url)) ?? []
                }
            }
            var all: [RemoteBuild] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }
    }

    /// Pull all macOS dmg entries from a single `BlenderX.Y/` folder.
    private static func fetchVersionDir(_ url: URL) async throws -> [RemoteBuild] {
        let (data, response) = try await session.data(from: url)
        try ensure2xx(response, url: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        let entries = parseIndex(html: html, baseURL: url)
        var perKey: [String: RemoteBuild] = [:]

        for entry in entries where macOSDMG(entry.href) {
            guard let build = makeBuildFromArchive(entry: entry, fileURL: url.appendingPathComponent(entry.href)) else {
                continue
            }
            // De-dup so a (version, arch) pair only appears once even if both
            // .dmg and .dmg.sha256 etc. exist alongside.
            let key = "\(build.version)|\(build.architecture ?? "any")"
            if let existing = perKey[key], existing.date > build.date { continue }
            perKey[key] = build
        }

        // Strict: only show builds for the user's architecture. Older Blender
        // releases that predate Apple Silicon natively were Intel-only — those
        // are intentionally excluded on arm64 since they require Rosetta.
        return perKey.values.filter { $0.architecture == arch }
    }

    // MARK: - Parsing helpers

    /// Heuristic: any file containing a macOS marker, ending in `.dmg`.
    private static func macOSDMG(_ name: String) -> Bool {
        guard name.hasSuffix(".dmg") else { return false }
        let lower = name.lowercased()
        return lower.contains("macos") || lower.contains("osx") || lower.contains("darwin")
    }

    private static func macOSCompatible(_ b: RemoteBuild) -> Bool {
        guard b.fileName.hasSuffix(".dmg") else { return false }
        let lower = b.fileName.lowercased()
        guard lower.contains("darwin") || lower.contains("macos") else { return false }
        return archMatches(b.architecture)
    }

    /// Tolerant architecture match. The builder API has used "arm64",
    /// "aarch64", and compound tokens like "darwin-arm64" across versions.
    private static func archMatches(_ buildArch: String?) -> Bool {
        guard let buildArch else { return false }
        let a = buildArch.lowercased()
        switch arch {
        case "arm64":   return a.contains("arm64") || a.contains("aarch64")
        case "x86_64":  return a.contains("x86_64") || a.contains("x64") || a == "intel"
        default:        return a == arch
        }
    }

    /// Each line in nginx auto-index looks like:
    ///   `<a href="X">X</a>      18-Dec-2017 13:35       94M`
    /// We capture href, date, and size (which is `-` for directories or a
    /// raw byte count for files in this server's config).
    private struct IndexEntry {
        let href: String
        let date: Date?
        let size: Int64?
    }

    private static let indexLine = #/<a href="([^"]+)">[^<]+</a>\s+(\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2})\s+(\S+)/#

    private static let indexDate: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "dd-MMM-yyyy HH:mm"
        return df
    }()

    private static func parseIndex(html: String, baseURL: URL) -> [IndexEntry] {
        var out: [IndexEntry] = []
        for match in html.matches(of: indexLine) {
            let href = String(match.output.1)
            if href == "../" { continue }
            let date = indexDate.date(from: String(match.output.2))
            let sizeRaw = String(match.output.3)
            let size: Int64? = (sizeRaw == "-") ? nil : Int64(sizeRaw)
            out.append(IndexEntry(href: href, date: date, size: size))
        }
        return out
    }

    private static func makeBuildFromArchive(entry: IndexEntry, fileURL: URL) -> RemoteBuild? {
        // Filenames like blender-2.83.20-macos-arm64.dmg, blender-2.83.0-macOS.dmg
        let name = entry.href
        let arch = parseArch(from: name)
        let version = parseVersion(from: name) ?? "?"
        guard let pv = Version(version) else { return nil }
        return RemoteBuild(
            url: fileURL,
            version: version,
            parsedVersion: pv,
            riskId: "stable",
            branch: "stable",
            hash: nil,
            fileName: name,
            fileSize: entry.size ?? 0,
            date: entry.date ?? .distantPast,
            architecture: arch
        )
    }

    private static func parseArch(from name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("arm64") { return "arm64" }
        if lower.contains("x86_64") || lower.contains("-x64") { return "x86_64" }
        // Pre-Apple-Silicon builds (e.g. "blender-2.83.0-macOS.dmg") were
        // Intel-only — treat the absence of an arch token as x86_64 so the
        // strict per-arch filter excludes them on arm64.
        if lower.contains("macos") || lower.contains("osx") { return "x86_64" }
        return nil
    }

    private static let versionPattern = #/blender-(\d+(?:\.\d+){1,2}[a-z]?)-/#
    private static func parseVersion(from name: String) -> String? {
        if let m = name.firstMatch(of: versionPattern) {
            return String(m.output.1)
        }
        return nil
    }

    private static func ensure2xx(_ response: URLResponse, url: URL) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpStatus(http.statusCode, url)
        }
    }

    enum APIError: LocalizedError {
        case httpStatus(Int, URL)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let code, let url): return "HTTP \(code) for \(url.path)"
            }
        }
    }
}

// MARK: - Builder JSON shape

private struct RawBuilderBuild: Decodable {
    let url: String
    let version: String?
    let risk_id: String?
    let branch: String?
    let hash: String?
    let platform: String?
    let architecture: String?
    let file_name: String?
    let file_size: Int64?
    let file_mtime: Double?

    func toRemote() -> RemoteBuild? {
        guard let parsed = URL(string: url),
              let fileName = file_name,
              let version = version,
              let pv = Version(version),
              let riskId = risk_id else { return nil }
        return RemoteBuild(
            url: parsed,
            version: version,
            parsedVersion: pv,
            riskId: riskId,
            branch: branch ?? "",
            hash: hash,
            fileName: fileName,
            fileSize: file_size ?? 0,
            date: Date(timeIntervalSince1970: file_mtime ?? 0),
            architecture: architecture
        )
    }
}
