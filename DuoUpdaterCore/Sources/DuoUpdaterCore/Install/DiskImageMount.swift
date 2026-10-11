import Foundation

/// Mounts a downloaded disk image read-only at a caller-owned directory, and
/// unmounts it again. Shared by both routes that open a vendor `.dmg`:
/// `ArchiveExtractor.fromDMG` (copy the `.app` out) and
/// `PackageInstaller.resolveInstaller` (copy the `.pkg` out).
///
/// **macOS 27.2+ attaches with `diskutil image attach`; earlier systems keep
/// `hdiutil attach`.** macOS 27 deprecates `hdiutil` in its man page and, from
/// 27.2, every `hdiutil attach`/`detach` prints a deprecation warning to stderr
/// — which would otherwise lead every `ExtractError.toolFailed` message. Sparkle
/// switched at the same boundary (sparkle-project/Sparkle#2930).
///
/// The two are different back ends, not two spellings of one: `hdiutil` is
/// served by DiskImages.framework's `diskimages-helper`, `diskutil image` by
/// DiskImages2's `diskimagesiod`. Measured on macOS 27.2 (M3 Max), copying
/// Chrome's 207 MB bzip2 image out with `ditto`: 13.2 s with `hdiutil`, whose
/// helper decompresses on one core (100% CPU), against 8.2 s with `diskutil`
/// (~350% average). The attach itself is ~0.3 s slower, so a small image is a
/// wash; the win is on large ones.
///
/// Measured behaviour this relies on, on 26.7 and 27.2:
/// - `--readOnly --nobrowse --mountPoint` behave as `hdiutil`'s `-readonly
///   -nobrowse -mountpoint`, including on a symlinked path (`$TMPDIR` under
///   `/var`). There is no `-noverify`: `diskutil` does not checksum at attach,
///   which is what `-noverify` asked `hdiutil` for.
/// - `diskutil` refuses `--mountPoint` on an image with more than one mountable
///   volume, where `hdiutil` mounts one of them. A failed `diskutil` attach
///   leaves nothing attached, so the `hdiutil` fallback below is clean.
/// - `diskutil eject force <mount point>` detaches the whole image (not only the
///   volume), whichever tool attached it, even with a file in it held open — as
///   `hdiutil detach -force` did. A plain `eject` is refused while busy.
/// - Encrypted images fail on both tools alike with stdin at `/dev/null`; no
///   route has ever answered a passphrase prompt.
///
/// **A license agreement is accepted on the user's behalf**, by answering `yes`
/// on stdin. Some vendors still wrap their `.dmg` in one, and without an answer
/// both tools print the license and cancel the attach (exit 1), so the update
/// could never install. The user asked for the update, and the license is the
/// one a manual install would show; Sparkle answers `yes\n` the same way, and
/// Homebrew `qy\n`. Measured: `hdiutil` (26.7, 27.2) and `diskutil image`
/// (27.2) read the answer from stdin and attach; `no` or an empty stdin
/// cancels; an image without a license ignores the bytes. `diskutil image` on
/// 26.7 ignores stdin and blocks on such an image until the watchdog — one more
/// reason it is not used before 27.2.
enum DiskImageMount {

    enum Tool: Sendable, Equatable {
        case diskutil, hdiutil
    }

    /// Test seam: force a tool regardless of the host's version, so the
    /// `diskutil` route is exercised on a Mac older than 27.2 (`diskutil image`
    /// itself exists earlier). Production never binds it.
    @TaskLocal static var toolOverride: Tool?

    /// The tool to try first on this Mac.
    static var preferredTool: Tool {
        if let toolOverride { return toolOverride }
        let modern = OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(modern) ? .diskutil : .hdiutil
    }

    struct AttachFailure: Error {
        let tool: String
        let code: Int32
        let stderr: String
    }

