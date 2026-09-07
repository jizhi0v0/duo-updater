import Testing
import Foundation
@testable import DuoUpdaterCore

/// Exercises the install pipeline against REAL Sparkle updates — download,
/// EdDSA verify, extract, code-signature + Team ID + bundle id verify — but
/// stops short of actually replacing anything on disk. Validates the security
/// gates against genuinely signed downloads without touching the user's apps.
///
/// This is the ONLY thing that walks the install path end to end. `duo verify`
/// deliberately never downloads an installer (it stops at resolving the URL), so
/// a failure that only shows up over the downloaded bytes — a vendor rotating
/// its Sparkle key, re-signing under a different Team, publishing an archive
/// that won't extract — is invisible to the nightly recipe sweep. Mirage Beacon
/// 1.3.0 (2026-08) was found by a user pressing Update, not by any check here.
///
/// Coverage is env-gated because breadth costs bandwidth:
///
/// - unset (the `make test` default): the first candidate only — a cheap smoke
///   test, the historical behaviour.
/// - `DUO_INSTALL_SMOKE=all`: every candidate, **strictly serially, deleting
///   each download before starting the next**, so peak disk is one archive and
///   not the sum of them. This is what the nightly runner sets.
@Test func installPipelineDryRun() async throws {
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    // Find Sparkle apps that have an update AND the metadata we need to verify.
    let apps = AppScanner().scan().filter {
        $0.sparkleFeedURL != nil && $0.sparkleEdPublicKey != nil
    }
    let checker = UpdateChecker(sources: [SparkleAppcastSource()])
    let results = await checker.check(apps)
    let candidates = results.filter {
        $0.hasUpdate && $0.remote?.edSignature != nil && $0.remote?.downloadURL != nil
    }

    let sweepAll = ProcessInfo.processInfo.environment["DUO_INSTALL_SMOKE"] == "all"
    let targets = sweepAll ? candidates : Array(candidates.prefix(1))

    log("\n=== Install dry-run: \(candidates.count) verifiable Sparkle updates"
        + " (checking \(targets.count)) ===")
    guard !targets.isEmpty else {
        log("(no candidate with EdDSA signature available — skipping)")
        return
    }

    // Collected rather than thrown, so one broken vendor doesn't hide the state
    // of every app queued behind it.
    var failures: [String] = []

    for target in targets {
        do {
            try await verifyGates(target, log: log)
        } catch {
            let label = "\(target.app.name) → \(target.remote?.displayVersion ?? "?")"
            log("✘ \(label): \(error.localizedDescription)")
            failures.append("\(label): \(error.localizedDescription)")
        }
    }

    #expect(
        failures.isEmpty,
        Comment(rawValue: "install path broken for:\n" + failures.joined(separator: "\n")))
}

