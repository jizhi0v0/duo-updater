import Foundation

/// The command-line tools DuoUpdater tracks outside Homebrew.
///
/// Each one has its own rules — where its installers put it, how its version is
/// read, which command updates it and when that may run — so each keeps its own
/// detection and update code (`ClaudeCode*`, `Bub*`, `Fx*`, `Uv*`, `Junie*`,
/// `Rust*`, `Npm*`, `Boat*`, `Codex*`, `Bun*`, `Opencode*`, `CursorAgent*`, `Amp*`, `VitePlus*`, `Herdr*`, `Luvus*`, `Lorca*`, `Zoxide*`, `Nvm*`, `Atuin*`, `Ghcup*`, `Flyctl*`, `Helm*`, `Starship*`, `Deno*`, `Mise*`, `Obelus*`, `Biome*`). What they share is
/// how the app lists them, sums them up and runs their updates: `CLIToolStatus`,
/// `CLIToolReport` and `CLIToolProvider` below. A later tool is a new provider and
/// a new `Kind`; the popover row and the workbench's CLI tab read it the same way.
public enum CLIToolKind: String, Sendable, Codable, CaseIterable {
    case claudeCode = "claude-code"
    case bub
    case fx
    case uv
    case junie
    /// rustup and the toolchains it keeps on a channel: one group, a row each.
    case rust
    /// Packages installed with `npm install -g`, one row per package and prefix.
    case npm
    /// boat.dev's sandbox CLI, `~/.ascii/bin/boat`.
    case boat
    /// OpenAI's Codex CLI as its standalone installer leaves it, `~/.local/bin/codex`.
    case codex
    /// bun at `~/.bun/bin/bun`, and the packages `bun add -g` installed: one
    /// group, a row each.
    case bun
    /// The packages `pnpm add -g` installed (`PnpmPackages`): one group, a row
    /// each. pnpm itself is wherever its installer put it, and not a row.
    case pnpm
    /// The packages `yarn global add` installed — Yarn 1's (`YarnPackages`).
    case yarn
    /// OpenCode as its installer leaves it, `~/.opencode/bin/opencode`.
    case opencode
    /// Cursor's command-line agent, `~/.local/bin/agent`.
    case cursorAgent = "cursor-agent"
    /// Amp Frontier's Amp, `~/.amp/bin/amp`.
    case amp
    /// VoidZero's Vite+ (`vp`), `~/.vite-plus` or `~/.local/share/vite-plus`.
    case vitePlus = "vite-plus"
    /// herdr.dev's terminal workspace, `~/.local/bin/herdr`.
    case herdr
    /// RizRiyz's Luvus, `/usr/local/bin/luvus` or `~/.local/bin/luvus`.
    case luvus
    /// egoist's Lorca CLI, `~/.local/bin/lorca`.
    case lorca
    /// ajeetdsouza's zoxide, `~/.local/bin/zoxide`.
    case zoxide
    /// nvm itself (not the nodes it keeps), `~/.nvm` or `~/.config/nvm`.
    case nvm
    /// atuinsh's Atuin, `~/.atuin/bin/atuin`.
    case atuin
    /// GHCup's own binary, `~/.ghcup/bin/ghcup` (not the toolchains it installs).
    case ghcup
    /// Fly.io's flyctl, `~/.fly/bin/flyctl`.
    case flyctl
    /// Helm, `/usr/local/bin/helm` as its official script installs it.
    case helm
    /// Starship, `/usr/local/bin/starship` as its official script installs it.
    case starship
    /// Deno as its installer leaves it, `~/.deno/bin/deno`.
    case deno
    /// jdx's mise as its installer leaves it, `~/.local/bin/mise`.
    case mise
    /// obelus-editor's Obelus, `~/.local/bin/obg` and `~/.local/bin/ob`: one
    /// group, a row each.
    case obelus
    /// Biome, the JS/TS linter and formatter, as its installer leaves it,
    /// `~/.local/bin/biome`.
    case biome
    /// Every item any manager keeps — mise's tools, uv's tools and Pythons,
    /// pipx venvs, nvm's and fnm's Nodes, pyenv's and rbenv's lines, cargo's
    /// and go's installs (`CLITools/Managed/`). Which manager is a value on
    /// the status (`ManagedItem.manager`), not a kind: one `ManagedProvider`
    /// per manager, all of this kind, told apart by `CLIToolProvider.id`. Last,
    /// so the managed groups come after every standalone kind (D12).
    case managed

