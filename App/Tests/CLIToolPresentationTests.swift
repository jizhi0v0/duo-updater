import Foundation
import Testing
import DuoUpdaterCore

/// How the workbench's CLI tab words an install of a tool without wording of its
/// own (bub, fx), from `CLIToolStatus`'s shared fields alone. Every path is made
/// up and `home` is passed in, so no answer depends on the Mac running the tests.
///
/// Each case names the one-line mutation of `CLIToolPresentation` it fails under.
struct CLIToolPresentationTests {

    private static let home = "/Users/ann"

    private func fx(
        _ path: String = "/Users/ann/.fx/bin/fx", version: String? = "0.4.0", latest: String? = "0.5.0",
        state: CLIToolState = .updateAvailable, channel: String? = "stable",
        oneClick: Bool = true, withheld: CLIToolWithheld? = nil, manual: Bool = false
    ) -> CLIToolStatus {
        let command = CLIToolCommand(executable: path, arguments: ["upgrade"], pathPrefix: nil)
        return CLIToolStatus(
            kind: .fx, path: path, installedVersion: version, latestVersion: latest, channel: channel,
            state: state, oneClick: oneClick ? command : nil,
            withheld: withheld, note: nil, manualCommand: manual ? command : nil,
            detail: .fx(FxInstall(path: path, version: version)))
    }

    /// The command to copy only beside an update withheld because the user turned
    /// the tool's auto-update off. Mutation: dropping the `withheld` check hands it
    /// out beside a running update.
    /// bub's first update creates its project and may rebuild the venv on
    /// another Python (measured on the user's Mac, 2026-10-01): said beside the
    /// click, only then. Mutation: dropping the `.absent` check says it beside
    /// every bub update.
    @Test func onlyBubsFirstUpdateCarriesTheCaution() {
        func bub(_ project: BubInstall.Project?, oneClick: Bool = true) -> CLIToolStatus {
            let path = "/Users/ann/.bub/.venv"
            return CLIToolStatus(
                kind: .bub, path: path, installedVersion: "0.4.4", latestVersion: "0.5.0", channel: nil,
                state: .updateAvailable,
                oneClick: oneClick ? CLIToolCommand(executable: path + "/bin/bub", arguments: ["update", "bub"], pathPrefix: nil) : nil,
                withheld: oneClick ? nil : .updaterMissing, note: nil,
                detail: .bub(BubInstall(path: path, method: .installer, executable: path + "/bin/bub",
                                        version: "0.4.4", project: project)))
        }
        #expect(CLIToolPresentation.caution(bub(.absent)) != nil)
        #expect(CLIToolPresentation.caution(bub(.listsBub)) == nil)
        #expect(CLIToolPresentation.caution(bub(.absent, oneClick: false)) == nil)
        #expect(CLIToolPresentation.caution(fx()) == nil)
    }