    /// Attach `image` read-only and hidden from Finder at `mountPoint`, which
    /// must already exist.
    ///
    /// When `diskutil` is preferred and refuses the image, `hdiutil` gets a
    /// second try: the one known refusal (several mountable volumes) is an image
    /// `hdiutil` opens. If both refuse, the failure reported is `diskutil`'s, the
    /// tool this Mac is meant to be using.
    ///
    /// Throws only when a tool cannot be launched at all.
    static func attach(_ image: URL, at mountPoint: URL) async throws -> Result<Void, AttachFailure> {
        let first = try await attach(image, at: mountPoint, using: preferredTool)
        guard case .failure = first, preferredTool == .diskutil else { return first }
        if case .success = try await attach(image, at: mountPoint, using: .hdiutil) {
            return .success(())
        }
        return first
    }

    /// Detach whatever is mounted at `mountPoint`, forcibly. Returns whether it
    /// came off.
    ///
    /// Retried once after a short pause: a `ditto` that just finished copying
    /// can leave the volume momentarily busy, and a single forced detach then
    /// fails, leaking the mount and blocking workDir cleanup. The retry uses the
    /// other tool, which can detach an image either one attached.
    ///
    /// The pause is taken in a detached task so a cancelled caller cannot cut it
    /// short — `Task.sleep` in this task would return at once and turn the retry
    /// into a second attempt on a volume that is still busy.
    @discardableResult
    static func detach(_ mountPoint: URL) async -> Bool {
        let tools: [Tool] = preferredTool == .diskutil ? [.diskutil, .hdiutil] : [.hdiutil, .diskutil]
        if await detach(mountPoint, using: tools[0]) { return true }
        await Task.detached { try? await Task.sleep(for: .milliseconds(500)) }.value
        return await detach(mountPoint, using: tools[1])
    }

    // MARK: - One tool

    private static func attach(
        _ image: URL, at mountPoint: URL, using tool: Tool
    ) async throws -> Result<Void, AttachFailure> {
        let (path, args, label): (String, [String], String) = switch tool {
        case .diskutil:
            ("/usr/sbin/diskutil",
             ["image", "attach", "--readOnly", "--nobrowse",
              "--mountPoint", mountPoint.path, image.path],
             "diskutil image attach")
        case .hdiutil:
            ("/usr/bin/hdiutil",
             ["attach", image.path, "-nobrowse", "-readonly", "-noverify",
              "-mountpoint", mountPoint.path],
             "hdiutil attach")
        }
        let r = try await run(path, args, standardInput: licenseAnswer)
        return r.code == 0 ? .success(()) : .failure(AttachFailure(tool: label, code: r.code, stderr: r.err))
    }

    private static func detach(_ mountPoint: URL, using tool: Tool) async -> Bool {
        let r = switch tool {
        case .diskutil: try? await run("/usr/sbin/diskutil", ["eject", "force", mountPoint.path])
        case .hdiutil: try? await run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
        }
        return r?.code == 0
    }

    /// What an attach reads from stdin: accept a license agreement, if the image
    /// has one. Short enough for `ChildProcess` to hand over before the spawn, so
    /// a tool that exits without reading it cannot SIGPIPE this process.
    static let licenseAnswer = Data("yes\n".utf8)

    /// Watchdog: a wedged attach on a malformed or maliciously crafted image can
    /// block indefinitely, freezing the install with no way out. SIGTERM at
    /// 300 s, SIGKILL at 305 s if it ignores that — the same bound
    /// `ArchiveExtractor` puts on every tool it runs.
    ///
    /// `.runToCompletion`: these run inside a caller's `defer` on cancellation,
    /// and a killed detach is exactly the leaked mount this type must not have.
    private static func run(
        _ launchPath: String, _ args: [String], standardInput: Data? = nil
    ) async throws -> (code: Int32, err: String) {
        let outcome = try await ChildProcess.run(
            launchPath, args, standardInput: standardInput, standardOutput: .discard,
            deadline: .init(terminateAfter: .seconds(300), killAfter: .seconds(305)),
            onCancel: .runToCompletion)
        return (outcome.terminationStatus, String(data: outcome.standardError, encoding: .utf8) ?? "")
    }
}
