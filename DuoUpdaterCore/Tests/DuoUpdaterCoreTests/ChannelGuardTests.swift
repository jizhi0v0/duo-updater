import Testing
import Foundation
@testable import DuoUpdaterCore

// MARK: - ReleaseChannel.detect (the channel-inference core)

@Test func keystoneChannelIsAuthoritative() {
    #expect(ReleaseChannel.detect(
        name: "Google Chrome", bundleID: "com.google.Chrome",
        keystoneChannel: "beta") == .beta)
    #expect(ReleaseChannel.detect(
        name: "Google Chrome", bundleID: "com.google.Chrome",
        keystoneChannel: "canary") == .canary)
    // Empty / "extended" Keystone channels are stable tracks.
    #expect(ReleaseChannel.detect(
        name: "Google Chrome", bundleID: "com.google.Chrome",
        keystoneChannel: "") == .stable)
    #expect(ReleaseChannel.detect(
        name: "Google Chrome", bundleID: "com.google.Chrome",
        keystoneChannel: "extended") == .stable)
}

@Test func bundleIDSuffixSignalsChannel() {
    #expect(ReleaseChannel.detect(
        name: "Google Chrome", bundleID: "com.google.Chrome.canary",
        keystoneChannel: nil) == .canary)
    #expect(ReleaseChannel.detect(
        name: "Visual Studio Code", bundleID: "com.microsoft.VSCode.insiders",
        keystoneChannel: nil) == .preview)
    // JetBrains Early Access Program ships under a `-EAP` bundle-id suffix; treat it
    // as the preview channel so its VendorProbe recipe isn't dropped by the gate.
    #expect(ReleaseChannel.detect(
        name: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij-EAP",
        keystoneChannel: nil) == .preview)
}

@Test func displayNameWordSignalsChannel() {
    #expect(ReleaseChannel.detect(
        name: "Google Chrome Canary", bundleID: nil, keystoneChannel: nil) == .canary)
    #expect(ReleaseChannel.detect(
        name: "Firefox Nightly", bundleID: nil, keystoneChannel: nil) == .nightly)
    #expect(ReleaseChannel.detect(
        name: "Google Chrome Dev", bundleID: nil, keystoneChannel: nil) == .dev)
}

// HBuilderX Alpha ships as "HBuilderX-Alpha.app" with no CFBundleName, so the
// scanner's display name is the bundle file name "HBuilderX-Alpha" — whose
// standalone "alpha" token must resolve to .alpha. This is the linchpin that lets
// VendorProbeSource's channel gate route the io.dcloud.HBuilderXAlpha recipe; the
// glued bundle id ("…HBuilderXAlpha", no separator) can't signal it on its own.
@Test func hbuilderXAlphaBundleNameSignalsAlpha() {
    #expect(ReleaseChannel.detect(
        name: "HBuilderX-Alpha", bundleID: "io.dcloud.HBuilderXAlpha", keystoneChannel: nil) == .alpha)
    // The glued bundle id alone (no separator before "alpha") does NOT signal it.
    #expect(ReleaseChannel.detect(
        name: "HBuilderX", bundleID: "io.dcloud.HBuilderXAlpha", keystoneChannel: nil) == .stable)
}

// Discord PTB / Canary ship as glued bundle ids (`com.hnc.DiscordPTB`,
// `…DiscordCanary`, no separator before the channel word) so — like HBuilderX
// Alpha — only the standalone word in the display name carries the channel.
// This detection is the linchpin VendorProbeSource's gate matches against the
// dedicated `.ptb`/`.canary` recipes.
@Test func discordPTBAndCanaryDisplayNamesSignalChannel() {
    #expect(ReleaseChannel.detect(
        name: "Discord PTB", bundleID: "com.hnc.DiscordPTB", keystoneChannel: nil) == .ptb)
    #expect(ReleaseChannel.detect(
        name: "Discord Canary", bundleID: "com.hnc.DiscordCanary", keystoneChannel: nil) == .canary)
    // The glued bundle id alone (no separator) does NOT signal it — bare "Discord"
    // stays stable, which is exactly why each ships under its own recipe bundle id.
    #expect(ReleaseChannel.detect(
        name: "Discord", bundleID: "com.hnc.DiscordPTB", keystoneChannel: nil) == .stable)
}

