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
/// one a manual install would show. Sparkle answers `yes\n` the same way
/// (sparkle-project/Sparkle#2930); Homebrew gets there by another road,
/// answering `qn\n` and, when that attach fails, converting the image to UDTO
/// (which drops the license) and mounting the copy.
///
/// Measured: `hdiutil` (26.7, 27.2) and `diskutil image` (27.2) read the answer
/// from stdin and attach; `no` or an empty stdin cancels; an image without a
/// license ignores the bytes. `diskutil image` on 26.7 ignores stdin and blocks
/// on such an image until the watchdog — one more reason it is not used before
/// 27.2.
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

    /// Detach `image`, mounted at `mountPoint`, forcibly. Returns whether it came
    /// off.
    ///
    /// Retried once after a short pause: a `ditto` that just finished copying
    /// can leave the volume momentarily busy, and a single forced detach then
    /// fails, leaking the mount and blocking workDir cleanup. The retry uses the
    /// other tool, which can detach an image either one attached.
    ///
    /// **When both fail, by the image's own disk.** A detach can unmount the
    /// volume and then fail on the disk, "Resource busy". The mount point is a
    /// plain directory from then on, so the second try by path fails "Failed to
    /// find disk" — and the image stayed attached, with nothing reported. Measured
    /// 2026-10-12 on the hosted xcode-27 runner (macOS 27.0.1), replaying this
    /// extraction on vendor images: once in 2640, with six at once; still attached
    /// 20 s later, gone at the first detach by device (runs 38272974218 and
    /// 38275499974). Not seen in 840 on a macOS 27.2 dev Mac. So the image is
    /// looked up in `hdiutil info` by its path and detached by device every
    /// second, for up to `deviceRetryBound`: on that runner a test image's disk
    /// stayed busy 8–19 s (#1244). The caller waits for it rather than leaving it
    /// to a background task, which `duo` could exit before.
    ///
    /// The pauses are taken in a detached task so a cancelled caller cannot cut
    /// them short — `Task.sleep` in this task would return at once and turn the
    /// retry into a second attempt on a volume that is still busy.
    @discardableResult
    static func detach(_ mountPoint: URL, image: URL) async -> Bool {
        await detach(mountPoint, image: image, steps: .live)
    }

    /// How long `detach` keeps trying by device once both tries by path failed.
    static let deviceRetryBound: Duration = .seconds(30)

    /// Where `hdiutil info` has an image: not attached, attached as a disk, or
    /// unknown — the table could not be read, or the entry has no whole disk.
    enum Attachment: Equatable {
        case none
        case disk(String)
        case unknown
    }

    /// What `detach` runs, so a test can replay a disk that stays busy without
    /// waiting on a real one. Production uses `live`.
    struct DetachSteps: Sendable {
        var byMountPoint: @Sendable (URL, Tool) async -> Bool
        var attachment: @Sendable (URL) async -> Attachment
        var byDevice: @Sendable (String, Tool) async -> Bool
        var pause: @Sendable (Duration) async -> Void
        var now: @Sendable () -> ContinuousClock.Instant

        static let live = DetachSteps(
            byMountPoint: { await DiskImageMount.detach($0, using: $1) },
            attachment: { await DiskImageMount.attachment(of: $0) },
            byDevice: { await DiskImageMount.detachDevice($0, using: $1) },
            pause: { duration in await Task.detached { try? await Task.sleep(for: duration) }.value },  // cancel-ok: Task.detached, so the caller's cancel never reaches this sleep (see detach)
            now: { ContinuousClock.now })
    }

    static func detach(_ mountPoint: URL, image: URL, steps: DetachSteps) async -> Bool {
        let tools: [Tool] = preferredTool == .diskutil ? [.diskutil, .hdiutil] : [.hdiutil, .diskutil]
        if await steps.byMountPoint(mountPoint, tools[0]) { return true }
        await steps.pause(.milliseconds(500))
        if await steps.byMountPoint(mountPoint, tools[1]) { return true }

        let deadline = steps.now() + deviceRetryBound
        var tries = 0
        while true {
            switch await steps.attachment(image) {
            case .none:
                return true
            case .unknown:
                Log.install.error(
                    "dmg: could not detach \(mountPoint.path, privacy: .public), and could not tell whether the image is still attached")
                return false
            case .disk(let device):
                tries += 1
                if await steps.byDevice(device, tools[0]) {
                    Log.install.notice(
                        "dmg: \(device, privacy: .public) stayed attached after its volume was unmounted; detached by device, try \(tries)")
                    return true
                }
                guard steps.now() < deadline else {
                    Log.install.error(
                        "dmg: \(device, privacy: .public) still attached after \(tries) tries by device; left attached")
                    return false
                }
            }
            await steps.pause(.seconds(1))
        }
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

    /// Both take a disk whose volume is already unmounted, whichever tool attached
    /// it (measured on 27.2: each tool on its own attach, `diskutil` on an
    /// `hdiutil` attach, `hdiutil` on a `diskutil` one).
    private static func detachDevice(_ device: String, using tool: Tool) async -> Bool {
        let r = switch tool {
        case .diskutil: try? await run("/usr/sbin/diskutil", ["eject", "force", device])
        case .hdiutil: try? await run("/usr/bin/hdiutil", ["detach", device, "-force"])
        }
        return r?.code == 0
    }

    /// `image`'s entry in `hdiutil info`, which lists what either tool attached.
    /// The device is the image's first whole disk: detaching it takes every disk
    /// the image carries, an APFS image's synthesized container included
    /// (measured on 27.2 with either tool: disk17 and its container disk18 both
    /// gone after detaching disk17).
    ///
    /// **Not listed is only believed after `absentListings` listings in a row.**
    /// While other images attach and detach, `hdiutil info -plist` now and then
    /// exits 0, with nothing on stderr, leaving out images that are attached, and
    /// the next listing has them again. On a 27.2 dev Mac, with an image held
    /// attached while eight others attached and detached in a loop: 9 such
    /// listings in 2,900, each with only the system's own images, and the 30
    /// listings read straight after 6 of them all had the image. On the hosted
    /// xcode-27 runner (27.0.1) a 7 KB listing among 11–21 KB ones left out an
    /// image a test held attached, while ten other detaches finished; the six
    /// listings over the next 5 s all had it (diag run 38376650037). Taken at its
    /// word, that is `.none`, which `detach` reports as detached while the disk
    /// stays attached.
    static func attachment(of image: URL) async -> Attachment {
        await attachment(of: image) {
            guard let r = try? await run("/usr/bin/hdiutil", ["info", "-plist"], capturingOutput: true),
                  r.code == 0
            else { return nil }
            return r.out
        }
    }

    /// How many `hdiutil info` listings in a row must leave an image out before
    /// `attachment(of:)` reports it `.none`.
    static let absentListings = 3

    /// `attachment(of:)` over `listing`, which returns `hdiutil info -plist`'s
    /// output, or nil when it could not be run — a test seam.
    static func attachment(of image: URL, listing: () async -> Data?) async -> Attachment {
        var found = Attachment.none
        for _ in 0..<absentListings {
            found = attachment(of: image, in: await listing())
            guard found == .none else { break }
        }
        return found
    }

    private static func attachment(of image: URL, in listing: Data?) -> Attachment {
        guard let listing,
              let plist = try? PropertyListSerialization.propertyList(from: listing, format: nil)
                as? [String: Any]
        else { return .unknown }
        let wanted = canonicalPath(image.path)
        let images = plist["images"] as? [[String: Any]] ?? []
        guard let entry = images.first(where: {
            ($0["image-path"] as? String).map(canonicalPath) == wanted
        }) else { return .none }
        let entities = entry["system-entities"] as? [[String: Any]] ?? []
        let device = entities.lazy
            .compactMap { $0["dev-entry"] as? String }
            .first { $0.range(of: #"^/dev/disk\d+$"#, options: .regularExpression) != nil }
        return device.map(Attachment.disk) ?? .unknown
    }

    /// An image `hdiutil info` lists: its file and where its volumes are
    /// mounted (none for a disk whose volume was unmounted and the disk left).
    struct AttachedImage: Equatable, Sendable {
        let image: String
        let mountPoints: [String]
    }

    /// Every image in one `hdiutil info -plist` listing, paths canonical; nil
    /// when the listing is missing or does not parse.
    static func attachedImages(in listing: Data?) -> [AttachedImage]? {
        guard let listing,
              let plist = try? PropertyListSerialization.propertyList(from: listing, format: nil)
                as? [String: Any]
        else { return nil }
        let images = plist["images"] as? [[String: Any]] ?? []
        return images.compactMap { entry in
            guard let path = entry["image-path"] as? String else { return nil }
            let entities = entry["system-entities"] as? [[String: Any]] ?? []
            return AttachedImage(
                image: canonicalPath(path),
                mountPoints: entities.compactMap { ($0["mount-point"] as? String).map(canonicalPath) })
        }
    }

    /// The images attached now, by `absentListings` listings merged: a listing
    /// can leave out an image that is attached (see `attachment(of:)`), never
    /// add one that is not, so an image in any of them is taken as attached.
    /// Nil when no listing could be read at all.
    static func attachedImages(listing: () async -> Data?) async -> [AttachedImage]? {
        var merged: [String: AttachedImage] = [:]
        var readAny = false
        for _ in 0..<absentListings {
            guard let images = attachedImages(in: await listing()) else { continue }
            readAny = true
            for image in images where merged[image.image] == nil { merged[image.image] = image }
        }
        return readAny ? merged.values.sorted { $0.image < $1.image } : nil
    }

    /// `hdiutil info -plist`, or nil when it cannot be run.
    static func infoListing() async -> Data? {
        guard let r = try? await run("/usr/bin/hdiutil", ["info", "-plist"], capturingOutput: true),
              r.code == 0
        else { return nil }
        return r.out
    }

    /// `hdiutil info` reports the path as it was passed to the attach, `/var/…`
    /// or `/private/var/…` for the same `$TMPDIR` file (measured on 27.2, either
    /// tool). Standardizing drops the `/private` while the file exists, which it
    /// does until the caller's `defer` has run.
    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
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
        _ launchPath: String, _ args: [String], standardInput: Data? = nil,
        capturingOutput: Bool = false
    ) async throws -> (code: Int32, err: String, out: Data) {
        let outcome = try await ChildProcess.run(
            launchPath, args, standardInput: standardInput,
            standardOutput: capturingOutput ? .capture : .discard,
            deadline: .init(terminateAfter: .seconds(300), killAfter: .seconds(305)),
            onCancel: .runToCompletion)
        return (outcome.terminationStatus, String(data: outcome.standardError, encoding: .utf8) ?? "",
                outcome.standardOutput)
    }
}
