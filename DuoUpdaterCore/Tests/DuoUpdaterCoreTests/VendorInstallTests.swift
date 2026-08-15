import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Live verification of the vendor in-place install pipeline — WITHOUT the final
/// swap, so it never touches the installed apps. Confirms the two things that
/// can't be unit-tested offline: that each recipe resolves a real installer URL,
/// and that a downloaded build passes the mandatory code-signature + Team ID gate.

/// Every recipe with an install spec must resolve a concrete download URL + kind
/// from its live feed — on ITS OWN channel. Prints the plan to stderr.
///
/// The stable half is a curated smoke list: `duo verify` sweeps all ~55 stable
/// install recipes nightly (with per-host throttling, retries and a baseline), so
/// there is no reason to re-run that breadth on every `swift test`.
///
/// The non-stable half is NOT curated — it is derived from the registry, so every
/// channel recipe is covered and a new one cannot be added without appearing here.
/// Channels get the stricter treatment for two reasons. They are the ones written
/// by copying a stable sibling, which is how Signal Beta ended up reusing stable's
/// dmg filename pattern: the version still resolved, one-click silently degraded
/// to detection-only, and nothing anywhere reported it. And they are the ones
/// where "it resolved something" is not enough — resolving the STABLE artifact
/// for a Beta install passes every other check, including the Team-ID gate, so
/// each one is held to `ChannelProofRegistry`'s marker for its own train.
///
/// The channel is load-bearing in the fixture too: `VendorProbeSource` only picks
/// a recipe whose channel matches the app's, and `InstalledApp.releaseChannel`
/// defaults to `.stable` — a bundleID-only list exercised nothing but stable.
/// Setting it directly deliberately bypasses scan-time detection (Mozilla's
/// `RemotingName`, Android Studio's channel-marked bundle filename, Tailscale's
/// `UnstableUpdatesEnabled`); `ChannelGuardTests` covers that half. It also leaves
/// `isToolboxManaged` false, so JetBrains/Android Studio are exercised on their
/// website-install path — the Toolbox gate is pinned separately in
/// `toolboxManagedCopiesResolveDetectionOnly`.
@Test func vendorResolvesInstallPlans() async {
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    // The stable bundles we've enabled for one-click install (zip/dmg/tarGz swap,
    // or pkg → system installer).
    let stable: [(id: String, channel: ReleaseChannel)] = [
        ("com.microsoft.VSCode", .stable), ("app.chatwise", .stable),
        ("com.openai.codex", .stable), ("com.conductor.app", .stable),
        ("org.videolan.vlc", .stable), ("dev.kdrag0n.MacVirt", .stable),
        ("io.tailscale.ipn.macsys", .stable), ("com.anthropic.claudefordesktop", .stable),
        ("ai.elementlabs.lmstudio", .stable), ("dev.warp.Warp-Stable", .stable),
        ("com.google.android.studio", .stable),  // website-install path (Toolbox copies are gated)
        ("com.oray.sunlogin.macclient", .stable),  // AweSun: pkg → system installer (WAF Referer)
        ("com.postmanlabs.mac", .stable),          // Postman: zip → in-place (self-updater, same Team)
        // Signal stable's sibling is derived below; keep stable here so the pair is
        // always resolved together — the two feeds are what got confused.
        ("org.whispersystems.signal-desktop", .stable),
        // Outlook: pkg → system installer. Absent from this list, the 2026-08-09
        // breakage (Microsoft dropped the key the install spec read) showed up
        // nowhere — the version kept resolving and one-click just stopped
        // existing. This live check is what makes that loud.
        ("com.microsoft.Outlook", .stable),
    ]
    let targets =
        stable.map { ChannelProofKey($0.id, $0.channel) }
        + ChannelProofRegistry.channelRecipesWithInstall.sorted {
            ($0.bundleID, $0.channel.rawValue) < ($1.bundleID, $1.channel.rawValue)
        }
    let byKey = Dictionary(
        VendorProbeRegistry.recipes.filter { $0.install != nil }
            .map { (ChannelProofKey($0.bundleID, $0.channel), $0) },
        uniquingKeysWith: { a, _ in a })

    let source = VendorProbeSource()
    func probe(_ key: ChannelProofKey) async -> RemoteVersion? {
        let app = InstalledApp(
            name: key.bundleID, bundleID: key.bundleID,
            shortVersion: "0.0.0", buildVersion: "0",
            path: URL(fileURLWithPath: "/Applications/\(key.bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: key.channel)
        return (try? await source.latestVersion(for: app)) ?? nil
    }

    // Bounded fan-out: firing all ~45 feed fetches at once is both rude to the
    // vendors and enough contention to time a probe out while the rest of this
    // suite is downloading, which showed up as a spurious "resolved no URL". A
    // miss is retried ONCE and the retry is logged — the breakage this guards
    // against is deterministic and fails both attempts; a network blip does not.
    var results: [ChannelProofKey: RemoteVersion?] = [:]
    for chunk in stride(from: 0, to: targets.count, by: 12).map({
        Array(targets[$0..<min($0 + 12, targets.count)])
    }) {
        await withTaskGroup(of: (ChannelProofKey, RemoteVersion?).self) { group in
            for key in chunk { group.addTask { (key, await probe(key)) } }
            for await (key, remote) in group { results[key] = remote }
        }
    }
    var retried: [ChannelProofKey] = []
    for key in targets where (results[key] ?? nil)?.downloadURL == nil {
        retried.append(key)
        results[key] = await probe(key)
    }

    log("\n=== vendor install plans (\(targets.count) recipes) ===")
    if !retried.isEmpty {
        log("↻ retried after a first-pass miss: \(retried.map(\.description).joined(separator: ", "))")
    }
    for key in targets {
        let remote = results[key] ?? nil
        let kind = remote?.vendorInstallerKind.map { "\($0)" } ?? "nil"
        let sum = remote?.expectedSHA512 != nil ? "sha512✓" : "—"
        // `versionIsBuild` recipes (Outlook) put the build in `version` and leave
        // `shortVersion` nil unless they carry a display pattern — fall back so the
        // sweep never prints a bare "v?" for a recipe that did resolve.
        let shown = remote?.shortVersion ?? remote?.version ?? "?"
        log("• \(key): v\(shown)  [\(kind)] \(sum)")
        log("    \(remote?.downloadURL?.absoluteString ?? "NO URL")")
        #expect(remote?.downloadURL != nil, "\(key) resolved no installer URL")
        #expect(remote?.vendorInstallerKind != nil, "\(key) resolved no installer kind")
        // pkg → manual installer (system installer); archives → in-place swap.
        #expect(remote?.requiresManualInstaller == (remote?.vendorInstallerKind == .pkg),
                "\(key) install routing disagrees with its kind")
        // …and that the build came off this channel's train. Same rule the nightly
        // `duo verify` sweep applies, read from the core registry so the two can't
        // drift (see `RecipeSanity.crossChannelArtifact`).
        if let recipe = byKey[key], let remote {
            let complaint = RecipeSanity.crossChannelArtifact(recipe: recipe, remote: remote)
            #expect(complaint == nil, "\(key): \(complaint ?? "")")
        }
    }
}

/// `ChannelProofRegistry.proofs` must cover every non-stable install recipe, and
/// must not carry entries for recipes that no longer exist.
///
/// Offline and instant, unlike the live sweep above — this is the half that has to
/// fail in a PR, so someone adding a channel recipe is forced to say how they know
/// it isn't crossing trains rather than discovering it from a nightly warning.
@Test func channelProofsCoverEveryChannelRecipe() {
    let needed = Set(ChannelProofRegistry.channelRecipesWithInstall)
    let have = Set(ChannelProofRegistry.proofs.keys)
    let unproven = needed.subtracting(have).map(\.description).sorted()
    let orphaned = have.subtracting(needed).map(\.description).sorted()
    #expect(unproven.isEmpty, "channel recipes with an install spec but no ChannelProof: \(unproven)")
    #expect(orphaned.isEmpty, "ChannelProof entries for recipes that no longer carry a channel install spec: \(orphaned)")
    // A duplicate (bundleID, channel) used to mean an unreachable recipe, because
    // `latestVersion` took the FIRST match for the app's channel. It now probes
    // every match and answers with the highest (`VendorProbeSource.best`), so a
    // duplicate is legal — but only when it is deliberate. The `variant` is that
    // declaration: it also splits the two recipes' `recipeID`s, without which they
    // would share one verify baseline entry and one issue history.
    let grouped = Dictionary(grouping: VendorProbeRegistry.recipes) {
        ChannelProofKey($0.bundleID, $0.channel)
    }
    for (key, group) in grouped where group.count > 1 {
        #expect(
            group.allSatisfy { $0.variant != nil },
            "\(key.description) has \(group.count) recipes; each needs a `variant`, else it is an accidental duplicate that doubles the requests and shares a baseline key")
        #expect(
            Set(group.map(\.recipeID)).count == group.count,
            "\(key.description) has recipes with the same variant")
        // `best(of:)` ranks one string per outcome, and `versionIsBuild` decides
        // whether that string is a build or a marketing version. Mixing the two
        // within a channel would compare e.g. 26053122 against 16.109.3 — the
        // phantom-update bug `versionIsBuild` exists to prevent.
        #expect(
            Set(group.map(\.versionIsBuild)).count == 1,
            "\(key.description) mixes versionIsBuild across endpoints that get compared")
    }
}

