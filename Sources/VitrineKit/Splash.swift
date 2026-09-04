import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches and caches the splash artwork Blender ships with a release — the
/// painting on the startup screen, commissioned fresh for every X.Y series.
///
/// There is no API for it. The artwork is the social-preview image on the
/// release's own announcement page, so that is what gets read; the file names
/// themselves follow no pattern worth guessing at (`splash5_2.webp`,
/// `blender_splash_45.webp`, `splash_render-final_2k-480x270.webp`).
///
/// Everything here is best-effort. A redesign, a missing page or no network
/// leaves the caller with nil and a window that simply has no picture behind
/// it.
public struct SplashLibrary: Sendable {
    private let directory: URL

    public init(platform: any PlatformIntegration = Platform.current) {
        self.directory = platform.configDirectory
            .appendingPathComponent("Splash", isDirectory: true)
    }

    /// The artwork for a minor series ("5.2"), downloading it the first time
    /// and reading the cache afterwards. Returns a local file URL.
    public func artwork(forSeries series: String) async -> URL? {
        if let cached = cachedFile(forSeries: series) { return cached }
        guard let remote = try? await Self.remoteArtworkURL(forSeries: series),
              let data = try? await Self.download(remote), !data.isEmpty
        else { return nil }

        let destination = directory.appendingPathComponent(
            "\(series).\(remote.pathExtension.isEmpty ? "img" : remote.pathExtension)"
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return nil }
        return destination
    }

    /// Any previously downloaded artwork for the series, whatever extension it
    /// arrived with.
    private func cachedFile(forSeries series: String) -> URL? {
        let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        return entries?.first { $0.deletingPathExtension().lastPathComponent == series }
    }

    // MARK: - Remote

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = ["User-Agent": "Vitrine/1.0"]
        return URLSession(configuration: cfg)
    }()

    /// "5.2" → the artwork linked from `blender.org/download/releases/5-2/`.
    static func remoteArtworkURL(forSeries series: String) async throws -> URL? {
        let slug = series.replacingOccurrences(of: ".", with: "-")
        guard let page = URL(string: "https://www.blender.org/download/releases/\(slug)/")
        else { return nil }
        let data = try await download(page)
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        return parseArtworkURL(html: html)
    }

    /// Reads the page's social-preview image. Kept separate so it can be
    /// tested against captured markup without a network. Both attribute
    /// orders are accepted, since nothing obliges the page to pick one.
    static func parseArtworkURL(html: String) -> URL? {
        let propertyFirst = #/<meta[^>]+property=["']og:image["'][^>]*?content=["']([^"']+)["']/#
        let contentFirst = #/<meta[^>]+content=["']([^"']+)["'][^>]*?property=["']og:image["']/#
        let raw = html.firstMatch(of: propertyFirst).map { String($0.output.1) }
            ?? html.firstMatch(of: contentFirst).map { String($0.output.1) }
        guard let raw else { return nil }
        return URL(string: raw)
    }

    private static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BlenderAPI.APIError.httpStatus(http.statusCode, url)
        }
        return data
    }
}
