import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// herdr: finding the install without running or hashing it, herdr's own config,
/// which build a sha256 is (herdr.dev's manifests, then GitHub's digests), the
/// order of stable and preview builds, and the verdict built from them. Nothing
/// here reaches the network or runs a herdr build: the fetches are injected,
/// and an "executable" is bytes written to a temporary HOME.
@Suite struct HerdrTests {

    final class Sandbox {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var herdr: URL { home.appendingPathComponent(".local/bin/herdr") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("herdr-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: herdr.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// A Mach-O header for `cpu` (arm64 by default), then filler.
        static func binary(cpu: [UInt8] = [0x0C, 0x00, 0x00, 0x01], filler: UInt8 = 0xAB) -> Data {
            var data = Data([0xCF, 0xFA, 0xED, 0xFE] + cpu)
            data.append(Data(repeating: filler, count: 64))
            return data
        }

        func config(_ toml: String, at url: URL? = nil) throws {
            let url = url ?? HerdrSettings.location(home: home, environment: [:])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(toml.utf8).write(to: url)
        }

        func scanner(environment: [String: String] = [:], quarantined: Bool = false) -> HerdrScanner {
            HerdrScanner(home: home, environment: environment, isQuarantined: { _ in quarantined })
        }
    }

    // MARK: - Settings