    /// The tool's own name, as its vendor writes it. Untranslated, like a formula
    /// name on the brew row.
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .bub: return "bub"
        case .fx: return "fx"
        case .uv: return "uv"
        case .junie: return "Junie"
        case .rust: return "Rust"
        case .npm: return "npm"
        case .boat: return "Boat"
        case .codex: return "Codex"
        case .bun: return "Bun"
        case .opencode: return "OpenCode"
        case .cursorAgent: return "Cursor CLI"
        case .amp: return "Amp"
        case .vitePlus: return "Vite+"
        case .herdr: return "Herdr"
        case .luvus: return "Luvus"
        case .lorca: return "Lorca"
        case .zoxide: return "zoxide"
        case .nvm: return "nvm"
        case .atuin: return "Atuin"
        case .ghcup: return "GHCup"
        case .flyctl: return "flyctl"
        case .helm: return "Helm"
        case .starship: return "Starship"
        case .deno: return "Deno"
        case .mise: return "mise"
        case .obelus: return "Obelus"
        case .biome: return "Biome"
        case .pnpm: return "pnpm"
        case .yarn: return "Yarn"
        // Never a row's title: a managed row is named by its item, its group
        // by its manager (`ManagerDescriptor.displayName`).
        case .managed: return "Managed tools"
        }
    }
}

/// A command to run, spelled out in full: no `PATH` lookup, no shell.
public struct CLIToolCommand: Sendable, Equatable, Codable {
    public let executable: String
    public let arguments: [String]
    /// Put first on the child's `PATH`, so a `#!/usr/bin/env node` script finds
    /// the node of *this* prefix and not whichever one the GUI sees.
    public let pathPrefix: String?

    public init(executable: String, arguments: [String], pathPrefix: String?) {
        self.executable = executable
        self.arguments = arguments
        self.pathPrefix = pathPrefix
    }

    public var display: String { ([executable] + arguments).joined(separator: " ") }
}

public enum CLIToolState: String, Sendable, Codable {
    case upToDate
    case updateAvailable
    /// Newer than the channel — a dev or `latest` build on a machine whose channel
    /// now points lower.
    case ahead
    /// No comparison possible; the status's `withheld` and `note` say why.
    case unknown
    /// A newer version exists, but the user pinned this one: a package whose
    /// specifier in its package manager's global `package.json` is an exact
    /// version, which that manager's own `update -g` holds where it is. Reported,
    /// never offered, and not counted as an update (agreed 2026-10-13).
    case pinned
}

/// The gate that stopped a verdict short, as a value the app words in the user's
/// language — a status's `note` is the English sentence for `duo`.
public enum CLIToolWithheld: String, Sendable, Codable {
    /// The install is broken, not outdated.
    case broken
    /// Not signed by the tool's vendor (or not as the tool).
    case wrongSigner
    case versionUnreadable
    /// The channel could not be read (network).
    case channelUnreadable
    /// The channel is the GitHub API, and it refused the read for its rate limit
    /// (`GitHubReleasesSource.statusError`'s rule). Apart from `channelUnreadable`
    /// because a token is the fix: the popover's rate-limit banner counts it with
    /// the app rows.
    case rateLimited
    /// The tool's own settings block every update path.
    case updatesDisabled
    /// The tool's own auto-update is off: reported, never offered.
    case autoUpdateOff
    /// An update is already running.
    case busy
    /// The file on disk is not the release its layout names.
    case versionMismatch
    /// No vendor-documented update for this kind of install.
    case unsupportedInstaller
    /// Claude Code's npm prefix without a node and npm of its own
    /// (`ClaudeCodeStatus.Withheld.noOwnNpm`).
    case noOwnNpm
    /// The user's channel ships builds without the vendor's signature — fx's `dev`
    /// channel is ad hoc signed — so its builds are neither run nor installed.
    case channelUnsigned
    /// The tool's own project file, which its update syncs from, no longer lists
    /// the tool: bub's `~/.bub/bub-project` left by an interrupted `bub update`,
    /// where `bub update bub` would exit 0 having changed nothing.
    case projectIncomplete
    /// The program the documented update runs with cannot be found — `uv`, which
    /// `bub update` needs on its `PATH`.
    case updaterMissing
    /// No vendor signature to check, and the file is not byte for byte the build
    /// the vendor published for its version (`CLIToolTrust`): nothing of it is
    /// run. The user agreed the rule on 2026-10-01 — a binary is run only when it
    /// carries the vendor's Team ID or its sha256 equals the vendor's own.
    case unverified
    /// The newer release needs a newer runtime than the one this install runs on
    /// — an npm package whose `engines.node` excludes its prefix's node.
    case runtimeTooOld
    /// The tool has already downloaded the update and installs it itself the next
    /// time it starts (Junie's `pending-update.json`).
    case staged
}

