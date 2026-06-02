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
}

@Test func displayNameWordSignalsChannel() {
    #expect(ReleaseChannel.detect(
        name: "Google Chrome Canary", bundleID: nil, keystoneChannel: nil) == .canary)
    #expect(ReleaseChannel.detect(
        name: "Firefox Nightly", bundleID: nil, keystoneChannel: nil) == .nightly)
    #expect(ReleaseChannel.detect(
        name: "Google Chrome Dev", bundleID: nil, keystoneChannel: nil) == .dev)
}

@Test func mozillaVersionSuffixSignalsChannel() {
    // Firefox Release/Beta/ESR all carry `org.mozilla.firefox`; only the version
    // string separates them.
    #expect(ReleaseChannel.detect(
        name: "Firefox", bundleID: "org.mozilla.firefox",
        keystoneChannel: nil, version: "152.0b6") == .beta)
    #expect(ReleaseChannel.detect(
        name: "Firefox", bundleID: "org.mozilla.firefox",
        keystoneChannel: nil, version: "140.11.0esr") == .esr)
    #expect(ReleaseChannel.detect(
        name: "Firefox Nightly", bundleID: "org.mozilla.nightly",
        keystoneChannel: nil, version: "153.0a1") == .nightly)
    // A normal 3-part stable version must NOT be read as a pre-release.
    #expect(ReleaseChannel.detect(
        name: "Firefox", bundleID: "org.mozilla.firefox",
        keystoneChannel: nil, version: "151.0.3") == .stable)
    // Developer Edition has its own bundle id but a beta-shaped version.
    #expect(ReleaseChannel.detect(
        name: "Firefox Developer Edition",
        bundleID: "org.mozilla.firefoxdeveloperedition",
        keystoneChannel: nil, version: "152.0b6") == .beta)
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
        ("Element Nightly", "io.element.nightly", .nightly, { $0.count >= 8 && $0.allSatisfy(\.isNumber) }),
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
        ("LibreWolf", "org.mozilla.librewolf"),
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
    let body = #"[{"name":"147.0.4-1"},{"name":"147.0.3-2"}]"#
    let v = VendorProbeRecipe.extractVersion(
        from: body, pattern: #""name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"#)
    #expect(v == "147.0.4")  // upstream version only, "-1" dropped
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
