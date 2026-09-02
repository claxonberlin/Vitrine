import XCTest
@testable import Vitrine

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
    func testKnownBranches() {
        XCTAssertTrue(LTS.contains(version: "4.2.3"))
        XCTAssertTrue(LTS.contains(version: "3.3.0"))
        XCTAssertFalse(LTS.contains(version: "4.1.1"))
        XCTAssertFalse(LTS.contains(version: "not-a-version"))
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
        XCTAssertTrue(DownloadState.installing.isActive)
        XCTAssertFalse(DownloadState.idle.isActive)
        XCTAssertFalse(DownloadState.failed("boom").isActive)
    }
}
