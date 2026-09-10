import Foundation

/// Declaration order is presentation order: both front ends list branches in
/// `allCases` order, and Daily leads because it is the one track that moves
/// every night — the list people come back to check.
public enum BuildBranch: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily, stable, experimental

    public var id: String { rawValue }
    public var title: String { rawValue.capitalizedFirst }
}

// Some list and picker widgets label an option by interpolating it, so the
// display name is reachable without a separate label closure.
extension BuildBranch: CustomStringConvertible {
    public var description: String { title }
}

/// Numeric version that compares as a tuple of components.
///
/// Tolerant of trailing letters used by old Blender releases (e.g. `2.79b`):
/// only the leading digit/dot run is parsed, so "2.79b" → [2, 79].
public struct Version: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let components: [Int]
    public let raw: String

    public init?(_ s: String) {
        var buf = ""
        for ch in s {
            if ch.isNumber || ch == "." { buf.append(ch) }
            else if !buf.isEmpty { break }
        }
        let parts = buf.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.components = parts
        self.raw = s
    }

    /// Sorts below every real version; used as a parse-failure fallback.
    public static let zero = Version("0")!

    public static func < (a: Version, b: Version) -> Bool {
        let n = max(a.components.count, b.components.count)
        for i in 0..<n {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// Equality pads with zeros exactly like `<` does, so "4.2" == "4.2.0"
    /// and Comparable's trichotomy holds. (The synthesized == compared `raw`
    /// too, leaving "4.2" vs "4.2.0" neither equal nor ordered.) `raw` is
    /// display-only.
    public static func == (a: Version, b: Version) -> Bool {
        !(a < b) && !(b < a)
    }

    public func hash(into hasher: inout Hasher) {
        // Drop trailing zeros so versions that compare equal hash equal.
        var c = components[...]
        while c.count > 1, c.last == 0 { c = c.dropLast() }
        hasher.combine(c)
    }

    /// Whether a version *starting with* these components could be ≥ `floor`.
    /// Used to prune whole archive directories: a folder keyed "4.2" must
    /// survive a floor of "4.2.1" because it may hold 4.2.2. Compares the
    /// shared prefix only; ties pass.
    public func couldContain(atLeast floor: Version) -> Bool {
        for (mine, theirs) in zip(components, floor.components) where mine != theirs {
            return mine > theirs
        }
        return true
    }

    public var description: String { raw }

    /// Returns "X.Y" for use as an LTS lookup key. Returns nil if the version
    /// has fewer than two components.
    public var minorKey: String? {
        guard components.count >= 2 else { return nil }
        return "\(components[0]).\(components[1])"
    }

    /// The leading component, i.e. the major version. Nil for an empty
    /// version string.
    public var major: Int? { components.first }
}

/// The X.Y branches Blender designates as Long-Term Support (two years of
/// bug-fix updates).
///
/// There is no LTS flag in any of Blender's build APIs — builder.blender.org
/// reports every maintained branch as `release_cycle: "stable"`, LTS or not —
/// so the authoritative source is the LTS page on blender.org. It is fetched
/// at startup and cached in settings; `fallback` only covers a first run with
/// no network.
public struct LTSBranches: Sendable, Codable, Equatable {
    public var minorKeys: Set<String>

    public init(minorKeys: Set<String>) {
        self.minorKeys = minorKeys
    }

    /// Last known published list. Kept current on a best-effort basis, but it
    /// is a cold-start fallback, not the source of truth.
    public static let fallback = LTSBranches(
        minorKeys: ["2.83", "2.93", "3.3", "3.6", "4.2", "4.5", "5.2"]
    )

    public func contains(version raw: String) -> Bool {
        guard let v = Version(raw), let key = v.minorKey else { return false }
        return minorKeys.contains(key)
    }

    /// Extracts the designated branches from the LTS page's markup.
    ///
    /// Each LTS gets a card titled "Blender X.Y LTS"; the same string also
    /// appears as the card image's alt text, which is harmless since the
    /// results are a set. Returns nil when nothing matches, so a page redesign
    /// leaves the caller's cached list intact rather than un-badging every
    /// LTS release.
    public static func parse(html: String) -> LTSBranches? {
        let keys = Set(
            html.matches(of: #/Blender\s+(\d+\.\d+)\s+LTS/#).map { String($0.output.1) }
        )
        return keys.isEmpty ? nil : LTSBranches(minorKeys: keys)
    }
}

/// A bundle of remote builds sharing the same X.Y minor key (e.g. "4.5"),
/// used to render the catalogue as collapsible headers + child rows.
/// `builds` is sorted descending so `latest` is `builds.first!`.
public struct RemoteBuildGroup: Identifiable, Hashable, Sendable {
    public let minorKey: String
    public let builds: [RemoteBuild]

    public init(minorKey: String, builds: [RemoteBuild]) {
        self.minorKey = minorKey
        self.builds = builds
    }

    public var id: String { minorKey }
    public var latest: RemoteBuild { builds[0] }
}

public struct RemoteBuild: Identifiable, Hashable, Codable, Sendable {
    public let url: URL
    public let version: String
    public let parsedVersion: Version
    public let riskId: String          // "stable", "alpha", "candidate", ...
    public let branch: String
    public let hash: String?
    public let fileName: String
    public let fileSize: Int64
    public let date: Date              // upload time as published by blender.org
    public let architecture: String?

    public init(url: URL, version: String, parsedVersion: Version, riskId: String,
                branch: String, hash: String?, fileName: String, fileSize: Int64,
                date: Date, architecture: String?) {
        self.url = url
        self.version = version
        self.parsedVersion = parsedVersion
        self.riskId = riskId
        self.branch = branch
        self.hash = hash
        self.fileName = fileName
        self.fileSize = fileSize
        self.date = date
        self.architecture = architecture
    }

    public var id: String { url.absoluteString }
    public var riskLabel: String { riskId.capitalizedFirst }

    /// The risk chip a front end should draw, or nil where it would only
    /// repeat the heading above it: everything filed under Stable is stable.
    public func riskLabel(under branch: BuildBranch) -> String? {
        (branch == .stable && riskId == "stable") ? nil : riskLabel
    }
}

public struct InstalledBuild: Identifiable, Hashable, Codable, Sendable {
    /// Risk id marking externally-managed builds the user pointed Vitrine at.
    public static let customRiskID = "custom"

    public let id: UUID
    public var version: String
    public var riskId: String
    public var branch: BuildBranch
    public var installedAt: Date
    public var lastLaunchedAt: Date?
    public var sourceURL: URL?
    /// When blender.org built or published this build, as opposed to when it
    /// landed here. Nil for custom builds, and for library folders installed
    /// before Vitrine recorded it.
    public var builtAt: Date?
    /// The short commit hash the builder API publishes, and the only thing
    /// that distinguishes two daily builds: a daily keeps one version string
    /// for months while the hash changes every night. Nil where unknown —
    /// the stable archive publishes no hash.
    public var sourceHash: String?
    /// The runnable build: a `.app` bundle on macOS, a build directory on Linux.
    public var buildPath: URL
    public var pinned: Bool

    public init(id: UUID, version: String, riskId: String, branch: BuildBranch,
                installedAt: Date, lastLaunchedAt: Date?, sourceURL: URL?,
                builtAt: Date? = nil, sourceHash: String? = nil,
                buildPath: URL, pinned: Bool) {
        self.id = id
        self.version = version
        self.riskId = riskId
        self.branch = branch
        self.installedAt = installedAt
        self.lastLaunchedAt = lastLaunchedAt
        self.sourceURL = sourceURL
        self.builtAt = builtAt
        self.sourceHash = sourceHash
        self.buildPath = buildPath
        self.pinned = pinned
    }

    public var riskLabel: String { riskId.capitalizedFirst }

    /// The date this build is placed by: its own build date where blender.org
    /// published one, and otherwise the day it was installed. Used for both
    /// the date a row shows and the order dailies are pruned in, so the two
    /// can never disagree.
    public var buildDate: Date {
        if let builtAt, builtAt != .distantPast { return builtAt }
        return installedAt
    }

    /// True when `buildDate` is the build's own date rather than a stand-in.
    public var hasBuildDate: Bool { builtAt != nil && builtAt != .distantPast }

    /// The risk chip a front end should draw — nil under the Stable heading,
    /// which already says as much. See `RemoteBuild.riskLabel(under:)`.
    public var displayRiskLabel: String? {
        (branch == .stable && riskId == "stable") ? nil : riskLabel
    }

    /// Custom builds are tracked, not owned: never deleted from disk, never
    /// given metadata files, and persisted in the config store instead of
    /// being rediscovered from the library folder.
    public var isCustom: Bool { riskId == Self.customRiskID }
}

public enum DownloadState: Equatable, Sendable {
    case idle
    case queued
    case downloading(received: Int64, total: Int64, bytesPerSecond: Double)
    /// Unpacking. The fraction is the share of the build's bytes already
    /// written where the platform can measure that, and nil where it can't —
    /// the copy on macOS is watched, the `tar` on Linux reports nothing.
    case installing(fraction: Double?)
    case failed(String)

    /// True while a download occupies its slot — used to block duplicate
    /// starts and to drive in-progress spinners.
    public var isActive: Bool {
        switch self {
        case .queued, .downloading, .installing: return true
        case .idle, .failed: return false
        }
    }
}

// MARK: - Formatting
//
// Hand-rolled rather than delegating to ByteCountFormatter and
// RelativeDateTimeFormatter. Those are thin shims over ICU/CoreFoundation on
// Apple platforms and have patchy coverage in swift-corelibs-foundation, so
// rolling them keeps output byte-identical on macOS and Fedora.

public enum ByteFormat {
    /// Decimal (1000-based) units, matching ByteCountFormatter's `.file`
    /// count style and the sizes blender.org publishes.
    public static func string(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return "\(bytes) bytes" }
        // The number is formatted on its own and the unit interpolated:
        // `String(format:)` with "%@" takes an NSString, which doesn't bridge
        // from a Swift String under swift-corelibs-foundation.
        let number = String(format: value >= 100 ? "%.0f" : "%.1f", value)
        return "\(number) \(units[index])"
    }
}

public enum DateFormat {
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        // Pinned locale so the month abbreviation is stable across platforms
        // and independent of the user's regional settings.
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "dd MMM yyyy"
        return df
    }()

    /// "12 Jun 2026" — or "—" for the .distantPast placeholder the archive
    /// parser emits when a listing has no date column.
    public static func day(_ date: Date) -> String {
        date == .distantPast ? "—" : dayFormatter.string(from: date)
    }

    /// Compact past-tense interval, e.g. "3d ago".
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds.isFinite else { return "—" }
        guard seconds >= 60 else { return "just now" }
        let steps: [(limit: Double, divisor: Double, suffix: String)] = [
            (3600, 60, "m"),
            (86_400, 3600, "h"),
            (604_800, 86_400, "d"),
            (2_629_800, 604_800, "w"),
            (31_557_600, 2_629_800, "mo")
        ]
        for step in steps where seconds < step.limit {
            return "\(Int(seconds / step.divisor))\(step.suffix) ago"
        }
        return "\(Int(seconds / 31_557_600))y ago"
    }
}

extension String {
    /// "alpha" → "Alpha" — for the lowercase identifiers the API publishes.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
