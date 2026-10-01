import Foundation

/// The command-line tools DuoUpdater tracks outside Homebrew.
///
/// Each one has its own rules — where its installers put it, how its version is
/// read, which command updates it and when that may run — so each keeps its own
/// detection and update code (`ClaudeCode*`, `Bub*`, `Fx*`). What they share is
/// how the app lists them, sums them up and runs their updates: `CLIToolStatus`,
/// `CLIToolReport` and `CLIToolProvider` below. A later tool is a new provider and
/// a new `Kind`; the popover row and the workbench's CLI tab read it the same way.
public enum CLIToolKind: String, Sendable, Codable, CaseIterable {
    case claudeCode = "claude-code"
    case bub
    case fx

    /// The tool's own name, as its vendor writes it. Untranslated, like a formula
    /// name on the brew row.
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .bub: return "bub"
        case .fx: return "fx"
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
    /// The program the documented update runs with cannot be found — `uv`, which
    /// `bub update` needs on its `PATH`.
    case updaterMissing
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
    /// take: only with `withheld == .autoUpdateOff` — the user turned the tool's own
    /// auto-update off, so DuoUpdater reports the update and hands over the very
    /// command a one-click would have run, instead of running it.
    public let manualCommand: CLIToolCommand?
    /// The tool's own view of the install, for its detail pane.
    public let detail: Detail

    public enum Detail: Sendable, Equatable {
        case claudeCode(ClaudeCodeStatus)
        case bub(BubInstall)
        case fx(FxInstall)
    }

    public init(
        kind: CLIToolKind, path: String, installedVersion: String?, latestVersion: String?,
        channel: String?, state: CLIToolState, oneClick: CLIToolCommand?,
        withheld: CLIToolWithheld?, note: String?, manualCommand: CLIToolCommand? = nil, detail: Detail
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
        self.detail = detail
    }
}

/// One full look at one tool on this Mac.
public struct CLIToolReport: Sendable, Equatable {
    public let kind: CLIToolKind
    public let statuses: [CLIToolStatus]
    /// The tool-wide settings the verdicts were made under, for its group header.
    public let context: Context

    public enum Context: Sendable, Equatable {
        case claudeCode(ClaudeCodeSettings)
        case bub
        case fx(FxSettings)
    }

    public init(kind: CLIToolKind, statuses: [CLIToolStatus], context: Context) {
        self.kind = kind
        self.statuses = statuses
        self.context = context
    }
}

/// What a local, network-free look finds: which installs there are and the
/// version each one reads as. Enough to reserve the popover row and to tell that
/// something changed since the last check.
public struct CLIToolSighting: Sendable, Hashable {
    public let kind: CLIToolKind
    public let path: String
    public let version: String?

    public init(kind: CLIToolKind, path: String, version: String?) {
        self.kind = kind
        self.path = path
        self.version = version
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
}

public enum CLIToolReleaseNotesError: Error, Equatable {
    case http(Int)
    /// The document came back but no longer looks like release notes — kept apart
    /// from a network failure so a format drift is not mistaken for a blip.
    case noSections
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

    /// The tool's release notes, newest first, one entry per version. The app
    /// cuts them to one install with `CLIToolChangelog.relevant`.
    func releaseNotes(force: Bool) async throws -> Changelog
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
