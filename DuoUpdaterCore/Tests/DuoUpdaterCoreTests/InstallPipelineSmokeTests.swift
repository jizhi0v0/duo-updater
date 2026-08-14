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
    let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DuoUpdaterTest-\(target.app.scratchSlug)")
    try? FileManager.default.removeItem(at: workDir)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }

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