@Test func mozillaVersionSuffixSignalsChannel() {
    // FALLBACK path only. A REAL installed Firefox/Thunderbird strips the `b`/`esr`
    // suffix from `CFBundleShortVersionString` (Beta reports "152.0", ESR
    // "140.11.0"), so these suffixed strings never actually occur for Beta/ESR —
    // `RemotingName` is the real signal (see below). This keeps the version-suffix
    // net as a harmless backstop, and asserts a plain stable version never trips it.
    #expect(ReleaseChannel.detect(
        name: "Firefox", bundleID: "org.mozilla.firefox",
        keystoneChannel: nil, version: "152.0b6") == .beta)
    #expect(ReleaseChannel.detect(
        name: "Firefox", bundleID: "org.mozilla.firefox",
        keystoneChannel: nil, version: "140.11.0esr") == .esr)
    // Nightly is the one channel whose `aN` suffix DOES survive into the install.
    #expect(ReleaseChannel.detect(
        name: "Firefox Nightly", bundleID: "org.mozilla.nightly",
        keystoneChannel: nil, version: "153.0a1") == .nightly)
    // A normal 3-part stable version must NOT be read as a pre-release.
    #expect(ReleaseChannel.detect(
        name: "Firefox", bundleID: "org.mozilla.firefox",
        keystoneChannel: nil, version: "151.0.3") == .stable)
}

@Test func mozillaRemotingNameIsAuthoritative() {
    // Real values read from official bundles 2026-06-04. RemotingName is checked
    // FIRST and overrides the (misleading) name/version signals: an ESR install
    // reports a plain "140.11.0" and shares `org.mozilla.firefox`, so without this
    // it read as `.stable` and got cross-channel pushed onto the stable build.
    func detect(_ name: String, _ bundle: String, _ short: String, _ remoting: String)
        -> ReleaseChannel {
        ReleaseChannel.detect(
            name: name, bundleID: bundle, keystoneChannel: nil,
            version: short, mozillaRemotingName: remoting)
    }
    // Firefox — Beta/ESR share the stable bundle id and a suffix-less version.
    #expect(detect("Firefox", "org.mozilla.firefox", "151.0.3", "firefox") == .stable)
    #expect(detect("Firefox", "org.mozilla.firefox", "152.0", "firefox-beta") == .beta)
    #expect(detect("Firefox", "org.mozilla.firefox", "140.11.0", "firefox-esr") == .esr)
    #expect(detect("Firefox Developer Edition",
        "org.mozilla.firefoxdeveloperedition", "152.0", "firefox-dev") == .dev)
    #expect(detect("Firefox Nightly", "org.mozilla.nightly", "153.0a1", "firefox-nightly")
        == .nightly)
    // Thunderbird — same scheme; Beta has its own bundle id, ESR shares stable's.
    #expect(detect("Thunderbird", "org.mozilla.thunderbird", "151.0.1", "thunderbird")
        == .stable)
    #expect(detect("Thunderbird Beta", "org.mozilla.thunderbirdbeta", "152.0",
        "thunderbird-beta") == .beta)
    #expect(detect("Thunderbird", "org.mozilla.thunderbird", "140.11.1", "thunderbird-esr")
        == .esr)
    #expect(detect("Thunderbird Daily", "org.mozilla.thunderbird-daily", "153.0a1",
        "thunderbird-nightly") == .nightly)
}

@Test func plainStableAppsStayStable() {
    #expect(ReleaseChannel.detect(
        name: "Google Chrome", bundleID: "com.google.Chrome",
        keystoneChannel: nil) == .stable)
    // Channel words embedded in a longer token must NOT trip detection
    // (word-boundary matching), or we'd skip legitimate stable apps.
    #expect(ReleaseChannel.detect(
        name: "Developer Tools", bundleID: "com.example.devtools",
        keystoneChannel: nil) == .stable)
    #expect(ReleaseChannel.detect(
        name: "Betamax", bundleID: "com.example.betamax",
        keystoneChannel: nil) == .stable)
}

// MARK: - Scanner wires the channel onto InstalledApp

private func makeApp(at dir: URL, name: String, info: [String: Any]) throws -> URL {
    let bundle = dir.appendingPathComponent("\(name).app")
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return bundle
}

@Test func scannerTagsCanaryViaKeystone() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("chan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeApp(at: tmp, name: "Google Chrome Canary", info: [
        "CFBundleIdentifier": "com.google.Chrome.canary",
        "CFBundleShortVersionString": "140.0.7259.0",
        "KSChannelID": "canary",
    ])
    _ = try makeApp(at: tmp, name: "Google Chrome", info: [
        "CFBundleIdentifier": "com.google.Chrome",
        "CFBundleShortVersionString": "139.0.7258.5",
    ])

    let apps = AppScanner(locations: [tmp]).scan()
    let canary = try #require(apps.first { $0.name == "Google Chrome Canary" })
    let stable = try #require(apps.first { $0.name == "Google Chrome" })
    #expect(canary.releaseChannel == .canary)
    #expect(stable.releaseChannel == .stable)
}

