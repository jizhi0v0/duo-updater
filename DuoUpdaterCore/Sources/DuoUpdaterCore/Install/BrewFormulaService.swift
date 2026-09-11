import Foundation

/// One outdated Homebrew package this surface is responsible for.
///
/// Formulae always are. Casks are the exception rather than the rule: a GUI cask
/// installs a `.app`, which the scanner finds and `HomebrewCaskSource` surfaces as
/// its own row, so folding it in here would double-count it. But **a cask that
/// installs no app** — a CLI (`codex`, `android-platform-tools`), a font, a driver
/// — has no app row and so had no home at all: invisible to the per-app list
/// because there's no bundle to scan, and invisible here because this service used
/// to be `--formula` only. Those are included; see `installsAnApp(caskToken:)` for
/// how the line is drawn.
///
/// Upgrades stay explicitly scoped either way — `--formula` for formulae, and
/// `--cask <token>` naming exactly the tokens listed here. Never a bare
/// `brew upgrade --cask`, which would reach GUI casks this surface doesn't own
/// (and could `--force` re-adopt a vendor-installed app).
public struct BrewOutdatedFormula: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case formula
        case cask
    }

    public var id: String { name }
    public let name: String
    public let installedVersion: String
    public let currentVersion: String
    public var kind: Kind = .formula

    public init(
        name: String, installedVersion: String, currentVersion: String,
        kind: Kind = .formula
    ) {
        self.name = name
        self.installedVersion = installedVersion
        self.currentVersion = currentVersion
        self.kind = kind
    }
}

/// A top-level installed formula (a `brew leaves` entry — one you installed on
/// purpose, not a dependency pulled in for something else), with the newer version
/// available when there is one. Drives the workbench Brew tree, which mirrors the
/// Apps tree by listing everything you manage, not just what's outdated.
public struct BrewInstalledFormula: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let installedVersion: String
    /// The version `brew outdated` says is available, or nil when up to date.
    public let availableVersion: String?
    public var hasUpdate: Bool { availableVersion != nil }
}

