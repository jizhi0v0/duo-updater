import Foundation
import DuoUpdaterCore

/// How the workbench words one install of any command-line tool: its name in the
/// list, its caption, and why no update is offered.
///
/// Claude Code keeps its own wording (`ClaudeCodePresentation`), which knows its
/// installers and signatures; every other tool is worded from `CLIToolStatus`'s
/// shared fields alone, so a new tool shows up sensibly before it has any wording
/// of its own.
///
/// Foundation only, and no `AppListModel`, so the app test target can compile it
/// (see `DuoUpdaterAppTests` in `App/project.yml`). The views in
/// `CLIToolsWorkbench.swift` only lay these strings out.
enum CLIToolPresentation {

    /// The install's name in the list: Claude Code's own title; the install's own
    /// name when its tool's group holds several kinds of thing (`status.name`:
    /// "rustup", "stable-aarch64-apple-darwin", an npm package); otherwise its
    /// path with the home directory written `~`. The path stays in the detail
    /// pane's header and the row's tooltip.
    ///
    /// One npm package can be installed under two node prefixes, and its name
    /// alone would then title two rows alike: among `others`, such a twin also
    /// says which node — its major version when that tells them apart (beside
    /// the Update button the sidebar has room for "openclaw · node 24", rendered
    /// in German, not for the whole version), else the whole version, else which
    /// prefix.
    static func title(of status: CLIToolStatus, home: String, among others: [CLIToolStatus] = []) -> String {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.title(of: claudeCode.install, home: home)
        }
        guard let name = status.name else { return ClaudeCodePresentation.abbreviate(status.path, home: home) }
        guard case .npm(let package) = status.detail else { return name }
        let twins = others.compactMap { other -> NpmPackage? in
            guard other.kind == .npm, other.name == name, other.path != status.path,
                  case .npm(let twin) = other.detail
            else { return nil }
            return twin
        }
        guard !twins.isEmpty else { return name }
        if let node = nodeVersion(of: package) {
            let major = { (version: String) in String(version.prefix { $0 != "." }) }
            if !twins.contains(where: { nodeVersion(of: $0).map(major) == major(node) }) {
                return "\(name) · node \(major(node))"
            }
            if !twins.contains(where: { nodeVersion(of: $0) == node }) { return "\(name) · node \(node)" }
        }
        return "\(name) · \(ClaudeCodePresentation.abbreviate(package.install.prefix.path, home: home))"
    }

    /// One section of the CLI tab: a tool's installs — or, for npm, the packages of
    /// one node prefix. Each prefix is its own `npm install -g`: its own npm, its
    /// own `lib/node_modules`, its own node. One npm group over two of them read
    /// "node 24.13.0, 24.12.0" and could not say which package was where.
    struct Group: Identifiable {
        let kind: CLIToolKind
        /// The node prefix of an npm group; nil for every other tool.
        let prefix: NodePrefix?
        let statuses: [CLIToolStatus]
        var id: String { kind.rawValue + ":" + (prefix?.path ?? "") }
    }

    /// `statuses` with the tools that have an update first — the Apps tab's and the
    /// casks' rule, which the CLI tab did not keep: its groups stood in
    /// `CLIToolKind`'s order and its formulae alphabetically, updates scattered
    /// among them (2026-10-06). A group with an outdated copy comes before one
    /// without, and within a group the outdated copies come first. Stable
    /// otherwise, so tool order and each tool's own order still decide ties.
    /// Flattened, in the order `groups` then draws.
    static func updatesFirst(_ statuses: [CLIToolStatus]) -> [CLIToolStatus] {
        let outdated: (CLIToolStatus) -> Bool = { $0.state == .updateAvailable }
        let all = groups(statuses)
        let ordered = all.filter { $0.statuses.contains(where: outdated) }
            + all.filter { !$0.statuses.contains(where: outdated) }
        return ordered.flatMap { outdatedFirst($0.statuses, outdated) }
    }

    /// `items` with the outdated ones first, otherwise in their own order: a
    /// group's copies, and Homebrew's formulae by name (`installedLeaves` sorts
    /// them, and `merge` keeps the order).
    static func outdatedFirst<T>(_ items: [T], _ outdated: (T) -> Bool) -> [T] {
        items.filter(outdated) + items.filter { !outdated($0) }
    }

    /// `items` in the order `held` names them, while there is one: the order a run
    /// of updates started with. Updates first would otherwise move each row to its
    /// place among the current ones as its update lands — under a parallel Update
    /// All, one row after another while the user watches. An item `held` does not
    /// name goes after the rest, in its own order.
    static func holding<T>(_ items: [T], to held: [String]?, id: (T) -> String) -> [T] {
        guard let held else { return items }
        let rank = Dictionary(held.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return items.enumerated().sorted { a, b in
            let (ra, rb) = (rank[id(a.element)] ?? Int.max, rank[id(b.element)] ?? Int.max)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// `statuses` as the CLI tab draws them, in their own order (`CLIToolKind`'s,
    /// then each tool's): one group per tool, npm's split by prefix, each prefix
    /// where its first package stood. Flattened, the order of every row.
    static func groups(_ statuses: [CLIToolStatus]) -> [Group] {
        var keys: [String] = []
        var members: [String: (kind: CLIToolKind, prefix: NodePrefix?, statuses: [CLIToolStatus])] = [:]
        for status in statuses {
            var prefix: NodePrefix?
            if status.kind == .npm, case .npm(let package) = status.detail { prefix = package.install.prefix }
            let key = status.kind.rawValue + ":" + (prefix?.path ?? "")
            if members[key] == nil {
                keys.append(key)
                members[key] = (status.kind, prefix, [])
            }
            members[key]?.statuses.append(status)
        }
        return keys.compactMap { key in
            members[key].map { Group(kind: $0.kind, prefix: $0.prefix, statuses: $0.statuses) }
        }
    }

    /// Which prefix an npm group is, for its header: the version manager that
    /// keeps it ("nvm", "fnm"), else its path with the home directory as `~`
    /// ("/opt/homebrew", "~/.npm-global").
    static func prefixLabel(_ prefix: NodePrefix, home: String) -> String {
        switch prefix.source {
        case .nvm, .fnm, .mise, .asdf: return prefix.source.rawValue
        default: return ClaudeCodePresentation.abbreviate(prefix.path, home: home)
        }
    }

    /// The node an npm prefix runs: as checked, else as its layout names it.
    private static func nodeVersion(of package: NpmPackage) -> String? {
        package.install.runtime.nodeVersion ?? package.install.prefix.layoutNodeVersion
    }

    /// A row's caption when it shows versions: `0.4.2 → 0.5.0` when there is an
    /// update, the installed version otherwise.
    static func versionCaption(_ status: CLIToolStatus) -> String {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.versionCaption(claudeCode)
        }
        if status.state == .updateAvailable, let installed = status.installedVersion,
           let latest = status.latestVersion {
            return "\(installed) → \(latest)"
        }
        return status.installedVersion ?? String(localized: "Version can’t be read")
    }

    /// The one line a row shows instead of versions when the check gave no
    /// verdict. nil when it did.
    static func rowWarning(_ status: CLIToolStatus) -> String? {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.rowWarning(claudeCode)
        }
        guard status.state == .unknown, let withheld = status.withheld else { return nil }
        return CLIToolsModel.reason(withheld, of: status)
    }

    /// Why no update is offered — for the detail pane and the row's tooltip. nil
    /// when one is offered, or when there is nothing to offer (up to date, ahead).
    static func explanation(_ status: CLIToolStatus) -> String? {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.explanation(claudeCode)
        }
        guard status.oneClick == nil, let withheld = status.withheld else { return nil }
        return CLIToolsModel.reason(withheld, of: status)
    }

    /// What the click will do besides updating, said beside an update that is
    /// offered:
    /// - bub's first update: with no `~/.bub/bub-project`, `bub update bub`
    ///   creates it and may rebuild the venv on another Python
    ///   (`BubInstall.Project.absent`). The user chose to keep the click and say
    ///   so (2026-10-01).
    /// - Junie's every update: the vendor's installer downloads the whole build
    ///   (~330 MB, no resume) and rewrites the `~/.local/bin/junie` launcher with
    ///   its own shim (`JunieUpdater`).
    /// - openclaw's own `openclaw update`: it also runs `openclaw doctor`,
    ///   restarts its gateway if one is loaded and syncs its npm plugins
    ///   (`NpmCheck.updateCommand`).
    /// - an unsigned uv's first update: the click downloads the release archive
    ///   of the version its receipt names to check the files against it
    ///   (`UvVerifier`) — 18,986,443 bytes for 0.9.18, the one measured.
    static func caution(_ status: CLIToolStatus) -> String? {
        guard status.oneClick != nil else { return nil }
        switch status.detail {
        case .bub(let bub) where bub.project == .absent:
            return String(localized: "The first update creates bub’s project in ~/.bub/bub-project and may rebuild its environment with a newer Python. Packages installed into it by hand would be lost.")
        case .junie:
            return String(localized: "Each update downloads the whole build again (about 330 MB) and rewrites the launcher at ~/.local/bin/junie.")
        case .npm(let package) where package.updater == .openclaw:
            return String(localized: "openclaw update also runs openclaw doctor, restarts openclaw’s gateway if it’s running, and syncs its plugins.")
        case .uv(let uv) where (uv.signature == .adHoc || uv.signature == .unsigned) && uv.hashVerdict == nil:
            let version = uv.receiptVersion ?? "?"
            return String(localized: "Before this first update, DuoUpdater downloads Astral’s archive of uv \(version) (about 19 MB) to confirm the installed files are Astral’s.")
        default:
            return nil
        }
    }

    /// One line of a detail pane's facts: its label and its value, both worded.
    struct Fact: Equatable {
        let label: String
        let value: String
    }

    /// What the tool's own payload adds to the detail pane, beside the version,
    /// channel and update every pane shows: who signed it and how it got there,
    /// and anything else the verdict rests on. Empty for a tool without a payload
    /// worth showing (bub, fx, a Rust toolchain, whose channel is already there).
    static func facts(of status: CLIToolStatus, home: String) -> [Fact] {
        switch status.detail {
        case .uv(let uv): return facts(of: uv, home: home)
        case .junie(let junie): return facts(of: junie, withheld: status.withheld)
        case .rust(let item): return facts(of: item, withheld: status.withheld)
        case .npm(let package): return facts(of: package, withheld: status.withheld, home: home)
        case .codex(let codex): return facts(of: codex)
        case .bun(let bun): return facts(of: bun)
        case .opencode(let opencode): return facts(of: opencode)
        case .amp(let amp): return facts(of: amp)
        case .claudeCode, .bub, .fx, .boat, .cursorAgent, .vitePlus, .herdr, .luvus, .lorca, .zoxide, .nvm: return []
        }
    }

    /// The signature as a fact's value. `signer` is the certificate's name, which
    /// for uv is not the tool's vendor.
    static func signature(_ signature: CLIToolTrust.Signature?, signer: String, team: String) -> String {
        switch signature {
        case .vendor?: return String(localized: "Signed by \(signer) (Team \(team))")
        case .otherSigner?: return String(localized: "Signed, but not by \(signer)")
        case .adHoc?: return String(localized: "Ad hoc signed (no developer identity)")
        case .unsigned?: return String(localized: "Unsigned")
        case .invalid?: return String(localized: "Its signature doesn’t validate")
        case nil: return String(localized: "Not checked")
        }
    }

    private static func facts(of uv: UvInstall, home: String) -> [Fact] {
        var facts: [Fact] = []
        let installedBy: String
        switch uv.layout {
        case .standalone: installedBy = String(localized: "uv’s standalone installer")
        case .link: installedBy = String(localized: "A link (uv tool or pipx)")
        case .unreceipted: installedBy = String(localized: "Unknown: no installer receipt names it")
        }
        facts.append(Fact(label: String(localized: "Installed by"), value: installedBy))
        if let receipt = uv.receiptVersion {
            facts.append(Fact(label: String(localized: "Receipt"), value: receipt))
        }
        guard uv.problem == nil else { return facts }
        var signed: String
        if uv.signature == .vendor {
            // From 0.12.12 Astral's releases carry this certificate (`UvInstall`).
            let signer = "OpenAI OpCo, LLC"
            signed = String(localized: "Signed by \(signer) (Team \(UvScanner.teamIdentifier)), which signs Astral’s releases")
        } else {
            signed = signature(uv.signature, signer: "Astral", team: UvScanner.teamIdentifier)
        }
        // An unsigned copy is trusted only once found byte for byte the release
        // (`UvVerifier`), which only the standalone copy is ever checked for.
        if uv.signature == .adHoc || uv.signature == .unsigned {
            switch uv.hashVerdict {
            case .matches?: signed += " · " + String(localized: "byte for byte Astral’s published build")
            case .differs?: signed += " · " + String(localized: "not Astral’s published build")
            case nil where uv.layout == .standalone:
                signed += " · " + String(localized: "checked against Astral’s published build at the first update")
            case nil: break
            }
        }
        facts.append(Fact(label: String(localized: "Signature"), value: signed))
        return facts
    }

    private static func facts(of junie: JunieInstall, withheld: CLIToolWithheld?) -> [Fact] {
        var facts = [Fact(
            label: String(localized: "Launcher"),
            value: junie.shim == .managed
                ? String(localized: "Junie’s managed launcher")
                : String(localized: "First-generation launcher"))]
        if junie.problem == nil {
            facts.append(Fact(
                label: String(localized: "Signature"),
                value: signature(junie.signature, signer: "JetBrains", team: JunieScanner.teamIdentifier)))
        }
        // `.staged` already says it in the Update line.
        if let pending = junie.pendingUpdate, withheld != .staged {
            facts.append(Fact(
                label: String(localized: "Downloaded"),
                value: String(localized: "\(pending), installed the next time Junie starts")))
        }
        return facts
    }

    /// The signature the click rests on: the installer runs the installed binary.
    private static func facts(of codex: CodexInstall) -> [Fact] {
        guard codex.problem == nil || codex.problem == .launcherElsewhere else { return [] }
        let signer = "OpenAI OpCo, LLC"
        return [Fact(label: String(localized: "Signature"),
                     value: signature(codex.signature, signer: signer, team: CodexScanner.teamIdentifier))]
    }

    /// bun is run by every update in its group, its own and its packages'.
    private static func facts(of bun: BunInstall) -> [Fact] {
        guard bun.problem == nil else { return [] }
        let signer = "Oven"
        return [Fact(label: String(localized: "Signature"),
                     value: signature(bun.signature, signer: signer, team: BunScanner.teamIdentifier))]
    }

    /// Informational: OpenCode is never run, and builds before 1.18.34 are ad hoc.
    private static func facts(of opencode: OpencodeInstall) -> [Fact] {
        guard opencode.problem == nil else { return [] }
        let signer = "Anomaly Innovations, Inc."
        return [Fact(label: String(localized: "Signature"),
                     value: signature(opencode.signature, signer: signer, team: OpencodeScanner.teamIdentifier))]
    }

    /// The release Amp's installer left: its Developer ID, checked after every update.
    private static func facts(of amp: AmpInstall) -> [Fact] {
        guard amp.problem == nil else { return [] }
        let signer = "Amp Frontier Corporation"
        return [Fact(label: String(localized: "Signature"),
                     value: signature(amp.signature, signer: signer, team: AmpScanner.teamIdentifier))]
    }

    /// rustup has no signature to go by: what lets it run is its sha256 being one
    /// rust-lang publishes (`RustCheck.rustupStatus`). A toolchain's channel is
    /// already the pane's.
    private static func facts(of item: RustItem, withheld: CLIToolWithheld?) -> [Fact] {
        guard case .rustup = item.kind else { return [] }
        let value: String
        if let trusted = item.trustedRustup {
            value = String(localized: "Its sha256 matches the published rustup \(trusted.version) for \(trusted.hostTriple)")
        } else if let version = item.version {
            value = String(localized: "Its sha256 matches the published rustup \(version)")
        } else if withheld == .unverified {
            value = String(localized: "Its sha256 matches no published rustup build")
        } else {
            return []
        }
        return [Fact(label: String(localized: "Verification"), value: value)]
    }

    private static func facts(of package: NpmPackage, withheld: CLIToolWithheld?, home: String) -> [Fact] {
        let install = package.install
        var facts = [Fact(
            label: String(localized: "Prefix"),
            value: ClaudeCodePresentation.abbreviate(install.prefix.path, home: home))]
        let node: String
        if install.runtime.node == nil {
            node = String(localized: "None of its own")
        } else {
            node = [nodeVersion(of: package),
                    signature(install.runtime.nodeSignature, signer: "Node.js Foundation",
                              team: NpmScanner.nodeTeamIdentifier)]
                .compactMap { $0 }.joined(separator: " · ")
        }
        facts.append(Fact(label: String(localized: "Node"), value: node))
        // `.runtimeTooOld` already says it in the Update line; beside an offered
        // update it is the other half of the story.
        if let gap = package.gap, withheld != .runtimeTooOld {
            facts.append(Fact(label: String(localized: "Newer release"),
                              value: CLIToolsModel.requirement(gap, of: gap.version)))
        }
        if let target = install.linkTarget {
            facts.append(Fact(label: String(localized: "Linked to"),
                              value: ClaudeCodePresentation.abbreviate(target, home: home)))
        }
        if let registry = install.customRegistry {
            facts.append(Fact(label: String(localized: "Registry"), value: registry.url))
        }
        return facts
    }

    /// The command to copy beside an update the user turned the tool's auto-update
    /// off for — the same command a one-click would run. nil otherwise: every
    /// other gate means it should not be run now, or it is DuoUpdater's to run.
    ///
    /// zoxide and nvm also hand theirs out where DuoUpdater will not run the
    /// update itself: nvm always (`NvmCheck`), zoxide when its directory needs
    /// `sudo` or what the installer leaves could not be checked (`ZoxideCheck`).
    /// Their checks set the command only then — never beside a running update.
    static func manualCommand(_ status: CLIToolStatus) -> String? {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.manualCommand(claudeCode)
        }
        guard status.state == .updateAvailable,
              status.withheld == .autoUpdateOff
                || ([.zoxide, .nvm].contains(status.kind) && [.unsupportedInstaller, .unverified].contains(status.withheld))
        else { return nil }
        return status.manualCommand?.display
    }

    /// The channel a tool's group header names, read off its installs: one name
    /// when they agree, each when they do not. nil for a tool without channels.
    static func channels(of statuses: [CLIToolStatus]) -> String? {
        var seen: [String] = []
        for channel in statuses.compactMap(\.channel) where !seen.contains(channel) {
            seen.append(channel)
        }
        return seen.isEmpty ? nil : seen.joined(separator: ", ")
    }

    /// The group header of uv, Junie, Rust, npm, Boat, Codex, Bun and OpenCode: what decides their installs'
    /// verdicts tool-wide, kept short — several languages are twice the English
    /// width, and the header shrinks a little, then cuts.
    /// - uv: nothing. It has no channels and no setting of its own.
    /// - Junie: the channel, and that its `auto-update` is off when it is.
    /// - Rust: the toolchains' channels, and rustup's `auto_self_update` when it
    ///   is not `enable` — which turns the rustup row's click into a command to copy.
    /// - npm: which nodes the prefixes run, the one thing every row's verdict
    ///   is held against (`engines`).
    /// - Boat: the channel its config names (`prod` until the user picks one).
    /// - Codex: `latest`, its installer's only channel, and that its update check
    ///   is off when it is.
    /// - Bun: like npm, the node its packages are held against.
    /// - OpenCode: `latest`, and that its `autoupdate` is off when it is.
    /// - Cursor CLI: its channel (`prod` unless set; `static` turns updates off).
    /// - Herdr: the channel its config names, `stable` or `preview`.
    static func headerSummary(
        _ kind: CLIToolKind, statuses: [CLIToolStatus], context: CLIToolReport.Context?
    ) -> String? {
        let mine = statuses.filter { $0.kind == kind }
        switch (kind, context) {
        case (.junie, let context):
            guard let channels = channels(of: mine) else { return nil }
            if case .junie(let settings)? = context, !settings.autoUpdate {
                return String(localized: "\(channels) · auto-update off")
            }
            return channels
        case (.rust, let context):
            var parts = [channels(of: mine)].compactMap { $0 }
            if case .rust(let settings)? = context, !settings.selfUpdateEnabled {
                switch settings.autoSelfUpdate {
                case "disable": parts.append(String(localized: "rustup self-update off"))
                case "check-only": parts.append(String(localized: "rustup self-update: check only"))
                case let value?: parts.append(String(localized: "rustup self-update: \(value)"))
                case nil: break
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case (.boat, _), (.cursorAgent, _), (.herdr, _):
            return channels(of: mine)
        case (.opencode, let context):
            guard let channels = channels(of: mine) else { return nil }
            if case .opencode(let settings)? = context, !settings.autoUpdate {
                return String(localized: "\(channels) · auto-update off")
            }
            return channels
        case (.codex, let context):
            guard let channels = channels(of: mine) else { return nil }
            if case .codex(let settings)? = context, !settings.checkForUpdates {
                return String(localized: "\(channels) · update check off")
            }
            return channels
        case (.npm, _), (.bun, _):
            var nodes: [String] = []
            for case .npm(let package) in mine.map(\.detail) {
                if let node = nodeVersion(of: package), !nodes.contains(node) { nodes.append(node) }
            }
            // A tool name and version numbers: the same in every language.
            return nodes.isEmpty ? nil : "node " + nodes.joined(separator: ", ")
        default:
            return nil
        }
    }
}