    @Test func onlyAutoUpdateOffHandsOutTheCommand() {
        #expect(CLIToolPresentation.manualCommand(fx(oneClick: false, withheld: .autoUpdateOff, manual: true))
                == "/Users/ann/.fx/bin/fx upgrade")
        #expect(CLIToolPresentation.manualCommand(fx(oneClick: false, withheld: .busy, manual: true)) == nil)
        #expect(CLIToolPresentation.manualCommand(
            fx(state: .upToDate, oneClick: false, withheld: .autoUpdateOff, manual: true)) == nil)
    }

    /// Mutation: drop the `.claudeCode` branch from `title(of:home:)` — an nvm
    /// copy of Claude Code would then be named by its whole package path.
    @Test func theTitleIsThePathWithHomeAsTildeAndClaudeCodeKeepsItsOwn() {
        #expect(CLIToolPresentation.title(of: fx(), home: Self.home) == "~/.fx/bin/fx")

        let prefix = "/Users/ann/.nvm/versions/node/v24.13.0"
        let path = prefix + "/lib/node_modules/@anthropic-ai/claude-code"
        let json: [String: Any] = [
            "install": ["path": path, "method": "npm", "origin": "conventional", "nodePrefix": prefix],
            "channel": "latest", "state": "upToDate",
        ]
        let claudeCode = try! JSONDecoder().decode(
            ClaudeCodeStatus.self, from: try! JSONSerialization.data(withJSONObject: json))
        let status = CLIToolStatus(
            kind: .claudeCode, path: path, installedVersion: nil, latestVersion: nil, channel: "latest",
            state: .upToDate, oneClick: nil, withheld: nil, note: nil, detail: .claudeCode(claudeCode))
        #expect(CLIToolPresentation.title(of: status, home: Self.home) == "nvm · node v24.13.0")
    }

    /// An update shows both versions; otherwise the version alone.
    ///
    /// Mutation: drop `status.state == .updateAvailable,` from `versionCaption`.
    @Test func theCaptionShowsTheUpdateOnlyWhenThereIsOne() {
        #expect(CLIToolPresentation.versionCaption(fx()) == "0.4.0 → 0.5.0")
        #expect(CLIToolPresentation.versionCaption(fx(state: .ahead)) == "0.4.0")
    }

    /// The row's warning replaces the versions only when there is no verdict. An
    /// outdated copy that is only held back keeps its versions on the row; why it
    /// is held back is the pane's (and the tooltip's) to say.
    ///
    /// Mutation: drop `status.state == .unknown,` from `rowWarning`.
    @Test func onlyAnUncheckedCopyWarnsOnTheRow() {
        let heldBack = fx(oneClick: false, withheld: .autoUpdateOff)
        #expect(CLIToolPresentation.rowWarning(heldBack) == nil)
        #expect(CLIToolPresentation.explanation(heldBack) == "Auto-update is off in fx’s settings")

        let unchecked = fx(latest: nil, state: .unknown, oneClick: false, withheld: .wrongSigner)
        #expect(CLIToolPresentation.rowWarning(unchecked) == "Not signed by Vercel")
    }

    /// The group header names a channel once however many copies are on it, and
    /// each when they differ.
    ///
    /// Mutation: drop `where !seen.contains(channel)` from `channels(of:)`.
    @Test func theHeaderNamesEachChannelOnce() {
        #expect(CLIToolPresentation.channels(of: [fx(), fx("/opt/homebrew/bin/fx")]) == "stable")
        #expect(CLIToolPresentation.channels(of: [fx(), fx("/opt/homebrew/bin/fx", channel: "canary")])
            == "stable, canary")
        #expect(CLIToolPresentation.channels(of: [fx(channel: nil)]) == nil)
    }
}

// MARK: - uv, Junie, Rust and npm

/// Statuses of the four tools whose rows carry a payload of their own, built
/// through Core's public initializers — the shapes their checks return, with
/// made-up paths under `/Users/ann`. Shared with `CLIToolsModelTests`.
enum CLIToolFixtures {

    static func status(
        _ kind: CLIToolKind, path: String, detail: CLIToolStatus.Detail, name: String? = nil,
        version: String? = "1.0.0", latest: String? = "2.0.0", channel: String? = nil,
        state: CLIToolState = .updateAvailable, oneClick: Bool = false, withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        CLIToolStatus(
            kind: kind, path: path, installedVersion: version, latestVersion: latest, channel: channel,
            state: state,
            oneClick: oneClick ? CLIToolCommand(executable: path, arguments: ["update"], pathPrefix: nil) : nil,
            withheld: withheld, note: nil, name: name, detail: detail)
    }

    static func boat(
        channel: String = "prod", customAPI: String? = nil, quarantined: Bool = false,
        withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.ascii/bin/boat"
        let install = BoatInstall(path: path, version: "1.0.37", quarantined: quarantined,
                                  settings: BoatSettings(channel: channel, customAPI: customAPI))
        return status(.boat, path: path, detail: .boat(install), version: "1.0.37", latest: "1.0.38",
                      channel: channel, withheld: withheld)
    }

    static func uv(
        _ path: String = "/Users/ann/.local/bin/uv", layout: UvInstall.Layout = .standalone,
        signature: CLIToolTrust.Signature? = .adHoc, quarantined: Bool = false,
        hashVerdict: UvInstall.HashVerdict? = nil, oneClick: Bool = false, withheld: CLIToolWithheld? = nil,
        state: CLIToolState = .updateAvailable
    ) -> CLIToolStatus {
        let install = UvInstall(
            path: path, layout: layout, executable: path, version: "0.9.18",
            receiptVersion: layout == .standalone ? "0.9.18" : nil, signature: signature,
            quarantined: quarantined, hashVerdict: hashVerdict)
        return status(.uv, path: path, detail: .uv(install), version: "0.9.18", latest: "0.12.21",
                      state: state, oneClick: oneClick, withheld: withheld)
    }

