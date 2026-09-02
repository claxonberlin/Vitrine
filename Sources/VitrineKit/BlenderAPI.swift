import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Two data sources merged behind one façade:
///   1. `builder.blender.org` JSON — fast, structured, current daily/exp builds.
///   2. `download.blender.org/release/` HTML index — every stable release ever.
///
/// Which files count as installable is decided entirely by the `BuildPlatform`
/// passed in, so this type contains no `#if os(...)` of its own.
public struct BlenderAPI {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = ["User-Agent": "Vitrine/1.0"]
        return URLSession(configuration: cfg)
    }()

    // MARK: - Builder API (daily / experimental)

    public enum BuilderKind: Sendable {
        case daily, experimental

        var url: URL {
            switch self {
            case .daily:
                return URL(string: "https://builder.blender.org/download/daily/?format=json&v=2")!
            case .experimental:
                return URL(string: "https://builder.blender.org/download/experimental/?format=json&v=2")!
            }
        }
    }

    public static func fetchBuilderBuilds(_ kind: BuilderKind,
                                          platform: BuildPlatform) async throws -> [RemoteBuild] {
        let (data, response) = try await session.data(from: kind.url)
        try ensure2xx(response, url: kind.url)
        let raw = try JSONDecoder().decode([RawBuilderBuild].self, from: data)
        return raw.compactMap { $0.toRemote() }.filter { build in
            platform.matchesArchive(build.fileName)
                && platform.matchesArchitecture(build.architecture)
        }
    }

    // MARK: - LTS designations

    /// Scrapes blender.org's LTS page for the designated branches.
    ///
    /// This is the only published source: the build APIs carry no LTS flag,
    /// and report every maintained branch — LTS or not — as
    /// `release_cycle: "stable"`. Each LTS gets a card titled
    /// "Blender X.Y LTS", which is what the pattern below anchors on.
    ///
    /// A page redesign that breaks the parse yields an empty set, which is
    /// reported as `noLTSEntriesFound` so the caller keeps its cached list
    /// rather than silently un-badging every LTS release.
    public static func fetchLTSBranches() async throws -> LTSBranches {
        let url = URL(string: "https://www.blender.org/download/lts/")!
        let (data, response) = try await session.data(from: url)
        try ensure2xx(response, url: url)
        guard let html = String(data: data, encoding: .utf8),
              let branches = LTSBranches.parse(html: html)
        else { throw APIError.noLTSEntriesFound }
        return branches
    }

    // MARK: - Stable archive scraping

    /// Scrapes the full `/release/` archive for every `BlenderX.Y/` folder
    /// whose version is at or above `minVersion`. Each version directory
    /// contributes one `RemoteBuild` per (version, arch) pair.
    public static func fetchStableArchive(minVersion: Version,
                                          platform: BuildPlatform) async throws -> [RemoteBuild] {
        let topURL = URL(string: "https://download.blender.org/release/")!
        let (data, response) = try await session.data(from: topURL)
        try ensure2xx(response, url: topURL)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        let entries = parseIndex(html: html)
        let directories = entries.filter { $0.href.hasSuffix("/") && $0.href.hasPrefix("Blender") }

        // Skip whole subdirs below the threshold to keep the request count
        // down. Directory keys are truncated ("Blender4.2/"), so compare only
        // the shared prefix: a floor of 4.2.1 must not discard the 4.2
        // folder, which may still hold 4.2.2.
        let candidates = directories.filter { dir in
            guard let v = Version(String(dir.href.dropFirst("Blender".count).dropLast()))
            else { return false }
            return v.couldContain(atLeast: minVersion)
        }

        return await withTaskGroup(of: [RemoteBuild].self) { group in
            for dir in candidates {
                group.addTask {
                    let url = topURL.appendingPathComponent(dir.href)
                    // Per-directory failures are tolerated — one bad folder
                    // shouldn't empty the whole catalogue.
                    return (try? await fetchVersionDir(url, platform: platform)) ?? []
                }
            }
            var all: [RemoteBuild] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }
    }

    /// Pulls all installable entries from a single `BlenderX.Y/` folder.
    private static func fetchVersionDir(_ url: URL,
                                        platform: BuildPlatform) async throws -> [RemoteBuild] {
        let (data, response) = try await session.data(from: url)
        try ensure2xx(response, url: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        var perKey: [String: RemoteBuild] = [:]
        for entry in parseIndex(html: html) where platform.matchesArchive(entry.href) {
            guard let build = makeBuildFromArchive(
                entry: entry,
                fileURL: url.appendingPathComponent(entry.href),
                platform: platform
            ) else { continue }
            // De-dup so a (version, arch) pair only appears once even if
            // checksums or variants sit alongside.
            let key = "\(build.version)|\(build.architecture ?? "any")"
            if let existing = perKey[key], existing.date > build.date { continue }
            perKey[key] = build
        }

        // Strict: only builds for the host architecture. Older releases that
        // predate Apple Silicon were Intel-only, and those are intentionally
        // excluded on arm64 rather than silently requiring Rosetta.
        return perKey.values.filter { platform.matchesArchitecture($0.architecture) }
    }

    // MARK: - Parsing helpers

    /// Each line in the nginx auto-index looks like:
    ///   `<a href="X">X</a>      18-Dec-2017 13:35       94M`
    /// We capture href, date, and size (`-` for directories, a raw byte count
    /// for files in this server's config).
    private struct IndexEntry {
        let href: String
        let date: Date?
        let size: Int64?
    }

    private static let indexDate: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "dd-MMM-yyyy HH:mm"
        return df
    }()

    private static func parseIndex(html: String) -> [IndexEntry] {
        // Declared inline rather than as a static: `Regex` isn't Sendable, so
        // a shared static is rejected under strict concurrency. Compiling it
        // per call is free next to the HTTP request that produced `html`.
        let indexLine =
            #/<a href="([^"]+)">[^<]+</a>\s+(\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2})\s+(\S+)/#
        var out: [IndexEntry] = []
        for match in html.matches(of: indexLine) {
            let href = String(match.output.1)
            if href == "../" { continue }
            let sizeRaw = String(match.output.3)
            out.append(IndexEntry(
                href: href,
                date: indexDate.date(from: String(match.output.2)),
                size: sizeRaw == "-" ? nil : Int64(sizeRaw)
            ))
        }
        return out
    }

    private static func makeBuildFromArchive(entry: IndexEntry,
                                             fileURL: URL,
                                             platform: BuildPlatform) -> RemoteBuild? {
        // Filenames like blender-2.83.20-macos-arm64.dmg,
        // blender-4.2.1-linux-x64.tar.xz, blender-2.83.0-macOS.dmg
        let name = entry.href
        guard let version = parseVersion(from: name), let pv = Version(version) else { return nil }
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
            architecture: parseArch(from: name, platform: platform)
        )
    }

    /// Upstream naming has drifted a lot: `linux64`, `linux-x64`, `macos-arm64`,
    /// and (pre-Apple-Silicon) no arch token at all.
    private static func parseArch(from name: String, platform: BuildPlatform) -> String? {
        let lower = name.lowercased()
        if lower.contains("arm64") || lower.contains("aarch64") { return "arm64" }
        if lower.contains("x86_64") || lower.contains("-x64") || lower.contains("linux64") {
            return "x86_64"
        }
        if lower.contains("i686") || lower.contains("i386") || lower.contains("linux32") {
            return "i386"
        }
        // A macOS build with no arch token ("blender-2.83.0-macOS.dmg") predates
        // Apple Silicon and was Intel-only, so the strict per-arch filter
        // excludes it on arm64.
        if platform.builderToken == "darwin" { return "x86_64" }
        return nil
    }

    private static func parseVersion(from name: String) -> String? {
        name.firstMatch(of: #/blender-(\d+(?:\.\d+){1,2}[a-z]?)-/#)
            .map { String($0.output.1) }
    }

    private static func ensure2xx(_ response: URLResponse, url: URL) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpStatus(http.statusCode, url)
        }
    }

    public enum APIError: LocalizedError {
        case httpStatus(Int, URL)
        case noLTSEntriesFound

        public var errorDescription: String? {
            switch self {
            case .httpStatus(let code, let url):
                return "HTTP \(code) for \(url.path)"
            case .noLTSEntriesFound:
                return "Could not read the LTS list from blender.org"
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
              let version,
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