/// Reads outdated Homebrew formulae and runs a formula-only `brew upgrade`.
///
/// Detection reads the *local* tap (`brew outdated` does not auto-update), so the
/// count can lag the absolute latest until the user's next `brew update`. That's
/// an acceptable trade for a CLI-tools convenience: no subprocess writes to the
/// user's tap on a mere check, and `brew` itself auto-updates on the actual
/// `brew upgrade` (>24h since last update) — so clicking Upgrade still lands the
/// real latest even if the pre-count was conservative.
public actor BrewFormulaService {

    /// A read-only `brew` invocation, factored out so tests can control timing and
    /// outcomes without spawning a real subprocess or asking the host whether
    /// Homebrew is installed. `nil` means "no brew" (never throws for that case), a
    /// thrown error means the process itself couldn't start (mirrors
    /// `Process.run()` throwing), and a returned tuple is the definite outcome —
    /// the *caller* decides what a nonzero `status` means (an error for
    /// `outdated()`, an empty read for `runReading`).
    ///
    /// `HomebrewInstaller.brewPath()` lives INSIDE `realExecutor` below, not in
    /// `outdated()` / `installedLeaves()` / `outdatedCasks()` themselves — those
    /// three used to each ask it directly before running the subprocess, which
    /// would leave a fake executor unable to answer "no brew" on its own and would
    /// leave a test for "did the two reads overlap" quietly asking the real host
    /// underneath its own fixture. See CLAUDE.md "测试不能问宿主".
    typealias Executor = @Sendable ([String]) throws -> (status: Int32, stdout: Data)?

    private let executor: Executor

    public init() {
        self.executor = Self.realExecutor
    }

    /// Test seam — not public, this is a harness detail. `BrewFormulaServiceTests`
    /// injects a fake executor to control timing and outcomes deterministically,
    /// instead of depending on Homebrew being installed and on real wall-clock
    /// subprocess latency.
    init(executor: @escaping Executor) {
        self.executor = executor
    }

    public enum BrewError: LocalizedError {
        case brewNotFound
        case failed(code: Int32, output: String)

        public var errorDescription: String? {
            switch self {
            case .brewNotFound:
                return "Homebrew isn’t installed (no brew found in the usual locations)."
            case .failed(let code, let output):
                let tail = output.split(separator: "\n").suffix(3).joined(separator: " ")
                return "brew failed (\(code)): \(tail)"
            }
        }
    }

    /// True when `brew` is present — used to hide the whole surface on machines
    /// without Homebrew rather than showing an empty/erroring row.
    public static var isAvailable: Bool { HomebrewInstaller.brewPath() != nil }

    /// Run `brew outdated --formula --json=v2` and parse the outdated formulae.
    /// Returns an empty list (never throws) when brew is absent or nothing is
    /// outdated, so a missing/clean machine simply shows no row.
    public func outdated() async throws -> [BrewOutdatedFormula] {
        // --formula: casks are HomebrewCaskSource's job. --json=v2: stable schema.
        // `HOMEBREW_NO_AUTO_UPDATE=1` (set inside `realExecutor`) keeps this a pure
        // read of local state — never an implicit `brew update`.
        //
        // The spawn/read/wait happens inside `executor`, off this actor via
        // `offCooperativePool` — doing that sequence directly here would occupy one
        // of the cooperative pool's few threads for the whole subprocess. See
        // `offCooperativePool`'s doc comment for why that matters.
        let exec = executor
        let outcome = try await offCooperativePool({
            try exec(["outdated", "--formula", "--json=v2"])
        })
        guard let outcome else { return [] }

        guard outcome.status == 0 else {
            let text = String(data: outcome.stdout, encoding: .utf8) ?? ""
            throw BrewError.failed(code: outcome.status, output: text)
        }

        return Self.parse(outcome.stdout)
    }

    /// Fast local inventory: top-level installed formulae (`brew leaves`) with their
    /// installed version (`brew list --formula --versions`), but WITHOUT update info —
    /// `availableVersion` is always nil. This is the cheap first phase of a two-phase
    /// load: two quick local reads, no `brew outdated`, so the workbench Brew tree can
    /// paint immediately (the way the Apps tree shows apps before their update checks
    /// land). The caller fills in the update badges afterward by merging in
    /// `outdated()` via `Self.merge(_:outdated:)`. Sorted by name. Returns an empty
    /// list (never throws) when brew is absent, so a brew-less machine shows no tree.
    ///
    /// `leaves` deliberately excludes dependency-only formulae: the hundreds of
    /// transitive packages brew installs to satisfy others would bury the list, and
    /// the user only cares about what they asked for (the analog of "apps you have").
    public func installedLeaves() async throws -> [BrewInstalledFormula] {
        // The two reads are independent and each spawns a brew subprocess, and they
        // genuinely overlap now that `runReading` hops off the actor for the
        // blocking part (see `offCooperativePool`): the `await` inside it is a real
        // suspension point, so this actor is free to start the second `async let`
        // while the first's subprocess is still running.
        //
        // Before that hop, `runReading`'s body had no suspension point at all — the
        // whole Process spawn/read/wait ran synchronously on this actor — so the
        // second `async let` could not even begin until the first one returned.
        // This comment used to claim the two reads ran concurrently; they did not.
        // Measured 2026-09-11, during review of this fix, against the real
        // (pre-fix) BrewFormulaService on a 14-core M3 Max under heavy load
        // (1-minute load average 10-20): two reads on the un-hopped actor took
        // 1357-1439 ms whether called in sequence or as an `async let` pair — i.e.
        // the pair bought nothing — while the identical two `brew` commands run on
        // two separate Dispatch threads took 760-783 ms.
        async let leafNames = runReading(["leaves"])
        async let versionList = runReading(["list", "--formula", "--versions"])

        let leaves = Set(Self.parseLines(await leafNames))
        guard !leaves.isEmpty else { return [] }
        let versions = Self.parseVersions(await versionList)

        return leaves.map { name in
            BrewInstalledFormula(
                name: name,
                installedVersion: versions[name] ?? "—",
                availableVersion: nil)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Re-stamp a fast `installedLeaves()` inventory with the available upgrades from
    /// `outdated()`, re-sorting so rows with an update float to the top — the second
    /// phase of the two-phase load. Pure (no subprocess), so it's trivially testable
    /// and runs instantly once both reads are in hand.
    public static func merge(
        _ inventory: [BrewInstalledFormula],
        outdated: [BrewOutdatedFormula]
    ) -> [BrewInstalledFormula] {
        let available = Dictionary(
            outdated.map { ($0.name, $0.currentVersion) },
            uniquingKeysWith: { a, _ in a })
        return inventory.map { f in
            BrewInstalledFormula(
                name: f.name,
                installedVersion: f.installedVersion,
                availableVersion: available[f.name])
        }
        .sorted { lhs, rhs in
            if lhs.hasUpdate != rhs.hasUpdate { return lhs.hasUpdate }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// `name` → installed version, parsed from `brew list --formula --versions`
    /// (each line is "name v1 [v2 …]"; we keep the last/newest version token).
    static func parseVersions(_ output: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard let name = parts.first, parts.count >= 2 else { continue }
            out[String(name)] = String(parts.last!)
        }
        return out
    }

    /// Non-empty whitespace-trimmed lines, for the one-name-per-line `brew leaves`.
    static func parseLines(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Run a read-only `brew` subcommand and return stdout, never triggering an
    /// implicit `brew update`. Returns "" on any failure — no brew, the process
    /// failing to start, or a nonzero exit — the callers treat a missing read as
    /// "nothing to show" rather than surfacing an error.
    ///
    /// The spawn/read/wait happens inside `executor`, off this actor via
    /// `offCooperativePool`. That suspension point is also what lets two
    /// `runReading` calls (the `async let` pair in `installedLeaves()`) genuinely
    /// overlap instead of serializing behind this actor — see the comment there.
    private func runReading(_ arguments: [String]) async -> String {
        let exec = executor
        let outcome: (status: Int32, stdout: Data)?
        do {
            outcome = try await offCooperativePool({ try exec(arguments) })
        } catch {
            return ""
        }
        guard let outcome, outcome.status == 0 else { return "" }
        return String(data: outcome.stdout, encoding: .utf8) ?? ""
    }

    /// The real `Executor`: locate `brew`, spawn it read-only (never an implicit
    /// `brew update`), and block until it exits.
    ///
    /// This is the ONLY place that calls `HomebrewInstaller.brewPath()` for the
    /// three read paths in this actor — keeping that check out of `outdated()` /
    /// `installedLeaves()` / `outdatedCasks()` themselves is what lets a fake
    /// `Executor` answer "no brew" on its own, without a test asking the actual
    /// host underneath its own fixture.
    ///
    /// Always runs off the actor: called only from inside `offCooperativePool` (in
    /// `outdated()` and `runReading`), never directly from actor-isolated code —
    /// this function itself blocks synchronously.
    private static func realExecutor(_ arguments: [String]) throws -> (status: Int32, stdout: Data)? {
        guard let brew = HomebrewInstaller.brewPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environmentWithSystemProxy
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        // nullDevice, not Pipe(): an undrained stderr pipe deadlocks once its
        // 64KB buffer fills — brew blocks writing (a long run of deprecation
        // warnings or a Ruby backtrace is enough), we block forever in the
        // `readDataToEndOfFile()` below waiting on stdout, which brew never
        // reaches. Same failure shape as `AppListModel.runningBuildVersions`'s
        // `lsappinfo` call, which documents it at the call site. `offCooperativePool`
        // is not cancellable, so this would leak a Dispatch thread and a wedged
        // `brew` process — and since this is what the Brew tree loads on, the
        // menu's Brew list would simply never finish loading.
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    /// Outdated casks that install **no app** — the ones nothing else covers. See
    /// `BrewOutdatedFormula` for why GUI casks are excluded, and
    /// `installsAnApp(caskToken:)` for how that's decided.
    ///
    /// Non-greedy on purpose: `--greedy` would pull in `auto_updates` casks, whose
    /// update channel is the app's own updater, not brew.
    ///
    /// No direct `HomebrewInstaller.brewPath()` check here — `runReading` asks the
    /// executor, the one seam a test can control (see `Executor`); an absent brew
    /// reaches this the same way any other empty read does, via `output == ""`.
    public func outdatedCasks() async throws -> [BrewOutdatedFormula] {
        let output = await runReading(["outdated", "--cask", "--json=v2"])
        guard let data = output.data(using: .utf8) else { return [] }
        return Self.parseCasks(data).filter { !Self.installsAnApp(caskToken: $0.name) }
    }

    /// Whether a cask's staged artifacts contain a `.app` (or a `.pkg`, which
    /// generally installs one). Read straight off the Caskroom rather than from the
    /// cask definition, so it needs no network and no catalog load.
    ///
    /// True → the app is on disk, the scanner finds it, and it already has its own
    /// row; this surface must not list it too. False → a CLI, a font, a driver:
    /// nothing else can show it.
    ///
    /// Known edge: a cask whose pkg is deleted from the Caskroom after installing
    /// would read as "no app" and get a second row here. Benign (a duplicate row,
    /// never a missed update or a wrong install), and the upgrade path stays correct
    /// either way — the token is genuinely brew-installed, or `brew outdated`
    /// wouldn't have listed it.
    static func installsAnApp(
        caskToken: String,
        caskroomPaths: [String] = BrewLocalInventory.defaultCaskroomPaths
    ) -> Bool {
        let fm = FileManager.default
        let roots = caskroomPaths
            .map { URL(fileURLWithPath: $0).appendingPathComponent(caskToken) }
        for root in roots {
            guard let versions = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            else { continue }
            for version in versions {
                guard let staged = try? fm.contentsOfDirectory(
                    at: version, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                else { continue }
                for entry in staged {
                    let ext = entry.pathExtension.lowercased()
                    if ext == "app" || ext == "pkg" || ext == "mpkg" { return true }
                }
            }
        }
        return false
    }

    /// Parse the `casks` array of an `outdated --json=v2` payload. Same shape as
    /// `parse`, minus pinned entries — a pinned cask is deliberately held back, so
    /// offering to upgrade it would fight the user's own decision.
    static func parseCasks(_ data: Data) -> [BrewOutdatedFormula] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let casks = root["casks"] as? [[String: Any]]
        else { return [] }

        var out: [BrewOutdatedFormula] = []
        for c in casks {
            guard
                let name = c["name"] as? String,
                let current = c["current_version"] as? String,
                let installed = (c["installed_versions"] as? [String])?.last,
                (c["pinned"] as? Bool) != true
            else { continue }
            out.append(BrewOutdatedFormula(
                name: name,
                installedVersion: installed,
                currentVersion: current,
                kind: .cask
            ))
        }
        return out
    }

    /// Parse the `--json=v2` payload's `formulae` array. Tolerant: skips any entry
    /// missing a name or a usable installed/current version rather than failing the
    /// whole list.
    static func parse(_ data: Data) -> [BrewOutdatedFormula] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let formulae = root["formulae"] as? [[String: Any]]
        else { return [] }

        var out: [BrewOutdatedFormula] = []
        for f in formulae {
            guard
                let name = f["name"] as? String,
                let current = f["current_version"] as? String,
                let installed = (f["installed_versions"] as? [String])?.last
            else { continue }
            out.append(BrewOutdatedFormula(
                name: name,
                installedVersion: installed,
                currentVersion: current
            ))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// Run `brew upgrade --formula`, streaming output lines. Upgrades every
    /// outdated formula at once — the bulk action, mirroring a bare terminal
    /// `brew upgrade` but scoped so casks (and their distribution channel) are
    /// never touched.
    public func upgradeAll(
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        try await run(["upgrade", "--formula"], onOutput: onOutput)
    }

    /// Upgrade specific casks by token (`brew upgrade --cask <tokens…>`).
    ///
    /// Always named explicitly — never a bare `brew upgrade --cask`, which would
    /// sweep GUI casks this surface doesn't own. Callers pass only the app-less
    /// casks `outdatedCasks()` returned. A no-op on an empty list so the caller can
    /// call it unconditionally.
    public func upgrade(
        casks tokens: [String],
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        guard !tokens.isEmpty else { return }
        try await run(["upgrade", "--cask"] + tokens, onOutput: onOutput)
    }

    /// Upgrade a single formula by name (`brew upgrade --formula <name>`). The
    /// `--formula` flag disambiguates a token that also names a cask, so this can
    /// never touch the cask channel.
    public func upgrade(
        formula name: String,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        try await run(["upgrade", "--formula", name], onOutput: onOutput)
    }

    /// Shared streaming runner for the `brew upgrade …` variants above.
    private func run(
        _ arguments: [String],
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        guard let brew = HomebrewInstaller.brewPath() else { throw BrewError.brewNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = arguments
        // Non-interactive so brew never blocks on a prompt we can't answer. We do
        // NOT set HOMEBREW_NO_AUTO_UPDATE here: on the real upgrade, letting brew
        // refresh first is correct — it's what a terminal `brew upgrade` does, and
        // it ensures we land the genuine latest even if the pre-count was stale.
        var env = ProcessInfo.processInfo.environmentWithSystemProxy
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collected = OutputBox()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            collected.append(text)
            for line in text.split(separator: "\n") {
                onOutput(String(line))
            }
        }

        try process.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        handle.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw BrewError.failed(code: process.terminationStatus, output: collected.text)
        }
    }

    /// Thread-safe accumulator for output streamed off a background readability
    /// handler (same pattern as `HomebrewInstaller`).
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = ""
        func append(_ s: String) { lock.lock(); buffer += s; lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return buffer }
    }
}
