import XCTest
@testable import VitrineKit

final class VersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(Version("4.2.1")?.components, [4, 2, 1])
        XCTAssertEqual(Version("2.79b")?.components, [2, 79])  // trailing letter
        XCTAssertEqual(Version("v3.6")?.components, [3, 6])    // leading junk
        XCTAssertEqual(Version("4.5")?.raw, "4.5")
    }

    func testParsingRejectsJunk() {
        XCTAssertNil(Version(""))
        XCTAssertNil(Version("Benchmark"))
        XCTAssertNil(Version("..."))
    }

    func testOrderingComparesNumerically() {
        XCTAssertLessThan(Version("2.93")!, Version("3.0")!)
        XCTAssertLessThan(Version("4.2.9")!, Version("4.2.20")!)  // not lexicographic
        XCTAssertLessThan(Version("4.2")!, Version("4.2.1")!)
        XCTAssertGreaterThan(Version("4.10")!, Version("4.9")!)
    }

    func testEqualityMatchesOrderingSemantics() {
        // "4.2" and "4.2.0" are the same version: neither orders before the
        // other, so == and hashValue must agree (Comparable trichotomy).
        let short = Version("4.2")!
        let padded = Version("4.2.0")!
        XCTAssertEqual(short, padded)
        XCTAssertEqual(short.hashValue, padded.hashValue)
        XCTAssertFalse(short < padded)
        XCTAssertFalse(padded < short)
        XCTAssertNotEqual(Version("4.2")!, Version("4.2.1")!)
    }

    func testMinorKey() {
        XCTAssertEqual(Version("4.2.7")?.minorKey, "4.2")
        XCTAssertEqual(Version("2.79b")?.minorKey, "2.79")
        XCTAssertNil(Version("4")?.minorKey)
    }

    func testCouldContainAtLeast() {
        // A "Blender4.2/" archive folder must survive a floor of 4.2.1 —
        // it can hold 4.2.2 — while "Blender4.1/" can never reach 4.2.
        XCTAssertTrue(Version("4.2")!.couldContain(atLeast: Version("4.2.1")!))
        XCTAssertTrue(Version("4.2")!.couldContain(atLeast: Version("4.2")!))
        XCTAssertTrue(Version("5.0")!.couldContain(atLeast: Version("4.2.1")!))
        XCTAssertFalse(Version("4.1")!.couldContain(atLeast: Version("4.2")!))
        XCTAssertFalse(Version("3.6")!.couldContain(atLeast: Version("4.0")!))
    }
}

final class LTSTests: XCTestCase {
    private let branches = LTSBranches.fallback

    func testMatchesOnTheMinorBranchNotTheExactVersion() {
        XCTAssertTrue(branches.contains(version: "4.2.3"))
        XCTAssertTrue(branches.contains(version: "3.3.0"))
        XCTAssertTrue(branches.contains(version: "5.2.1"))
        XCTAssertFalse(branches.contains(version: "4.1.1"))
        XCTAssertFalse(branches.contains(version: "5.1.0"))
        XCTAssertFalse(branches.contains(version: "not-a-version"))
    }

    /// blender.org publishes no LTS flag in any build API — every maintained
    /// branch reports `release_cycle: "stable"` — so the list is scraped from
    /// the LTS page. This pins the shape that scrape depends on.
    func testParsesTheLTSPageMarkup() {
        let html = """
            <div class="cards-item-title">Blender 5.2 LTS</div>
            <img src="/5_2.webp" alt="Blender 5.2 LTS">
            <div class="cards-item-title">Blender 4.5 LTS</div>
            <div class="cards-item-title">Blender 2.83 LTS</div>
            <p>Initially released in June 2020, Blender 2.83 LTS is the first.</p>
            """
        let parsed = LTSBranches.parse(html: html)
        XCTAssertEqual(parsed?.minorKeys, ["5.2", "4.5", "2.83"])
    }

    func testIgnoresVersionsThatAreNotMarkedLTS() {
        let html = """
            <div class="cards-item-title">Blender 5.2 LTS</div>
            <a href="/download/releases/5-1/">Blender 5.1</a>
            <a href="/download/releases/4-3/">Blender 4.3</a>
            """
        XCTAssertEqual(LTSBranches.parse(html: html)?.minorKeys, ["5.2"])
    }

    /// A redesign that breaks the scrape must yield nil, so the caller keeps
    /// its cached list instead of silently un-badging every LTS release.
    func testReturnsNilWhenNothingMatches() {
        XCTAssertNil(LTSBranches.parse(html: "<html><body>Downloads</body></html>"))
        XCTAssertNil(LTSBranches.parse(html: ""))
    }
}

