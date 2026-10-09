import Foundation

/// The command-line tools DuoUpdater tracks outside Homebrew.
///
/// Each one has its own rules — where its installers put it, how its version is
/// read, which command updates it and when that may run — so each keeps its own
/// detection and update code (`ClaudeCode*`, `Bub*`, `Fx*`, `Uv*`, `Junie*`,
/// `Rust*`, `Npm*`, `Boat*`, `Codex*`, `Bun*`, `Opencode*`, `CursorAgent*`, `Amp*`, `VitePlus*`, `Herdr*`, `Luvus*`, `Lorca*`, `Zoxide*`, `Nvm*`, `Atuin*`, `Ghcup*`, `Flyctl*`, `Helm*`, `Starship*`, `Deno*`, `Mise*`). What they share is
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
/// whatever the tool. Identity is `(kind, path)`.
public struct CLIToolStatus: Sendable, Equatable {
    public let kind: CLIToolKind
    /// The install's identity on disk; what "this copy" means to the tool's own
    /// code (`ClaudeCodeInstall.path`, …).
    public let path: String
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
    }

    public init(
        kind: CLIToolKind, path: String, installedVersion: String?, latestVersion: String?,
        channel: String?, state: CLIToolState, oneClick: CLIToolCommand?,
        withheld: CLIToolWithheld?, note: String?, manualCommand: CLIToolCommand? = nil,
        name: String? = nil, releaseNotesKey: String? = nil, detail: Detail, needsAdministrator: Bool = false
    ) {
        self.kind = kind
        self.path = path
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
    }

    public init(
        kind: CLIToolKind, statuses: [CLIToolStatus], context: Context, sightings: [CLIToolSighting]? = nil
    ) {
        self.kind = kind
        self.statuses = statuses
        self.context = context
        self.sightings = sightings ?? statuses.map {
            CLIToolSighting(kind: $0.kind, path: $0.path, version: $0.installedVersion)
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

    public init(kind: CLIToolKind, path: String, version: String?, state: String = "") {
        self.kind = kind
        self.path = path
        self.version = version
        self.state = state
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