/// One install of one tool and its verdict: what every surface reads the same way
/// whatever the tool. Identity is `(kind, identity)` — and `identity` is `path`
/// for every kind but `.managed`.
public struct CLIToolStatus: Sendable, Equatable {
    public let kind: CLIToolKind
    /// Where the install is on disk; what "this copy" means to the tool's own
    /// code (`ClaudeCodeInstall.path`, …).
    public let path: String
    /// What names this copy across checks: `path`, except for a managed row,
    /// whose directory moves when a new version lands beside the old one and
    /// which is named "<manager>|<root>|<key>" instead (`ManagedItem.identity`).
    /// The app's `CLIToolID`, the announcement ledger's keys and `duo`'s job ids
    /// are built from this.
    public let identity: String
    /// What the install reads as, nil when it could not be read.
    public let installedVersion: String?
    /// What the install's channel points at, nil when it could not be read.
    public let latestVersion: String?
    /// The channel the verdict was made on, in the tool's own spelling
    /// ("stable", "latest", "dev"); nil for a tool without channels.
    public let channel: String?
    public let state: CLIToolState
    /// The one-click update, present only when every gate passed.
    public let oneClick: CLIToolCommand?
    public let withheld: CLIToolWithheld?
    /// Why, in English, for `duo` and the log.
    public let note: String?
    /// The command for the user to run themselves, when the update is theirs to
    /// take: with `withheld == .autoUpdateOff` — the user turned the tool's own
    /// auto-update off, so DuoUpdater reports the update and hands over the very
    /// command a one-click would have run, instead of running it. zoxide and nvm
    /// also set it where DuoUpdater will not run their update (`ZoxideCheck`,
    /// `NvmCheck`).
    public let manualCommand: CLIToolCommand?
    /// The install's own name when the tool's group holds more than one kind of
    /// thing — "rustup", "stable-aarch64-apple-darwin", an npm package's name;
    /// nil when the tool's name says it.
    public let name: String?
    /// Which release notes this install reads, for the app's session cache: the
    /// kind's raw value unless one tool has several documents (rustup's own
    /// changelog and Rust's, one per npm package).
    public let releaseNotesKey: String
    /// The tool's own view of the install, for its detail pane.
    public let detail: Detail
    /// `oneClick` runs as root, behind the system's administrator panel
    /// (`CLIToolAdministratorRun`): the install's directory is root's. Only a
    /// click on the row's own Update runs it, never Update All.
    public let needsAdministrator: Bool

    public enum Detail: Sendable, Equatable {
        case claudeCode(ClaudeCodeStatus)
        case bub(BubInstall)
        case fx(FxInstall)
        case uv(UvInstall)
        case junie(JunieInstall)
        case rust(RustItem)
        case npm(NpmPackage)
        case boat(BoatInstall)
        case codex(CodexInstall)
        /// bun's own row; its packages' rows carry `.npm`.
        case bun(BunInstall)
        case opencode(OpencodeInstall)
        case cursorAgent(CursorAgentInstall)
        case amp(AmpInstall)
        case vitePlus(VitePlusInstall)
        case herdr(HerdrInstall)
        case luvus(LuvusInstall)
        case lorca(LorcaInstall)
        case zoxide(ZoxideInstall)
        case nvm(NvmInstall)
        case atuin(AtuinInstall)
        case ghcup(GhcupInstall)
        case flyctl(FlyctlInstall)
        case helm(HelmInstall)
        case starship(StarshipInstall)
        case deno(DenoInstall)
        case mise(MiseInstall)
        case obelus(ObelusInstall)
        case biome(BiomeInstall)
        /// Any manager's item (`CLITools/Managed/`).
        case managed(ManagedItem)
    }

