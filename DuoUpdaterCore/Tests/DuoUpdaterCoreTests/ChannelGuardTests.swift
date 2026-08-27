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

// VSCodium Insiders ships as bundle id `com.vscodium.VSCodiumInsiders` — like
// HBuilderX Alpha / Discord PTB above, that's a single glued camelCase
// component ("VSCodiumInsiders", no separator before "Insiders"), so `detect`'s
// bundle-id-suffix step (which only fires on a `.`/`-` separated
// `-insiders`/`.insiders`) does NOT resolve it. What DOES is the display-name
// step: the installed app's CFBundleName/CFBundleDisplayName is "VSCodium -
// Insiders" (confirmed 2026-08-27 by downloading the real release asset and
// reading Info.plist), and "Insiders" is a standalone word there. This is the
// linchpin GitHubReleasesSource's channel gate needs to route the
// com.vscodium.VSCodiumInsiders rule to a Preview install rather than skipping
// it as an unmatched-channel stable one.
@Test func vscodiumInsidersDisplayNameSignalsPreview() {
    #expect(ReleaseChannel.detect(
        name: "VSCodium - Insiders", bundleID: "com.vscodium.VSCodiumInsiders",
        keystoneChannel: nil) == .preview)
    // The glued bundle id alone (no separator before "Insiders") does NOT signal
    // it — a bare "VSCodium" display name would stay stable.
    #expect(ReleaseChannel.detect(
        name: "VSCodium", bundleID: "com.vscodium.VSCodiumInsiders",
        keystoneChannel: nil) == .stable)
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

// GitHub Desktop Beta shares Stable's bundle id (`com.github.GitHubClient`) AND its
// app name ("GitHub Desktop") — the installed `-betaN` version suffix is the ONLY
// channel signal. This is the linchpin the GitHubReleasesSource channel gate uses to
// route the `.beta` rule (keeping the `-betaN` tag) instead of the stable one.
@Test func githubDesktopBetaVersionSuffixSignalsBeta() {
    #expect(ReleaseChannel.detect(
        name: "GitHub Desktop", bundleID: "com.github.GitHubClient",
        keystoneChannel: nil, version: "3.5.12-beta2") == .beta)
    // Stable build (no suffix) stays stable.
    #expect(ReleaseChannel.detect(
        name: "GitHub Desktop", bundleID: "com.github.GitHubClient",
        keystoneChannel: nil, version: "3.5.12") == .stable)
    // Build-metadata shapes other apps use for NON-channel builds must NOT trip it:
    // the trailing digits must be the whole tail (`-beta[0-9]+$`). Real installed
    // examples 2026-06-06: ClaudeUsageMenuBar `…-beta.1429+sha`, DuoPaste `…-beta+sha`.
    #expect(ReleaseChannel.detect(
        name: "ClaudeUsageMenuBar", bundleID: "com.example.claudeusage",
        keystoneChannel: nil, version: "0.3.377-beta.1429+09acc19") == .stable)
    #expect(ReleaseChannel.detect(
        name: "DuoPaste", bundleID: "com.example.duopaste",
        keystoneChannel: nil, version: "0.1.1251-beta+962a0e1") == .stable)
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

@Test func androidStudioChannelFromBundleFilename() {
    // Real bundle facts (read off the official DMGs 2026-06-06): Stable, Canary,
    // and Beta all carry bundle id `com.google.android.studio`, CFBundleName
    // "Android Studio", and a marketing version truncated to "2026.1" — so the
    // ONLY channel signal is the on-disk bundle filename (Homebrew's casks name
    // them per track). The scanner's display name is CFBundleName ("Android
    // Studio"), which carries no word, so channel detection must key on the
    // filename via the dedicated `bundleFileName` parameter.
    func detect(_ fileName: String) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "Android Studio", bundleID: "com.google.android.studio",
            keystoneChannel: nil, version: "2026.1", bundleFileName: fileName)
    }
    #expect(detect("Android Studio") == .stable)
    #expect(detect("Android Studio Preview Canary") == .canary)
    // "Preview Beta" contains BOTH "Preview" and "Beta"; the generic channelWord
    // table ranks preview above beta, so this must NOT route through it — the
    // scoped match takes canary>beta>preview and lands on .beta.
    #expect(detect("Android Studio Preview Beta") == .beta)
    // The raw DMG name ("Android Studio Preview.app", channel-ambiguous) maps to
    // .preview — no recipe targets it, so it's safely skipped, NEVER misdetected
    // as .stable and offered a cross-channel Stable build.
    #expect(detect("Android Studio Preview") == .preview)
    // The bundle-filename signal is scoped to Android Studio's id: another app
    // that happens to live in a "… Canary.app" still goes through normal signals.
    #expect(ReleaseChannel.detect(
        name: "Some App", bundleID: "com.example.other",
        keystoneChannel: nil, bundleFileName: "Some App") == .stable)
}