    static func junie(
        channel: String = "release", shim: JunieInstall.Shim = .managed, pending: String? = nil,
        signature: CLIToolTrust.Signature? = .vendor, oneClick: Bool = false, withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.local/bin/junie"
        let install = JunieInstall(
            path: path, shim: shim, version: "3419.26", bundleVersion: "3419.26", channel: channel,
            signature: signature, pendingUpdate: pending)
        return status(.junie, path: path, detail: .junie(install), version: "3419.26", latest: "3612.1",
                      channel: channel, oneClick: oneClick, withheld: withheld)
    }

    static let rustupPath = "/Users/ann/.cargo/bin/rustup"

    static func rustup(
        version: String? = "1.29.1", trusted: Bool = true, state: CLIToolState = .updateAvailable,
        withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let proof = trusted && version != nil
            ? RustItem.TrustedRustup(path: rustupPath, sha256: String(repeating: "a", count: 64),
                                     version: version!, hostTriple: "aarch64-apple-darwin")
            : nil
        return status(.rust, path: rustupPath,
                      detail: .rust(RustItem(path: rustupPath, version: version, kind: .rustup, trustedRustup: proof)),
                      name: "rustup", version: version, latest: "1.29.2", state: state, withheld: withheld)
    }

    static func toolchain(
        _ name: String = "stable-aarch64-apple-darwin", withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.rustup/toolchains/\(name)"
        let parsed = RustToolchainName.parse(name)!
        return status(.rust, path: path,
                      detail: .rust(RustItem(path: path, version: "1.98.0", kind: .toolchain(parsed))),
                      name: name, version: "1.98.0", latest: "1.99.0", channel: parsed.channel, withheld: withheld)
    }

    static func nvm(_ node: String) -> NodePrefix {
        NodePrefix(path: "/Users/ann/.nvm/versions/node/v\(node)", source: .nvm, layoutNodeVersion: node)
    }

    static func npmInstall(
        _ name: String = "openclaw", prefix: NodePrefix = nvm("24.13.0"), manifestName: String? = nil,
        nodeSignature: CLIToolTrust.Signature? = .vendor, nodeQuarantined: Bool = false,
        linkTarget: String? = nil, ownUpdate: NpmOwnUpdate? = nil
    ) -> NpmInstall {
        let bin = prefix.path + "/bin"
        return NpmInstall(
            path: prefix.path + "/lib/node_modules/" + name, name: name, version: "2026.3.28",
            manifestName: manifestName ?? name, prefix: prefix,
            runtime: NpmRuntime(
                node: bin + "/node", npm: bin + "/npm", npmVersion: "11.6.2", nodeSignature: nodeSignature,
                nodeQuarantined: nodeQuarantined, nodeVersion: prefix.layoutNodeVersion),
            linkTarget: linkTarget, ownUpdate: ownUpdate)
    }

    /// openclaw at 2026.3.28 under node 24.13.0, as measured on 2026-10-02
    /// (`NpmPackage`): 2026.6.35 runs there, 2026.9.7 needs Node ≥ 24.16.0.
    static let gap = NpmPackage.RuntimeGap(
        version: "2026.9.7", node: ">=24.16.0 <25 || >=26.1.0", npm: nil, nodeVersion: "24.13.0",
        minimumNode: "24.16.0")

    static func npm(
        _ install: NpmInstall = npmInstall(), offered: String? = "2026.6.35", gap: NpmPackage.RuntimeGap? = gap,
        updater: NpmPackage.Updater? = nil, oneClick: Bool = false, withheld: CLIToolWithheld? = nil,
        state: CLIToolState = .updateAvailable
    ) -> CLIToolStatus {
        let package = NpmPackage(
            install: install, tag: "latest", newest: "2026.9.7", offered: offered, gap: gap,
            pending: ["2026.6.35"], updater: updater)
        return status(.npm, path: install.path, detail: .npm(package), name: install.name, version: "2026.3.28",
                      latest: offered ?? "2026.9.7", channel: "latest", state: state, oneClick: oneClick,
                      withheld: withheld)
    }
}

