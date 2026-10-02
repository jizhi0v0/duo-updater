import Testing
import Foundation
@testable import DuoUpdaterCore

/// A fake home with node prefixes and global packages, in a temporary directory.
/// Nothing here reads the host's prefixes, npmrc files, process table or registry.
final class NpmSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("npm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    func path(_ relative: String) -> String { url(relative).path }

    @discardableResult
    func write(_ relative: String, _ text: String, executable: Bool = false) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url
    }

    func symlink(_ relative: String, to destination: String) throws {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    /// A package `name` at `version` in the prefix at `prefix` (relative to root),
    /// with a `bin` unless `bin` is false.
    func package(_ prefix: String, _ name: String, version: String, bin: Bool = true, extra: [String: Any] = [:]) throws {
        var manifest: [String: Any] = ["name": name, "version": version]
        if bin { manifest["bin"] = [String(name.split(separator: "/").last!): "cli.js"] }
        manifest.merge(extra) { $1 }
        try write("\(prefix)/lib/node_modules/\(name)/package.json", json(manifest))
    }

    /// A prefix's own node (a script printing `node`'s version) and npm 11.6.2.
    func runtime(_ prefix: String, node: String = "#!/bin/sh\necho v24.13.0\n") throws {
        try write("\(prefix)/bin/node", node, executable: true)
        try write("\(prefix)/lib/node_modules/npm/package.json", json(["name": "npm", "version": "11.6.2", "bin": ["npm": "bin/npm-cli.js"]]))
        try write("\(prefix)/lib/node_modules/npm/bin/npm-cli.js", "// npm\n")
        try symlink("\(prefix)/bin/npm", to: "../lib/node_modules/npm/bin/npm-cli.js")
    }

    func prefix(_ relative: String, _ source: NodePrefix.Source = .nvm, node: String? = "24.13.0") -> NodePrefix {
        NodePrefix(path: path(relative), source: source, layoutNodeVersion: node)
    }

    func scanner(_ prefixes: [NodePrefix], signature: CLIToolTrust.Signature = .vendor) -> NpmScanner {
        NpmScanner(home: home, prefixes: prefixes, checkSignature: { _ in signature })
    }
}

final class NpmRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.withLock { items.append(item) } }
    var all: [String] { lock.withLock { items } }
}

@Suite struct NpmTests {

    // MARK: - Node prefixes

