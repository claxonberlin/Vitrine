import Foundation

/// Minimal async wrapper around `Process`.
///
/// Both platform layers delegate to command-line tools that ship with the OS
/// — `hdiutil` on macOS, `tar` / `xdg-mime` / `gsettings` on Linux — so this
/// is the single shared primitive underneath them. Everything is invoked via
/// `/usr/bin/env` (present on both platforms) so tool locations resolve from
/// PATH rather than being hardcoded per distribution.
enum Shell {
    struct Result: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data

        var ok: Bool { status == 0 }
        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    }

    /// Runs `tool` with `arguments` and collects its output.
    ///
    /// Both pipes are drained concurrently *before* reaping the process. The
    /// obvious alternative — reading inside `terminationHandler` — deadlocks
    /// as soon as a tool writes more than the 64 KB pipe buffer, because the
    /// child blocks on write and so never terminates.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) async throws -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [tool] + arguments
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = FileHandle.nullDevice

        try proc.run()

        async let stdout = drain(out.fileHandleForReading)
        async let stderr = drain(err.fileHandleForReading)
        let (o, e) = await (stdout, stderr)

        // Both pipes are at EOF, so the child has finished writing and this
        // returns essentially immediately.
        proc.waitUntilExit()
        return Result(status: proc.terminationStatus, stdout: o, stderr: e)
    }

    /// Launches `tool` and returns without waiting. Used for the Blender
    /// process itself, which must outlive the call (and ideally Vitrine).
    static func spawnDetached(_ executable: URL, arguments: [String] = []) throws {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        proc.currentDirectoryURL = executable.deletingLastPathComponent()
        try proc.run()
    }

    /// Whether a tool exists on PATH. Lets the Linux layer degrade gracefully
    /// on desktops that lack `gsettings` (KDE, Sway, …) instead of erroring.
    static func exists(_ tool: String) async -> Bool {
        ((try? await run("sh", ["-c", "command -v \(tool) >/dev/null 2>&1"]))?.ok) ?? false
    }

    private static func drain(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: (try? handle.readToEnd()) ?? Data())
            }
        }
    }
}
