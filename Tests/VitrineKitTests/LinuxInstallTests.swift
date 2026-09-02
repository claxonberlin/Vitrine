#if os(Linux)
import XCTest
@testable import VitrineKit

/// Exercises the Linux unpack path against a real tarball shaped like the ones
/// blender.org publishes: a single top-level directory holding a `blender`
/// executable. This is the newest code in the project and the part that can't
/// be verified from macOS at all.
final class LinuxInstallTests: XCTestCase {
    private var scratch: URL!
    private let platform = LinuxIntegration()

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vitrine-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Builds `<name>.tar.gz` containing `<name>/blender` (mode 0755).
    private func makeArchive(named name: String) async throws -> URL {
        let staging = scratch.appendingPathComponent("staging", isDirectory: true)
        let buildDir = staging.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)

        let exe = buildDir.appendingPathComponent("blender")
        try "#!/bin/sh\necho 'Blender 4.2.1'\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let archive = scratch.appendingPathComponent("\(name).tar.gz")
        let result = try await Shell.run(
            "tar", ["-czf", archive.path, "-C", staging.path, name]
        )
        XCTAssertTrue(result.ok, "tar failed: \(result.stderrText)")
        return archive
    }

    func testExtractLiftsTheWrapperDirectoryIntoPlace() async throws {
        let name = "blender-4.2.1-linux-x64"
        let archive = try await makeArchive(named: name)
        let destination = scratch.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let buildPath = try await platform.extract(archive: archive, into: destination)

        XCTAssertEqual(buildPath.lastPathComponent, name)
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: buildPath.appendingPathComponent("blender").path
            )
        )
        // The staging directory must not survive the move.
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: destination.path
        )
        XCTAssertEqual(leftovers, [name])
    }

    func testFindBuildLocatesTheDirectoryHoldingTheExecutable() async throws {
        let name = "blender-4.5.0-linux-x64"
        let archive = try await makeArchive(named: name)
        let destination = scratch.appendingPathComponent("library2", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try await platform.extract(archive: archive, into: destination)

        let found = platform.findBuild(in: destination)
        XCTAssertEqual(found?.lastPathComponent, name)
    }

    func testVersionComesFromTheDirectoryName() async throws {
        let name = "blender-4.2.1-linux-x64"
        let archive = try await makeArchive(named: name)
        let destination = scratch.appendingPathComponent("library3", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let buildPath = try await platform.extract(archive: archive, into: destination)

        let version = await platform.version(ofBuildAt: buildPath)
        XCTAssertEqual(version, "4.2.1")
    }

    /// A build the user added by hand can sit in an arbitrarily named folder,
    /// so the version has to come from `blender --version` instead.
    func testVersionFallsBackToAskingBlender() async throws {
        let buildDir = scratch.appendingPathComponent("my-custom-build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let exe = buildDir.appendingPathComponent("blender")
        try "#!/bin/sh\necho 'Blender 4.2.1'\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let version = await platform.version(ofBuildAt: buildDir)
        XCTAssertEqual(version, "4.2.1")
    }

    func testExtractRejectsAnArchiveWithNoBlenderInside() async throws {
        let staging = scratch.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("junk"), withIntermediateDirectories: true
        )
        try "nothing".write(
            to: staging.appendingPathComponent("junk/readme.txt"),
            atomically: true, encoding: .utf8
        )
        let archive = scratch.appendingPathComponent("junk.tar.gz")
        _ = try await Shell.run("tar", ["-czf", archive.path, "-C", staging.path, "junk"])

        let destination = scratch.appendingPathComponent("library4", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            _ = try await platform.extract(archive: archive, into: destination)
            XCTFail("expected extraction to fail")
        } catch {
            XCTAssertTrue(error is InstallError)
        }
    }
}
#endif