    public init(
        kind: CLIToolKind, path: String, identity: String? = nil, installedVersion: String?, latestVersion: String?,
        channel: String?, state: CLIToolState, oneClick: CLIToolCommand?,
        withheld: CLIToolWithheld?, note: String?, manualCommand: CLIToolCommand? = nil,
        name: String? = nil, releaseNotesKey: String? = nil, detail: Detail, needsAdministrator: Bool = false
    ) {
        self.kind = kind
        self.path = path
        self.identity = identity ?? path
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.channel = channel
        self.state = state
        self.oneClick = oneClick
        self.withheld = withheld
        self.note = note
        self.manualCommand = manualCommand
        self.name = name
        self.releaseNotesKey = releaseNotesKey ?? kind.rawValue
        self.detail = detail
        self.needsAdministrator = needsAdministrator
    }

    /// The command-line counterpart of `UpdateStatus.isRateLimitError`: the check
    /// stopped on GitHub's API rate limit.
    public var isRateLimitError: Bool { withheld == .rateLimited }

    /// This verdict with its one-click held back because the GitHub API budget
    /// its updater would spend is closed until `until` (`GitHubRateLimitGate`):
    /// the vendor's command asks GitHub itself, out of our process, where the
    /// gate cannot stop it — so we do not run it. The update stays reported;
    /// only the click is withheld, and comes back when the gate opens.
    public func heldBackByGitHubRateLimit(until: Date) -> CLIToolStatus {
        CLIToolStatus(
            kind: kind, path: path, identity: identity, installedVersion: installedVersion, latestVersion: latestVersion,
            channel: channel, state: state, oneClick: nil, withheld: .rateLimited,
            note: "update held back: GitHub's API budget is spent until \(until.formatted(.iso8601))",
            manualCommand: manualCommand, name: name, releaseNotesKey: releaseNotesKey, detail: detail,
            needsAdministrator: needsAdministrator)
    }

    /// The id of the provider that made this verdict (`CLIToolProvider.id`): the
    /// kind's raw value, or "managed:<manager>" for a managed row — the key the
    /// app and `duo` look a status's provider up by, since every manager's
    /// provider is of kind `.managed`.
    public var providerID: String {
        if case .managed(let item) = detail { return item.descriptor.providerID }
        return kind.rawValue
    }

    /// The managed item behind this row, nil for every other kind.
    public var managedItem: ManagedItem? {
        if case .managed(let item) = detail { return item }
        return nil
    }
}

/// One full look at one tool on this Mac.
public struct CLIToolReport: Sendable, Equatable {
    public let kind: CLIToolKind
    public let statuses: [CLIToolStatus]
    /// The tool-wide settings the verdicts were made under, for its group header.
    public let context: Context
    /// What `scan()` would have answered for the installs this report checked —
    /// built by the same rule, so an open of the popover can tell whether the disk
    /// moved since.
    public let sightings: [CLIToolSighting]

    public enum Context: Sendable, Equatable {
        case claudeCode(ClaudeCodeSettings)
        case bub
        case fx(FxSettings)
        case uv
        case junie(JunieSettings)
        case rust(RustupSettings)
        case npm
        case boat
        case codex(CodexSettings)
        case bun
        case opencode(OpencodeSettings)
        case cursorAgent(CursorAgentSettings)
        case amp(AmpSettings)
        case vitePlus
        case herdr
        case luvus
        case lorca
        case zoxide
        case nvm
        case atuin
        case ghcup
        case flyctl
        case helm
        case starship
        case deno
        case mise
        case obelus
        case biome
        case pnpm
        case yarn
        /// A manager and the installs of it the check found (`ManagedProvider`).
        case managed(ManagerContext)
    }

    public init(
        kind: CLIToolKind, statuses: [CLIToolStatus], context: Context, sightings: [CLIToolSighting]? = nil
    ) {
        self.kind = kind
        self.statuses = statuses
        self.context = context
        // `name` stays nil here: an existing provider's own `scan()` sets none,
        // and the two are compared as sets (`CLIToolsModel.onOpen`).
        self.sightings = sightings ?? statuses.map {
            CLIToolSighting(kind: $0.kind, path: $0.path, version: $0.installedVersion, identity: $0.identity)
        }
    }
}

