import Testing
import Foundation
@testable import DuoUpdaterCore

/// Exercises the install pipeline against a REAL Sparkle update — download,
/// EdDSA verify, extract, code-signature + Team ID verify — but stops short of
/// actually replacing anything on disk. Validates the security gates against a
/// genuinely signed download without touching the user's apps.
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

    log("\n=== Install dry-run: \(candidates.count) verifiable Sparkle updates ===")
    guard let target = candidates.first else {
        log("(no candidate with EdDSA signature available — skipping)")
        return
    }
    guard let remote = target.remote, let url = remote.downloadURL else { return }
    log("Target: \(target.app.name) \(target.app.shortVersion ?? "?") → \(remote.displayVersion ?? "?")")
    log("URL: \(url.absoluteString)")

    let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DuoUpdaterTest-\(target.app.id)")
    try? FileManager.default.removeItem(at: workDir)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }

    // 1. Download
    let downloader = Downloader(destinationDir: workDir) { _ in }
    let archive = try await downloader.download(url)
    let size = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int) ?? 0
    log("✓ downloaded \(archive.lastPathComponent) (\((size ?? 0) / 1024) KB)")

    // Traffic accounting: the byte count we report for per-app stats must equal
    // the exact size of the file we wrote — to the byte, over a real download.
    #expect(downloader.bytesDownloaded == Int64(size ?? 0))
    #expect(downloader.bytesDownloaded > 0)

    // 2. EdDSA
    let data = try Data(contentsOf: archive, options: .mappedIfSafe)
    try SignatureVerifier.verifyEdSignature(
        fileData: data, signatureBase64: remote.edSignature, publicKeyBase64: target.app.sparkleEdPublicKey!
    )
    log("✓ EdDSA signature valid")

    // 3. Extract
    let newApp = try ArchiveExtractor.extractApp(from: archive, workDir: workDir)
    log("✓ extracted \(newApp.lastPathComponent)")

    // 4. Code signature + Team ID
    try SignatureVerifier.verifyCodeSignature(appAt: newApp)
    let newTeam = try SignatureVerifier.teamIdentifier(at: newApp)
    let oldTeam = try SignatureVerifier.teamIdentifier(at: target.app.path)
    try SignatureVerifier.verifyTeamIdentifierMatch(installedApp: target.app.path, downloadedApp: newApp)
    log("✓ code signature valid; Team ID match: \(oldTeam ?? "?") == \(newTeam ?? "?")")
    log("=== ALL GATES PASSED (no install performed) ===")
}