    /// fnm keeps versions under three roots — its XDG default, the legacy
    /// `~/.fnm`, and on macOS `~/Library/Application Support/fnm` — each as
    /// `node-versions/v<version>/installation`. Its `aliases/` are links to those
    /// and are not prefixes of their own.
    @Test func fnmPrefixesUnderEveryRoot() throws {
        let box = try NpmSandbox()
        try box.write("home/.local/share/fnm/node-versions/v24.12.0/installation/bin/node", "")
        try box.write("home/.local/share/fnm/node-versions/v22.21.1/installation/bin/node", "")
        try box.write("home/.fnm/node-versions/v20.1.0/installation/bin/node", "")
        try box.write("home/Library/Application Support/fnm/node-versions/v18.0.0/installation/bin/node", "")
        try box.symlink("home/.local/share/fnm/aliases/default", to: box.path("home/.local/share/fnm/node-versions/v24.12.0/installation"))

        let found = NodePrefixes(home: box.home, systemPrefixes: []).discover([.fnm])
        #expect(found.map(\.path) == [
            box.path("home/.local/share/fnm/node-versions/v22.21.1/installation"),
            box.path("home/.local/share/fnm/node-versions/v24.12.0/installation"),
            box.path("home/.fnm/node-versions/v20.1.0/installation"),
            box.path("home/Library/Application Support/fnm/node-versions/v18.0.0/installation"),
        ])
        #expect(found.map(\.layoutNodeVersion) == ["22.21.1", "24.12.0", "20.1.0", "18.0.0"])
    }

    /// mise keeps alias links (`24` → `24.13.0`, `latest`) beside the real
    /// version directories; listing them would show one prefix twice.
    ///
    /// Mutation: drop the symlink check in `versionDirectories` → three prefixes.
    @Test func miseAliasLinksAreNotPrefixes() throws {
        let box = try NpmSandbox()
        try box.write("home/.local/share/mise/installs/node/24.13.0/bin/node", "")
        try box.symlink("home/.local/share/mise/installs/node/24", to: "24.13.0")
        try box.symlink("home/.local/share/mise/installs/node/latest", to: "24.13.0")

        let found = NodePrefixes(home: box.home, systemPrefixes: []).discover([.mise])
        #expect(found.map(\.layoutNodeVersion) == ["24.13.0"])
    }

    /// Homebrew's `bin/node` links into its keg; the keg names the version, with
    /// Homebrew's rebuild counter (`_1`) dropped.
    @Test func homebrewKegNamesTheNodeVersion() throws {
        let box = try NpmSandbox()
        try box.write("brew/Cellar/node/26.10.0_1/bin/node", "")
        try box.symlink("brew/bin/node", to: "../Cellar/node/26.10.0_1/bin/node")
        try box.write("intel/bin/node", "")  // the nodejs.org .pkg: a plain file

        let found = NodePrefixes(home: box.home, systemPrefixes: [box.url("brew"), box.url("intel")]).discover([.system])
        #expect(found.map(\.layoutNodeVersion) == ["26.10.0", nil])
    }

    @Test func npmrcPrefixIsReadWithHomeExpanded() throws {
        let box = try NpmSandbox()
        try box.write("home/.npmrc", "; comment\n//registry.npmjs.org/:_authToken=secret\nprefix = \"~/.local/npm\"\n")
        let found = NodePrefixes(home: box.home, systemPrefixes: []).discover([.npmrc])
        #expect(found.map(\.path) == [box.path("home/.local/npm")])
        try box.write("home/.npmrc", "prefix=${HOME}/g\n")
        #expect(NodePrefixes(home: box.home, systemPrefixes: []).discover([.npmrc]).map(\.path) == [box.path("home/g")])
    }

    /// Claude Code's npm installs under fnm were invisible before the shared
    /// discovery (2026-10-02).
    ///
    /// Mutation: leave `.fnm` out of `NodePrefixes.claudeCodeSources` → no install.
    @Test func claudeCodeFindsItsNpmInstallUnderFnm() throws {
        let box = try NpmSandbox()
        let prefix = "home/.local/share/fnm/node-versions/v24.12.0/installation"
        try box.write("\(prefix)/lib/node_modules/@anthropic-ai/claude-code/package.json",
                      #"{"name":"@anthropic-ai/claude-code","version":"2.1.280"}"#)
        var bytes = [UInt8](repeating: 0, count: 64)
        bytes[0] = 0xCF; bytes[1] = 0xFA; bytes[2] = 0xED; bytes[3] = 0xFE; bytes[4] = 0x0C; bytes[7] = 0x01
        try FileManager.default.createDirectory(
            at: box.url("\(prefix)/lib/node_modules/@anthropic-ai/claude-code/bin"), withIntermediateDirectories: true)
        try Data(bytes).write(to: box.url("\(prefix)/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"))

        let scanner = ClaudeCodeScanner(home: box.home, systemPrefixes: [], checkSignature: { _ in .anthropic })
        let install = try #require(scanner.scan().first)
        #expect(install.method == .npm)
        #expect(install.nodePrefix == box.path(prefix))
        #expect(install.version == "2.1.280")
    }

    /// The order Claude Code always scanned in, with fnm after nvm.
    @Test func claudeCodePrefixOrderIsUnchangedButForFnm() throws {
        let box = try NpmSandbox()
        try box.write("home/.nvm/versions/node/v24.13.0/bin/node", "")
        try box.write("home/.local/share/fnm/node-versions/v24.12.0/installation/bin/node", "")
        try box.write("home/.local/share/mise/installs/node/24.13.0/bin/node", "")
        let scanner = ClaudeCodeScanner(home: box.home, systemPrefixes: [box.url("brew")], checkSignature: { _ in .anthropic })
        #expect(scanner.nodePrefixes().map(\.path) == [
            box.path("brew"),
            box.path("home/.nvm/versions/node/v24.13.0"),
            box.path("home/.local/share/fnm/node-versions/v24.12.0/installation"),
            box.path("home/.npm-global"),
        ])
    }

    // MARK: - Scanner

    /// Rule 1: commands only. A library (`docx`), npm and corepack (they ship
    /// with node) and Claude Code (its own group) are not rows.
    ///
    /// Mutations: make `hasBin` return true → `docx` listed; empty `excluded` →
    /// npm, corepack and claude-code listed.
    @Test func onlyCommandLinePackagesAreListed() throws {
        let box = try NpmSandbox()
        try box.runtime("p")
        try box.package("p", "docx", version: "9.5.1", bin: false)
        try box.package("p", "corepack", version: "0.34.0")
        try box.package("p", "@anthropic-ai/claude-code", version: "2.1.280")
        try box.package("p", "mcp-remote", version: "0.1.38")
        try box.package("p", "@tencent-qqmail/agently-cli", version: "1.0.6")
        try box.package("p", "dirbin", version: "1.0.0", bin: false, extra: ["directories": ["bin": "./bin"]])
        try box.write("p/lib/node_modules/.package-lock.json", "{}")
        try box.write("p/lib/node_modules/.mcp-remote-AbCd/package.json", #"{"name":"mcp-remote","version":"0.0.1","bin":"x"}"#)

        let names = box.scanner([box.prefix("p")]).scan().map(\.name)
        #expect(names == ["@tencent-qqmail/agently-cli", "dirbin", "mcp-remote"])
    }

    @Test func runtimeOfThePrefixIsRead() throws {
        let box = try NpmSandbox()
        try box.runtime("p")
        try box.package("p", "mcp-remote", version: "0.1.38", extra: ["repository": ["url": "https://github.com/geelen/mcp-remote"]])
        let install = try #require(box.scanner([box.prefix("p")]).scan().first)
        #expect(install.runtime.node == box.path("p/bin/node"))
        #expect(install.runtime.npm == box.path("p/bin/npm"))
        #expect(install.runtime.npmVersion == "11.6.2")
        #expect(install.runtime.nodeVersion == "24.13.0")
        #expect(install.runtime.nodeSignature == .vendor)
        #expect(install.repository == "https://github.com/geelen/mcp-remote")
        #expect(install.linkTarget == nil)
    }

    /// One prefix met twice (an npmrc prefix that is also `~/.npm-global`) is
    /// scanned once.
    @Test func aPrefixMetTwiceIsScannedOnce() throws {
        let box = try NpmSandbox()
        try box.package("home/.npm-global", "mcp-remote", version: "0.1.38")
        let installs = box.scanner([box.prefix("home/.npm-global", .npmGlobal, node: nil),
                                    box.prefix("home/.npm-global", .npmrc, node: nil)]).scan()
        #expect(installs.count == 1)
        #expect(installs.first?.runtime.node == nil)
    }

    @Test func aLinkedPackageCarriesItsTarget() throws {
        let box = try NpmSandbox()
        try box.write("src/mytool/package.json", #"{"name":"mytool","version":"1.0.0","bin":"cli.js"}"#)
        try box.symlink("p/lib/node_modules/mytool", to: "../../../src/mytool")
        let install = try #require(box.scanner([box.prefix("p")]).scan().first)
        #expect(install.linkTarget == box.path("src/mytool"))
    }

    /// A `registry` (or `@scope:registry`) in an npmrc is noted, with its file;
    /// npm's own registry, spelled out, is not a custom one.
    @Test func customRegistriesAreNoticed() throws {
        let box = try NpmSandbox()
        try box.runtime("p")
        try box.package("p", "mcp-remote", version: "0.1.38")
        try box.package("p", "@corp/tool", version: "1.0.0")
        try box.write("home/.npmrc", "registry=https://registry.npmjs.org\n@corp:registry=https://npm.corp.example/\n//npm.corp.example/:_authToken=secret\n")
        var installs = box.scanner([box.prefix("p")]).scan()
        #expect(installs.first { $0.name == "mcp-remote" }?.customRegistry == nil)
        #expect(installs.first { $0.name == "@corp/tool" }?.customRegistry
                == .init(url: "https://npm.corp.example/", file: box.path("home/.npmrc")))

        try box.write("p/etc/npmrc", "registry=https://registry.npmmirror.com/\n")
        try box.write("home/.npmrc", "")
        installs = box.scanner([box.prefix("p")]).scan()
        #expect(installs.first { $0.name == "mcp-remote" }?.customRegistry?.url == "https://registry.npmmirror.com/")
    }

    @Test func openclawSettingsAreReadFromItsJSON5Config() throws {
        let box = try NpmSandbox()
        try box.package("p", "openclaw", version: "2026.3.28")
        try box.write("p/lib/node_modules/openclaw/docs/cli/update.md", "- `--tag <dist-tag|version|spec>`: override\n")
        try box.write("home/.openclaw/openclaw.json", "{\n  // json5\n  update: { channel: 'beta', auto: { enabled: false, }, },\n}\n")
        let install = try #require(box.scanner([box.prefix("p")]).scan().first)
        #expect(install.ownUpdate == .openclaw(OpenClawSettings(channel: "beta", autoUpdate: false, supportsTag: true)))
    }

    // MARK: - Pick

    func doc(_ tags: [String: String], _ versions: [String: NpmPackument.Manifest]) -> NpmPackument {
        NpmPackument(distTags: tags, versions: versions)
    }

    /// openclaw on 2026-10-02 under node 24.13.0: `latest` 2026.9.7 needs
    /// `>=24.16.0 <25 || >=26.1.0`; the newest it runs is 2026.6.35.
    @Test func newestRunnableVersionIsOfferedAndTheNewerOneIsNamed() throws {
        let packument = doc(["latest": "2026.9.7", "beta": "2026.9.7"], [
            "2026.3.28": .init(node: ">=22.14.0"),
            "2026.6.35": .init(node: ">=22.19.0"),
            "2026.7.35": .init(node: ">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0"),
            "2026.9.1-beta.1": .init(node: ">=22.19.0"),
            "2026.9.7": .init(node: ">=24.16.0 <25 || >=26.1.0"),
        ])
        let pick = try #require(NpmPick.pick(packument, installed: "2026.3.28", tag: "latest",
                                             node: NpmVersion("24.13.0"), npm: NpmVersion("11.6.2")))
        #expect(pick.offered == "2026.6.35")
        #expect(pick.gap?.version == "2026.9.7")
        #expect(pick.gap?.minimumNode == "24.16.0")
        #expect(pick.gap?.requirement == "needs Node ≥ 24.16.0")
        #expect(pick.pending == ["2026.6.35"])  // the beta is not on `latest`'s track
    }

    /// Mutation: drop `runs(...)` from the offered filter → 2.0.0 offered.
    @Test func noRunnableVersionLeavesOnlyTheGap() throws {
        let packument = doc(["latest": "2.0.0"], ["1.0.0": .init(), "2.0.0": .init(node: ">=26")])
        let pick = try #require(NpmPick.pick(packument, installed: "1.0.0", tag: "latest", node: NpmVersion("24.13.0"), npm: nil))
        #expect(pick.offered == nil)
        #expect(pick.gap == .init(version: "2.0.0", node: ">=26", npm: nil, nodeVersion: "24.13.0", minimumNode: "26.0.0"))
        #expect(pick.pending == ["2.0.0"])
    }

    /// pnpm's 12.8.2 is above `latest` (12.8.1) under `next-12` only: not offered.
    /// Deprecated versions are skipped.
    ///
    /// Mutations: drop `v <= ceiling` → 12.8.2; drop `!deprecated` → 12.8.1-dep.
    @Test func neverAboveTheTagAndNeverDeprecated() throws {
        let packument = doc(["latest": "12.8.1", "next-12": "12.8.2"], [
            "10.27.0": .init(), "12.8.0": .init(), "12.8.1": .init(deprecated: true), "12.8.2": .init(),
        ])
        let pick = try #require(NpmPick.pick(packument, installed: "10.27.0", tag: "latest", node: nil, npm: nil))
        #expect(pick.offered == "12.8.0")
        #expect(pick.tagVersion == "12.8.1")
    }

    /// Mutation: drop the `current < ceiling` guard → an "offer" below the install.
    @Test func neverADowngrade() throws {
        // prettier@next 4.0.0-alpha.13 with `latest` at 3.9.9: `npm update -g`
        // took it down to 3.9.9 (observed); here it is ahead of `latest`.
        let packument = doc(["latest": "3.9.9"], ["3.9.9": .init(), "4.0.0-alpha.13": .init()])
        let pick = try #require(NpmPick.pick(packument, installed: "4.0.0-alpha.13", tag: "latest", node: nil, npm: nil))
        #expect(pick.offered == nil)
        #expect(pick.pending.isEmpty)
    }

    /// A prerelease follows the tag named after its prerelease word, else the
    /// highest other tag on that word, else `latest`.
    @Test func prereleasesFollowTheirTag() throws {
        let tags = ["latest": "3.9.9", "next": "4.0.0-alpha.14", "beta": "5.0.0-beta.1"]
        #expect(NpmPick.track(installed: try #require(NpmVersion("4.0.0-alpha.13")), distTags: tags) == "next")
        #expect(NpmPick.track(installed: try #require(NpmVersion("5.0.0-beta.0")), distTags: tags) == "beta")
        #expect(NpmPick.track(installed: try #require(NpmVersion("3.0.0")), distTags: tags) == "latest")
        #expect(NpmPick.track(installed: try #require(NpmVersion("4.0.0-rc.1")), distTags: tags) == "latest")
        // The tag named after the word wins even where it points at a release
        // (openclaw's `beta` == `latest`, 2026-10-02) and another tag holds a
        // newer prerelease with that word. Mutation: drop the named lookup → `canary`.
        let openclaw = ["latest": "2026.9.7", "beta": "2026.9.7", "canary": "2026.9.8-beta.2"]
        #expect(NpmPick.track(installed: try #require(NpmVersion("2026.9.1-beta.1")), distTags: openclaw) == "beta")

        let packument = doc(tags, ["4.0.0-alpha.13": .init(), "4.0.0-alpha.14": .init(), "3.9.9": .init()])
        let pick = try #require(NpmPick.pick(packument, installed: "4.0.0-alpha.13", tag: "next", node: nil, npm: nil))
        #expect(pick.offered == "4.0.0-alpha.14")
    }

    /// Mutation: drop `prereleaseTrack || !v.isPrerelease` → a beta offered on `latest`.
    @Test func latestTrackOffersReleasesOnly() throws {
        let packument = doc(["latest": "1.1.0"], ["1.0.0": .init(), "1.1.0": .init(node: ">=99"), "1.1.0-beta.1": .init()])
        let pick = try #require(NpmPick.pick(packument, installed: "1.0.0", tag: "latest", node: NpmVersion("24.0.0"), npm: nil))
        #expect(pick.offered == nil)
    }

    @Test func openclawBetaFallsBackToANewerLatest() {
        #expect(NpmPick.openclawTag(channel: "beta", distTags: ["latest": "2026.9.7", "beta": "2026.9.7"]) == "beta")
        #expect(NpmPick.openclawTag(channel: "beta", distTags: ["latest": "2026.9.7", "beta": "2026.9.1-beta.1"]) == "latest")
        #expect(NpmPick.openclawTag(channel: "beta", distTags: ["latest": "2026.9.7"]) == "latest")
        #expect(NpmPick.openclawTag(channel: "stable", distTags: ["latest": "2026.9.7", "beta": "2026.9.8-beta.1"]) == "latest")
    }

    @Test func packumentParsesTheAbbreviatedDocument() throws {
        let json = """
            {"name":"pnpm","dist-tags":{"latest":"12.8.1"},"versions":{
              "12.8.1":{"name":"pnpm","version":"12.8.1","engines":{"node":">=18.*"}},
              "1.0.0":{"engines":["node >= 0.8"]},
              "2.0.0":{"engines":{"node":null},"deprecated":"use 3"},
              "3.0.0":{"deprecated":""}}}
            """
        let packument = try #require(NpmPackument.parse(Data(json.utf8)))
        #expect(packument.distTags == ["latest": "12.8.1"])
        #expect(packument.versions["12.8.1"] == .init(node: ">=18.*"))
        #expect(packument.versions["1.0.0"] == .init())
        #expect(packument.versions["2.0.0"] == .init(deprecated: true))
        #expect(packument.versions["3.0.0"] == .init())
        #expect(NpmRegistry.url(for: "@tencent-qqmail/agently-cli").absoluteString
                == "https://registry.npmjs.org/@tencent-qqmail%2fagently-cli")
    }

    // MARK: - Check

    func install(
        _ box: NpmSandbox, _ name: String = "mcp-remote", version: String = "0.1.38",
        signature: CLIToolTrust.Signature = .vendor, extra: [String: Any] = [:]
    ) throws -> NpmInstall {
        try box.runtime("p")
        try box.package("p", name, version: version, extra: extra)
        return try #require(box.scanner([box.prefix("p")], signature: signature).scan().first { $0.name == name })
    }

    let mcpRemote = NpmPackument(distTags: ["latest": "0.14.3"], versions: ["0.1.38": .init(), "0.14.3": .init()])

    func check(_ box: NpmSandbox, _ packument: NpmPackument? = nil, asked: NpmRecorder? = nil) -> NpmCheck {
        let document = packument ?? mcpRemote
        return NpmCheck(packument: { name in
            asked?.add(name)
            return document
        })
    }

    @Test func anOutdatedRegistryPackageIsOfferedItsExactVersion() async throws {
        let box = try NpmSandbox()
        let install = try install(box)
        let status = await check(box).status(of: install, busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "0.14.3")
        #expect(status.channel == "latest")
        #expect(status.name == "mcp-remote")
        #expect(status.releaseNotesKey == "npm:mcp-remote")
        #expect(status.withheld == nil)
        #expect(status.oneClick == CLIToolCommand(
            executable: box.path("p/bin/node"),
            arguments: [box.path("p/bin/npm"), "install", "-g", "--prefix", box.path("p"), "--engine-strict", "mcp-remote@0.14.3"],
            pathPrefix: box.path("p/bin")))
    }

    @Test func upToDateAndAheadOfferNothing() async throws {
        let box = try NpmSandbox()
        var status = await check(box).status(of: try install(box, version: "0.14.3"), busy: nil)
        #expect(status.state == .upToDate)
        #expect(status.oneClick == nil)
        guard case .npm(let package) = status.detail else { Issue.record("detail"); return }
        #expect(package.pending == ["0.14.3"])
        let ahead = NpmPackument(distTags: ["latest": "0.14.3"], versions: ["0.14.3": .init(), "0.15.0": .init()])
        status = await check(box, ahead).status(of: try install(box, version: "0.15.0"), busy: nil)
        #expect(status.state == .ahead)
    }

    /// Rule 4: a linked package is someone's working copy.
    ///
    /// Mutation: drop the `linkTarget` gate → offered, the registry asked.
    @Test func aLinkedPackageIsReportedOnly() async throws {
        let box = try NpmSandbox()
        try box.runtime("p")
        try box.write("src/mcp-remote/package.json", #"{"name":"mcp-remote","version":"0.1.38","bin":"x"}"#)
        try box.symlink("p/lib/node_modules/mcp-remote", to: box.path("src/mcp-remote"))
        let install = try #require(box.scanner([box.prefix("p")]).scan().first)
        let asked = NpmRecorder()
        let status = await check(box, asked: asked).status(of: install, busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
        #expect(status.note?.contains(box.path("src/mcp-remote")) == true)
        #expect(asked.all.isEmpty)
    }

    /// Rule 4: a version the registry does not list came from git, a tarball
    /// or a fork.
    ///
    /// Mutation: drop the `versions[installed]` guard → offered over the fork.
    @Test func aVersionTheRegistryDoesNotListIsReportedOnly() async throws {
        let box = try NpmSandbox()
        let status = await check(box).status(of: try install(box, version: "0.1.38-fork.1"), busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.state == .unknown)
        #expect(status.oneClick == nil)
    }

    /// Mutation: drop the alias gate → `foo@0.14.3` would install the wrong package.
    @Test func anAliasIsReportedOnly() async throws {
        let box = try NpmSandbox()
        try box.runtime("p")
        try box.write("p/lib/node_modules/foo/package.json", #"{"name":"mcp-remote","version":"0.1.38","bin":"x"}"#)
        let install = try #require(box.scanner([box.prefix("p")]).scan().first)
        let status = await check(box).status(of: install, busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
    }

    /// No token is read, so a package from another registry is not looked up.
    ///
    /// Mutation: drop the `customRegistry` gate → the public registry is asked.
    @Test func aCustomRegistryIsReportedOnly() async throws {
        let box = try NpmSandbox()
        try box.write("home/.npmrc", "registry=https://registry.npmmirror.com/\n")
        let asked = NpmRecorder()
        let status = await check(box, asked: asked).status(of: try install(box), busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.note?.contains("registry.npmmirror.com") == true)
        #expect(asked.all.isEmpty)
    }

    @Test func registryFailuresAreSaidApart() async throws {
        let box = try NpmSandbox()
        let install = try install(box)
        var status = await NpmCheck(packument: { _ in throw NpmRegistry.Failure.notFound })
            .status(of: install, busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        status = await NpmCheck(packument: { _ in throw NpmRegistry.Failure.http(503) })
            .status(of: install, busy: nil)
        #expect(status.withheld == .channelUnreadable)
    }

    /// Rule 3's whole verdict: nothing newer runs here.
    @Test func onlyTooNewVersionsAreWithheldAsRuntimeTooOld() async throws {
        let box = try NpmSandbox()
        let packument = NpmPackument(distTags: ["latest": "0.14.3"],
                                     versions: ["0.1.38": .init(), "0.14.3": .init(node: ">=24.16.0 <25 || >=26.1.0")])
        let status = await check(box, packument).status(of: try install(box), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .runtimeTooOld)
        #expect(status.latestVersion == "0.14.3")
        #expect(status.oneClick == nil)
        #expect(status.note == "0.14.3 needs Node ≥ 24.16.0 (this prefix has 24.13.0): no version above 0.1.38 runs here")
    }

    /// Rule 3 alongside an offer: the row can say both.
    @Test func aCompatibleOfferNamesTheNewerVersionItCannotRun() async throws {
        let box = try NpmSandbox()
        let packument = NpmPackument(distTags: ["latest": "0.14.3"], versions: [
            "0.1.38": .init(), "0.13.0": .init(node: ">=20"), "0.14.3": .init(node: ">=26")])
        let status = await check(box, packument).status(of: try install(box), busy: nil)
        #expect(status.latestVersion == "0.13.0")
        #expect(status.oneClick?.arguments.last == "mcp-remote@0.13.0")
        #expect(status.note == "0.14.3 needs Node ≥ 26.0.0")
        guard case .npm(let package) = status.detail else { Issue.record("detail"); return }
        #expect(package.offered == "0.13.0")
        #expect(package.newest == "0.14.3")
        #expect(package.gap?.minimumNode == "26.0.0")
    }

    /// `~/.npm-global` holds links only: which npm owns it cannot be told.
    ///
    /// Mutation: drop the own-npm gate → a command with no executable.
    @Test func aPrefixWithoutItsOwnNodeIsReportedOnly() async throws {
        let box = try NpmSandbox()
        try box.package("g", "mcp-remote", version: "0.1.38")
        let install = try #require(box.scanner([box.prefix("g", .npmGlobal, node: nil)]).scan().first)
        let status = await check(box).status(of: install, busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .noOwnNpm)
        #expect(status.oneClick == nil)
    }

    /// The trust rule: only a Node.js-signed node is run. Homebrew's is ad hoc.
    ///
    /// Mutation: let `.adHoc` through the signature switch → offered.
    @Test func aNodeNotSignedByNodeJSIsNotRun() async throws {
        for (signature, withheld) in [(CLIToolTrust.Signature.adHoc, CLIToolWithheld.unverified),
                                      (.unsigned, .unverified), (.otherSigner, .wrongSigner), (.invalid, .wrongSigner)] {
            let box = try NpmSandbox()
            let status = await check(box).status(of: try install(box, signature: signature), busy: nil)
            #expect(status.withheld == withheld, "\(signature)")
            #expect(status.oneClick == nil)
            #expect(status.state == .updateAvailable)
        }
    }

    /// Mutation: drop the quarantine gate → offered.
    @Test func aQuarantinedNodeIsNotRun() async throws {
        let box = try NpmSandbox()
        let base = try install(box)
        let runtime = base.runtime
        let quarantined = NpmInstall(
            path: base.path, name: base.name, version: base.version, manifestName: base.manifestName, prefix: base.prefix,
            runtime: NpmRuntime(node: runtime.node, npm: runtime.npm, npmVersion: runtime.npmVersion,
                                nodeSignature: .vendor, nodeQuarantined: true, nodeVersion: runtime.nodeVersion))
        let status = await check(box).status(of: quarantined, busy: nil)
        #expect(status.withheld == .unverified)
        #expect(status.oneClick == nil)
    }

    /// Mutation: drop the busy gate → offered while npm runs.
    @Test func aChangeInFlightWithholdsTheOffer() async throws {
        let box = try NpmSandbox()
        let status = await check(box).status(of: try install(box), busy: .npm("npm install", pid: 42))
        #expect(status.withheld == .busy)
        #expect(status.oneClick == nil)
        #expect(status.note == "npm install is running in this node prefix (pid 42)")
    }

    @Test func eachPackageIsAskedOnce() async throws {
        let box = try NpmSandbox()
        try box.runtime("q")
        try box.package("q", "mcp-remote", version: "0.1.38")
        let installs = [try install(box)] + box.scanner([box.prefix("q")]).scan()
        let asked = NpmRecorder()
        let statuses = await check(box, asked: asked).statuses(of: installs) { _ in nil }
        #expect(statuses.count == 2)
        #expect(asked.all == ["mcp-remote"])
    }

    // MARK: - Check: packages with their own updater

    let openclaw = NpmPackument(distTags: ["latest": "2026.9.7", "beta": "2026.9.7"], versions: [
        "2026.3.28": .init(node: ">=22.14.0"), "2026.6.35": .init(node: ">=22.19.0"),
        "2026.9.7": .init(node: ">=24.16.0 <25 || >=26.1.0"),
    ])

    func openclawInstall(_ box: NpmSandbox, config: String? = nil, documentsTag: Bool = true) throws -> NpmInstall {
        if let config { try box.write("home/.openclaw/openclaw.json", config) }
        if documentsTag {
            try box.write("p/lib/node_modules/openclaw/docs/cli/update.md", "- `--tag <dist-tag|version|spec>`: override\n")
        }
        return try install(box, "openclaw", version: "2026.3.28")
    }

    /// `openclaw update --tag <exact>`, by this prefix's node, its `bin` first.
    @Test func openclawUpdatesItselfToTheExactVersion() async throws {
        let box = try NpmSandbox()
        let status = await check(box, openclaw).status(of: try openclawInstall(box), busy: nil)
        #expect(status.oneClick == CLIToolCommand(
            executable: box.path("p/bin/node"),
            arguments: [box.path("p/lib/node_modules/openclaw/openclaw.mjs"), "update", "--tag", "2026.6.35"],
            pathPrefix: box.path("p/bin")))
        guard case .npm(let package) = status.detail else { Issue.record("detail"); return }
        #expect(package.updater == .openclaw)
        #expect(status.note == "2026.9.7 needs Node ≥ 24.16.0")
    }

    /// Mutation: drop the `supportsTag` condition → `--tag` sent to an openclaw
    /// that does not document it.
    @Test func openclawWithoutTagFallsBackToNpm() async throws {
        let box = try NpmSandbox()
        let status = await check(box, openclaw).status(of: try openclawInstall(box, documentsTag: false), busy: nil)
        #expect(status.oneClick?.arguments.contains("openclaw@2026.6.35") == true)
        #expect(status.note?.contains("does not document --tag") == true)
    }

    /// openclaw's own `npm i -g` has no `--prefix`: an npmrc `prefix=` elsewhere
    /// would install a second copy there.
    ///
    /// Mutation: ignore `npmrcPrefix` → `openclaw update` offered.
    @Test func openclawUnderARedirectingNpmrcFallsBackToNpm() async throws {
        let box = try NpmSandbox()
        try box.write("home/.npmrc", "prefix=~/.npm-global\n")
        let status = await check(box, openclaw).status(of: try openclawInstall(box), busy: nil)
        #expect(status.oneClick?.arguments.contains("--prefix") == true)
        // The same prefix named in the npmrc is no redirect.
        try box.write("home/.npmrc", "prefix=\(box.path("p"))\n")
        let same = await check(box, openclaw).status(of: try openclawInstall(box), busy: nil)
        #expect(same.oneClick?.arguments.contains("update") == true)
    }

    /// Mutation: drop the `autoUpdate == false` gate → offered.
    @Test func openclawWithAutoUpdateTurnedOffIsReportedWithTheCommand() async throws {
        let box = try NpmSandbox()
        let status = await check(box, openclaw)
            .status(of: try openclawInstall(box, config: #"{"update":{"auto":{"enabled":false}}}"#), busy: nil)
        #expect(status.withheld == .autoUpdateOff)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand?.arguments.suffix(3) == ["update", "--tag", "2026.6.35"])
        // Unset is openclaw's default, not the user turning it off.
        let unset = await check(box, openclaw).status(of: try openclawInstall(box, config: "{}"), busy: nil)
        #expect(unset.oneClick != nil)
    }

    /// Mutation: drop the dev-channel gate → offered from npm.
    @Test func openclawOnTheDevChannelIsReportedOnly() async throws {
        let box = try NpmSandbox()
        let status = await check(box, openclaw)
            .status(of: try openclawInstall(box, config: #"{"update":{"channel":"dev"}}"#), busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
    }

    @Test func openclawOnBetaFollowsTheBetaTag() async throws {
        let box = try NpmSandbox()
        let packument = NpmPackument(distTags: ["latest": "2026.6.35", "beta": "2026.7.1-beta.2"], versions: [
            "2026.3.28": .init(), "2026.6.35": .init(), "2026.7.1-beta.2": .init()])
        let status = await check(box, packument)
            .status(of: try openclawInstall(box, config: #"{"update":{"channel":"beta"}}"#), busy: nil)
        #expect(status.channel == "beta")
        #expect(status.latestVersion == "2026.7.1-beta.2")
    }

    /// `agent-browser upgrade` installs `@latest`; npm installs the exact version.
    @Test func agentBrowserIsUpdatedWithNpm() async throws {
        let box = try NpmSandbox()
        let packument = NpmPackument(distTags: ["latest": "0.38.1"],
                                     versions: ["0.34.0": .init(node: ">=24.0.0"), "0.38.1": .init(node: ">=24.0.0")])
        let status = await check(box, packument).status(of: try install(box, "agent-browser", version: "0.34.0"), busy: nil)
        #expect(status.oneClick?.arguments.last == "agent-browser@0.38.1")
        #expect(status.note?.contains("agent-browser upgrade") == true)
    }

    // MARK: - Activity

    func activityInstall(_ box: NpmSandbox, _ name: String = "mcp-remote") throws -> NpmInstall {
        try install(box, name, version: name == "openclaw" ? "2026.3.28" : "0.1.38")
    }

    /// npm writes its title over argv; only the executable still names the
    /// prefix (measured 2026-10-02, see `NpmActivity`).
    ///
    /// Mutation: drop the executable comparison → another prefix's npm counts.
    @Test func npmIsAttributedToThePrefixByItsNode() throws {
        let box = try NpmSandbox()
        let install = try activityInstall(box)
        let title = ["npm install cowsay@1.6.0", "", "", "", "", "", ""]
        #expect(NpmActivity.busy(install, processes: [.init(pid: 7, arguments: title, executable: box.path("p/bin/node"))])
                == .npm("npm install", pid: 7))
        #expect(NpmActivity.busy(install, processes: [.init(pid: 7, arguments: title, executable: "/ZZFixture-other/bin/node")]) == nil)
        #expect(!FileManager.default.fileExists(atPath: "/ZZFixture-other"))
        // Before npm sets its title.
        let started = [box.path("p/bin/node"), box.path("p/bin/npm"), "install", "-g", "--prefix", box.path("p"), "x@1"]
        #expect(NpmActivity.busy(install, processes: [.init(pid: 8, arguments: started, executable: box.path("p/bin/node"))])
                == .npm("npm install", pid: 8))
        #expect(NpmActivity.busy(install, processes: [.init(pid: 9, arguments: ["npm", "", ""], executable: box.path("p/bin/node"))])
                == .npm("npm", pid: 9))
    }

    @Test func npmCommandsThatDoNotWriteAreNotBusy() {
        for title in ["npm run dev", "npm ls -g", "npm view openclaw", "npm exec foo", "node server.js"] {
            #expect(NpmActivity.npmCommand([title, ""]) == nil, "\(title)")
        }
        #expect(NpmActivity.npmCommand(["npm uninstall foo", ""]) == "npm uninstall")
        #expect(NpmActivity.npmCommand(["/x/node", "/x/lib/node_modules/npm/bin/npm-cli.js", "--loglevel=info", "-g", "ls"]) == nil)
        #expect(NpmActivity.npmCommand(["/x/node", "/x/lib/node_modules/npm/bin/npm-cli.js", "-g", "update"]) == "npm update")
    }

    @Test func aPackagesOwnUpdaterIsBusy() throws {
        let box = try NpmSandbox()
        let install = try activityInstall(box, "openclaw")
        try box.symlink("p/bin/openclaw", to: "../lib/node_modules/openclaw/openclaw.mjs")
        try box.write("p/lib/node_modules/openclaw/openclaw.mjs", "")
        let running = NpmActivity.Process(pid: 5, arguments: ["node", box.path("p/bin/openclaw"), "update", "--tag", "x"],
                                          executable: "/ZZFixture-elsewhere/node")
        #expect(NpmActivity.busy(install, processes: [running]) == .ownUpdater("openclaw update", pid: 5))
        let status = NpmActivity.Process(pid: 6, arguments: ["node", box.path("p/bin/openclaw"), "status"], executable: nil)
        #expect(NpmActivity.busy(install, processes: [status]) == nil)
    }

    /// Once running, openclaw's update and its doctor carry only their titles —
    /// `openclaw-update`, `openclaw-doctor` — and count, run by this prefix's node.
    /// Its other commands, and another node's, do not.
    ///
    /// Mutation: drop `ownUpdaterTitle` from `busy`.
    @Test func openclawsOwnUpdateIsBusyUnderItsTitle() throws {
        let box = try NpmSandbox()
        let install = try activityInstall(box, "openclaw")
        let node = box.path("p/bin/node")
        for title in ["openclaw-update", "openclaw-doctor"] {
            let running = NpmActivity.Process(pid: 5, arguments: [title, "", ""], executable: node)
            #expect(NpmActivity.busy(install, processes: [running]) == .ownUpdater("openclaw " + title.dropFirst(9), pid: 5))
        }
        let gateway = NpmActivity.Process(pid: 6, arguments: ["openclaw-gateway", "", ""], executable: node)
        #expect(NpmActivity.busy(install, processes: [gateway]) == nil)
        let elsewhere = NpmActivity.Process(pid: 7, arguments: ["openclaw-update", ""], executable: "/ZZFixture-other/bin/node")
        #expect(NpmActivity.busy(install, processes: [elsewhere]) == nil)
    }

    // MARK: - Provider

    /// A Node.js-signed node whose layout does not name its version is asked,
    /// once; any other node is not run.
    ///
    /// Mutation: drop the `.vendor` condition → the ad hoc node is run.
    @Test func nodeVersionIsAskedOnlyOfASignedNode() async throws {
        let box = try NpmSandbox()
        try box.runtime("p")
        try box.package("p", "a", version: "1.0.0")
        try box.package("p", "b", version: "1.0.0")
        let signed = box.scanner([box.prefix("p", .system, node: nil)]).scan()
        let asked = NpmRecorder()
        let filled = await NpmProvider.withNodeVersions(signed) { asked.add($0); return "24.13.0" }
        #expect(filled.map(\.runtime.nodeVersion) == ["24.13.0", "24.13.0"])
        #expect(asked.all == [box.path("p/bin/node")])

        let adHoc = box.scanner([box.prefix("p", .system, node: nil)], signature: .adHoc).scan()
        let notAsked = NpmRecorder()
        let left = await NpmProvider.withNodeVersions(adHoc) { notAsked.add($0); return "24.13.0" }
        #expect(left.map(\.runtime.nodeVersion) == [nil, nil])
        #expect(notAsked.all.isEmpty)
    }

    @Test func sightingChangesWhenTheVerdictsGroundsDo() throws {
        let box = try NpmSandbox()
        let install = try install(box)
        let before = NpmProvider.sighting(install)
        let adHoc = try #require(box.scanner([box.prefix("p")], signature: .adHoc).scan().first)
        #expect(NpmProvider.sighting(adHoc) != before)
        #expect(before.kind == .npm)
        #expect(before.path == install.path)
    }
}

/// Which prefixes' node may be run: the Node.js Foundation's, or Homebrew's own
/// keg (ad hoc signed; the user chose to trust it on 2026-10-02).
@Suite struct NpmNodeTrustTests {

    func runtime(_ signature: CLIToolTrust.Signature?, keg: String?, quarantined: Bool = false) -> NpmRuntime {
        NpmRuntime(node: "/ZZFixture-node/bin/node", npm: "/ZZFixture-node/bin/npm", npmVersion: "11.6.2",
                   nodeSignature: signature, nodeQuarantined: quarantined, nodeVersion: "24.13.0", homebrewKeg: keg)
    }

    /// Mutation: return `true` for `.adHoc` whatever the keg.
    @Test func anAdHocNodeIsTrustedOnlyAsAHomebrewKeg() {
        #expect(runtime(.vendor, keg: nil).nodeIsTrusted)
        #expect(runtime(.adHoc, keg: "/opt/homebrew/Cellar/node/26.10.0_1").nodeIsTrusted)
        #expect(!runtime(.adHoc, keg: nil).nodeIsTrusted)
        #expect(!runtime(.otherSigner, keg: "/opt/homebrew/Cellar/node/26.10.0_1").nodeIsTrusted)
        #expect(!runtime(.invalid, keg: "/opt/homebrew/Cellar/node/26.10.0_1").nodeIsTrusted)
    }

    /// Mutation: drop the quarantine guard in `nodeIsTrusted`.
    @Test func aQuarantinedNodeIsNeverTrusted() {
        #expect(!runtime(.vendor, keg: nil, quarantined: true).nodeIsTrusted)
        #expect(!runtime(.adHoc, keg: "/opt/homebrew/Cellar/node/26.10.0_1", quarantined: true).nodeIsTrusted)
    }

    /// A keg is a node under `<root>/Cellar/node[@n]/<v>/bin/node` with brew's
    /// receipt beside it, for a Homebrew root only.
    ///
    /// Mutations: drop the receipt check; drop the root check.
    @Test func aHomebrewKegNeedsItsRootItsCellarAndItsReceipt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-brew-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let keg = root.appendingPathComponent("Cellar/node/26.10.0_1")
        let node = keg.appendingPathComponent("bin/node")
        try FileManager.default.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: node)
        let roots = [root.path]

        #expect(NodePrefixes.homebrewKeg(ofNode: node, prefix: root, homebrewRoots: roots) == nil)
        try Data("{}".utf8).write(to: keg.appendingPathComponent("INSTALL_RECEIPT.json"))
        #expect(NodePrefixes.homebrewKeg(ofNode: node, prefix: root, homebrewRoots: roots) == keg.path)
        #expect(NodePrefixes.homebrewKeg(ofNode: node, prefix: root) == nil)

        let elsewhere = root.appendingPathComponent("opt/node/bin/node")
        #expect(NodePrefixes.homebrewKeg(ofNode: elsewhere, prefix: root, homebrewRoots: roots) == nil)
    }
}
