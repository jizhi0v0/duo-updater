import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Live verification of the vendor in-place install pipeline — WITHOUT the final
/// swap, so it never touches the installed apps. Confirms the two things that
/// can't be unit-tested offline: that each recipe resolves a real installer URL,
/// and that a downloaded build passes the mandatory code-signature + Team ID gate.

/// Every recipe with an install spec must resolve a concrete download URL + kind
/// from its live feed. Prints the plan to stderr.
@Test func vendorResolvesInstallPlans() async {
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    // The bundles we've enabled for one-click install (zip/dmg/tarGz swap, or
    // pkg → system installer). The channel is load-bearing: `VendorProbeSource`
    // only picks a recipe whose channel matches the app's, and `InstalledApp`
    // defaults to `.stable` — so a non-stable recipe must be asked for by channel
    // or it silently resolves nothing.
    let targets: [(id: String, channel: ReleaseChannel)] = [
        ("com.microsoft.VSCode", .stable), ("app.chatwise", .stable),
        ("com.openai.codex", .stable), ("com.conductor.app", .stable),
        ("org.videolan.vlc", .stable), ("dev.kdrag0n.MacVirt", .stable),
        ("io.tailscale.ipn.macsys", .stable), ("com.anthropic.claudefordesktop", .stable),
        ("ai.elementlabs.lmstudio", .stable), ("dev.warp.Warp-Stable", .stable),
        ("com.google.android.studio", .stable),  // website-install path (Toolbox copies are gated)
        ("com.oray.sunlogin.macclient", .stable),  // AweSun: pkg → system installer (WAF Referer)
        ("com.postmanlabs.mac", .stable),          // Postman: zip → in-place (self-updater, same Team)
        // Both Signal channels: the per-channel dmg filenames differ (beta carries
        // an extra `beta-` segment) and a vendor rename silently drops one-click to
        // detection-only, so each channel has to be resolved live, not just offline.
        ("org.whispersystems.signal-desktop", .stable),
        ("org.whispersystems.signal-desktop-beta", .beta),
    ]
    let source = VendorProbeSource()
    log("\n=== vendor install plans ===")
    for (bundleID, channel) in targets {
        let app = InstalledApp(
            name: bundleID, bundleID: bundleID,
            shortVersion: "0.0.0", buildVersion: "0",
            path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: channel)
        let remote = try? await source.latestVersion(for: app)
        let kind = remote?.vendorInstallerKind.map { "\($0)" } ?? "nil"
        let sum = remote?.expectedSHA512 != nil ? "sha512✓" : "—"
        log("• \(bundleID): v\(remote?.shortVersion ?? "?")  [\(kind)] \(sum)")
        log("    \(remote?.downloadURL?.absoluteString ?? "NO URL")")
        #expect(remote?.downloadURL != nil)
        #expect(remote?.vendorInstallerKind != nil)
        // pkg → manual installer (system installer); archives → in-place swap.
        #expect(remote?.requiresManualInstaller == (remote?.vendorInstallerKind == .pkg))
    }
}

/// AweSun's download host (`dw.oray.com`) sits behind an Aliyun WAF that serves
/// the dmg only to requests carrying a `Referer` — otherwise an anti-bot JS
/// challenge page (text/html). This proves (a) the recipe resolves a pkg plan
/// that carries the `Referer` header, and (b) that header is load-bearing: the
/// SAME range request serves `application/octet-stream` with it and `text/html`
/// without it. Uses a 1-byte range so it never pulls the ~99 MB dmg.
@Test func aweSunPkgPlanCarriesLoadBearingWAFHeader() async throws {
    let source = VendorProbeSource()
    let app = InstalledApp(
        name: "AweSun", bundleID: "com.oray.sunlogin.macclient",
        shortVersion: "0.0.0", buildVersion: "0",
        path: URL(fileURLWithPath: "/Applications/AweSun.app"),
        isMASApp: false, sparkleFeedURL: nil)

    guard let remote = try await source.latestVersion(for: app) else {
        Issue.record("AweSun probe resolved nothing"); return
    }
    #expect(remote.vendorInstallerKind == .pkg)
    #expect(remote.requiresManualInstaller == true)             // → system installer
    #expect(remote.downloadURL?.pathExtension.lowercased() == "dmg")
    #expect(remote.downloadHeaders["Referer"] != nil)           // WAF header present
    guard let url = remote.downloadURL else { return }

    func contentType(withReferer: Bool) async throws -> String? {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if withReferer, let ref = remote.downloadHeaders["Referer"] {
            req.setValue(ref, forHTTPHeaderField: "Referer")
        }
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
    }

    let withHeader = try await contentType(withReferer: true)
    let without = try await contentType(withReferer: false)
    #expect(withHeader?.contains("application/octet-stream") == true)  // real dmg
    #expect(without?.contains("text/html") == true)                    // WAF challenge
}