/// The install half of a vendor probe must stay OFF for a Toolbox-managed copy.
///
/// Android Studio's Canary/Beta are the one case where a Toolbox-managed app is
/// still routed through its `VendorProbeRecipe` (Toolbox's local verdict is flaky
/// there — see `InstalledApp.prefersVendorProbeOverToolbox`). We borrow the probe
/// for the VERSION only: installing must still go through Toolbox, never an
/// in-place bundle swap that would desync Toolbox's state. Same recipe and channel
/// the sweep above resolves, so the only difference is the Toolbox flag — this
/// pins the gate, not the recipe.
@Test func toolboxManagedCopiesResolveDetectionOnly() async throws {
    let source = VendorProbeSource()
    for channel in [ReleaseChannel.canary, .beta] {
        let app = InstalledApp(
            name: "Android Studio", bundleID: "com.google.android.studio",
            shortVersion: "0.0.0", buildVersion: "AI-000.0.0",
            path: URL(fileURLWithPath: "/Applications/Android Studio Preview.app"),
            isMASApp: false, isToolboxManaged: true, sparkleFeedURL: nil,
            releaseChannel: channel)
        #expect(app.prefersVendorProbeOverToolbox)  // linchpin for the branch below
        let remote = try await source.latestVersion(for: app)
        #expect(remote?.version != nil, "Toolbox-managed \(channel.rawValue) lost its version")
        #expect(remote?.vendorInstallerKind == nil,
                "Toolbox-managed \(channel.rawValue) offered an in-place install")
        #expect(remote?.requiresManualInstaller == true)
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

    guard let remote = await LiveProbe.remote(app, source: source, "AweSun") else { return }
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

/// Outlook's Office AutoUpdate manifest publishes three `.pkg` URLs per entry and
/// only one of them is installable: `FullUpdaterLocation` (the 1.29GB standalone
/// package), never the `_Delta.pkg` / `_BinaryDelta.pkg` patches, whose
/// `InstallationCheck()` tests nothing but the min OS — run one against a
/// mismatched baseline and it lays down a partial Outlook without complaint.
///
/// The other half is the version-scheme trap: `Update Version` is the BUILD
/// (16.109.26053122; the pkg's own Distribution declares marketing 16.109.3), so
/// this pins the resolved pkg to the build the SAME probe reported. A live check,
/// because the failure it guards against is a vendor-side edit — Microsoft
/// dropping the `Update Version Location` key is what killed one-click in the
/// first place, and no fixture would have noticed.
@Test func microsoftOutlookInstallURLMatchesProbedBuild() async throws {
    let source = VendorProbeSource()
    let app = InstalledApp(
        name: "Microsoft Outlook", bundleID: "com.microsoft.Outlook",
        shortVersion: "0.0.0", buildVersion: "0",
        path: URL(fileURLWithPath: "/Applications/Microsoft Outlook.app"),
        isMASApp: false, sparkleFeedURL: nil)

    guard let remote = await LiveProbe.remote(app, source: source, "Outlook") else { return }
    #expect(remote.vendorInstallerKind == .pkg)
    #expect(remote.requiresManualInstaller == true)   // → system installer
    // versionIsBuild routes the build into `version` and leaves `shortVersion` nil.
    let build = try #require(remote.version)
    #expect(remote.shortVersion == nil)
    let url = try #require(remote.downloadURL?.absoluteString)
    #expect(url.hasSuffix("/Microsoft_Outlook_\(build)_Updater.pkg"))
    #expect(!url.contains("Delta"))
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

    guard let remote = await LiveProbe.remote(app, source: source, "Postman") else { return }
    let url = try #require(remote.downloadURL)
    let version = try #require(remote.shortVersion)
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

    guard let remote = await LiveProbe.remote(app, "\(app.name) gate") else { return }
    guard let url = remote.downloadURL, let kind = remote.vendorInstallerKind else {
        Issue.record(Comment(rawValue: "\(app.name): resolved a version but no install plan"))
        return
    }
    log("download: \(url.absoluteString)  [\(kind)]")

    let workDir = FileManager.default.temporaryDirectory
        // `scratchSlug`, not `app.id`: the id is the full bundle PATH, so the work
        // dir came out as `…/T/vendor-gate-test-/Applications/VLC.app` — a directory
        // whose last component ends in `.app`. Unpacking into it produced
        // `VLC.app/VLC.app` and made the extract/move fail intermittently.
        // `scratchSlug` is the filesystem-safe token the real installers use for
        // exactly this.
        .appendingPathComponent("vendor-gate-test-\(app.scratchSlug)")
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