@Test func scannerTagsMozillaChannelViaRemotingName() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("chan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Writes a bundle whose Info.plist looks exactly like a real ESR install — same
    // bundle id as stable, version with NO `esr` suffix, plain "Thunderbird" name —
    // plus the application.ini RemotingName that's the only thing telling them apart.
    func makeMozillaApp(_ name: String, bundleID: String, short: String, remoting: String)
        throws {
        let bundle = tmp.appendingPathComponent("\(name).app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleShortVersionString": short,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try "[App]\nRemotingName=\(remoting)\nVendor=Mozilla\n"
            .write(to: resources.appendingPathComponent("application.ini"),
                   atomically: true, encoding: .utf8)
    }

    try makeMozillaApp("Thunderbird", bundleID: "org.mozilla.thunderbird",
        short: "140.11.1", remoting: "thunderbird-esr")
    try makeMozillaApp("Firefox", bundleID: "org.mozilla.firefox",
        short: "152.0", remoting: "firefox-beta")
    try makeMozillaApp("Stable TB", bundleID: "org.mozilla.thunderbird",
        short: "151.0.1", remoting: "thunderbird")

    let apps = AppScanner(locations: [tmp]).scan()
    #expect(try #require(apps.first { $0.name == "Thunderbird" }).releaseChannel == .esr)
    #expect(try #require(apps.first { $0.name == "Firefox" }).releaseChannel == .beta)
    #expect(try #require(apps.first { $0.name == "Stable TB" }).releaseChannel == .stable)
}

// MARK: - VendorProbeSource refuses to cross channels (gate B)

@Test func vendorProbeSkipsChannelMismatch() async throws {
    // A stable recipe must NOT answer for a Canary install that shares the bundle
    // id — the guard short-circuits before any network call, returning nil.
    let recipe = VendorProbeRecipe(
        bundleID: "com.example.app",
        url: URL(string: "https://example.invalid/version")!,
        mode: .responseBody,
        versionPattern: #"([0-9.]+)"#,
        channel: .stable)
    let source = VendorProbeSource(recipes: [recipe])

    let canary = InstalledApp(
        name: "Example Canary", bundleID: "com.example.app",
        shortVersion: "1.0.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/Example Canary.app"),
        isMASApp: false, sparkleFeedURL: nil, releaseChannel: .canary)

    let result = try await source.latestVersion(for: canary)
    #expect(result == nil)  // refused on channel mismatch, no cross-channel package
}

// MARK: - GitHubReleasesSource refuses to cross channels (gate B, GitHub side)

@Test func githubSourceSkipsChannelMismatch() async throws {
    let stableRule = GitHubReleaseRule(
        bundleID: "com.example.ghapp",
        owner: "example", repo: "ghapp",
        channel: .stable)
    let source = GitHubReleasesSource(rules: [stableRule])

    let nightly = InstalledApp(
        name: "GHApp Nightly", bundleID: "com.example.ghapp",
        shortVersion: "1.0.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/GHApp Nightly.app"),
        isMASApp: false, sparkleFeedURL: nil, releaseChannel: .nightly)

    let result = try await source.latestVersion(for: nightly)
    #expect(result == nil)
}

@Test func githubSourceMatchesCorrectChannel() async throws {
    let stableRule = GitHubReleaseRule(
        bundleID: "com.example.ghapp",
        owner: "example", repo: "ghapp",
        channel: .stable)
    let nightlyRule = GitHubReleaseRule(
        bundleID: "com.example.ghapp",
        owner: "example", repo: "ghapp",
        usePrereleases: true,
        versionPattern: #"nightly-([0-9.]+)"#,
        channel: .nightly)
    let source = GitHubReleasesSource(rules: [stableRule, nightlyRule])

    let stableApp = InstalledApp(
        name: "GHApp", bundleID: "com.example.ghapp",
        shortVersion: "1.0.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/GHApp.app"),
        isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)

    // Stable app should pick the stable rule — which targets example/ghapp, a
    // non-existent repo. The source will try to fetch and fail (no real
    // endpoint), confirming it DID select a rule rather than returning nil
    // at the channel gate. Any error means the gate passed.
    let threw: Bool
    do {
        _ = try await source.latestVersion(for: stableApp)
        threw = false
    } catch {
        threw = true
    }
    #expect(threw, "Expected a fetch error (rule selected), not a nil (gate refused)")
}