/// Postman ships a zip we swap in place, even though it self-updates via Squirrel:
/// the build comes from Postman's own CDN (`dl.pstmn.io`, no WAF) and the bundle
/// inside is signed by the SAME Team as the installed app, so the install can't
/// cross channels or downgrade. Confirms the resolved plan and that the CDN
/// actually serves a versioned zip (1-byte range — no ~131 MB pull).
@Test func postmanZipPlanResolvesOfficialBuild() async throws {
    let source = VendorProbeSource()
    let app = InstalledApp(
        name: "Postman", bundleID: "com.postmanlabs.mac",
        shortVersion: "0.0.0", buildVersion: "0",
        path: URL(fileURLWithPath: "/Applications/Postman.app"),
        isMASApp: false, sparkleFeedURL: nil)

    guard let remote = try await source.latestVersion(for: app),
          let url = remote.downloadURL, let version = remote.shortVersion else {
        Issue.record("Postman probe resolved no install plan"); return
    }
    #expect(remote.vendorInstallerKind == .zip)
    #expect(remote.requiresManualInstaller == false)            // → in-place swap
    #expect(remote.downloadHeaders.isEmpty)                     // no WAF, no headers
    #expect(url.host == "dl.pstmn.io")
    #expect(url.absoluteString.contains(version))               // versioned URL
    #expect(url.absoluteString.hasSuffix("osx_arm64"))

    var req = URLRequest(url: url)
    req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    let (_, resp) = try await URLSession.shared.data(for: req)
    let http = resp as? HTTPURLResponse
    let disp = http?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
    #expect(disp.lowercased().contains(".zip"))                 // a real zip download
    #expect(disp.contains(version))                             // for this exact version
}

/// The real proof: take whichever enabled app is actually installed (ChatWise
/// preferred — it ships a SHA-512), download the official build, verify checksum,
/// unpack, and run the SAME code-signature + Team ID gate the installer uses —
/// then stop. No swap, nothing replaced.
@Test func vendorDownloadPassesSignatureGate() async throws {
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    let installed = AppScanner().scan()
    // Exercise both archive paths with modestly-sized downloads: ChatWise (zip +
    // checksum) and VLC (dmg → hdiutil mount, http→https, ascending last-match).
    // Skip the big ones (OrbStack ~404 MB, Claude ~283 MB) — same code paths.
    let enabled = ["app.chatwise", "org.videolan.vlc"]
    let apps = enabled.compactMap { id in installed.first { $0.bundleID == id } }
    guard !apps.isEmpty else {
        log("⚠️ none of the targeted vendor apps are installed — skipping")
        return
    }
    for app in apps {
        try await checkGate(app, log: log)
    }
}

private func checkGate(_ app: InstalledApp, log: (String) -> Void) async throws {
    log("\n=== signature-gate check: \(app.name) (\(app.bundleID ?? "?")) ===")

    let source = VendorProbeSource()
    guard let remote = try await source.latestVersion(for: app),
          let url = remote.downloadURL,
          let kind = remote.vendorInstallerKind else {
        Issue.record("probe did not resolve an install plan for \(app.name)")
        return
    }
    log("download: \(url.absoluteString)  [\(kind)]")

    let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vendor-gate-test-\(app.id)")
    try? FileManager.default.removeItem(at: workDir)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }

    // Download.
    let downloader = Downloader(destinationDir: workDir) { _ in }
    let file = try await downloader.download(url)

    // Normalize extension by kind (mirror VendorInstaller).
    let ext: String
    switch kind { case .zip: ext = "zip"; case .dmg: ext = "dmg"; case .tarGz: ext = "tar.gz"; case .pkg: ext = "pkg" }
    var archive = file
    if !file.lastPathComponent.lowercased().hasSuffix(ext) {
        archive = workDir.appendingPathComponent("download.\(ext)")
        try FileManager.default.moveItem(at: file, to: archive)
    }

    // Checksum, when published.
    if let expected = remote.expectedSHA512 {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let actual = Data(SHA512.hash(data: data)).base64EncodedString()
        log("sha512 expected: \(expected.prefix(16))…  actual: \(actual.prefix(16))…")
        #expect(actual == expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Unpack + the mandatory gate.
    let newApp = try ArchiveExtractor.extractApp(from: archive, workDir: workDir)
    try SignatureVerifier.verifyCodeSignature(appAt: newApp)
    let installedTeam = try SignatureVerifier.teamIdentifier(at: app.path)
    let downloadedTeam = try SignatureVerifier.teamIdentifier(at: newApp)
    log("Team ID  installed: \(installedTeam ?? "nil")  downloaded: \(downloadedTeam ?? "nil")")
    try SignatureVerifier.verifyTeamIdentifierMatch(installedApp: app.path, downloadedApp: newApp)
    log("✅ gate passed — would swap safely (no swap performed)")
}
