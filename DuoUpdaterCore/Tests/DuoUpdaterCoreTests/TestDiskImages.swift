import Foundation
@testable import DuoUpdaterCore

/// The disk images tests attach, read from `hdiutil info` rather than from the
/// mount point — and the ones earlier runs left behind.
///
/// Two ways an image outlived its test on the dev Macs (2026-10-12):
///
/// - The test process was killed between `attach` and its cleanup, so no `defer`
///   ran: the image is still mounted and its scratch directory is still there.
///   Nothing in-process can stop that, so `sweepStaleOnce` clears it on the next
///   run instead.
/// - `detach <mount point>` unmounted the volume but the disk stayed attached (an
///   APFS sparse image, once in ~30 `BackupDestinationProbeTests` runs). The mount
///   point is now a plain directory, so a retry by path cannot reach the disk —
///   `detach` here goes by the image's own device node.
enum TestDiskImages {

    /// Scratch images older than this are no live run's: every test that
    /// attaches one finishes in well under a minute.
    static let staleAfter: TimeInterval = 3600

    struct Attachment {
        let imagePath: String
        /// The image's own disk (`/dev/diskN`), the first whole-disk entry `hdiutil`
        /// lists for it. Detaching it ejects every disk the image carries, an APFS
        /// image's synthesized container included: an APFS sparse image lists
        /// disk4, disk4s1, disk5 (the container), disk5s1, and `detach disk4`
        /// leaves none of them (macOS 26.7, 2026-10-12).
        let device: String?
    }

    static func attachments() async -> [Attachment] {
        guard let outcome = try? await ChildProcess.run(
            "/usr/bin/hdiutil", ["info", "-plist"], standardError: .discard,
            onCancel: .runToCompletion),
            outcome.terminationStatus == 0,
            let plist = try? PropertyListSerialization.propertyList(
                from: outcome.standardOutput, format: nil) as? [String: Any],
            let images = plist["images"] as? [[String: Any]]
        else { return [] }
        return images.compactMap { image in
            guard let path = image["image-path"] as? String else { return nil }
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            let device = entities.lazy
                .compactMap { $0["dev-entry"] as? String }
                .first { $0.range(of: #"^/dev/disk\d+$"#, options: .regularExpression) != nil }
            return Attachment(imagePath: path, device: device)
        }
    }

    static func isAttached(_ image: URL) async -> Bool {
        let path = canonical(image.path)
        return await attachments().contains { canonical($0.imagePath) == path }
    }

    /// Detach `image` by its device node if it is still attached. True when it is
    /// gone afterwards (or was never attached).
    ///
    /// Retried for up to a minute, a second apart: on the hosted xcode-27 runner
    /// (macOS 27.0.1) the disk can stay busy for a moment after its volume is
    /// unmounted. In 60 full Release runs of the Core tests there (diag run
    /// 38251826792, 2026-10-12), `detach /dev/diskN` and then `detach -force`
    /// both failed "couldn't eject "diskN" - Resource busy" (exit 49168) 12
    /// times, and every one ejected on a later try. `sudo lsof` on the disk's /dev
    /// and /dev/r nodes found no open file, and `mount` no longer listed the disk,
    /// so what held it is unknown. Retrying every second with nothing in between
    /// (diag run 38264772681), the 5 busy disks in 330 detaches ejected 7.9–10.6 s
    /// after the first try. `diskutil eject` did no better: 7 in 330 after an
    /// `hdiutil` attach, 6 in 330 after a `diskutil image attach`, ejected
    /// 7.1–18.6 s after the first try.
    @discardableResult
    static func detach(_ image: URL) async -> Bool {
        let path = canonical(image.path)
        let deadline = ContinuousClock.now + .seconds(60)
        while true {
            let devices = await attachments()
                .filter { canonical($0.imagePath) == path }
                .compactMap(\.device)
            if devices.isEmpty { return await !isAttached(image) }
            for device in devices {
                if await hdiutil(["detach", device]) != 0 {
                    await hdiutil(["detach", device, "-force"])
                }
            }
            if await !isAttached(image) { return true }
            guard ContinuousClock.now < deadline,
                  (try? await Task.sleep(for: .seconds(1))) != nil
            else { return false }
        }
    }

    /// Once per test process: detach what earlier, killed runs left attached, and
    /// remove its scratch files. Only images under `$TMPDIR` with a test's naming,
    /// and only stale ones — a concurrent run in another worktree shares `$TMPDIR`.
    static func sweepStaleOnce() async { await sweep.value }

    private static let sweep = Task { await sweepStale() }

    private static func sweepStale() async {
        let fm = FileManager.default
        let tmp = canonical(fm.temporaryDirectory.path)
        for attachment in await attachments() {
            let image = URL(fileURLWithPath: canonical(attachment.imagePath))
            guard image.path.hasPrefix(tmp + "/"),
                  let leftover = scratchOwning(image, under: tmp)
            else { continue }
            // A missing backing file is an image some test already cleaned up
            // after; nothing live deletes its image before detaching it.
            if let modified = (try? fm.attributesOfItem(atPath: image.path))?[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < staleAfter { continue }
            guard await detach(image) else { continue }
            for url in leftover { try? fm.removeItem(at: url) }
        }
    }

    /// What a test made alongside `image`, to remove once it is detached — or nil
    /// when `image` is not a test's at all.
    private static func scratchOwning(_ image: URL, under tmp: String) -> [URL]? {
        let name = image.lastPathComponent
        // `BackupDestinationProbeTests.withVolume`: duo-<UUID>.sparseimage, mounted
        // at duo-mnt-<UUID>.
        if image.deletingLastPathComponent().path == tmp,
           name.hasPrefix("duo-"), name.hasSuffix(".sparseimage") {
            let id = name.dropFirst("duo-".count).dropLast(".sparseimage".count)
            return [image, URL(fileURLWithPath: tmp).appendingPathComponent("duo-mnt-\(id)")]
        }
        // `InstallChildProcessTests.scratch`: everything under one
        // ZZFixture-install-<label>-<UUID> directory.
        let relative = image.path.dropFirst(tmp.count + 1)
        if let top = relative.split(separator: "/").first, top.hasPrefix("ZZFixture-install-") {
            return [URL(fileURLWithPath: tmp).appendingPathComponent(String(top))]
        }
        return nil
    }

    /// `hdiutil` reports `/var/folders/…`; `$TMPDIR` may come back as either that
    /// or `/private/var/folders/…`.
    private static func canonical(_ path: String) -> String {
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        return standard.hasPrefix("/private/var/") ? String(standard.dropFirst("/private".count)) : standard
    }

    @discardableResult
    private static func hdiutil(_ arguments: [String]) async -> Int32 {
        (try? await ChildProcess.run(
            "/usr/bin/hdiutil", arguments,
            standardOutput: .discard, standardError: .discard,
            onCancel: .runToCompletion))?.terminationStatus ?? -1
    }
}