/// The payload-aware wording of the CLI tab: names, facts, cautions and group
/// headers of uv, Junie, Rust and npm.
///
/// Each case names the one-line mutation of `CLIToolPresentation` it fails under.
struct CLIToolPayloadPresentationTests {

    private static let home = "/Users/ann"
    private typealias F = CLIToolFixtures

    /// A row of a group that holds several kinds of thing is titled by its own
    /// name; uv, with none, keeps its path.
    ///
    /// Mutation: drop `guard let name = status.name` from `title(of:home:among:)`.
    @Test func aNamedInstallIsTitledByItsName() {
        #expect(CLIToolPresentation.title(of: F.rustup(), home: Self.home) == "rustup")
        #expect(CLIToolPresentation.title(of: F.toolchain(), home: Self.home) == "stable-aarch64-apple-darwin")
        #expect(CLIToolPresentation.title(of: F.npm(), home: Self.home) == "openclaw")
        #expect(CLIToolPresentation.title(of: F.uv(), home: Self.home) == "~/.local/bin/uv")
    }

    /// One package under two node prefixes: each row says which node — its major
    /// when that is enough, else the whole version — or, when both run the same
    /// one, which prefix.
    ///
    /// Mutations: drop the `!twins.isEmpty` guard (every npm row grows a node);
    /// drop the major-version `if` (24.13.0 and 24.12.0 both read "node 24");
    /// drop the whole-version `if` (two rows on one node read alike).
    @Test func twinPackagesSayWhichNodeTellsThemApart() {
        let on24 = F.npm(F.npmInstall(prefix: F.nvm("24.13.0")))
        let on22 = F.npm(F.npmInstall(prefix: F.nvm("22.21.1")))
        let all = [on24, on22, F.npm(F.npmInstall("agent-browser"))]
        #expect(CLIToolPresentation.title(of: on24, home: Self.home, among: all) == "openclaw · node 24")
        #expect(CLIToolPresentation.title(of: on22, home: Self.home, among: all) == "openclaw · node 22")
        #expect(CLIToolPresentation.title(of: all[2], home: Self.home, among: all) == "agent-browser")

        let on2412 = F.npm(F.npmInstall(prefix: F.nvm("24.12.0")))
        #expect(CLIToolPresentation.title(of: on24, home: Self.home, among: [on24, on2412])
            == "openclaw · node 24.13.0")