// MARK: - DB Browser for SQLite nightly: filename is the only signal (issue #94)

/// The nightly ships the STABLE bundle id, a clean `CFBundleName` and a version
/// that is not a channel token, so the bundle filename is the whole signal.
/// Filenames from Homebrew's casks, read 2026-08-27:
/// stable `DB Browser for SQLite.app`, `@nightly` `DB Browser for SQLite Nightly.app`.
@Test func dbBrowserNightlyChannelFromBundleFilename() {
    func detect(_ fileName: String) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "DB Browser for SQLite", bundleID: "net.sourceforge.sqlitebrowser",
            keystoneChannel: nil, version: "3.13.99", bundleFileName: fileName)
    }
    #expect(detect("DB Browser for SQLite Nightly.app") == .nightly)
    #expect(detect("DB Browser for SQLite.app") == .stable)
    // The version is a frozen placeholder, not a channel token, and must stay
    // one — 3.13.99 is what BOTH tracks report.
    #expect(ReleaseChannel.detect(
        name: "DB Browser for SQLite", bundleID: "net.sourceforge.sqlitebrowser",
        keystoneChannel: nil, version: "3.13.99") == .stable)
    // Scoped to this bundle id: another app in a "… Nightly.app" is not swept up
    // by this rule (it falls through to the ordinary signals).
    #expect(ReleaseChannel.detect(
        name: "Some App", bundleID: "com.example.other",
        keystoneChannel: nil, bundleFileName: "Some App Nightly.app") == .stable)
}

/// The reason the rule above is worth having, given that a nightly can never be
/// UPDATED (its version is frozen at `3.13.99`): stable is covered by a real
/// registry rule that carries a one-click install spec, and without the channel
/// the nightly install sits squarely in that rule's reach. Drives the REAL
/// registry entry rather than a fixture, so it cannot drift away from shipping
/// behaviour.
@Test func dbBrowserStableRecipeDoesNotReachTheNightly() async throws {
    let rule = try #require(
        GitHubReleaseRegistry.rules.first { $0.bundleID == "net.sourceforge.sqlitebrowser" })
    #expect(rule.channel == .stable)
    // If this stops being true the cross-channel risk goes away with it, and
    // this test should be re-read rather than deleted.
    #expect(rule.installAssetPattern != nil,
            "stable rule lost its install spec — the hazard this guards has changed")

    let source = GitHubReleasesSource(rules: [rule])
    let nightly = InstalledApp(
        name: "DB Browser for SQLite", bundleID: "net.sourceforge.sqlitebrowser",
        shortVersion: "3.13.99", buildVersion: "3.13.99",
        path: URL(fileURLWithPath: "/Applications/DB Browser for SQLite Nightly.app"),
        isMASApp: false, sparkleFeedURL: nil,
        releaseChannel: ReleaseChannel.detect(
            name: "DB Browser for SQLite", bundleID: "net.sourceforge.sqlitebrowser",
            keystoneChannel: nil, version: "3.13.99",
            bundleFileName: "DB Browser for SQLite Nightly.app"))

    #expect(nightly.releaseChannel == .nightly)
    // Skipped before any fetch — a network call here would be a bug on its own.
    #expect(try await source.latestVersion(for: nightly) == nil)
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

// MARK: - Prerelease WORD in the version tail (issue #93)

