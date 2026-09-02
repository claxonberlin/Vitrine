import Foundation

enum BuildBranch: String, CaseIterable, Identifiable, Codable, Sendable {
    case stable, daily, experimental

    var id: String { rawValue }
    var title: String { rawValue.capitalizedFirst }
}

enum TopTab: String, CaseIterable, Identifiable, Sendable {
    case installed, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .installed: return "Vitrine"
        case .library: return "Catalogue"
        }
    }
}

/// Numeric version that compares as a tuple of components.
///
/// Tolerant of trailing letters used by old Blender releases (e.g. `2.79b`):
/// only the leading digit/dot run is parsed, so "2.79b" → [2, 79].
struct Version: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    let components: [Int]
    let raw: String

    init?(_ s: String) {
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
    static let zero = Version("0")!

    static func < (a: Version, b: Version) -> Bool {
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
    static func == (a: Version, b: Version) -> Bool {
        !(a < b) && !(b < a)
    }

    func hash(into hasher: inout Hasher) {
        // Drop trailing zeros so versions that compare equal hash equal.
        var c = components[...]
        while c.count > 1, c.last == 0 { c = c.dropLast() }
        hasher.combine(c)
    }

    /// Whether a version *starting with* these components could be ≥ `floor`.
    /// Used to prune whole archive directories: a folder keyed "4.2" must
    /// survive a floor of "4.2.1" because it may hold 4.2.2. Compares the
    /// shared prefix only; ties pass.
    func couldContain(atLeast floor: Version) -> Bool {
        for (mine, theirs) in zip(components, floor.components) where mine != theirs {
            return mine > theirs
        }
        return true
    }

    var description: String { raw }

    /// Returns "X.Y" for use as an LTS lookup key. Returns nil if the version
    /// has fewer than two components.
    var minorKey: String? {
        guard components.count >= 2 else { return nil }
        return "\(components[0]).\(components[1])"
    }
}

/// Blender designates specific X.Y branches as Long-Term Support releases
/// (two years of bug-fix updates). The set is announced per cycle; the
/// current published list (as of 2026) is hardcoded here. New entries can
/// be added when Blender announces them.
enum LTS {
    static let branches: Set<String> = [
        "2.83", "2.93", "3.3", "3.6", "4.2", "4.5"
    ]

    static func contains(version raw: String) -> Bool {
        guard let v = Version(raw), let key = v.minorKey else { return false }
        return branches.contains(key)
    }
}

/// A bundle of remote builds sharing the same X.Y minor key (e.g. "4.5"),
/// used to render the catalogue as collapsible headers + child rows.
/// `builds` is sorted descending so `latest` is `builds.first!`.
struct RemoteBuildGroup: Identifiable, Hashable, Sendable {
    let minorKey: String
    let builds: [RemoteBuild]

    var id: String { minorKey }
    var latest: RemoteBuild { builds[0] }
}

struct RemoteBuild: Identifiable, Hashable, Codable, Sendable {
    let url: URL
    let version: String
    let parsedVersion: Version
    let riskId: String          // "stable", "alpha", "candidate", ...
    let branch: String
    let hash: String?
    let fileName: String
    let fileSize: Int64
    let date: Date              // upload time as published by blender.org
    let architecture: String?

    var id: String { url.absoluteString }

    var riskLabel: String { riskId.capitalizedFirst }
}

struct InstalledBuild: Identifiable, Hashable, Codable, Sendable {
    /// Risk id marking externally-managed apps the user pointed Vitrine at.
    static let customRiskID = "custom"

    let id: UUID
    var version: String
    var riskId: String
    var branch: BuildBranch
    var installedAt: Date
    var lastLaunchedAt: Date?
    var sourceURL: URL?
    var appPath: URL
    var pinned: Bool

    var riskLabel: String { riskId.capitalizedFirst }

    /// Custom builds are tracked, not owned: never deleted from disk, never
    /// given metadata files, and persisted in UserDefaults instead of being
    /// rediscovered from the library folder.
    var isCustom: Bool { riskId == Self.customRiskID }
}

enum DownloadState: Equatable, Sendable {
    case idle
    case queued
    case downloading(received: Int64, total: Int64, bytesPerSecond: Double)
    case installing
    case failed(String)

    /// True while a download occupies its slot — used to block duplicate
    /// starts and to drive in-progress spinners.
    var isActive: Bool {
        switch self {
        case .queued, .downloading, .installing: return true
        case .idle, .failed: return false
        }
    }
}

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()
    static func string(_ bytes: Int64) -> String { formatter.string(fromByteCount: bytes) }
}

enum DurationFormat {
    static func eta(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0, seconds < 60 * 60 * 24 else { return "—" }
        let s = Int(seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

enum DateFormat {
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd MMM yyyy"
        return df
    }()

    // Formatters are expensive to create; shared instances are fine here
    // since all formatting happens on the main thread (SwiftUI bodies).
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    /// "12 Jun 2026" — or "—" for the .distantPast placeholder the archive
    /// parser emits when a listing has no date column.
    static func day(_ date: Date) -> String {
        date == .distantPast ? "—" : dayFormatter.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

private extension String {
    /// "alpha" → "Alpha" — for the lowercase identifiers the API publishes.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
