import XCTest
@testable import VitrineKit

/// `ByteFormat` and `DateFormat.relative` replace ByteCountFormatter and
/// RelativeDateTimeFormatter, which have patchy coverage in
/// swift-corelibs-foundation. These tests pin the output so macOS and Fedora
/// can't drift apart.
final class ByteFormatTests: XCTestCase {
    func testBelowOneKilobyteStaysExact() {
        XCTAssertEqual(ByteFormat.string(0), "0 bytes")
        XCTAssertEqual(ByteFormat.string(512), "512 bytes")
        XCTAssertEqual(ByteFormat.string(999), "999 bytes")
    }

    func testDecimalUnits() {
        // 1000-based, matching ByteCountFormatter's .file style and the sizes
        // blender.org publishes.
        XCTAssertEqual(ByteFormat.string(1_000), "1.0 KB")
        XCTAssertEqual(ByteFormat.string(1_500), "1.5 KB")
        XCTAssertEqual(ByteFormat.string(1_000_000), "1.0 MB")
        XCTAssertEqual(ByteFormat.string(1_500_000_000), "1.5 GB")
    }

    func testDropsDecimalOnceValueReachesThreeDigits() {
        XCTAssertEqual(ByteFormat.string(350_000_000), "350 MB")
        XCTAssertEqual(ByteFormat.string(99_900_000), "99.9 MB")
    }
}

final class RelativeDateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func relative(secondsAgo: Double) -> String {
        DateFormat.relative(now.addingTimeInterval(-secondsAgo), now: now)
    }

    func testSubMinuteCollapsesToJustNow() {
        XCTAssertEqual(relative(secondsAgo: 0), "just now")
        XCTAssertEqual(relative(secondsAgo: 59), "just now")
    }

    func testEachUnitBoundary() {
        XCTAssertEqual(relative(secondsAgo: 90), "1m ago")
        XCTAssertEqual(relative(secondsAgo: 3_700), "1h ago")
        XCTAssertEqual(relative(secondsAgo: 172_800), "2d ago")
        XCTAssertEqual(relative(secondsAgo: 864_000), "1w ago")
        XCTAssertEqual(relative(secondsAgo: 3_456_000), "1mo ago")
        XCTAssertEqual(relative(secondsAgo: 34_560_000), "1y ago")
    }
}

/// The platform descriptors decide which upstream files are installable, so
/// both are exercised from either host.
final class BuildPlatformTests: XCTestCase {
    private let mac = BuildPlatform(
        builderToken: "darwin",
        archiveSuffixes: [".dmg"],
        nameMarkers: ["darwin", "macos", "osx"],
        architectures: ["arm64", "aarch64"]
    )

    private let linux = BuildPlatform(
        builderToken: "linux",
        archiveSuffixes: [".tar.xz", ".tar.bz2", ".tar.gz"],
        nameMarkers: ["linux"],
        architectures: ["x86_64", "x64", "intel"]
    )

    func testArchiveMatchingIsScopedToTheHostOS() {
        XCTAssertTrue(mac.matchesArchive("blender-4.2.1-macos-arm64.dmg"))
        XCTAssertFalse(mac.matchesArchive("blender-4.2.1-linux-x64.tar.xz"))

        XCTAssertTrue(linux.matchesArchive("blender-4.2.1-linux-x64.tar.xz"))
        XCTAssertTrue(linux.matchesArchive("blender-2.83.0-linux64.tar.bz2"))
        XCTAssertFalse(linux.matchesArchive("blender-4.2.1-macos-arm64.dmg"))
    }

    func testNonArchiveFilesAreRejected() {
        // Checksums and installers sit alongside the real downloads.
        XCTAssertFalse(linux.matchesArchive("blender-4.2.1-linux-x64.tar.xz.sha256"))
        XCTAssertFalse(mac.matchesArchive("blender-4.2.1-windows-x64.msi"))
    }

    func testArchitectureAliasesAreTolerated() {
        // Upstream has used several spellings for the same architecture.
        XCTAssertTrue(mac.matchesArchitecture("arm64"))
        XCTAssertTrue(mac.matchesArchitecture("darwin-arm64"))
        XCTAssertTrue(mac.matchesArchitecture("aarch64"))
        XCTAssertFalse(mac.matchesArchitecture("x86_64"))
        XCTAssertFalse(mac.matchesArchitecture(nil))

        XCTAssertTrue(linux.matchesArchitecture("x86_64"))
        XCTAssertTrue(linux.matchesArchitecture("x64"))
        XCTAssertFalse(linux.matchesArchitecture("arm64"))
    }
}