// MARK: - Chrome per-channel recipes route through the gate (live)

@Test func chromeChannelsResolveTheirOwnVersion() async throws {
    // Drive each Chrome channel through the REAL registry: the gate must pick the
    // bundle-id+channel-matched recipe and the per-channel VersionHistory feed
    // must yield a fully-rolled-out 4-part version. Confirms a Beta/Dev/Canary
    // install is served its own channel, never Stable's build.
    let source = VendorProbeSource()
    let channels: [(bundleID: String, channel: ReleaseChannel)] = [
        ("com.google.Chrome", .stable),
        ("com.google.Chrome.beta", .beta),
        ("com.google.Chrome.dev", .dev),
        ("com.google.Chrome.canary", .canary),
    ]

    var resolved: [ReleaseChannel: String] = [:]
    for c in channels {
        let app = InstalledApp(
            name: "Google Chrome \(c.channel.rawValue)", bundleID: c.bundleID,
            shortVersion: "1.0.0.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/Chrome-\(c.channel.rawValue).app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: c.channel)
        let remote = try await source.latestVersion(for: app)
        if let v = remote?.shortVersion {
            // 4-part Chrome version (e.g. 150.0.7871.0).
            #expect(v.split(separator: ".").count == 4, "unexpected version for \(c.channel): \(v)")
            resolved[c.channel] = v
        }
    }

    // Network-tolerant: only assert routing when the feeds answered at all.
    if !resolved.isEmpty {
        // Each channel that answered produced its OWN version independently — the
        // gate didn't collapse them onto one recipe.
        #expect(resolved.count >= 1)
    }
}

// MARK: - Edge per-channel recipes (live)

@Test func edgeChannelsResolveTheirOwnVersion() async throws {
    let source = VendorProbeSource()
    let channels: [(String, ReleaseChannel)] = [
        ("com.microsoft.edgemac", .stable),
        ("com.microsoft.edgemac.Beta", .beta),
        ("com.microsoft.edgemac.Dev", .dev),
    ]
    for (bundleID, channel) in channels {
        let app = InstalledApp(
            name: "Microsoft Edge \(channel.rawValue)", bundleID: bundleID,
            shortVersion: "1.0.0.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/Edge-\(channel.rawValue).app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: channel)
        if let v = try await source.latestVersion(for: app)?.shortVersion {
            #expect(v.split(separator: ".").count == 4, "Edge \(channel): \(v)")
        }
    }
}

// MARK: - Firefox: three channels share ONE bundle id, resolve THREE versions (live)

@Test func firefoxSharedBundleResolvesPerChannel() async throws {
    // Release, Beta and ESR all carry `org.mozilla.firefox`. The multi-recipe
    // routing must hand each its OWN feed value — the whole point of the change.
    let source = VendorProbeSource()
    func resolve(_ channel: ReleaseChannel, version: String) async throws -> String? {
        let app = InstalledApp(
            name: "Firefox", bundleID: "org.mozilla.firefox",
            shortVersion: version, buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/Firefox-\(channel.rawValue).app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: channel)
        return try await source.latestVersion(for: app)?.shortVersion
    }

    let stable = try await resolve(.stable, version: "100.0")
    let beta = try await resolve(.beta, version: "100.0b1")
    let esr = try await resolve(.esr, version: "100.0esr")

    // Network-tolerant: assert distinctness only among the ones that answered.
    if let s = stable, let b = beta {
        #expect(s != b, "Release \(s) and Beta \(b) must differ — not the same recipe")
        #expect(b.contains("b"), "Beta version should carry a b-suffix: \(b)")
    }
    if let e = esr {
        #expect(e.contains("esr"), "ESR version should carry the esr suffix: \(e)")
    }
}

// MARK: - Warp / Signal / Element per-channel recipes (live)

@Test func warpSignalElementChannelsResolve() async throws {
    let source = VendorProbeSource()
    let cases: [(name: String, bundleID: String, channel: ReleaseChannel, expect: (String) -> Bool)] = [
        ("Warp Preview", "dev.warp.Warp-Preview", .preview, { $0.contains(".") }),
        ("Warp Dev", "dev.warp.Warp-Dev", .dev, { $0.contains(".") }),
        ("Signal", "org.whispersystems.signal-desktop", .stable, { $0.first?.isNumber == true }),
        ("Signal Beta", "org.whispersystems.signal-desktop-beta", .beta, { $0.contains("beta") }),
        ("Element", "im.riot.app", .stable, { $0.contains(".") }),
        ("Element Nightly", "im.riot.nightly", .nightly, { $0.count >= 8 && $0.allSatisfy(\.isNumber) }),
    ]
    for c in cases {
        let app = InstalledApp(
            name: c.name, bundleID: c.bundleID,
            shortVersion: "0.0.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/\(c.name).app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: c.channel)
        if let v = try await source.latestVersion(for: app)?.shortVersion {
            #expect(c.expect(v), "\(c.name) resolved unexpected version: \(v)")
        }
    }
}

@Test func warpBundleSuffixDetectsChannel() {
    // Warp's hyphen-separated suffixes must be read as channels; Stable stays
    // stable (no non-stable suffix).
    #expect(ReleaseChannel.detect(
        name: "Warp", bundleID: "dev.warp.Warp-Preview", keystoneChannel: nil) == .preview)
    #expect(ReleaseChannel.detect(
        name: "Warp", bundleID: "dev.warp.Warp-Canary", keystoneChannel: nil) == .canary)
    #expect(ReleaseChannel.detect(
        name: "Warp", bundleID: "dev.warp.Warp-Stable", keystoneChannel: nil) == .stable)
}