    @Test func settingsReadTheUpdateTableOnly() {
        #expect(HerdrSettings.parse("") == HerdrSettings())
        #expect(HerdrSettings.parse("""
            [ui]
            channel = "preview"   # another table's key
            [update]
            channel = "preview" # herdr channel set preview
            version_check = false
            [theme]
            version_check = true
            """) == HerdrSettings(channel: "preview", versionCheck: false))
        // Dotted keys at the top level, an inline table, single quotes, a `#`
        // inside a string.
        #expect(HerdrSettings.parse("update.channel = 'preview'\n[update]\nversion_check = true")
            == HerdrSettings(channel: "preview"))
        #expect(HerdrSettings.parse("update = { channel = \"preview\", version_check = false }")
            == HerdrSettings(channel: "preview", versionCheck: false))
        #expect(HerdrSettings.parse("[update]\nchannel = \"stable#1\"").channel == "stable#1")
        // A table nested under update, and an array of tables, are not it.
        #expect(HerdrSettings.parse("[update.extra]\nchannel = \"preview\"\n[[update]]\nchannel = \"preview\"")
            == HerdrSettings())
        // A value herdr does not know is kept as written, and reported.
        #expect(!HerdrSettings.parse("[update]\nchannel = \"beta\"").channelIsKnown)
        #expect(HerdrSettings.parse("[update]\nversion_check = \"no\"").versionCheck)
    }

    /// `$HERDR_CONFIG_PATH`, else `$XDG_CONFIG_HOME/herdr`, else `~/.config/herdr`;
    /// an empty variable is not a path.
    @Test func settingsLocationFollowsHerdrsEnvironment() {
        let home = URL(fileURLWithPath: "/ZZFixture-home")
        #expect(HerdrSettings.location(home: home, environment: [:]).path == "/ZZFixture-home/.config/herdr/config.toml")
        #expect(HerdrSettings.location(home: home, environment: ["XDG_CONFIG_HOME": "/ZZFixture-xdg"]).path
            == "/ZZFixture-xdg/herdr/config.toml")
        #expect(HerdrSettings.location(home: home, environment: [
            "XDG_CONFIG_HOME": "/ZZFixture-xdg", "HERDR_CONFIG_PATH": "/ZZFixture-c.toml",
        ]).path == "/ZZFixture-c.toml")
        #expect(HerdrSettings.location(home: home, environment: ["XDG_CONFIG_HOME": "", "HERDR_CONFIG_PATH": ""]).path
            == "/ZZFixture-home/.config/herdr/config.toml")
    }

    // MARK: - Finding the file

    @Test func scannerFindsTheInstallersFile() async throws {
        let box = try Sandbox()
        #expect(await box.scanner().scan().isEmpty)
        try Sandbox.binary().write(to: box.herdr)
        try box.config("[update]\nchannel = \"preview\"\n")
        let install = try #require(await box.scanner().scan().first)
        #expect(install.path == box.herdr.path)
        #expect(install.target == "macos-aarch64")
        #expect(install.problem == nil)
        #expect(install.identity != nil)
        #expect(install.settings.channel == "preview")
        #expect(await box.scanner(quarantined: true).scan().first?.quarantined == true)

        try Sandbox.binary(cpu: [0x07, 0x00, 0x00, 0x01]).write(to: box.herdr)
        #expect(await box.scanner().scan().first?.target == "macos-x86_64")
        try Data("#!/bin/sh\n".utf8).write(to: box.herdr)
        #expect(await box.scanner().scan().first?.target == nil)
        try Data().write(to: box.herdr)
        #expect(await box.scanner().scan().first?.problem == .executableMissing)
    }

    /// The config is read where the environment the update runs with puts it.
    @Test func scannerReadsTheConfigTheEnvironmentNames() async throws {
        let box = try Sandbox()
        try Sandbox.binary().write(to: box.herdr)
        let xdg = box.root.appendingPathComponent("xdg")
        try box.config("[update]\nchannel = \"preview\"\n", at: xdg.appendingPathComponent("herdr/config.toml"))
        #expect(await box.scanner().scan().first?.settings.channel == "stable")
        #expect(await box.scanner(environment: ["XDG_CONFIG_HOME": xdg.path]).scan().first?.settings.channel == "preview")
    }

    /// A new file by rename — what `herdr update` leaves — is a new identity,
    /// and so a new sighting.
    @Test func renamedInFileChangesTheSighting() async throws {
        let box = try Sandbox()
        try Sandbox.binary().write(to: box.herdr)
        let before = HerdrProvider.sighting(try #require(await box.scanner().scan().first))
        let next = box.root.appendingPathComponent("next")
        try Sandbox.binary(filler: 0xCD).write(to: next)
        _ = try FileManager.default.replaceItemAt(box.herdr, withItemAt: next)
        let after = HerdrProvider.sighting(try #require(await box.scanner().scan().first))
        #expect(before != after)
        #expect(before.version == nil)
        #expect(HerdrProvider.sighting(HerdrInstall(path: "/h", settings: HerdrSettings(channel: "preview")))
            != HerdrProvider.sighting(HerdrInstall(path: "/h")))
    }

    /// A link into Homebrew's, mise's or Nix's copy is theirs; a link anywhere
    /// else is reported, and one to nothing is broken.
    @Test func linksArePackageManagersOrReported() async throws {
        let box = try Sandbox()
        let cellar = box.root.appendingPathComponent("opt/homebrew/Cellar/herdr/0.9.3/bin/herdr")
        try FileManager.default.createDirectory(at: cellar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Sandbox.binary().write(to: cellar)
        try FileManager.default.createSymbolicLink(at: box.herdr, withDestinationURL: cellar)
        #expect(await box.scanner().scan().isEmpty)

        try FileManager.default.removeItem(at: box.herdr)
        let elsewhere = box.root.appendingPathComponent("src/herdr/target/release/herdr")
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Sandbox.binary().write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: box.herdr, withDestinationURL: elsewhere)
        let linked = try #require(await box.scanner().scan().first)
        #expect(linked.problem == .linkedElsewhere)
        #expect(linked.linkTarget?.hasSuffix("src/herdr/target/release/herdr") == true)

        try FileManager.default.removeItem(at: elsewhere)
        #expect(await box.scanner().scan().first?.problem == .executableMissing)

        #expect(HerdrScanner.isPackageManaged("/opt/homebrew/Cellar/herdr/0.9.3/bin/herdr"))
        #expect(HerdrScanner.isPackageManaged("/Users/ZZFixture/.local/share/mise/installs/herdr/0.9.3/bin/herdr"))
        #expect(HerdrScanner.isPackageManaged("/nix/store/abc-herdr-0.9.3/bin/herdr"))
        #expect(!HerdrScanner.isPackageManaged("/Users/ZZFixture/src/herdr/bin/herdr"))
    }

    // MARK: - Builds and their order

    @Test func buildsOrderStableBeforeItsPreviewsBeforeTheNextStable() {
        let stable092 = HerdrBuild(base: "0.9.2")
        let stable093 = HerdrBuild(base: "0.9.3")
        let early = HerdrBuild(base: "0.9.2", previewID: "2026-09-29-9dc3a1df2b56", builtAt: "2026-09-29T11:40:00Z")
        let late = HerdrBuild(base: "0.9.2", previewID: "2026-09-29-8e78f929d8f0", builtAt: "2026-09-29T18:25:31Z")
        let older = HerdrBuild(base: "0.9.2", previewID: "2026-09-28-80c0c07250d2")
        #expect(late.version == "0.9.2-preview.2026-09-29-8e78f929d8f0")
        #expect(stable093.version == "0.9.3")
        #expect(HerdrBuild.compare(stable092, late) == .orderedAscending)
        #expect(HerdrBuild.compare(late, stable093) == .orderedAscending)
        #expect(HerdrBuild.compare(stable093, late) == .orderedDescending)
        #expect(HerdrBuild.compare(older, early) == .orderedAscending)
        #expect(HerdrBuild.compare(early, late) == .orderedAscending)
        #expect(HerdrBuild.compare(late, late) == .orderedSame)
        // One day, no build times: cannot be told.
        #expect(HerdrBuild.compare(HerdrBuild(base: "0.9.2", previewID: "2026-09-29-9dc3a1df2b56"), late) == nil)
        #expect(HerdrBuild.compare(HerdrBuild(base: "0.10.0"), stable093) == .orderedDescending)
        #expect(HerdrBuild.isPreviewID("2026-09-29-8e78f929d8f0"))
        #expect(!HerdrBuild.isPreviewID("2026-09-29-8E78F929D8F0"))
        #expect(!HerdrBuild.isPreviewID("2026-09-29-8e78f929d8f"))
        #expect(!HerdrBuild.isBase("0.9.3-preview"))
    }

    // MARK: - Manifests

    static let hexStable093 = String(repeating: "a", count: 64)
    static let hexStable092 = String(repeating: "b", count: 64)
    static let hexStable092Intel = String(repeating: "c", count: 64)
    static let hexPreviewNew = String(repeating: "d", count: 64)
    static let hexPreviewOld = String(repeating: "e", count: 64)
    static let hexGitHubOld = String(repeating: "f", count: 64)
    static let hexGitHubPreview = String(repeating: "1", count: 64)

    /// latest.json's shape on 2026-10-07, cut down: top-level `assets` are URL
    /// strings, the hashes in `sha256`; `releases` has notes for all and hashes
    /// for the newer ones.
    static let stableJSON = """
        {"version":"0.9.3","protocol":22,"endpoint_generation":1,"notes":"…",
         "assets":{"macos-aarch64":"https://github.com/herdrdev/herdr/releases/download/v0.9.3/herdr-macos-aarch64"},
         "sha256":{"macos-aarch64":"\(hexStable093)","windows-x86_64":"\(String(repeating: "9", count: 64))"},
         "releases":{
           "0.9.3":{"notes":"### Fixed\\n- Escape-prefixed shortcuts work again in panes.","sha256":{"macos-aarch64":"\(hexStable093)"}},
           "0.9.2":{"notes":"### Added\\n- Remote machines.\\n\\n### Fixed\\n- A crash on resize.","sha256":{"macos-aarch64":"\(hexStable092)","macos-x86_64":"\(hexStable092Intel)"}},
           "0.1.0":{"notes":"### Added\\n- Initial release."},
           "not-a-version":{"notes":"### Added\\n- ignored","sha256":{"macos-aarch64":"\(String(repeating: "8", count: 64))"}}
         }}
        """

    /// preview.json's shape: the newest build at the top level, assets as
    /// objects, and `builds` keeping older ones.
    static let previewJSON = """
        {"schema_version":1,"channel":"preview","base_version":"0.9.2","build_id":"2026-09-29-8e78f929d8f0",
         "commit":"8e78f929d8f0306a5c68518969e90274c44cb1f0","built_at":"2026-09-29T18:25:31Z","protocol":22,
         "notes":"Preview build 2026-09-29-8e78f929d8f0",
         "assets":{"macos-aarch64":{"url":"https://github.com/herdrdev/herdr/releases/download/preview-2026-09-29-8e78f929d8f0/herdr-macos-aarch64","sha256":"\(hexPreviewNew)"}},
         "builds":{
           "2026-09-29-8e78f929d8f0":{"base_version":"0.9.2","built_at":"2026-09-29T18:25:31Z","assets":{"macos-aarch64":{"sha256":"\(hexPreviewNew)"}}},
           "2026-09-16-2c29fb29e302":{"base_version":"0.9.1","built_at":"2026-09-16T10:00:00Z","assets":{"macos-aarch64":{"sha256":"\(hexPreviewOld)"}}}
         }}
        """

    /// The GitHub release list: an old stable release and an old preview, each
    /// with its asset digests.
    static let releasesJSON = """
        [{"tag_name":"v0.7.5","draft":false,"prerelease":false,"published_at":"2026-07-21T18:11:20Z","body":"### Fixed\\n- x",
          "assets":[{"name":"herdr-macos-aarch64","digest":"sha256:\(hexGitHubOld)"}]},
         {"tag_name":"preview-2026-06-05-1ce4213d9ebb","draft":false,"prerelease":true,"published_at":"2026-06-05T12:00:00Z",
          "body":"Preview build 2026-06-05-1ce4213d9ebb\\n\\nBase stable: v0.6.8\\nCompare: …",
          "assets":[{"name":"herdr-macos-aarch64","digest":"sha256:\(hexGitHubPreview)"}]},
         {"tag_name":"preview-2026-09-21-0ff0f27e2226","draft":false,"prerelease":true,"body":"Preview build",
          "assets":[{"name":"herdr-macos-aarch64","digest":"sha256:\(String(repeating: "2", count: 64))"}]}]
        """

    final class Fetched: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ url: URL) { lock.withLock { urls.append(url) } }
        var all: [URL] { lock.withLock { urls } }
    }

    static func release(
        stable: String = stableJSON, preview: String = previewJSON, releases: String = releasesJSON,
        failing: Set<String> = [], fetched: Fetched = Fetched()
    ) -> HerdrRelease {
        HerdrRelease(fetch: { url in
            fetched.add(url)
            let host = url.host ?? ""
            if failing.contains(host) || failing.contains(url.lastPathComponent) { return (Data(), 503) }
            switch url.lastPathComponent {
            case "latest.json": return (Data(stable.utf8), 200)
            case "preview.json": return (Data(preview.utf8), 200)
            case "releases": return (Data(releases.utf8), 200)
            default: return (Data(), 404)
            }
        })
    }

    /// A preview's base: the older previews' `Base stable:` line, else the
    /// compare link the five newest carry alone (bodies as published, 2026-10-08),
    /// never the commit after the `...`. Mutations: drop the compare form; let it
    /// run past the `...`.
    @Test func previewBodiesNameTheirBase() {
        #expect(HerdrRelease.previewBase("Preview build 2026-06-05-1ce4213d9ebb\n\nBase stable: v0.6.8\nCompare: …")
            == "0.6.8")
        #expect(HerdrRelease.previewBase(
            "Preview build 2026-09-29-8e78f929d8f0\n\n[View changes](https://github.com/herdrdev/herdr/compare/v0.9.2...8e78f929d8f0306a5c68518969e90274c44cb1f0)")
            == "0.9.2")
        #expect(HerdrRelease.previewBase("Preview build") == nil)
        #expect(HerdrRelease.previewBase("https://github.com/herdrdev/herdr/compare/v0.9...8e78") == nil)
    }

    @Test func manifestsNameEveryBuildTheyHash() throws {
        let stable = try #require(HerdrRelease.parseStable(Data(Self.stableJSON.utf8)))
        #expect(stable.offers["macos-aarch64"] == .init(build: HerdrBuild(base: "0.9.3"), sha256: Self.hexStable093))
        #expect(stable.offers["macos-x86_64"] == nil)
        #expect(stable.builds[Self.hexStable092Intel] == HerdrBuild(base: "0.9.2"))
        #expect(stable.builds.count == 4)
        let preview = try #require(HerdrRelease.parsePreview(Data(Self.previewJSON.utf8)))
        let newest = HerdrBuild(base: "0.9.2", previewID: "2026-09-29-8e78f929d8f0", builtAt: "2026-09-29T18:25:31Z")
        #expect(preview.offers["macos-aarch64"] == .init(build: newest, sha256: Self.hexPreviewNew))
        #expect(preview.builds[Self.hexPreviewOld]?.version == "0.9.1-preview.2026-09-16-2c29fb29e302")
        // Each is only what it says it is.
        #expect(HerdrRelease.parsePreview(Data(Self.stableJSON.utf8)) == nil)
        #expect(HerdrRelease.parseStable(Data("{\"version\":\"latest\"}".utf8)) == nil)
    }

    /// The channel's manifest first, the other one next, GitHub last — and only
    /// as far as needed.
    @Test func resolveLooksAsFarAsItMust() async throws {
        let fetched = Fetched()
        let release = Self.release(fetched: fetched)
        let current = try await release.resolve(channel: "stable", target: "macos-aarch64", sha256: Self.hexStable092.uppercased())
        #expect(current == .init(offered: HerdrBuild(base: "0.9.3"), installed: .published(HerdrBuild(base: "0.9.2"))))
        #expect(fetched.all.map(\.lastPathComponent) == ["latest.json"])

        let preview = try await release.resolve(channel: "stable", target: "macos-aarch64", sha256: Self.hexPreviewOld)
        #expect(preview.installed == .published(HerdrBuild(base: "0.9.1", previewID: "2026-09-16-2c29fb29e302",
                                                           builtAt: "2026-09-16T10:00:00Z")))

        let old = try await release.resolve(channel: "preview", target: "macos-aarch64", sha256: Self.hexGitHubOld)
        #expect(old.offered.version == "0.9.2-preview.2026-09-29-8e78f929d8f0")
        #expect(old.installed == .published(HerdrBuild(base: "0.7.5")))
        let oldPreview = try await release.resolve(channel: "stable", target: "macos-aarch64", sha256: Self.hexGitHubPreview)
        #expect(oldPreview.installed == .published(HerdrBuild(base: "0.6.8", previewID: "2026-06-05-1ce4213d9ebb",
                                                              builtAt: "2026-06-05T12:00:00Z")))

        let none = try await release.resolve(channel: "stable", target: "macos-aarch64", sha256: String(repeating: "7", count: 64))
        #expect(none.installed == .unpublished)
        // A release that matches but names no base cannot be placed.
        let unnamed = try await release.resolve(channel: "stable", target: "macos-aarch64", sha256: String(repeating: "2", count: 64))
        guard case .couldNotVerify = unnamed.installed else { Issue.record("\(unnamed)"); return }
    }

    @Test func resolveFailuresAreNotAccusations() async throws {
        // GitHub unreachable: the file is not called unpublished.
        let noGitHub = try await Self.release(failing: ["api.github.com"])
            .resolve(channel: "stable", target: "macos-aarch64", sha256: String(repeating: "7", count: 64))
        guard case .couldNotVerify(let reason) = noGitHub.installed else { Issue.record("\(noGitHub)"); return }
        #expect(reason.contains("GitHub"))
        // The channel's own manifest unreachable, or without this Mac's build: no answer.
        await #expect(throws: HerdrRelease.Failure.http(503)) {
            try await Self.release(failing: ["latest.json"]).resolve(channel: "stable", target: "macos-aarch64", sha256: Self.hexStable093)
        }
        await #expect(throws: HerdrRelease.Failure.noBuild("macos-x86_64")) {
            try await Self.release().resolve(channel: "stable", target: "macos-x86_64", sha256: Self.hexStable092Intel)
        }
    }

    // MARK: - Verdicts

    static func install(
        channel: String = "stable", versionCheck: Bool = true, quarantined: Bool = false,
        problem: HerdrInstall.Problem? = nil, target: String? = "macos-aarch64"
    ) -> HerdrInstall {
        HerdrInstall(path: "/h/.local/bin/herdr", target: target, quarantined: quarantined, identity: "1:2:3",
                     linkTarget: problem == .linkedElsewhere ? "/ZZFixture/src/herdr" : nil,
                     settings: HerdrSettings(channel: channel, versionCheck: versionCheck), problem: problem)
    }

    static func check(_ sha: String, release: HerdrRelease = release()) -> HerdrCheck {
        HerdrCheck(resolve: { try await release.resolve(channel: $0, target: $1, sha256: $2) }, hash: { _ in sha })
    }

    @Test func verdictsOnStable() async {
        let behind = await Self.check(Self.hexStable092).status(of: Self.install(), busy: nil)
        #expect(behind.state == .updateAvailable)
        #expect(behind.installedVersion == "0.9.2")
        #expect(behind.latestVersion == "0.9.3")
        #expect(behind.channel == "stable")
        #expect(behind.oneClick == CLIToolCommand(executable: "/h/.local/bin/herdr", arguments: ["update"], pathPrefix: nil))

        let current = await Self.check(Self.hexStable093).status(of: Self.install(), busy: nil)
        #expect(current.state == .upToDate && current.oneClick == nil)

        // A preview newer than stable's newest: herdr would install 0.9.2 over
        // it; it gets no click.
        let preview = HerdrRelease(fetch: { url in
            switch url.lastPathComponent {
            case "latest.json": return (Data(Self.stableJSON.replacingOccurrences(of: "\"version\":\"0.9.3\"", with: "\"version\":\"0.9.2\"").utf8), 200)
            case "preview.json": return (Data(Self.previewJSON.utf8), 200)
            default: return (Data(), 404)
            }
        })
        let ahead = await Self.check(Self.hexPreviewNew, release: preview).status(of: Self.install(), busy: nil)
        #expect(ahead.state == .ahead && ahead.oneClick == nil)
        #expect(ahead.installedVersion == "0.9.2-preview.2026-09-29-8e78f929d8f0")
        // An older preview on stable is behind 0.9.3, and offered.
        let oldPreview = await Self.check(Self.hexPreviewOld).status(of: Self.install(), busy: nil)
        #expect(oldPreview.state == .updateAvailable && oldPreview.oneClick != nil)
    }

    @Test func verdictsOnPreview() async {
        // A stable 0.9.3 is newer than a preview based on 0.9.2: never offered.
        let stable = await Self.check(Self.hexStable093).status(of: Self.install(channel: "preview"), busy: nil)
        #expect(stable.state == .ahead && stable.oneClick == nil)
        #expect(stable.latestVersion == "0.9.2-preview.2026-09-29-8e78f929d8f0")
        let older = await Self.check(Self.hexPreviewOld).status(of: Self.install(channel: "preview"), busy: nil)
        #expect(older.state == .updateAvailable && older.oneClick != nil)
        #expect(older.channel == "preview")
        let newest = await Self.check(Self.hexPreviewNew).status(of: Self.install(channel: "preview"), busy: nil)
        #expect(newest.state == .upToDate)
    }

    /// Mutations: drop the quarantine gate, the version_check gate or the busy
    /// gate; offer a click for an unpublished file.
    @Test func gatesWithholdTheClick() async {
        let unverified = await Self.check(String(repeating: "7", count: 64)).status(of: Self.install(), busy: nil)
        #expect(unverified.state == .unknown && unverified.withheld == .unverified && unverified.oneClick == nil)
        #expect(unverified.installedVersion == nil && unverified.latestVersion == "0.9.3")

        let quarantined = await Self.check(Self.hexStable092).status(of: Self.install(quarantined: true), busy: nil)
        #expect(quarantined.withheld == .unverified && quarantined.oneClick == nil)

        let off = await Self.check(Self.hexStable092).status(of: Self.install(versionCheck: false), busy: nil)
        #expect(off.state == .updateAvailable && off.withheld == .autoUpdateOff && off.oneClick == nil)
        #expect(off.manualCommand?.display == "/h/.local/bin/herdr update")

        let busy = await Self.check(Self.hexStable092).status(of: Self.install(), busy: .update(42))
        #expect(busy.withheld == .busy && busy.oneClick == nil)
        // Up to date: no gate is asked.
        let idle = await Self.check(Self.hexStable093).status(of: Self.install(quarantined: true), busy: .update(42))
        #expect(idle.state == .upToDate && idle.withheld == nil)
    }

    @Test func problemsAreReportedWithoutAsking() async {
        let asked = Fetched()
        let check = Self.check(Self.hexStable092, release: Self.release(fetched: asked))
        #expect(await check.status(of: Self.install(problem: .executableMissing), busy: nil).withheld == .broken)
        let linked = await check.status(of: Self.install(problem: .linkedElsewhere), busy: nil)
        #expect(linked.withheld == .unsupportedInstaller)
        #expect(linked.note?.contains("/ZZFixture/src/herdr") == true)
        #expect(await check.status(of: Self.install(target: nil), busy: nil).withheld == .versionUnreadable)
        #expect(await check.status(of: Self.install(channel: "beta"), busy: nil).withheld == .channelUnreadable)
        #expect(asked.all.isEmpty)
        let down = await Self.check(Self.hexStable092, release: Self.release(failing: ["latest.json"]))
            .status(of: Self.install(), busy: nil)
        #expect(down.withheld == .channelUnreadable && down.state == .unknown)
    }

    // MARK: - Activity

    @Test func activitySeesAnUpdateItsDownloadAndTheInstaller() throws {
        func process(_ pid: pid_t, _ args: String...) -> ClaudeCodeActivity.Process {
            ClaudeCodeActivity.Process(pid: pid, arguments: args)
        }
        let box = try Sandbox()
        let bin = box.herdr.deletingLastPathComponent()
        #expect(HerdrActivity.busy(directory: bin, processes: [process(1, "/h/.local/bin/herdr", "update")]) == .update(1))
        #expect(HerdrActivity.busy(directory: bin, processes: [process(2, "herdr", "--session", "work", "update")]) == .update(2))
        #expect(HerdrActivity.busy(directory: bin, processes: [process(3, "herdr", "channel", "set", "preview")]) == .update(3))
        #expect(HerdrActivity.busy(directory: bin, processes: [process(4, "herdr", "server")]) == nil)
        #expect(HerdrActivity.busy(directory: bin, processes: [process(5, "/x/notherdr", "update")]) == nil)
        #expect(HerdrActivity.busy(directory: bin, processes: [
            process(6, "/usr/bin/curl", "-fsSL", "https://github.com/herdrdev/herdr/releases/download/v0.9.3/herdr-macos-aarch64"),
        ]) == .download(6))
        // The download file counts while its pid runs, not after.
        try Data().write(to: bin.appendingPathComponent(".herdr-update-777.tmp"))
        #expect(HerdrActivity.busy(directory: bin, processes: [process(777, "something")]) == .update(777))
        #expect(HerdrActivity.busy(directory: bin, processes: [process(778, "something")]) == nil)
        #expect(HerdrActivity.downloadPID(".herdr-update-12.tmp") == 12)
        #expect(HerdrActivity.downloadPID(".herdr-write-test") == nil)
    }

    @Test func reportHasOneRowPerInstallAndNoProcessesWithoutOne() async {
        let asked = Fetched()
        let empty = await HerdrProvider.report(
            installs: [], processes: { asked.add(URL(string: "ps:")!); return [] }, check: Self.check(Self.hexStable092))
        #expect(empty.statuses.isEmpty)
        #expect(asked.all.isEmpty)
        let one = await HerdrProvider.report(
            installs: [Self.install()], processes: { [] }, check: Self.check(Self.hexStable092))
        #expect(one.kind == .herdr)
        #expect(one.context == .herdr)
        #expect(one.statuses.map(\.path) == ["/h/.local/bin/herdr"])
        #expect(one.sightings == [HerdrProvider.sighting(Self.install())])
    }

    // MARK: - Release notes

    @Test func releaseNotesComeFromTheStableManifest() throws {
        let notes = try #require(HerdrChangelog.parse(Data(Self.stableJSON.utf8)))
        #expect(notes.entries.map(\.version) == ["0.9.3", "0.9.2", "0.1.0"])
        let entry = notes.entries[1]
        #expect(entry.items == ["Remote machines.", "A crash on resize."])
        #expect(entry.content.contains(.heading("Added")) && entry.content.contains(.heading("Fixed")))
        #expect(HerdrChangelog.parse(Data(Self.previewJSON.utf8)) == nil)
        #expect(HerdrChangelog.parse(Data("{\"releases\":{}}".utf8)) == nil)
    }
}
