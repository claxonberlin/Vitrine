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

final class DownloadStateTests: XCTestCase {
    func testIsActive() {
        XCTAssertTrue(DownloadState.queued.isActive)
        XCTAssertTrue(DownloadState.downloading(received: 1, total: 2).isActive)
        XCTAssertTrue(DownloadState.installing(fraction: nil).isActive)
        XCTAssertFalse(DownloadState.idle.isActive)
        XCTAssertFalse(DownloadState.failed("boom").isActive)
    }
}

/// Which builds wear a risk chip is one rule, shared by both front ends, by
/// both pages and by both kinds of build, so it is pinned here rather than
/// re-derived per view.
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

    func testStableBesideLTSSaysNothingTwice() {
        XCTAssertNil(remote(version: "4.5.13", riskId: "stable").riskLabel(besideLTS: true))
        XCTAssertNil(installed(version: "4.5.13", riskId: "stable", branch: .stable)
            .riskLabel(besideLTS: true))
    }

    func testStableOnItsOwnStillSaysSo() {
        XCTAssertEqual(remote(version: "4.3.2", riskId: "stable").riskLabel(besideLTS: false),
                       "Stable")
        XCTAssertEqual(installed(version: "4.3.2", riskId: "stable", branch: .stable)
            .riskLabel(besideLTS: false), "Stable")
    }

    func testAnythingElseKeepsItsChipEvenBesideLTS() {
        XCTAssertEqual(remote(version: "5.3.0", riskId: "alpha").riskLabel(besideLTS: true),
                       "Alpha")
        XCTAssertEqual(installed(version: "5.3.0", riskId: "alpha", branch: .daily)
            .riskLabel(besideLTS: false), "Alpha")
        XCTAssertEqual(installed(version: "mine", riskId: InstalledBuild.customRiskID,
                                 branch: .stable).riskLabel(besideLTS: false), "Custom")
    }
}

/// A daily says which day it came from, not how many hours ago it was built.
final class RecentDayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_757_500_000)

    private func day(offsetBy days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now)!
    }

    func testTodayAndYesterdayAreNamed() {
        XCTAssertEqual(DateFormat.recentDay(day(offsetBy: 0), now: now), "Today")
        XCTAssertEqual(DateFormat.recentDay(day(offsetBy: 1), now: now), "Yesterday")
    }

    func testAnythingOlderIsADate() {
        let older = day(offsetBy: 2)
        XCTAssertEqual(DateFormat.recentDay(older, now: now), DateFormat.day(older))
    }

    func testUndatedStaysThePlaceholder() {
        XCTAssertEqual(DateFormat.recentDay(.distantPast, now: now), "—")
    }
}

/// The paintings travel inside the app. If this fails, either `splashes.sh`
/// hasn't been run or the resource declaration in `Package.swift` moved.
final class BundledSplashTests: XCTestCase {
    func testEveryReleasedSeriesHasArtwork() {
        for series in ["2.80", "2.93", "3.6", "4.2", "4.5", "5.0", "5.2"] {
            XCTAssertNotNil(SplashLibrary.bundledFile(named: series),
                            "no bundled splash for \(series)")
        }
    }

    func testDailiesHaveTheirStandingBackdrop() {
        XCTAssertNotNil(SplashLibrary.dailyArtwork)
    }
}
