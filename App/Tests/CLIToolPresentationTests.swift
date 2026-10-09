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

    static func herdr(
        channel: String = "stable", quarantined: Bool = false, withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.local/bin/herdr"
        let install = HerdrInstall(path: path, quarantined: quarantined, settings: HerdrSettings(channel: channel))
        return status(.herdr, path: path, detail: .herdr(install), version: "0.9.2", latest: "0.9.3",
                      channel: channel, withheld: withheld)
    }

    static func luvus(
        version: String = "0.14.2", quarantined: Bool = false, writable: Bool = true,
        problem: LuvusInstall.Problem? = nil, withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.local/bin/luvus"
        let install = LuvusInstall(path: path, binary: path, version: version, quarantined: quarantined,
                                   writable: writable, problem: problem)
        return status(.luvus, path: path, detail: .luvus(install), version: version, latest: "0.14.3",
                      withheld: withheld)
    }

    static func lorca(
        version: String = "0.1.11", quarantined: Bool = false, writable: Bool = true,
        withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.local/bin/lorca"
        let install = LorcaInstall(path: path, binary: path, version: version, quarantined: quarantined,
                                   writable: writable)
        return status(.lorca, path: path, detail: .lorca(install), version: version, latest: "0.1.12",
                      withheld: withheld)
    }

    /// A status with the copy-command its check would set (`manual`).
    static func zoxide(
        linked: Bool = false, writable: Bool = true, withheld: CLIToolWithheld? = nil, manual: Bool = false
    ) -> CLIToolStatus {
        let path = "/Users/ann/.local/bin/zoxide"
        let install = ZoxideInstall(path: path, binary: path, version: "0.9.9", linked: linked, writable: writable)
        let command = CLIToolCommand(
            executable: "curl",
            arguments: ["-sSfL", "https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh", "|", "sh",
                        "-s", "--", "--bin-dir", "/Users/ann/.local/bin"],
            pathPrefix: nil)
        return CLIToolStatus(
            kind: .zoxide, path: path, installedVersion: "0.9.9", latestVersion: "0.10.0", channel: nil,
            state: .updateAvailable, oneClick: nil, withheld: withheld, note: nil,
            manualCommand: manual ? command : nil, detail: .zoxide(install))
    }

    static func nvm(state: CLIToolState = .updateAvailable, withheld: CLIToolWithheld? = .unsupportedInstaller) -> CLIToolStatus {
        let path = "/Users/ann/.nvm/nvm.sh"
        let command = CLIToolCommand(
            executable: "curl",
            arguments: ["-o-", "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh", "|", "bash"],
            pathPrefix: nil)
        return CLIToolStatus(
            kind: .nvm, path: path, installedVersion: "0.40.7", latestVersion: "0.40.8", channel: nil,
            state: state, oneClick: nil, withheld: withheld, note: nil, manualCommand: command,
            detail: .nvm(NvmInstall(path: path, version: "0.40.7")))
    }

    static func atuin(
        quarantined: Bool = false, writable: Bool = true, problem: AtuinInstall.Problem? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.atuin/bin/atuin"
        let install = AtuinInstall(path: path, binary: path, version: "18.22.0", installDirectory: "/Users/ann/.atuin/bin",
                                   quarantined: quarantined, writable: writable, problem: problem)
        return status(.atuin, path: path, detail: .atuin(install), version: "18.22.0", latest: "18.23.0")
    }

    static func ghcup(
        quarantined: Bool = false, writable: Bool = true, problem: GhcupInstall.Problem? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.ghcup/bin/ghcup"
        let install = GhcupInstall(path: path, version: "0.2.6.1", quarantined: quarantined, writable: writable,
                                   problem: problem)
        return status(.ghcup, path: path, detail: .ghcup(install), version: "0.2.6.1", latest: "0.2.6.2")
    }

    static func flyctl(quarantined: Bool = false, withheld: CLIToolWithheld? = nil) -> CLIToolStatus {
        let path = "/Users/ann/.fly/bin/flyctl"
        let install = FlyctlInstall(path: path, binary: path, version: "0.4.114", quarantined: quarantined)
        return status(.flyctl, path: path, detail: .flyctl(install), version: "0.4.114", latest: "0.4.115",
                      withheld: withheld)
    }

    static func helm(quarantined: Bool = false, writable: Bool = true, problem: HelmInstall.Problem? = nil) -> CLIToolStatus {
        let path = "/usr/local/bin/helm"
        let install = HelmInstall(path: path, binary: path, version: "3.21.4", quarantined: quarantined,
                                  writable: writable, problem: problem)
        return status(.helm, path: path, detail: .helm(install), version: "3.21.4", latest: "3.22.0")
    }

    static func starship(quarantined: Bool = false, writable: Bool = true) -> CLIToolStatus {
        let path = "/usr/local/bin/starship"
        let install = StarshipInstall(path: path, binary: path, version: "1.25.1", quarantined: quarantined,
                                      writable: writable)
        return status(.starship, path: path, detail: .starship(install), version: "1.25.1", latest: "1.26.0")
    }

    static func codex(
        signature: CLIToolTrust.Signature? = .vendor, quarantined: Bool = false,
        problem: CodexInstall.Problem? = nil, withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.local/bin/codex"
        let install = CodexInstall(path: path, version: "0.143.0", signature: signature, quarantined: quarantined,
                                   problem: problem)
        return status(.codex, path: path, detail: .codex(install), version: "0.143.0", latest: "0.160.0",
                      channel: "latest", withheld: withheld)
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

    static func bun(
        version: String = "1.3.10", signature: CLIToolTrust.Signature? = .vendor, quarantined: Bool = false,
        withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let path = "/Users/ann/.bun/bin/bun"
        return status(.bun, path: path,
                      detail: .bun(BunInstall(path: path, version: version, signature: signature, quarantined: quarantined)),
                      name: "bun", version: version, latest: "1.4.2", withheld: withheld)
    }

    /// openclaw from `bun add -g`, held against Homebrew's node 26.8.2.
    static func bunPackage(
        bunSignature: CLIToolTrust.Signature? = .vendor, bunQuarantined: Bool = false, node: Bool = true,
        withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        let prefix = NodePrefix(path: "/Users/ann/.bun/install/global", source: .bun, layoutNodeVersion: node ? "26.8.2" : nil)
        let install = NpmInstall(
            path: prefix.path + "/node_modules/openclaw", name: "openclaw", version: "2026.3.24", manifestName: "openclaw",
            prefix: prefix,
            runtime: NpmRuntime(
                node: node ? "/opt/homebrew/bin/node" : nil, npm: nil, npmVersion: nil, nodeSignature: node ? .adHoc : nil,
                nodeQuarantined: false, nodeVersion: node ? "26.8.2" : nil, homebrewKeg: node ? "/opt/homebrew/Cellar/node/26.8.2" : nil),
            bun: BunManager(path: "/Users/ann/.bun/bin/bun", signature: bunSignature, quarantined: bunQuarantined))
        return status(.bun, path: install.path, detail: .npm(NpmPackage(install: install, offered: "2026.9.8")),
                      name: "openclaw", version: "2026.3.24", latest: "2026.9.8", withheld: withheld)
    }

    static func cursorAgent(channel: String = "prod", withheld: CLIToolWithheld? = nil) -> CLIToolStatus {
        let path = "/Users/ann/.local/bin/agent"
        return status(.cursorAgent, path: path, detail: .cursorAgent(CursorAgentInstall(path: path, version: "2026.05.16-0338208")),
                      version: "2026.05.16-0338208", latest: "2026.10.01-e373342", channel: channel, withheld: withheld)
    }

    static func amp(signature: CLIToolTrust.Signature? = .vendor) -> CLIToolStatus {
        let path = "/Users/ann/.amp/bin/amp"
        return status(.amp, path: path, detail: .amp(AmpInstall(path: path, version: "0.0.1791091069-gb9917f", signature: signature)),
                      version: "0.0.1791091069-gb9917f", latest: "0.0.1791121193-ge297b9")
    }

    static func opencode(signature: CLIToolTrust.Signature? = .adHoc) -> CLIToolStatus {
        let path = "/Users/ann/.opencode/bin/opencode"
        return status(.opencode, path: path, detail: .opencode(OpencodeInstall(path: path, version: "1.18.15", signature: signature)),
                      version: "1.18.15", latest: "1.18.34", channel: "latest")
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

    /// The CLI tab's order: a group with an update before one without, the
    /// outdated copies first within a group, and tool order otherwise — npm's
    /// prefixes being groups of their own.
    ///
    /// Mutations: return `all.flatMap(\.statuses)` (no group order); drop
    /// `outdatedFirst` within a group.
    @Test func updatesComeFirst() {
        let fnm = NodePrefix(path: "/Users/ann/.local/share/fnm/node-versions/v24.12.0/installation",
                             source: .fnm, layoutNodeVersion: "24.12.0")
        let fxRow = CLIToolStatus(
            kind: .fx, path: "/Users/ann/.fx/bin/fx", installedVersion: "0.5.0", latestVersion: "0.5.0",
            channel: "stable", state: .upToDate, oneClick: nil, withheld: nil, note: nil,
            detail: .fx(FxInstall(path: "/Users/ann/.fx/bin/fx", version: "0.5.0")))
        let uv = F.uv(state: .updateAvailable)
        let agently = F.npm(F.npmInstall("agently-cli", prefix: F.nvm("24.13.0")), state: .upToDate)
        let browser = F.npm(F.npmInstall("agent-browser", prefix: F.nvm("24.13.0")), state: .updateAvailable)
        let pnpm = F.npm(F.npmInstall("pnpm", prefix: fnm), state: .upToDate)

        let ordered = CLIToolPresentation.updatesFirst([fxRow, uv, agently, browser, pnpm])

        #expect(ordered.map(\.path) == [uv, browser, agently, fxRow, pnpm].map(\.path))
        // Drawn as groups, the order holds: an npm prefix stays one group.
        #expect(CLIToolPresentation.groups(ordered).map(\.statuses.count) == [1, 2, 1, 1])
    }

    /// While updates run the tab keeps the order they started with, whatever the
    /// statuses say since; anything new goes after, in its own order.
    ///
    /// Mutation: `guard let held else { return items }` → `return items`.
    @Test func aHeldOrderOutlivesTheVerdicts() {
        let now = ["b", "d", "a", "c"]
        #expect(CLIToolPresentation.holding(now, to: ["a", "b", "c"], id: { $0 }) == ["a", "b", "c", "d"])
        #expect(CLIToolPresentation.holding(now, to: nil, id: { $0 }) == now)
        #expect(CLIToolPresentation.outdatedFirst([(1, false), (2, true), (3, false), (4, true)], \.1).map(\.0)
                == [2, 4, 1, 3])
    }

    /// npm is one group per node prefix — its own npm, `node_modules` and node —
    /// in the order its first package came; every other tool is one group. The
    /// header names the prefix by its version manager, else by its path.
    ///
    /// Mutations: key npm's groups by kind alone (both prefixes in one group);
    /// drop the `status.kind == .npm` test (a package bun installed splits from
    /// bun's own row); label every prefix by its path.
    @Test func npmIsOneGroupPerPrefix() throws {
        let fnm = NodePrefix(path: "/Users/ann/.local/share/fnm/node-versions/v24.12.0/installation",
                             source: .fnm, layoutNodeVersion: "24.12.0")
        let agently = F.npm(F.npmInstall("agently-cli", prefix: F.nvm("24.13.0")))
        let pnpm = F.npm(F.npmInstall("pnpm", prefix: fnm))
        let browser = F.npm(F.npmInstall("agent-browser", prefix: F.nvm("24.13.0")))
        let bunRow = CLIToolStatus(
            kind: .bun, path: "/Users/ann/.bun/bin/bun", installedVersion: "1.3.14", latestVersion: "1.3.14",
            channel: nil, state: .upToDate, oneClick: nil, withheld: nil, note: nil,
            detail: .bun(BunInstall(path: "/Users/ann/.bun/bin/bun", version: "1.3.14")))
        let bunPackage = CLIToolStatus(
            kind: .bun, path: "/Users/ann/.bun/install/global/node_modules/x", installedVersion: "1.0",
            latestVersion: "1.0", channel: nil, state: .upToDate, oneClick: nil, withheld: nil, note: nil,
            name: "x", detail: .npm(NpmPackage(install: F.npmInstall("x", prefix: F.nvm("26.8.2")))))

        let groups = CLIToolPresentation.groups([F.uv(), agently, pnpm, browser, bunRow, bunPackage])
        try #require(groups.count == 4)
        #expect(groups.map(\.kind) == [.uv, .npm, .npm, .bun])
        #expect(groups.map { $0.prefix?.path } == [nil, F.nvm("24.13.0").path, fnm.path, nil])
        #expect(groups[1].statuses.map(\.name) == ["agently-cli", "agent-browser"])
        #expect(groups[2].statuses.map(\.name) == ["pnpm"])
        #expect(groups[3].statuses.count == 2)

        #expect(CLIToolPresentation.prefixLabel(F.nvm("24.13.0"), home: Self.home) == "nvm")
        #expect(CLIToolPresentation.prefixLabel(fnm, home: Self.home) == "fnm")
        #expect(CLIToolPresentation.prefixLabel(
            NodePrefix(path: "/opt/homebrew", source: .system, layoutNodeVersion: "26.10.0"), home: Self.home)
            == "/opt/homebrew")
        #expect(CLIToolPresentation.prefixLabel(
            NodePrefix(path: "/Users/ann/.npm-global", source: .npmGlobal, layoutNodeVersion: nil), home: Self.home)
            == "~/.npm-global")
    }

    /// A broken Codex says what is missing; another tool keeps the shared line.
    ///
    /// Mutations: drop either Codex case (it reads "An install is broken").
    @Test func brokenCodexSaysWhatIsMissing() {
        func reason(_ status: CLIToolStatus) -> String { CLIToolsModel.reason(.broken, of: status) }
        #expect(reason(F.codex(problem: .noCurrent, withheld: .broken))
            == "Its standalone install has no current release")
        #expect(reason(F.codex(problem: .binaryMissing, withheld: .broken))
            == "Codex 0.143.0 is missing its program file")
        #expect(reason(F.uv(withheld: .broken)) == "An install is broken")
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
        #expect(CLIToolPresentation.headerSummary(.codex, statuses: [F.codex()], context: .codex(CodexSettings()))
            == "latest")
        #expect(CLIToolPresentation.headerSummary(
            .codex, statuses: [F.codex()], context: .codex(CodexSettings(checkForUpdates: false)))
            == "latest · update check off")
    }

    /// Cursor CLI: Anysphere by name, its channel in the header, the `static`
    /// channel as its own setting. Mutations: return no vendor; leave
    /// `.cursorAgent` out of the header.
    @Test func cursorAgentsReasonsAndHeader() {
        #expect(CLIToolsModel.vendor(of: .cursorAgent) == "Anysphere")
        #expect(CLIToolsModel.reason(.updatesDisabled, of: F.cursorAgent(channel: "static"))
            == "Updates are turned off in Cursor CLI’s settings")
        #expect(CLIToolPresentation.headerSummary(.cursorAgent, statuses: [F.cursorAgent()], context: .cursorAgent(CursorAgentSettings()))
            == "prod")
        #expect(CLIToolPresentation.facts(of: F.cursorAgent(), home: "/Users/ann").isEmpty)
    }

    /// Amp: Amp Frontier by name, its signature as a fact, no header. Mutations:
    /// return no vendor; drop the fact.
    @Test func ampsReasonsAndFacts() {
        #expect(CLIToolsModel.vendor(of: .amp) == "Amp Frontier")
        #expect(CLIToolsModel.reason(.wrongSigner, of: F.amp(signature: .adHoc)) == "Not signed by Amp Frontier")
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.amp()) == "Auto-update is off in Amp’s settings")
        #expect(CLIToolPresentation.facts(of: F.amp(), home: "/Users/ann")
            == [.init(label: "Signature", value: "Signed by Amp Frontier Corporation (Team PZT9BJUAA5)")])
        #expect(CLIToolPresentation.headerSummary(.amp, statuses: [F.amp()], context: .amp(AmpSettings())) == nil)
    }

    /// OpenCode: Anomaly by name, its signature as a fact, its `autoupdate` in
    /// the header. Mutations: return no vendor; drop the fact; leave `.opencode`
    /// out of the header.
    @Test func opencodesReasonsFactsAndHeader() {
        #expect(CLIToolsModel.vendor(of: .opencode) == "Anomaly")
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.opencode()) == "Auto-update is off in OpenCode’s settings")
        #expect(CLIToolPresentation.facts(of: F.opencode(), home: "/Users/ann")
            == [.init(label: "Signature", value: "Ad hoc signed (no developer identity)")])
        #expect(CLIToolPresentation.facts(of: F.opencode(signature: .vendor), home: "/Users/ann")
            == [.init(label: "Signature", value: "Signed by Anomaly Innovations, Inc. (Team 5NZ4Q7NXJ4)")])
        #expect(CLIToolPresentation.headerSummary(.opencode, statuses: [F.opencode()], context: .opencode(OpencodeSettings()))
            == "latest")
        #expect(CLIToolPresentation.headerSummary(
            .opencode, statuses: [F.opencode()], context: .opencode(OpencodeSettings(autoUpdate: false)))
            == "latest · auto-update off")
    }

    /// Bun's reasons, facts and header: Oven by name; a package's reasons are
    /// about its bun and the node found, never "npm" or "this prefix".
    ///
    /// Mutations: drop any of the `.npm` cases keyed on `install.bun`; drop the
    /// `(.unsupportedInstaller, .bun)` case; return no vendor for `.bun`; leave
    /// `.bun` out of the node header.
    @Test func bunsReasonsFactsAndHeader() {
        #expect(CLIToolsModel.vendor(of: .bun) == "Oven")
        #expect(CLIToolsModel.reason(.wrongSigner, of: F.bun(signature: .adHoc)) == "Not signed by Oven")
        #expect(CLIToolsModel.reason(.unverified, of: F.bun(quarantined: true)) == "Quarantined, so not run")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.bun(version: "1.4.3-canary.20"))
            == "A canary build, which has no version to compare")
        #expect(CLIToolPresentation.facts(of: F.bun(), home: "/Users/ann")
            == [.init(label: "Signature", value: "Signed by Oven (Team 7FRXF46ZSN)")])

        #expect(CLIToolsModel.reason(.wrongSigner, of: F.bunPackage(bunSignature: .adHoc)) == "Its bun isn’t signed by Oven")
        #expect(CLIToolsModel.reason(.unverified, of: F.bunPackage(bunQuarantined: true)) == "Its bun is quarantined, so not run")
        #expect(CLIToolsModel.reason(.versionUnreadable, of: F.bunPackage(node: false))
            == "No node found to check its engines against")
        #expect(CLIToolsModel.reason(.busy, of: F.bunPackage()) == "bun is already changing its global packages")
        #expect(CLIToolPresentation.facts(of: F.bunPackage(), home: "/Users/ann").first
            == .init(label: "Prefix", value: "~/.bun/install/global"))

        #expect(CLIToolPresentation.headerSummary(.bun, statuses: [F.bun(), F.bunPackage()], context: .bun)
            == "node 26.8.2")
        #expect(CLIToolPresentation.headerSummary(.bun, statuses: [F.bun()], context: .bun) == nil)
    }

    /// Codex's reasons and facts: OpenAI by name, a launcher that is not the
    /// install's, the update check turned off, a quarantined binary.
    ///
    /// Mutations: drop the `(.unsupportedInstaller, .codex)` case; drop the
    /// `(.autoUpdateOff, .codex)` case; return no vendor for `.codex`; drop the
    /// signature fact.
    @Test func codexsReasonsAndFacts() {
        #expect(CLIToolsModel.vendor(of: .codex) == "OpenAI")
        #expect(CLIToolsModel.reason(.wrongSigner, of: F.codex(signature: .adHoc)) == "Not signed by OpenAI")
        #expect(CLIToolsModel.reason(.unverified, of: F.codex(quarantined: true)) == "Quarantined, so not run")
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.codex()) == "Codex’s update check is off in its config")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.codex(problem: .launcherElsewhere))
            == "~/.local/bin/codex isn’t this install’s launcher")
        #expect(CLIToolPresentation.facts(of: F.codex(), home: "/Users/ann")
            == [.init(label: "Signature", value: "Signed by OpenAI OpCo, LLC (Team 2DC432GLL2)")])
        #expect(CLIToolPresentation.facts(of: F.codex(problem: .binaryMissing), home: "/Users/ann").isEmpty)
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

    /// Herdr's reasons: a quarantined file, a file that is not a published build
    /// (herdr has no Team ID, so no vendor is named), and its config's
    /// `version_check = false` worded as the update check it is. The header
    /// names the channel.
    ///
    /// Mutations: drop the `(.unverified, .herdr) where quarantined` case; drop
    /// the `(.autoUpdateOff, .herdr)` case; return a vendor for `.herdr`.
    @Test func herdrsReasons() {
        #expect(CLIToolsModel.reason(.unverified, of: F.herdr(quarantined: true)) == "Quarantined, so not run")
        #expect(CLIToolsModel.reason(.unverified, of: F.herdr()) == "Not the build its developer published")
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.herdr()) == "Herdr’s update check is off in its config")
        #expect(CLIToolsModel.vendor(of: .herdr) == nil)
        #expect(CLIToolPresentation.facts(of: F.herdr(), home: "/Users/ann").isEmpty)
        #expect(CLIToolPresentation.headerSummary(.herdr, statuses: [F.herdr(channel: "preview")], context: .herdr)
            == "preview")
    }

    /// GitHub's rate limit is said as the popover's banner says it, not as an
    /// unreachable channel, on the row and in the pane; the banner counts it.
    ///
    /// Mutation: drop the `.rateLimited` case of `reason(_:of:)` (back to the
    /// channel wording).
    @Test func aRateLimitedChannelSaysSo() {
        let limited = F.bun(withheld: .rateLimited)
        let unchecked = F.status(.bun, path: limited.path, detail: limited.detail, latest: nil, state: .unknown,
                                 withheld: .rateLimited)
        #expect(CLIToolPresentation.rowWarning(unchecked) == "Hitting GitHub’s rate limit")
        #expect(CLIToolPresentation.explanation(unchecked) == "Hitting GitHub’s rate limit")
        #expect(unchecked.isRateLimitError)
        #expect(CLIToolsModel.reason(.channelUnreadable, of: F.bun()) == "Couldn’t reach Bun’s release channel")
        #expect(!F.bun(withheld: .channelUnreadable).isRateLimitError)
    }

    /// Luvus's reasons, in its check's order: a link `luvus update` won't
    /// replace, a release from before the command, a folder only `sudo` could
    /// write to; a quarantined file; and, with no Team ID, no vendor named.
    ///
    /// Mutations: drop any branch of the `(.unsupportedInstaller, .luvus)` case;
    /// drop the `(.unverified, .luvus) where quarantined` case; return a vendor
    /// for `.luvus`.
    @Test func luvusReasons() {
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.luvus(problem: .unknownLocation))
            == "A link luvus update won’t replace")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.luvus(version: "0.11.0"))
            == "This version has no luvus update")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.luvus(writable: false))
            == "Updating it needs administrator rights")
        #expect(CLIToolsModel.reason(.unverified, of: F.luvus(quarantined: true)) == "Quarantined, so not run")
        #expect(CLIToolsModel.reason(.unverified, of: F.luvus()) == "Not the build its developer published")
        #expect(CLIToolsModel.vendor(of: .luvus) == nil)
        #expect(CLIToolPresentation.facts(of: F.luvus(), home: "/Users/ann").isEmpty)
    }

    /// Lorca's reasons, in its check's order: a release from before `lorca
    /// update`, a folder it cannot write to; a quarantined file; its own
    /// auto-update turned off; and, with no Team ID, no vendor named.
    ///
    /// Mutations: drop either branch of the `(.unsupportedInstaller, .lorca)`
    /// case; drop the `(.unverified, .lorca) where quarantined` case; return a
    /// vendor for `.lorca`.
    @Test func lorcaReasons() {
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.lorca(version: "0.1.10"))
            == "This version has no lorca update")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.lorca(writable: false))
            == "Updating it needs administrator rights")
        #expect(CLIToolsModel.reason(.unverified, of: F.lorca(quarantined: true)) == "Quarantined, so not run")
        #expect(CLIToolsModel.reason(.unverified, of: F.lorca()) == "Not the build its developer published")
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.lorca()) == "Auto-update is off in Lorca’s settings")
        #expect(CLIToolsModel.vendor(of: .lorca) == nil)
        #expect(CLIToolPresentation.facts(of: F.lorca(), home: "/Users/ann").isEmpty)
    }

    /// zoxide's and nvm's copy-commands are handed out beside the gates where
    /// DuoUpdater will not run the update itself, and their reasons say why:
    /// a folder that needs sudo, a release without a digest to check against.
    /// Never beside a running update, nor once up to date.
    ///
    /// Mutations: drop `.unsupportedInstaller` or `.unverified` from the gate in
    /// `manualCommand`; let it hand out a command beside `.busy`; drop the `writable` branch of the
    /// `(.unsupportedInstaller, .zoxide)` case or the `(.unverified, .zoxide)` case.
    @Test func zoxideAndNvmHandOutTheirCommand() {
        let zoxide = "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh -s -- --bin-dir /Users/ann/.local/bin"
        #expect(CLIToolPresentation.manualCommand(F.zoxide(writable: false, withheld: .unsupportedInstaller, manual: true)) == zoxide)
        #expect(CLIToolPresentation.manualCommand(F.zoxide(withheld: .unverified, manual: true)) == zoxide)
        #expect(CLIToolPresentation.manualCommand(F.zoxide(withheld: .busy, manual: true)) == nil)
        #expect(CLIToolPresentation.manualCommand(F.nvm())
            == "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash")
        #expect(CLIToolPresentation.manualCommand(F.nvm(state: .upToDate, withheld: nil)) == nil)

        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.zoxide(writable: false))
            == "Updating it needs administrator rights")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.zoxide(linked: true))
            == "No one-click update for this kind of install")
        #expect(CLIToolsModel.reason(.unverified, of: F.zoxide())
            == "The new release can’t be checked against a published digest")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.nvm()) == "No one-click update for this kind of install")
        #expect(CLIToolsModel.vendor(of: .zoxide) == nil)
        #expect(CLIToolsModel.vendor(of: .nvm) == nil)
    }

    /// Atuin's and GHCup's reasons: a folder they cannot write to, a quarantined
    /// file, Atuin's own update check turned off; a copy its updater refuses
    /// keeps the general wording; no vendor named.
    ///
    /// Mutations: drop the `(.autoUpdateOff, .atuin)` case; drop either
    /// `writable` case; drop either `(.unverified, …) where quarantined` case.
    @Test func atuinAndGhcupReasons() {
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.atuin()) == "Atuin’s update check is off in its config")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.atuin(writable: false))
            == "Updating it needs administrator rights")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.atuin(problem: .noReceipt))
            == "No one-click update for this kind of install")
        #expect(CLIToolsModel.reason(.unverified, of: F.atuin(quarantined: true)) == "Quarantined, so not run")
        #expect(CLIToolsModel.reason(.unverified, of: F.atuin()) == "Not the build its developer published")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.ghcup(writable: false))
            == "Updating it needs administrator rights")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.ghcup(problem: .link))
            == "No one-click update for this kind of install")
        #expect(CLIToolsModel.reason(.unverified, of: F.ghcup(quarantined: true)) == "Quarantined, so not run")
        #expect(CLIToolsModel.vendor(of: .atuin) == nil)
        #expect(CLIToolsModel.vendor(of: .ghcup) == nil)
        #expect(CLIToolPresentation.facts(of: F.atuin(), home: "/Users/ann").isEmpty)
        #expect(CLIToolPresentation.facts(of: F.ghcup(), home: "/Users/ann").isEmpty)
    }

    /// flyctl, Helm and Starship: a quarantined file; Helm's and Starship's
    /// folder only `sudo` could write to, and a link, which falls to the
    /// tool-wide wording; flyctl's own auto-update off; no vendor named.
    ///
    /// Mutations: drop any of the `(.unverified, …) where quarantined` cases;
    /// drop the `(.unsupportedInstaller, .helm)` or `.starship` case.
    /// A read-only Helm or Starship (`/usr/local/bin` owned by root) is reported
    /// with the vendor's documented command to copy, as `HelmCheck` and
    /// `StarshipCheck` set it; never beside a running update.
    ///
    /// Mutation: drop `.unsupportedInstaller` from the gate in `manualCommand`.
    @Test func readOnlyHelmAndStarshipHandOutTheVendorCommand() {
        func readOnly(_ base: CLIToolStatus, command: String, withheld: CLIToolWithheld) -> CLIToolStatus {
            CLIToolStatus(
                kind: base.kind, path: base.path, installedVersion: base.installedVersion, latestVersion: base.latestVersion,
                channel: nil, state: .updateAvailable, oneClick: nil, withheld: withheld, note: nil,
                manualCommand: CLIToolCommand(executable: "curl", arguments: [command], pathPrefix: nil),
                detail: base.detail)
        }
        let helm = readOnly(F.helm(writable: false), command: "-fsSL", withheld: .unsupportedInstaller)
        let starship = readOnly(F.starship(writable: false), command: "-sS", withheld: .unsupportedInstaller)
        #expect(CLIToolPresentation.manualCommand(helm) == "curl -fsSL")
        #expect(CLIToolPresentation.manualCommand(starship) == "curl -sS")
        #expect(CLIToolPresentation.manualCommand(readOnly(F.helm(), command: "-fsSL", withheld: .busy)) == nil)
    }

    @Test func flyctlHelmStarshipReasons() {
        let quarantined = "Quarantined, so not run"
        #expect(CLIToolsModel.reason(.unverified, of: F.flyctl(quarantined: true)) == quarantined)
        #expect(CLIToolsModel.reason(.unverified, of: F.helm(quarantined: true)) == quarantined)
        #expect(CLIToolsModel.reason(.unverified, of: F.starship(quarantined: true)) == quarantined)
        #expect(CLIToolsModel.reason(.unverified, of: F.helm()) == "Not the build its developer published")
        let admin = "Updating it needs administrator rights"
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.helm(writable: false)) == admin)
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.starship(writable: false)) == admin)
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.helm(problem: .linked))
            == "No one-click update for this kind of install")
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.flyctl()) == "Auto-update is off in flyctl’s settings")
        for kind in [CLIToolKind.flyctl, .helm, .starship] { #expect(CLIToolsModel.vendor(of: kind) == nil) }
        #expect(CLIToolPresentation.facts(of: F.helm(), home: "/Users/ann").isEmpty)
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