/// What a local, network-free look finds: which installs there are, the version
/// each one reads as, and what else on disk its verdict rests on. Enough to
/// reserve the popover row and to tell that something changed since the last
/// check.
public struct CLIToolSighting: Sendable, Hashable {
    public let kind: CLIToolKind
    public let path: String
    public let version: String?
    /// The rest of what the scan sees that decides a verdict — signature, a
    /// problem, where the package came from — in the tool's own opaque spelling.
    /// Without it a copy repaired in place at the same version (a broken venv
    /// reinstalled, an editable bub reinstalled from PyPI) looked unchanged, and
    /// its stale "not checked" stayed until the report aged out (review, #942).
    public let state: String
    /// What names the install across checks (`CLIToolStatus.identity`): `path`
    /// for every kind but `.managed`.
    public let identity: String
    /// The install's own name when its tool's group holds more than one kind of
    /// thing (`CLIToolStatus.name`) and the scan already knows it — a managed
    /// item's; nil otherwise, as `duo list` prints the tool's name then.
    public let name: String?

    public init(
        kind: CLIToolKind, path: String, version: String?, state: String = "", identity: String? = nil,
        name: String? = nil
    ) {
        self.kind = kind
        self.path = path
        self.version = version
        self.state = state
        self.identity = identity ?? path
        self.name = name
    }
}

public enum CLIToolUpdateOutcome: Sendable, Equatable {
    /// The command exited 0. `version` is what the install reads as afterwards
    /// (re-read from disk), or nil when it could not be read.
    case updated(version: String?)
    /// Something else started updating it between the check and the click; nothing
    /// was run. The English description, for the log.
    case busy(String)
    /// The status offers no one-click; nothing was run.
    case notOffered
    /// The command ran and failed. `message` is the line for the row, `output`
    /// the whole log for the detail pane.
    case failed(message: String, output: String)
    /// The user dismissed the administrator panel (`needsAdministrator`):
    /// nothing ran, and nothing failed.
    case declined
}

public enum CLIToolReleaseNotesError: Error, Equatable {
    case http(Int)
    /// The notes are on the GitHub API, and it refused them for its rate limit
    /// (`GitHubReleasesSource.isRateLimited`): said as such, since a token is the
    /// fix and "HTTP 403" told nobody that.
    case rateLimited
    /// The document came back but no longer looks like release notes — kept apart
    /// from a network failure so a format drift is not mistaken for a blip.
    case noSections

    /// What a non-2xx answer from `url` becomes: GitHub's rate limit by the app
    /// rows' own rule when `url` is the GitHub API, else its status.
    static func status(_ code: Int, rateLimitRemaining: String?, url: URL) -> CLIToolReleaseNotesError {
        guard ChangelogService.isGitHubAPI(url),
              GitHubReleasesSource.isRateLimited(code, rateLimitRemaining: rateLimitRemaining)
        else { return .http(code) }
        return .rateLimited
    }

    static func status(_ response: HTTPURLResponse, url: URL) -> CLIToolReleaseNotesError {
        status(response.statusCode, rateLimitRemaining: response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
               url: url)
    }
}

/// One tool: how to find it, check it, update it and read its release notes.
///
/// Every method is the tool's own — the app never decides which command updates
/// which install. Implementations must not reach the host from tests: each keeps
/// the injectable seams its own tests need.
public protocol CLIToolProvider: Sendable {
    var kind: CLIToolKind { get }

    /// What tells this provider from every other, where `kind` does not: the
    /// kind's raw value, except for a `ManagedProvider`, one per manager and
    /// all of kind `.managed` ("managed:<manager>"). A status names its own
    /// provider the same way (`CLIToolStatus.providerID`).
    var id: String { get }

    /// What the provider's requests are filed under in the request log, and
    /// what the check's timing log calls it: the kind's name, or the manager's.
    var attributionName: String { get }

    /// Local and quick: no network. May read files and verify signatures; may run
    /// the tool only where its version cannot be read any other way (fx).
    func scan() async -> [CLIToolSighting]

    /// Scan, read the tool's settings, ask its channel, apply its gates.
    func check() async -> CLIToolReport