        let brew = F.npm(F.npmInstall(prefix: NodePrefix(path: "/opt/homebrew", source: .system,
                                                          layoutNodeVersion: "24.13.0")))
        #expect(CLIToolPresentation.title(of: brew, home: Self.home, among: [on24, brew])
            == "openclaw · /opt/homebrew")
    }

    /// uv's signature says who signed it — "OpenAI OpCo, LLC" for Astral — and,
    /// for an unsigned copy, what the hash check found or when it will run.
    ///
    /// Mutation: drop the `case nil where uv.layout == .standalone` arm (an
    /// unsigned copy reads as if nothing would ever vouch for it).
    @Test func uvsSignatureFactSaysWhoSignedItAndWhatTheHashFound() {
        func signature(_ status: CLIToolStatus) -> String? {
            CLIToolPresentation.facts(of: status, home: Self.home).first { $0.label == "Signature" }?.value
        }
        #expect(signature(F.uv(signature: .vendor))
            == "Signed by OpenAI OpCo, LLC (Team 2DC432GLL2), which signs Astral’s releases")
        #expect(signature(F.uv())
            == "Ad hoc signed (no developer identity) · checked against Astral’s published build at the first update")
        #expect(signature(F.uv(hashVerdict: .matches))
            == "Ad hoc signed (no developer identity) · byte for byte Astral’s published build")
        #expect(signature(F.uv(layout: .link)) == "Ad hoc signed (no developer identity)")
        let facts = CLIToolPresentation.facts(of: F.uv(), home: Self.home)
        #expect(facts.first == .init(label: "Installed by", value: "uv’s standalone installer"))
        #expect(facts.contains(.init(label: "Receipt", value: "0.9.18")))
    }

    /// Junie's staged update is a fact of its own — unless the Update line is
    /// already saying it.
    ///
    /// Mutation: drop `withheld != .staged` from Junie's facts.
    @Test func junieSaysItsStagedUpdateOnce() {
        func labels(_ status: CLIToolStatus) -> [String] {
            CLIToolPresentation.facts(of: status, home: Self.home).map(\.label)
        }
        #expect(labels(F.junie()) == ["Launcher", "Signature"])
        #expect(labels(F.junie(pending: "3612.1", withheld: .busy)) == ["Launcher", "Signature", "Downloaded"])
        #expect(labels(F.junie(pending: "3612.1", withheld: .staged)) == ["Launcher", "Signature"])
        #expect(CLIToolPresentation.facts(of: F.junie(shim: .legacy), home: Self.home).first?.value
            == "First-generation launcher")
    }

    /// rustup is trusted by its published hash, never a signature: its fact says
    /// which build matched, a quarantined match, or that none did.
    ///
    /// Mutation: drop the `else if let version = item.version` arm (a
    /// quarantined rustup would read as matching nothing).
    @Test func rustupsFactIsItsPublishedHash() {
        func fact(_ status: CLIToolStatus) -> String? {
            CLIToolPresentation.facts(of: status, home: Self.home).first?.value
        }
        #expect(fact(F.rustup()) == "Its sha256 matches the published rustup 1.29.1 for aarch64-apple-darwin")
        #expect(fact(F.rustup(trusted: false, state: .unknown, withheld: .unverified))
            == "Its sha256 matches the published rustup 1.29.1")
        #expect(fact(F.rustup(version: nil, trusted: false, state: .unknown, withheld: .unverified))
            == "Its sha256 matches no published rustup build")
        #expect(CLIToolPresentation.facts(of: F.toolchain(), home: Self.home).isEmpty)
    }

    /// An npm row's facts: the prefix, its node, and the newer release this node
    /// cannot run — beside an offered update, not again when it is the reason.
    ///
    /// Mutation: drop `withheld != .runtimeTooOld` from npm's facts.
    @Test func npmSaysTheNewerReleaseItsNodeCannotRunOnce() {
        let offered = CLIToolPresentation.facts(of: F.npm(oneClick: true), home: Self.home)
        #expect(offered == [
            .init(label: "Prefix", value: "~/.nvm/versions/node/v24.13.0"),
            .init(label: "Node", value: "24.13.0 · Signed by Node.js Foundation (Team HX7739G8FX)"),
            .init(label: "Newer release", value: "2026.9.7 needs Node ≥ 24.16.0"),
        ])
        let held = CLIToolPresentation.facts(of: F.npm(offered: nil, withheld: .runtimeTooOld), home: Self.home)
        #expect(!held.map(\.label).contains("Newer release"))
        let linked = CLIToolPresentation.facts(
            of: F.npm(F.npmInstall(linkTarget: "/Users/ann/src/openclaw"), withheld: .unsupportedInstaller),
            home: Self.home)
        #expect(linked.contains(.init(label: "Linked to", value: "~/src/openclaw")))
    }

    /// The caution beside an offered update says only what the click really
    /// does besides updating (read in `JunieUpdater`, `NpmCheck.updateCommand`,
    /// `UvVerifier`), and nothing beside a click that is not offered.
    ///
    /// Mutations: drop `uv.hashVerdict == nil` (a verified copy would announce a
    /// download it no longer makes); drop `where package.updater == .openclaw`
    /// (every npm update would claim to restart a gateway).
    @Test func eachCautionSaysWhatTheClickReallyDoes() {
        #expect(CLIToolPresentation.caution(F.junie(oneClick: true))?.contains("330 MB") == true)
        #expect(CLIToolPresentation.caution(F.junie()) == nil)

        #expect(CLIToolPresentation.caution(F.npm(updater: .openclaw, oneClick: true))
            == "openclaw update also runs openclaw doctor, restarts openclaw’s gateway if it’s running, and syncs its plugins.")
        #expect(CLIToolPresentation.caution(F.npm(updater: .npm, oneClick: true)) == nil)

        #expect(CLIToolPresentation.caution(F.uv(oneClick: true))
            == "Before this first update, DuoUpdater downloads Astral’s archive of uv 0.9.18 (about 19 MB) to confirm the installed files are Astral’s.")
        #expect(CLIToolPresentation.caution(F.uv(hashVerdict: .matches, oneClick: true)) == nil)
        #expect(CLIToolPresentation.caution(F.uv(signature: .vendor, oneClick: true)) == nil)
    }

    /// The group headers: Junie's channel and its auto-update when off; the Rust
    /// toolchains' channels and rustup's self-update when not `enable`; the nodes
    /// npm's prefixes run; nothing for uv.
    ///
    /// Mutations: drop `!settings.selfUpdateEnabled` (an `enable` written out
    /// would still print one); drop `!nodes.contains(node)` (one node named twice);
    /// drop the Junie `!settings.autoUpdate` branch (its switch goes unsaid).
    @Test func eachGroupHeaderSaysWhatDecidesItsVerdicts() {
        let junie = [F.junie()]
        #expect(CLIToolPresentation.headerSummary(.junie, statuses: junie, context: .junie(JunieSettings()))
            == "release")
        #expect(CLIToolPresentation.headerSummary(.junie, statuses: junie,
                                                  context: .junie(JunieSettings(autoUpdate: false)))
            == "release · auto-update off")

        let rust = [F.rustup(), F.toolchain(), F.toolchain("nightly-aarch64-apple-darwin")]
        #expect(CLIToolPresentation.headerSummary(
            .rust, statuses: rust, context: .rust(RustupSettings(autoSelfUpdate: "enable")))
            == "stable, nightly")
        #expect(CLIToolPresentation.headerSummary(
            .rust, statuses: rust, context: .rust(RustupSettings(autoSelfUpdate: "disable")))
            == "stable, nightly · rustup self-update off")
        #expect(CLIToolPresentation.headerSummary(
            .rust, statuses: [F.rustup()], context: .rust(RustupSettings(autoSelfUpdate: "check-only")))
            == "rustup self-update: check only")

        let npm = [F.npm(), F.npm(F.npmInstall("agent-browser")), F.npm(F.npmInstall(prefix: F.nvm("22.21.1")))]
        #expect(CLIToolPresentation.headerSummary(.npm, statuses: npm, context: .npm) == "node 24.13.0, 22.21.1")
        #expect(CLIToolPresentation.headerSummary(.uv, statuses: [F.uv()], context: .uv) == nil)
        #expect(CLIToolPresentation.headerSummary(.boat, statuses: [F.boat()], context: .boat) == "prod")
        #expect(CLIToolPresentation.headerSummary(.boat, statuses: [F.boat(channel: "staging")], context: .boat)
            == "staging")
    }

    /// Boat's reasons: a quarantined file, a config pointing at another server,
    /// and a file that is not the published build — Boat has no Team ID, so no
    /// vendor is named.
    ///
    /// Mutations: drop the `(.unverified, .boat) where quarantined` case; drop the
    /// `(.unsupportedInstaller, .boat)` case; return a vendor for `.boat`.
    @Test func boatsReasons() {
        #expect(CLIToolsModel.reason(.unverified, of: F.boat(quarantined: true)) == "Quarantined, so not run")
        #expect(CLIToolsModel.reason(.unverified, of: F.boat()) == "Not the build its developer published")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.boat(customAPI: "https://staging.ascii.dev"))
            == "Boat’s config points at another server")
        #expect(CLIToolsModel.vendor(of: .boat) == nil)
        #expect(CLIToolPresentation.facts(of: F.boat(), home: "/Users/ann").isEmpty)
    }

    /// The pane's reason and the row's warning are the status's own: a newer
    /// release's Node, not just "needs a newer Node".
    ///
    /// Mutation: call `reason(_:of: status.kind)` from `explanation`.
    @Test func theExplanationReadsThePayload() {
        #expect(CLIToolPresentation.explanation(F.npm(offered: nil, withheld: .runtimeTooOld))
            == "openclaw 2026.9.7 needs Node ≥ 24.16.0")
        #expect(CLIToolPresentation.rowWarning(
            F.rustup(version: nil, trusted: false, state: .unknown, withheld: .unverified))
            == "Not a published rustup build")
    }
}