/// Freelens nightly, VLC nightly and the KeePassXC snapshot each ship the STABLE
/// bundle id, the stable app filename and a clean `CFBundleName` — the version
/// string is their ONLY local channel signal, and all three used to read as
/// `.stable`. Versions below were read off the real packages 2026-08-27.
@Test func prereleaseWordInVersionTailFlipsOffStable() {
    // Freelens nightly — a counter AND a date around the word.
    #expect(ReleaseChannel.detect(
        name: "Freelens", bundleID: "app.freelens.Freelens",
        keystoneChannel: nil, version: "2.0.0-0-nightly-2026-08-26") == .nightly)
    // VLC nightly — the bare word, no trailing components.
    #expect(ReleaseChannel.detect(
        name: "VLC", bundleID: "org.videolan.vlc",
        keystoneChannel: nil, version: "4.0.0-dev") == .dev)
    // KeePassXC snapshot.
    #expect(ReleaseChannel.detect(
        name: "KeePassXC", bundleID: "org.keepassxc.keepassxc",
        keystoneChannel: nil, version: "2.8.0-snapshot") == .preview)
    // Case is not a signal: the vendor may shout it.
    #expect(ReleaseChannel.detect(
        name: "VLC", bundleID: "org.videolan.vlc",
        keystoneChannel: nil, version: "4.0.0-DEV") == .dev)
}

/// The mirror, and the expensive direction: a version tail that is build
/// metadata rather than a channel must keep reading as `.stable`, or a working
/// stable app stops being answered for. Every string here is either named in
/// `ReleaseChannel`'s own comments or was live in the corpus on 2026-08-27.
@Test func nonChannelVersionTailsStayStable() {
    func detect(_ version: String) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "Some App", bundleID: "com.example.some",
            keystoneChannel: nil, version: version)
    }
    // The shapes the `-betaN` rule above already guards — still guarded.
    #expect(detect("0.3.377-beta.1429+sha") == .stable)
    #expect(detect("0.1.1251-beta+sha") == .stable)
    // Live on the dev machine 2026-08-27.
    #expect(detect("0.3.384-beta.1440+fd58749") == .stable)
    #expect(detect("0.1.1283-beta+dc86f01") == .stable)
    // A NON-channel word in the tail (Kontena Lens ships this on stable).
    #expect(detect("2026.8.190756-latest") == .stable)
    // Numeric and build-metadata tails.
    #expect(detect("6.5.2-366") == .stable)
    #expect(detect("3.22.3+105") == .stable)
    // Zen Browser stable — ends in a bare "b", must not read as a Mozilla beta.
    #expect(detect("1.21.15b") == .stable)
    // The word must be a WHOLE dash-delimited component. "dev" is the short,
    // common token the rule is most exposed on, so it is pinned hardest.
    #expect(detect("1.2.3-development") == .stable)
    #expect(detect("1.2.3-devel") == .stable)
    #expect(detect("4.0.0-devmate") == .stable)
    #expect(detect("1.2.3-snapshotting") == .stable)
    #expect(detect("1.2.3-nightlies") == .stable)
    // Only numeric components may sit between the version and the word, so a
    // tail of arbitrary words cannot smuggle one in.
    #expect(detect("2026.8.190756-dev-preview-latest") == .stable)
    // Needs a dotted-numeric prefix — a bare word is not a version.
    #expect(detect("dev") == .stable)
    #expect(detect("nightly-2026-08-26") == .stable)
}

/// Three places in the codebase rule on what a channel word means: this version
/// tail, `channelWord` (display name), and the `.snapshot`/`-snapshot` bundle-id
/// suffix. They must not disagree — otherwise the same build lands on a
/// different channel depending on which signal happened to see it first, and the
/// cross-channel gate stops being a gate. Compares two production paths rather
/// than asserting a hardcoded answer, so it cannot drift silently.
@Test func versionTailAgreesWithTheOtherChannelWordSignals() {
    for word in ["nightly", "snapshot", "dev"] {
        let fromVersion = ReleaseChannel.detect(
            name: "Some App", bundleID: "com.example.some",
            keystoneChannel: nil, version: "1.2.3-\(word)")
        let fromName = ReleaseChannel.detect(
            name: "Some App \(word)", bundleID: "com.example.some",
            keystoneChannel: nil)
        #expect(fromVersion == fromName,
                Comment(rawValue: "version tail and display name disagree on "
                                  + "\"\(word)\": \(fromVersion) vs \(fromName)"))
    }
    // ... and the bundle-id suffix path for the one word that has one.
    #expect(ReleaseChannel.detect(
        name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi.snapshot",
        keystoneChannel: nil) == .preview)
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

