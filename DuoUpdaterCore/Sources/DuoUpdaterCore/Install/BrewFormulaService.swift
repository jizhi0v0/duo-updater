import Foundation

/// One outdated Homebrew *formula* (a command-line package — NOT a cask). Casks
/// are deliberately out of scope here: GUI casks are already surfaced per-app by
/// `HomebrewCaskSource`, and folding them in again would double-count them. This
/// service mirrors the user's habit of running a bare `brew upgrade` in the
/// terminal, but scoped to `--formula` so it never touches the cask channel (and
/// so can never `--force` re-adopt a vendor-installed app the way an unscoped
/// upgrade could).
public struct BrewOutdatedFormula: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let installedVersion: String
    public let currentVersion: String
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

    public init() {}

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
        guard let brew = HomebrewInstaller.brewPath() else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        // --formula: casks are HomebrewCaskSource's job. --json=v2: stable schema.
        process.arguments = ["outdated", "--formula", "--json=v2"]
        // Never let a check trigger an implicit `brew update` (slow, writes the
        // user's tap). Keep it a pure read of the local state.
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()  // swallow stderr noise

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BrewError.failed(code: process.terminationStatus, output: text)
        }

        return Self.parse(data)
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
        guard HomebrewInstaller.brewPath() != nil else { return [] }

        // The two reads are independent and each spawns a brew subprocess, so run
        // them concurrently rather than serializing the latency.
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
    /// implicit `brew update`. Returns "" on any failure — the callers treat a
    /// missing read as "nothing to show" rather than surfacing an error.
    private func runReading(_ arguments: [String]) async -> String {
        guard let brew = HomebrewInstaller.brewPath() else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
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
        var env = ProcessInfo.processInfo.environment
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