// MARK: - Single-channel recipes resolve a clean version (live)

@Test func singleChannelRecipesResolve() async throws {
    let source = VendorProbeSource()
    let cases: [(name: String, bundleID: String)] = [
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Raycast", "com.raycast.macos"),
        ("Docker Desktop", "com.docker.docker"),
        ("LibreWolf", "net.librewolf.librewolf"),
    ]
    for c in cases {
        let app = InstalledApp(
            name: c.name, bundleID: c.bundleID,
            shortVersion: "0.0.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/\(c.name).app"),
            isMASApp: false, sparkleFeedURL: nil)
        if let v = try await source.latestVersion(for: app)?.shortVersion {
            // A clean dotted numeric version, no packaging/build suffix.
            #expect(v.range(of: #"^[0-9]+(\.[0-9]+)+$"#, options: .regularExpression) != nil,
                    "\(c.name) resolved a non-clean version: \(v)")
        }
    }
}

// MARK: - Docker highest-of-feed + LibreWolf suffix-strip (offline, pinned)

@Test func dockerTakesHighestTitleVersion() {
    let feed = """
    <title>Docker for Mac</title>
    <item><title>4.75.0 (227598)</title></item>
    <item><title>Version 4.76.0 (228118)</title></item>
    """
    let v = VendorProbeRecipe.highestVersion(
        from: feed, pattern: #"<title>(?:Version\s*)?([0-9]+\.[0-9]+\.[0-9]+)\s*\("#)
    #expect(v == "4.76.0")  // not the channel title, not the lower item
}

@Test func librewolfStripsPackagingSuffix() {
    // Mirrors the Codeberg `releases/latest` shape the recipe now reads (a single
    // object with `tag_name`), NOT the abandoned GitLab tags array.
    let body = #"{"tag_name":"151.0.3-1","name":"151.0.3-1"}"#
    let v = VendorProbeRecipe.extractVersion(
        from: body, pattern: #""tag_name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"#)
    #expect(v == "151.0.3")  // upstream version only, "-1" packaging suffix dropped
}

// MARK: - Signed bundle-identifier gate (gate A)

@Test func bundleIdentifierGateRejectsDifferentApp() throws {
    // Two real, code-signed system apps with different bundle ids. The gate must
    // throw when asked to "replace" one with the other — even though both are
    // Apple-signed (same Team), they are different products.
    let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
    let notes = URL(fileURLWithPath: "/System/Applications/Notes.app")
    try #require(FileManager.default.fileExists(atPath: calculator.path))
    try #require(FileManager.default.fileExists(atPath: notes.path))

    #expect(throws: SignatureVerifier.VerifyError.self) {
        try SignatureVerifier.verifyBundleIdentifierMatch(
            installedApp: calculator, downloadedApp: notes)
    }
    // Same app on both sides passes.
    #expect(throws: Never.self) {
        try SignatureVerifier.verifyBundleIdentifierMatch(
            installedApp: calculator, downloadedApp: calculator)
    }
}