    /// Run `status.oneClick` — and nothing else — re-asking any gate that can
    /// change between the check and the click.
    func update(_ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void) async -> CLIToolUpdateOutcome

    /// The release notes `status` reads (`CLIToolStatus.releaseNotesKey` names
    /// the document), newest first, one entry per version. The app cuts them to
    /// one install with `CLIToolChangelog.relevant`.
    func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog

    /// Whether `check()` asks api.github.com. Anonymous, that API allows 60
    /// requests an hour per IP, and a 304 still counts against them; with a token
    /// a 304 costs nothing. So the app's background check asks such a tool at
    /// most every 15 minutes when no token resolves (`CLIToolsModel.isDue`).
    ///
    /// Measured 2026-10-08: of the version checks, only Bun's and OpenCode's
    /// (`releases/latest`) ask it on every check (zoxide's and nvm's too, added
    /// 2026-10-09), and Herdr's when its manifests
    /// do not name the build. Every other source answers with an ETag or a
    /// Last-Modified that revalidates to 304 at no cost. Release notes are not
    /// part of a check and do not count here.
    var readsGitHubAPI: Bool { get }
}

extension CLIToolProvider {
    public var readsGitHubAPI: Bool { false }
    public var id: String { kind.rawValue }
    public var attributionName: String { kind.displayName }
}

public enum CLIToolChangelog {
    /// The entries worth putting in front of someone on `installed` whose channel
    /// points at `latest`. See `ClaudeCodeChangelog.relevant`, which this is.
    public static func relevant(
        _ changelog: Changelog, installed: String?, latest: String?, minimum: Int = 5
    ) -> Changelog? {
        ClaudeCodeChangelog.relevant(changelog, installed: installed, latest: latest, minimum: minimum)
    }
}

extension CLIToolKind {
    /// Whose GitHub API budget the tool's own update command spends, asking
    /// `api.github.com` from its own process (`CLIToolGitHubToken`'s list, read
    /// 2026-10-11): uv, bun and mise take our token when there is one;
    /// zoxide's `install.sh` and `atuin update` always go without; Codex's
    /// installer does only when `releases.openai.com` fails — counted, so a
    /// spent budget is never what its fallback meets. Nil for every other tool.
    public var updaterSpendsGitHubAPI: UpdaterGitHubAPI? {
        switch self {
        case .uv, .bun, .mise: return .ourTokenIfAny
        case .zoxide, .atuin, .codex: return .anonymous
        default: return nil
        }
    }

    public enum UpdaterGitHubAPI: Sendable, Equatable {
        /// Handed our token when one resolves (`CLIToolGitHubToken.app`), else anonymous.
        case ourTokenIfAny
        case anonymous
    }
}

extension CLIToolStatus {
    /// `CLIToolKind.updaterSpendsGitHubAPI` for this copy: the kind's answer, or
    /// the manager's (`ManagerDescriptor.updaterSpendsGitHubAPI`) for a managed
    /// row, since every manager's row is of one kind. `applyingGitHubPause` and
    /// `duo`'s check read this, never the kind's directly.
    public var updaterSpendsGitHubAPI: CLIToolKind.UpdaterGitHubAPI? {
        if case .managed(let item) = detail { return item.descriptor.updaterSpendsGitHubAPI }
        return kind.updaterSpendsGitHubAPI
    }

    /// This verdict as it may be offered while GitHub's API budgets are closed
    /// (`pause`, until when, per credential; one absent is open): with its
    /// one-click held back when the tool's own update command would spend a
    /// closed budget (`CLIToolKind.updaterSpendsGitHubAPI`), unchanged
    /// otherwise. `updatersGetOurToken`: a token resolves, so uv, bun and mise
    /// would spend ours rather than the anonymous one. The app's CLI tab and
    /// `duo install` both offer through here.
    public func applyingGitHubPause(
        _ pause: [GitHubRateLimitGate.Credential: Date], updatersGetOurToken: Bool, now: Date
    ) -> CLIToolStatus {
        guard oneClick != nil, let access = updaterSpendsGitHubAPI else { return self }
        let credential: GitHubRateLimitGate.Credential =
            access == .ourTokenIfAny && updatersGetOurToken ? .token : .anonymous
        guard let until = pause[credential], until > now else { return self }
        return heldBackByGitHubRateLimit(until: until)
    }
}