/// Download `target` and run every gate `SparkleInstaller.apply` runs, then
/// delete the download. The scratch dir is removed on the way out of this
/// function — success or failure — which is what keeps a full sweep's disk
/// footprint at one archive.
private func verifyGates(
    _ target: UpdateResult,
    log: (String) -> Void
) async throws {
    guard let remote = target.remote, let url = remote.downloadURL else { return }
    log("Target: \(target.app.name) \(target.app.shortVersion ?? "?") → \(remote.displayVersion ?? "?")")
    log("URL: \(url.absoluteString)")

    // `scratchSlug`, not `app.id` — the latter is the app's full path, so it
    // built a nested `DuoUpdaterTest-/Users/.../Foo.app` tree whose empty parent
    // directories outlived the run. Harmless once a day by hand; not something
    // to leave behind on a runner that now does this for every app, nightly.
    //
    // The UUID is what keeps the name from being a SHARED path. `scratchSlug` is
    // deliberately stable across launches (it is a SHA-256 of the installed app's
    // path, so a crashed install can reclaim its dir by name), and
    // `temporaryDirectory` is per-user, not per-process — so without it, every
    // process on this Mac running this test for the same app names the SAME
    // directory, and the two lines below are then aimed at each other: each run
    // deletes the other's in-flight download, and the loser's `Downloader` fails
    // its final rename with "either the former doesn't exist, or the folder
    // containing the latter doesn't exist". Measured 2026-09-07: two concurrent
    // `swift test --filter installPipelineDryRun` (separate `--scratch-path`s, so
    // SwiftPM's build lock doesn't serialise them) both failed that way, on
    // `DuoUpdaterTest-net.imput.helium-b233bd2839efd54c`. That is a collision, not
    // a vendor problem — but it arrives dressed as one, in a test whose whole job
    // is to report vendor breakage. Concurrent runs are routine here: this repo is
    // worked in several worktrees at once, which is the same hazard
    // `scripts/derived_data_path.py` exists to solve for xcodebuild.
    let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DuoUpdaterTest-\(target.app.scratchSlug)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }
    // A unique name means nothing reclaims it by name any more, so a run killed
    // mid-download (^C, the hang watchdog) would leak ~120 MB per crash instead of
    // being overwritten next time. Sweep old siblings instead — age-gated, because
    // "not mine" is exactly the judgement that caused the collision above, and a
    // live download can legitimately run for a long time on a slow link.
    sweepStaleScratchDirs(olderThan: 6 * 60 * 60)

    // 1. Download
    let downloader = Downloader(destinationDir: workDir) { _ in }
    let archive = try await downloader.download(url)
    let size = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int) ?? 0
    log("✓ downloaded \(archive.lastPathComponent) (\(size / 1024) KB)")

    // Traffic accounting: the byte count we report for per-app stats must equal
    // the exact size of the file we wrote — to the byte, over a real download.
    #expect(downloader.bytesDownloaded == Int64(size))
    #expect(downloader.bytesDownloaded > 0)

    // 2. EdDSA
    let data = try Data(contentsOf: archive, options: .mappedIfSafe)
    var edFailure: Error?
    do {
        try SignatureVerifier.verifyEdSignature(
            fileData: data, signatureBase64: remote.edSignature,
            publicKeyBase64: target.app.sparkleEdPublicKey!
        )
        log("✓ EdDSA signature valid")
    } catch SignatureVerifier.VerifyError.edSignatureInvalid {
        edFailure = SignatureVerifier.VerifyError.edSignatureInvalid
    }

    // 3. Extract
    let newApp = try ArchiveExtractor.extractApp(from: archive, workDir: workDir)
    log("✓ extracted \(newApp.lastPathComponent)")

    // 3b. Gate 1b — same call production makes: a signature that only verifies
    // under a DIFFERENT key shipped inside the download is a vendor key
    // rotation, and falls through to the gates below rather than failing. Worth
    // saying out loud in the log: the app is installable, but its Sparkle chain
    // is broken for everyone until they update once.
    if let edFailure {
        guard SignatureVerifier.isEdKeyRotation(
            fileData: data, signatureBase64: remote.edSignature,
            installedKeyBase64: target.app.sparkleEdPublicKey!, downloadedApp: newApp
        ) else { throw edFailure }
        log("⚠︎ EdDSA key rotated by vendor — falling back to the Team ID gate")
    }

    // 4. Code signature + Team ID + bundle id
    try SignatureVerifier.verifyCodeSignature(appAt: newApp)
    let newTeam = try SignatureVerifier.teamIdentifier(at: newApp)
    let oldTeam = try SignatureVerifier.teamIdentifier(at: target.app.path)
    try SignatureVerifier.verifyTeamIdentifierMatch(installedApp: target.app.path, downloadedApp: newApp)
    try SignatureVerifier.verifyBundleIdentifierMatch(installedApp: target.app.path, downloadedApp: newApp)
    log("✓ code signature valid; Team ID match: \(oldTeam ?? "?") == \(newTeam ?? "?")")
    log("=== ALL GATES PASSED (no install performed) ===")
}

/// Delete leftover scratch dirs from runs that were killed before their `defer`
/// could fire. Only dirs older than `seconds` are touched: a newer one may belong
/// to a run happening right now in another checkout.
private func sweepStaleScratchDirs(olderThan seconds: TimeInterval) {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory
    guard let entries = try? fm.contentsOfDirectory(
        at: tmp, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
    for entry in entries where entry.lastPathComponent.hasPrefix("DuoUpdaterTest-") {
        guard let touched = lastTouched(entry),
              Date().timeIntervalSince(touched) > seconds else { continue }
        try? fm.removeItem(at: entry)
    }
}

/// The most recent modification anywhere one level inside `dir`, or the dir's own
/// if it is empty.
///
/// A directory's own mtime records changes to its *entries*, not writes into
/// them: measured 2026-09-07, creating a `.partial` stamps the dir, and appending
/// 5 MB to that file three seconds later moves the file's mtime and leaves the
/// dir's exactly where it was. Reading only the dir would therefore date a live
/// download from the moment it *started*, so a transfer slow enough to run past
/// the age gate — a large payload on a throttled link, across up to
/// `Downloader.maxAttempts` resumes — would look abandoned to a run starting
/// beside it, and get deleted mid-flight. That is the collision this whole change
/// removes, so the gate has to key on progress rather than on age.
private func lastTouched(_ dir: URL) -> Date? {
    let key: URLResourceKey = .contentModificationDateKey
    let own = (try? dir.resourceValues(forKeys: [key]))?.contentModificationDate
    let children = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [key])) ?? []
    return children
        .compactMap { (try? $0.resourceValues(forKeys: [key]))?.contentModificationDate }
        .reduce(own) { max($0 ?? $1, $1) }
}