final class DurationFormatTests: XCTestCase {
    func testETAFormats() {
        XCTAssertEqual(DurationFormat.eta(seconds: 5), "0:05")
        XCTAssertEqual(DurationFormat.eta(seconds: 75), "1:15")
        XCTAssertEqual(DurationFormat.eta(seconds: 3675), "1:01:15")
    }

    func testETAPlaceholderForUnknowable() {
        XCTAssertEqual(DurationFormat.eta(seconds: 0), "—")
        XCTAssertEqual(DurationFormat.eta(seconds: -3), "—")
        XCTAssertEqual(DurationFormat.eta(seconds: .infinity), "—")
        XCTAssertEqual(DurationFormat.eta(seconds: 60 * 60 * 24), "—")
    }
}

final class DownloadStateTests: XCTestCase {
    func testIsActive() {
        XCTAssertTrue(DownloadState.queued.isActive)
        XCTAssertTrue(DownloadState.downloading(received: 1, total: 2, bytesPerSecond: 1).isActive)
        XCTAssertTrue(DownloadState.installing(fraction: nil).isActive)
        XCTAssertFalse(DownloadState.idle.isActive)
        XCTAssertFalse(DownloadState.failed("boom").isActive)
    }
}

/// Which builds wear a risk chip is one rule, shared by both front ends and
/// by both kinds of row, so it is pinned here rather than re-derived per view.
final class RiskLabelTests: XCTestCase {
    private func remote(version: String, riskId: String) -> RemoteBuild {
        RemoteBuild(url: URL(string: "https://example.invalid/\(version)")!,
                    version: version, parsedVersion: Version(version)!, riskId: riskId,
                    branch: "stable", hash: nil, fileName: "blender-\(version).dmg",
                    fileSize: 0, date: .distantPast, architecture: "arm64")
    }

    private func installed(version: String, riskId: String, branch: BuildBranch) -> InstalledBuild {
        InstalledBuild(id: UUID(), version: version, riskId: riskId, branch: branch,
                       installedAt: .distantPast, lastLaunchedAt: nil, sourceURL: nil,
                       buildPath: URL(fileURLWithPath: "/tmp/Blender.app"), pinned: false)
    }

    func testStableUnderStableSaysNothingTwice() {
        XCTAssertNil(remote(version: "4.2.1", riskId: "stable").riskLabel(under: .stable))
        XCTAssertNil(installed(version: "4.2.1", riskId: "stable", branch: .stable)
            .displayRiskLabel)
    }

    func testAnythingElseKeepsItsChip() {
        XCTAssertEqual(remote(version: "5.3.0", riskId: "alpha").riskLabel(under: .daily), "Alpha")
        // A stable-flagged build filed under another heading still says so.
        XCTAssertEqual(remote(version: "4.2.1", riskId: "stable").riskLabel(under: .daily), "Stable")
        XCTAssertEqual(installed(version: "5.3.0", riskId: "alpha", branch: .daily)
            .displayRiskLabel, "Alpha")
        // Builds the user added by hand are marked wherever they are filed.
        XCTAssertEqual(installed(version: "4.0", riskId: InstalledBuild.customRiskID,
                                 branch: .stable).displayRiskLabel, "Custom")
    }
}


/// Which date a row shows, and which one dailies are pruned in. Both read
/// `buildDate`, so the rule lives in one place and is pinned here.
final class BuildVintageTests: XCTestCase {
    private func build(installedAt: Date, builtAt: Date?) -> InstalledBuild {
        InstalledBuild(id: UUID(), version: "5.3.0", riskId: "alpha", branch: .daily,
                       installedAt: installedAt, lastLaunchedAt: nil, sourceURL: nil,
                       builtAt: builtAt, sourceHash: "d0cbe84903e8",
                       buildPath: URL(fileURLWithPath: "/tmp/Blender.app"), pinned: false)
    }

    func testBuildDatePrefersTheBuildsOwnDate() {
        let built = Date(timeIntervalSince1970: 1_000_000)
        let b = build(installedAt: Date(timeIntervalSince1970: 2_000_000), builtAt: built)
        XCTAssertEqual(b.buildDate, built)
        XCTAssertTrue(b.hasBuildDate)
    }

    func testInstallDateStandsInWhenNoneWasRecorded() {
        let added = Date(timeIntervalSince1970: 2_000_000)
        for missing in [nil, Date.distantPast] {
            let b = build(installedAt: added, builtAt: missing)
            XCTAssertEqual(b.buildDate, added)
            XCTAssertFalse(b.hasBuildDate)
        }
    }

    /// Daily leads both lists, because it is the track that moves nightly.
    func testDailyIsListedFirst() {
        XCTAssertEqual(BuildBranch.allCases, [.daily, .stable, .experimental])
    }
}