/// A Mac App Store copy and a GitHub build can share a bundle id while being
/// different distributions — LocalSend ships both, the store copy sandboxed with
/// a receipt and the GitHub one Developer ID signed without. The store owns its
/// copy's updates; offering a GitHub artifact over it would break the receipt and
/// the store's own update path, and now that GitHub rules can carry a one-click
/// installer that would be a real swap, not just a wrong number on a row.
@Test func githubSourceSkipsAppStoreCopies() async throws {
    let rule = GitHubReleaseRule(
        bundleID: "com.example.ghapp",
        owner: "example", repo: "ghapp",
        installAssetPattern: #"^GHApp\.dmg$"#,
        installerKind: .dmg)
    let source = GitHubReleasesSource(rules: [rule])

    let storeCopy = InstalledApp(
        name: "GHApp", bundleID: "com.example.ghapp",
        shortVersion: "1.0.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/GHApp.app"),
        isMASApp: true, sparkleFeedURL: nil, releaseChannel: .stable)

    // Skipped before any fetch — a network call here would be a bug on its own.
    #expect(try await source.latestVersion(for: storeCopy) == nil)
}

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
        let app = LiveProbe.app(
            "Chrome-\(c.channel.rawValue)", c.bundleID, channel: c.channel,
            installedVersion: "1.0.0.0")
        await LiveProbe.check(app, source: source, "Chrome \(c.channel.rawValue)") {
            // 4-part Chrome version (e.g. 150.0.7871.0).
            #expect($0.split(separator: ".").count == 4,
                    "unexpected version for \(c.channel.rawValue): \($0)")
            resolved[c.channel] = $0
        }
    }

    // Each channel that answered produced its OWN version — the gate didn't
    // collapse them onto one recipe. Only the network can shrink this set now:
    // a missing recipe or a broken pattern is already a recorded failure.
    let distinct = Set(resolved.values)
    #expect(distinct.count == resolved.count,
            "two Chrome channels resolved the same version: \(resolved)")
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
        let app = LiveProbe.app(
            "Edge-\(channel.rawValue)", bundleID, channel: channel,
            installedVersion: "1.0.0.0")
        await LiveProbe.check(app, source: source, "Edge \(channel.rawValue)") {
            #expect($0.split(separator: ".").count == 4, "Edge \(channel.rawValue): \($0)")
        }
    }
}

// MARK: - Firefox: three channels share ONE bundle id, resolve THREE versions (live)

@Test func firefoxSharedBundleResolvesPerChannel() async throws {
    // Release, Beta and ESR all carry `org.mozilla.firefox`. The multi-recipe
    // routing must hand each its OWN feed value — the whole point of the change.
    let source = VendorProbeSource()
    func resolve(_ channel: ReleaseChannel, version: String) async -> String? {
        // All three carry `org.mozilla.firefox`; the channel is what must pick
        // the recipe, which is the whole point of the test.
        let app = LiveProbe.app(
            "Firefox-\(channel.rawValue)", "org.mozilla.firefox",
            channel: channel, installedVersion: version)
        return await LiveProbe.version(app, source: source, "Firefox \(channel.rawValue)")
    }

    let stable = await resolve(.stable, version: "100.0")
    let beta = await resolve(.beta, version: "100.0b1")
    let esr = await resolve(.esr, version: "100.0esr")

    // A missing value here means the vendor's server was unreachable — a broken
    // recipe or a vanished channel gate has already been recorded as a failure
    // by `LiveProbe`, so the remaining tolerance is only for the network.
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
        let app = LiveProbe.app(c.name, c.bundleID, channel: c.channel)
        await LiveProbe.check(app, source: source, c.name) {
            #expect(c.expect($0), "\(c.name) resolved unexpected version: \($0)")
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

// Vivaldi Snapshot ships as a distinct bundle id with a `.snapshot` suffix and
// its display name contains "Snapshot" — both signals must map to `.preview`.
@Test func vivaldiSnapshotBundleIdAndNameSignalPreview() {
    #expect(ReleaseChannel.detect(
        name: "Vivaldi Snapshot", bundleID: "com.vivaldi.Vivaldi.snapshot",
        keystoneChannel: nil) == .preview)
    // The bundle id suffix alone is sufficient.
    #expect(ReleaseChannel.detect(
        name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi.snapshot",
        keystoneChannel: nil) == .preview)
    // A stable Vivaldi (no suffix) stays stable.
    #expect(ReleaseChannel.detect(
        name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi",
        keystoneChannel: nil) == .stable)
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
        await LiveProbe.check(LiveProbe.app(c.name, c.bundleID), source: source, c.name) {
            // A clean dotted numeric version, no packaging/build suffix.
            #expect($0.range(of: #"^[0-9]+(\.[0-9]+)+$"#, options: .regularExpression) != nil,
                    "\(c.name) resolved a non-clean version: \($0)")
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

