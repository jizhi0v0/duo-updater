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

/// An installed package from a third-party tap that Homebrew did **not** evaluate
/// against that tap — so no read in this service can say whether it's outdated.
///
/// Since Homebrew 6.0.0 brew refuses to load formulae/casks from taps the user
/// hasn't trusted (https://docs.brew.sh/Tap-Trust), and its listing commands skip
/// them without a word. Measured 2026-09-13 on Homebrew 7.0.0, tap `oven-sh/bun`
/// untrusted, bun 1.3.14 installed, the tap at 1.4.2: `brew leaves`,
/// `brew outdated --formula --json=v2` and `brew info --json=v2 --installed` all
/// exited 0 with bun simply absent (`Formula.installed` rescues every load error),
/// while `brew list --formula --full-name` still printed `oven-sh/bun/bun`.
/// Casks fail differently (same day, an app-less fixture cask in an untrusted local
/// tap, installed 1.0, tap at 2.0): `outdated --cask` omits it, but `info --installed`
/// still lists it — loaded from the copy stored in the Caskroom at install time, with
/// `tap: null` (every other installed cask had a tap), the INSTALLED version and
/// `outdated: false`. `list --cask --full-name` loads the same copy, so it prints the
/// bare token; only the Caskroom install receipt still names the tap.
///
/// Without this type both shapes read as "nothing to do": the formula has no row at
/// all, the cask has no update.
public struct BrewUncheckedPackage: Sendable, Identifiable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// `brew tap-info` reports the tap as not trusted.
        case tapNotTrusted
        /// Brew didn't read it from its tap for some other reason (the tap is
        /// trusted or gone, the definition is broken…). Not narrowed further — we
        /// only know brew's verdict, not its exception.
        case unreadable
    }

    public var id: String { "\(kind.rawValue):\(fullName)" }
    /// Tap-qualified: `oven-sh/bun/bun`. Bare only for a cask whose install receipt
    /// names no tap.
    public let fullName: String
    public let kind: BrewOutdatedFormula.Kind
    public let installedVersion: String
    public let reason: Reason

    public init(
        fullName: String, kind: BrewOutdatedFormula.Kind,
        installedVersion: String, reason: Reason
    ) {
        self.fullName = fullName
        self.kind = kind
        self.installedVersion = installedVersion
        self.reason = reason
    }

    /// `bun` for `oven-sh/bun/bun`.
    public var name: String { BrewFormulaService.shortName(fullName) }
    /// `oven-sh/bun` for `oven-sh/bun/bun`; nil when `fullName` is bare.
    public var tap: String? {
        let parts = fullName.split(separator: "/")
        return parts.count == 3 ? parts.prefix(2).joined(separator: "/") : nil
    }

    /// The command that grants trust to exactly this package — the narrowest grant,
    /// which is what Homebrew's docs recommend. Shown for the user to run; this app
    /// never runs it, trusting a tap is the user's security decision.
    public var trustCommand: String { "brew trust --\(kind.rawValue) \(fullName)" }
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
    /// `ChildProcess.run` throwing), and a returned tuple is the definite outcome —
    /// the *caller* decides what a nonzero `status` means (an error for
    /// `outdated()`, an empty read for `runReading`).
    ///
    /// `HomebrewInstaller.brewPath()` is asked only by the real executor
    /// (`executor(brewPath:)` below, wired in `init()`), not by
    /// `outdated()` / `installedLeaves()` / `outdatedCasks()` themselves — those
    /// three used to each ask it directly before running the subprocess, which
    /// would leave a fake executor unable to answer "no brew" on its own and would
    /// leave a test for "did the two reads overlap" quietly asking the real host
    /// underneath its own fixture. See CLAUDE.md "测试不能问宿主".
    typealias Executor = @Sendable ([String]) async throws -> (status: Int32, stdout: Data)?

    /// The tap a cask's Caskroom install receipt records (`source.tap`), or nil.
    /// A seam for the same reason as `Executor`: the real one reads the disk.
    typealias CaskReceiptTap = @Sendable (_ token: String) -> String?
    /// `installsAnApp(caskToken:)`, injectable for the same reason.
    typealias CaskInstallsAnApp = @Sendable (_ token: String) -> Bool

    private let executor: Executor
    private let caskReceiptTap: CaskReceiptTap
    private let caskInstallsAnApp: CaskInstallsAnApp

    public init() {
        self.executor = Self.executor(brewPath: HomebrewInstaller.brewPath)
        self.caskReceiptTap = { Self.realCaskReceiptTap($0) }
        self.caskInstallsAnApp = { Self.installsAnApp(caskToken: $0) }
    }

    /// Test seam — not public, this is a harness detail. `BrewFormulaServiceTests`
    /// injects a fake executor to control timing and outcomes deterministically,
    /// instead of depending on Homebrew being installed and on real wall-clock
    /// subprocess latency.
    init(
        executor: @escaping Executor,
        caskReceiptTap: @escaping CaskReceiptTap = { _ in nil },
        caskInstallsAnApp: @escaping CaskInstallsAnApp = { _ in false }
    ) {
        self.executor = executor
        self.caskReceiptTap = caskReceiptTap
        self.caskInstallsAnApp = caskInstallsAnApp
    }

    public enum BrewError: LocalizedError {
        case brewNotFound
        case failed(code: Int32, output: String)

        public var errorDescription: String? {
            switch self {
            case .brewNotFound:
                return "Homebrew isn’t installed (no brew found in the usual locations)."
            case .failed(let code, let output):
                return HomebrewInstaller.failureDescription(code: code, output: output)
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
        // `HOMEBREW_NO_AUTO_UPDATE=1` (set inside `executor(brewPath:)`) keeps this a pure
        // read of local state — never an implicit `brew update`.
        //
        // The spawn and the wait happen inside `executor`, which awaits the child
        // rather than parking a thread (see `ChildProcess`), so this actor is free
        // while `brew` runs.
        let outcome = try await executor(["outdated", "--formula", "--json=v2"])
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
        // genuinely overlap because `runReading` awaits the executor, which awaits
        // the child (see `ChildProcess`): the `await` inside it is a real
        // suspension point, so this actor is free to start the second `async let`
        // while the first's subprocess is still running.
        //
        // Before `runReading` hopped off the actor (through `offCooperativePool`,
        // until `ChildProcess` replaced that hop), its body had no suspension point
        // at all — the whole Process spawn/read/wait ran synchronously on this
        // actor — so the second `async let` could not even begin until the first
        // one returned.
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
                // `leaves` prints a tap formula tap-qualified (`oven-sh/bun/bun`),
                // `list --versions` keys it by rack name (`bun`).
                installedVersion: versions[Self.shortName(name)] ?? "—",
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

    /// The last path component of a possibly tap-qualified name: `bun` for
    /// `oven-sh/bun/bun`, `ripgrep` for `ripgrep`. That's the Cellar rack name.
    static func shortName(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    /// Installed third-party-tap packages brew did not read from their tap — see
    /// `BrewUncheckedPackage`. Includes dependencies as well as leaves: brew can't
    /// tell which is which without loading the formula, and an unchecked dependency
    /// is exactly as unchecked.
    ///
    /// The verdict is brew's own, not a re-implementation of its trust rules
    /// (per-item trust, remote matching, `HOMEBREW_NO_REQUIRE_TAP_TRUST` all change
    /// what loads). A formula counts when `brew list --formula --full-name` (read
    /// from the keg's receipt, no loading) names it tap-qualified and
    /// `brew info --json=v2 --installed` lacks it. A cask counts when `info` lists it
    /// with `tap: null`, i.e. brew fell back to the Caskroom copy. `tap-info` and the
    /// cask's install receipt only supply the label and the tap name.
    ///
    /// Fails closed: a failed `brew info` read (which `runReading` turns into "")
    /// doesn't parse, and that yields [] — never "brew loaded none of them, so every
    /// listed package is unchecked". A failed `list` read yields no candidates.
    public func uncheckedPackages() async -> [BrewUncheckedPackage] {
        async let formulaNames = runReading(["list", "--formula", "--full-name"])
        async let installedInfo = runReading(["info", "--json=v2", "--installed"])
        // Not `list --cask …` for anything: measured, `--versions` exits 1 outright
        // ("Refusing to load cask … from untrusted tap") when any installed cask is
        // untrusted, and `--full-name` prints such a cask bare.
        async let versionList = runReading(["list", "--formula", "--versions"])

        let candidates = Self.uncheckedCandidates(
            formulaFullNames: Self.parseLines(await formulaNames),
            installedInfo: Data(await installedInfo.utf8),
            formulaVersions: Self.parseVersions(await versionList),
            caskReceiptTap: caskReceiptTap,
            caskInstallsAnApp: caskInstallsAnApp)
        guard !candidates.isEmpty else { return [] }

        // `--installed` rather than naming the taps: `tap-info` on a tap that no
        // longer exists would fail the whole read and mislabel the others.
        let tapInfo = await runReading(["tap-info", "--json=v1", "--installed"])
        return Self.label(candidates, untrustedTaps: Self.parseUntrustedTaps(Data(tapInfo.utf8)))
    }

    /// Pure core of `uncheckedPackages()`: every candidate carries `.unreadable`
    /// until `label` looks at `tap-info`. `installedInfo` that doesn't parse → []
    /// (fail closed).
    static func uncheckedCandidates(
        formulaFullNames: [String],
        installedInfo: Data,
        formulaVersions: [String: String],
        caskReceiptTap: (String) -> String?,
        caskInstallsAnApp: (String) -> Bool
    ) -> [BrewUncheckedPackage] {
        guard
            let root = try? JSONSerialization.jsonObject(with: installedInfo) as? [String: Any],
            let formulae = root["formulae"] as? [[String: Any]],
            let casks = root["casks"] as? [[String: Any]]
        else { return [] }

        // Official formulae are listed bare (`ripgrep`); only tap-qualified ones can
        // be from an untrusted tap. (A bare one missing from `info` failed to load
        // for some other reason — not this type's business.)
        //
        // Matched by rack name, not full name: `list --full-name` takes the tap from
        // the keg's receipt, but a formula that has since moved taps is loaded by
        // bare name (`Formulary.from_keg` retries without the tap), so `info` says
        // `foo` for a keg `list` calls `someuser/tap/foo` — checked, not unchecked.
        // One rack per name, so a loaded rack name can't belong to a different keg.
        let loadedRacks = Set(formulae.compactMap { $0["name"] as? String })
        var out: [BrewUncheckedPackage] = []
        for fullName in formulaFullNames
        where fullName.split(separator: "/").count == 3 && !loadedRacks.contains(shortName(fullName)) {
            out.append(BrewUncheckedPackage(
                fullName: fullName, kind: .formula,
                installedVersion: formulaVersions[shortName(fullName)] ?? "—",
                reason: .unreadable))
        }

        // `tap` is set for a cask read from its tap or the API (`homebrew/cask`), and
        // JSON null when brew fell back to the Caskroom copy. `NSNull` is what a
        // present-but-null key decodes to; an absent key is not that signal.
        //
        // A cask that installs an app is skipped for the same reason `outdatedCasks()`
        // skips it: the app has its own row, possibly checked by another source.
        for cask in casks where cask["tap"] is NSNull {
            guard let token = cask["token"] as? String, !caskInstallsAnApp(token) else { continue }
            let fullName = caskReceiptTap(token).map { "\($0)/\(token)" } ?? token
            out.append(BrewUncheckedPackage(
                fullName: fullName, kind: .cask,
                installedVersion: (cask["installed"] as? String) ?? "—",
                reason: .unreadable))
        }

        return out.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Names of installed taps `brew tap-info --json=v1` marks `"trusted": false`.
    /// That field is tap-level only (`Trust.trusted_tap?`), which is fine here: it
    /// only labels packages brew has already declined to read.
    static func parseUntrustedTaps(_ data: Data) -> Set<String> {
        guard let taps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return Set(taps.compactMap { t in
            (t["trusted"] as? Bool) == false ? t["name"] as? String : nil
        })
    }

    static func label(
        _ candidates: [BrewUncheckedPackage], untrustedTaps: Set<String>
    ) -> [BrewUncheckedPackage] {
        candidates.map { p in
            BrewUncheckedPackage(
                fullName: p.fullName, kind: p.kind, installedVersion: p.installedVersion,
                reason: p.tap.map(untrustedTaps.contains) == true ? .tapNotTrusted : .unreadable)
        }
    }

    /// `source.tap` from `<Caskroom>/<token>/.metadata/INSTALL_RECEIPT.json`
    /// (measured present on both an API-installed and a local-tap cask).
    static func realCaskReceiptTap(
        _ token: String,
        caskroomPaths: [String] = BrewLocalInventory.defaultCaskroomPaths
    ) -> String? {
        for root in caskroomPaths {
            let url = URL(fileURLWithPath: root)
                .appendingPathComponent(token)
                .appendingPathComponent(".metadata/INSTALL_RECEIPT.json")
            guard
                let data = try? Data(contentsOf: url),
                let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let source = receipt["source"] as? [String: Any],
                let tap = source["tap"] as? String, !tap.isEmpty
            else { continue }
            return tap
        }
        return nil
    }

    /// Run a read-only `brew` subcommand and return stdout, never triggering an
    /// implicit `brew update`. Returns "" on any failure — no brew, the process
    /// failing to start, or a nonzero exit — the callers treat a missing read as
    /// "nothing to show" rather than surfacing an error.
    ///
    /// The spawn and the wait happen inside `executor`, awaited. That suspension
    /// point is also what lets two `runReading` calls (the `async let` pair in
    /// `installedLeaves()`) genuinely overlap instead of serializing behind this
    /// actor — see the comment there.
    private func runReading(_ arguments: [String]) async -> String {
        let outcome: (status: Int32, stdout: Data)?
        do {
            outcome = try await executor(arguments)
        } catch {
            return ""
        }
        guard let outcome, outcome.status == 0 else { return "" }
        return String(data: outcome.stdout, encoding: .utf8) ?? ""
    }

    /// The real `Executor`: locate `brew`, spawn it read-only (never an implicit
    /// `brew update`), and await its exit.
    ///
    /// This is the ONLY place `HomebrewInstaller.brewPath()` is consulted for the
    /// three read paths in this actor — keeping that check out of `outdated()` /
    /// `installedLeaves()` / `outdatedCasks()` themselves is what lets a fake
    /// `Executor` answer "no brew" on its own, without a test asking the actual
    /// host underneath its own fixture.
    ///
    /// stderr is discarded, as it was: `ChildProcess` drains it either way, so a
    /// long run of deprecation warnings or a Ruby backtrace cannot wedge the
    /// stdout read — the deadlock the old `nullDevice` here was avoiding.
    ///
    /// Runs to completion if the caller is cancelled, although it only reads. The
    /// caller does not stop when cancelled: `AppListModel.refreshBrewFormulae` runs
    /// from a view's `.task`, is cancelled when the popover closes, and goes on to
    /// write what these reads returned — a killed `brew` reads as `""` in
    /// `runReading`, so the Brew tree, the outdated badges and the unchecked list
    /// would all be replaced with empty ones. The Dispatch hop this replaced could
    /// not be cancelled, so those writes always carried real data.
    ///
    /// `brewPath` is a parameter so a test can hand in an invented script and still
    /// exercise this real executor, cancellation policy included.
    static func executor(brewPath: @escaping @Sendable () -> String?) -> Executor {
        { arguments in
            guard let brew = brewPath() else { return nil }
            var env = ProcessInfo.processInfo.environmentWithSystemProxy
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            let outcome = try await ChildProcess.run(
                brew, arguments, environment: env,
                standardError: .discard, onCancel: .runToCompletion)
            return (outcome.terminationStatus, outcome.standardOutput)
        }
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

    /// Name of the formula a `brew upgrade` success line reports, or nil for any
    /// other line. brew prints exactly one such line per formula it finishes
    /// installing, so counting them tracks bulk progress.
    ///
    /// The line is `FormulaInstaller#summary`: `[<badge>  ]<keg>: <abv>[, built in …]`,
    /// e.g. `🍺  /opt/homebrew/Cellar/xz/5.8.4: 96 files, 2.7MB`. The badge is
    /// `HOMEBREW_INSTALL_BADGE` (any text) and is dropped under `HOMEBREW_NO_EMOJI`,
    /// so the prefix is not the discriminator. What is: the keg path followed
    /// directly by `: ` and a `Pathname#abv` size. Every other `abv` caller puts the
    /// size in parentheses instead — `brew cleanup`'s
    /// `Removing: <keg>... (96 files, 2.7MB)`, which follows a successful upgrade and
    /// used to count the same formula a second time, `Would remove: <keg> (…)`, and
    /// `Uninstalling <keg>... (…)`. (Homebrew 7.0.0 source; `abv` omits
    /// `N files, ` when the keg has a single file.)
    public static func pouredFormula(fromLine line: String) -> String? {
        let ns = line as NSString
        guard let match = pouredLinePattern.firstMatch(
            in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static let pouredLinePattern = try! NSRegularExpression(
        pattern: #"/Cellar/([^/\s]+)/[^/\s:]+: (?:[\d,]+ files, )?\d+(?:\.\d)?[KMG]?B(?:, built in .+)?\s*$"#)

    /// Update Homebrew itself (`brew update`), with the user's shell-exported
    /// `HOMEBREW_*` variables (`HomebrewSelfUpdateCheck.Outcome.environment`) so it
    /// updates the way their terminal would — e.g. to `main` rather than to a tag
    /// when `HOMEBREW_DEVELOPER` is set only in their shell.
    public func updateHomebrew(
        environment: [String: String],
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        try await run(["update"], environment: environment, onOutput: onOutput)
    }

    /// Shared streaming runner for the `brew upgrade …` / `brew update` variants above.
    private func run(
        _ arguments: [String],
        environment extra: [String: String] = [:],
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        guard let brew = HomebrewInstaller.brewPath() else { throw BrewError.brewNotFound }

        // Non-interactive so brew never blocks on a prompt we can't answer. We do
        // NOT set HOMEBREW_NO_AUTO_UPDATE here: on the real upgrade, letting brew
        // refresh first is correct — it's what a terminal `brew upgrade` does, and
        // it ensures we land the genuine latest even if the pre-count was stale.
        var env = ProcessInfo.processInfo.environmentWithSystemProxy
        env.merge(extra) { _, user in user }
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"

        // Lines, not chunks, and until the output ends, not just the exit — see
        // `StreamedLines`. Runs to completion if the caller is cancelled: this is
        // brew replacing what is installed, and a SIGKILL halfway is worse than
        // letting it finish (the `terminationHandler` wait it replaced was not
        // cancellable either).
        let (outcome, output) = try await StreamedLines.run(
            brew, arguments, environment: env, onOutput: onOutput)

        guard outcome.succeeded else {
            throw BrewError.failed(code: outcome.terminationStatus, output: output)
        }
    }
}