@Test func alfredBindingCarriesChannelWithoutAFeedOverride() {
    // Alfred was wired as a Sparkle feed-swap app, but its endpoint serves an Apple
    // plist, not an appcast — and both appcast URLs the binding pointed at now 404,
    // which left the row permanently "Failed". The binding still decides the
    // channel; the endpoints are read by VendorProbeRecipe.
    let beta = AlfredChannel.resolve(prereleases: true)
    #expect(beta.channel == .beta)
    #expect(beta.feedOverride == nil)
    let stable = AlfredChannel.resolve(prereleases: false)
    #expect(stable.channel == .stable)
    #expect(stable.feedOverride == nil)
}

@Test func alfredHasARecipePerChannel() {
    let alfred = VendorProbeRegistry.recipes.filter { $0.bundleID == AlfredChannel.bundleID }
    #expect(alfred.count == 2)
    #expect(Set(alfred.map(\.channel)) == [.stable, .beta])
    // Both must be able to install: the tarball was verified same-team + notarized.
    #expect(alfred.allSatisfy { $0.install?.kind == .tarGz })
}

@Test func sparkleFeedErrorSaysWhatWentWrong() {
    // "SparkleError error 0" named the enum case index and hid the status code.
    let message = SparkleAppcastSource.SparkleError.badStatus(404).errorDescription ?? ""
    #expect(message.contains("404"))
}

@Test func ghosttyBindingSuppliesTheFeedItsInfoPlistOmits() {
    // Ghostty sets its Sparkle feed in code, so AppScanner finds no SUFeedURL and
    // the app arrived with no source at all. The binding supplies it; going through
    // Sparkle rather than a version regex is what keeps the EdDSA signature,
    // release notes and history.
    let resolved = try! #require(ChannelBinding.resolve(bundleID: GhosttyChannel.bundleID))
    #expect(resolved.channel == .stable)
    #expect(resolved.feedOverride == GhosttyChannel.feed)
}

@Test func ghosttyStableIsNeverOfferedATipBuild() {
    // Ghostty's appcast carries two 2024-12 tip entries whose shortVersionString is
    // a commit hash, untagged like every other item. A stable install must sort
    // above them, not be handed one.
    func item(_ short: String, _ build: String) -> SparkleAppcastItem {
        var i = SparkleAppcastItem()
        i.shortVersionString = short
        i.version = build
        i.enclosureURL = URL(string: "https://example.com/Ghostty.dmg")
        return i
    }
    let items = [item("0abd4ea8 (2024-12-20)", "8343"),
                 item("663205b5 (2024-12-20)", "8346"),
                 item("1.3.0", "15112"),
                 item("1.3.1", "15212")]
    let app = InstalledApp(
        name: "Ghostty", bundleID: GhosttyChannel.bundleID, shortVersion: "1.2.0",
        buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Ghostty.app"),
        isMASApp: false, sparkleFeedURL: GhosttyChannel.feed,
        releaseChannel: .stable, channelIsAuthoritative: true)
    let best = SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "26.6.0")
    #expect(best?.shortVersionString == "1.3.1")
}
