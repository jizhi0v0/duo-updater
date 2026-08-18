import Foundation
import DuoUpdaterCore

// Sweep every hand-written recipe against its live endpoint and report the ones
// that can no longer do their job.
//
// This exists because recipe breakage is currently found by accident: a vendor
// rewrites their download page, the probe quietly returns nil, the app degrades
// that app to "unknown", and nobody notices until someone happens to look. The
// existing live tests can't catch it either — they're written network-tolerant
// (`if let v = try await …`), so the nil a broken pattern produces passes.
//
// It runs the production diagnostic paths (`VendorProbeSource.probeDiagnostic`,
// `GitHubReleasesSource.resolveDiagnostic`, `ChangelogService.loadUncached`) and
// it NEVER downloads an installer: those resolve installer URLs (a HEAD at most)
// but never call `Downloader` or `VendorInstaller`.

public struct VerifyOptions: Sendable {
    public init() {}
    /// Restrict the sweep to recipes whose bundle id or recipe id contains one
    /// of these. Spot-checking one app shouldn't cost 150 requests.
    public var only: [String] = []
    public var registries: Set<Registry> = Set(Registry.allCases)
    public var hostConcurrency = 4
    public var perHostDelay: Duration = .milliseconds(250)
    public var infraRetries = 2
    public var showSamples = false
    /// Cross-check against the locally installed copy where there is one. Off on
    /// a CI runner, where nothing is installed.
    public var useInstalled = true
    public var githubToken: String?
    public var baselinePath: URL?
    public var jsonPath: URL?
    public var markdownPath: URL?
}

/// The installed version to compare a probe's answer against.
struct InstalledVersion: Sendable {
    let marketing: String?
    let build: String?
}

public enum Verify {

    public static func run(_ options: VerifyOptions) async -> Int32 {
        let vendor = filtered(VendorProbeRegistry.recipes, options) { $0.bundleID }
        let github = filtered(GitHubReleaseRegistry.rules, options) { $0.bundleID }
        let changelog = filtered(ChangelogRecipeRegistry.recipes, options) { $0.bundleID }

        let total = (options.registries.contains(.vendor) ? vendor.count : 0)
            + (options.registries.contains(.github) ? github.count : 0)
            + (options.registries.contains(.changelog) ? changelog.count : 0)
        guard total > 0 else {
            die("nothing to verify — no recipe matches \(options.only.joined(separator: ", "))",
                code: 2)
        }

        let installed = options.useInstalled ? await installedVersions() : [:]
        print("""

          duo verify
          \(options.registries.contains(.vendor) ? "\(vendor.count) vendor probes  " : "")\
        \(options.registries.contains(.github) ? "\(github.count) GitHub rules  " : "")\
        \(options.registries.contains(.changelog) ? "\(changelog.count) changelogs" : "")
          ─────────────────────────────────────────────
        """)

        let started = Date()
        var findings: [Finding] = []

        // Vendor and GitHub first: their answers are the reference the changelog
        // sweep compares against, and they resolve the `{version}` that
        // templated changelog URLs need.
        if options.registries.contains(.vendor) {
            findings += await sweepVendor(vendor, options: options, installed: installed)
        }
        if options.registries.contains(.github) {
            findings += await sweepGitHub(github, options: options, installed: installed)
        }
        // Keyed by bundle id AND channel, then by bare bundle id. A version-templated
        // changelog on a multi-channel app needs ITS channel's version: WeChat
        // DevTools publishes `logs/<channel>_v<version>.json` per train, so handing
        // the RC recipe the Stable version 404s — a failure invented by the sweep,
        // not by the vendor. The bare-id entries stay as the fallback for the common
        // case (one recipe, `channel: nil`), where there is nothing to disambiguate.
        var knownVersions: [String: String] = [:]
        for finding in findings {
            guard let version = finding.version else { continue }
            let keyed = "\(finding.bundleID):\(finding.channel)"
            if knownVersions[keyed] == nil { knownVersions[keyed] = version }
            if knownVersions[finding.bundleID] == nil { knownVersions[finding.bundleID] = version }
        }
        if options.registries.contains(.changelog) {
            // Fall back to the installed copy's version for templated recipes
            // when no version source ran this sweep (`--changelog` on its own).
            var versions = knownVersions
            for (key, value) in installed {
                let bundleID = String(key.dropFirst("vendor:".count).prefix { $0 != ":" })
                if versions[bundleID] == nil, let marketing = value.marketing {
                    versions[bundleID] = marketing
                }
            }
            findings += await sweepChangelog(changelog, options: options, versions: versions)
        }

        findings.sort { $0.recipeID < $1.recipeID }

        // Fold in history: version regressions, and the failure streak that
        // decides whether anything is worth reporting at all.
        var baseline = options.baselinePath.map(Baseline.load) ?? Baseline()
        findings = findings.map { finding in
            guard let complaint = baseline.reconcile(finding) else { return finding }
            return finding.adding(warning: complaint)
        }
        baseline.updatedAt = Date()

        Report.text(findings, elapsed: Int(Date().timeIntervalSince(started)),
                    baseline: baseline, showSamples: options.showSamples)
        writeArtifacts(findings, baseline: baseline, options: options)

        // Broken recipes below the streak threshold don't fail the run — a first
        // bad sweep is information, not a verdict. An endpoint that has been
        // unreachable for a week does fail it: at that point it is a dead recipe
        // wearing a network error's clothes.
        return findings.contains(where: {
            $0.status == .warn
                || ($0.status == .broken && baseline.isReportable($0.recipeID))
                || ($0.status == .infra && baseline.isInfraReportable($0.recipeID))
        }) ? 1 : 0
    }

    private static func filtered<T>(
        _ items: [T], _ options: VerifyOptions, id: (T) -> String
    ) -> [T] {
        guard !options.only.isEmpty else { return items }
        return items.filter { item in
            options.only.contains { id(item).localizedCaseInsensitiveContains($0) }
        }
    }

    private static func writeArtifacts(
        _ findings: [Finding], baseline: Baseline, options: VerifyOptions
    ) {
        if let path = options.jsonPath {
            do { try Report.json(findings, to: path) }
            catch { FileHandle.standardError.write(Data("could not write \(path.path): \(error)\n".utf8)) }
        }
        if let path = options.markdownPath {
            do { try Report.markdown(findings, baseline: baseline, to: path) }
            catch { FileHandle.standardError.write(Data("could not write \(path.path): \(error)\n".utf8)) }
        }
        if let path = options.baselinePath {
            do { try baseline.save(to: path) }
            catch { FileHandle.standardError.write(Data("could not write \(path.path): \(error)\n".utf8)) }
        }
    }

    /// Why a changelog recipe produced no entries, as the report should say it.
    ///
    /// Split out of the sweep so it can be tested: a wrong answer here does not
    /// break the app, it sends whoever reads the report to the wrong place. The
    /// distinction that matters is WHICH request failed. A two-stage recipe
    /// (`indexLinkPattern`) fetches an index and then the per-release page it
    /// points at; before this existed, a failure of that second request surfaced
    /// as `noEntriesExtracted` with the entry pattern quoted — a regex that had
    /// never run. HBuilderX Alpha spent a sweep flagged that way on 2026-08-16
    /// (elapsed 15131 ms, exactly the fetch timeout) while its pattern still
    /// matched the page perfectly.
    static func classifyChangelogFailure(
        _ diagnostic: ChangelogService.ChangelogDiagnostic,
        recipe: ChangelogRecipe,
        host: String
    ) -> (kind: String, detail: String, status: FindingStatus, pattern: String?) {
        // Stage 1: the index (or, for a one-stage recipe, the page itself).
        if diagnostic.fetchFailed {
            guard let code = diagnostic.httpStatus else {
                return ("transport", "could not reach \(host)", .infra, recipe.entryPattern)
            }
            return ("httpStatus\(code)",
                    "HTTP \(code) — the changelog page has moved or gone",
                    (code >= 500 || code == 429) ? .infra : .broken,
                    recipe.entryPattern)
        }
        // Stage 2: the per-release page. No pattern is quoted — none of them ran.
        if diagnostic.detailFetchFailed {
            let reached = diagnostic.detailURL?.host ?? host
            guard let code = diagnostic.detailHTTPStatus else {
                return ("detailTransport",
                        "index ok, but could not reach the release page on \(reached)",
                        .infra, nil)
            }
            return ("detailHttpStatus\(code)",
                    "index ok, but the release page returned HTTP \(code)",
                    (code >= 500 || code == 429) ? .infra : .broken,
                    nil)
        }
        // The index answered but held no link: the INDEX pattern is the broken one.
        if diagnostic.detailURL == nil, let indexPattern = recipe.indexLinkPattern {
            return ("noDetailLink",
                    "fetched \(host) fine, but the index pattern found no release link",
                    .broken, indexPattern)
        }
        return ("noEntriesExtracted",
                "fetched \(host) fine, but the entry pattern matched nothing",
                .broken, recipe.entryPattern)
    }

    // MARK: - vendor probes

    private static func sweepVendor(
        _ recipes: [VendorProbeRecipe], options: VerifyOptions,
        installed: [String: InstalledVersion]
    ) async -> [Finding] {
        await byHost(recipes, host: { $0.url.host ?? "-" }, options: options) { recipe in
            // A credential-bearing recipe is never fetched by the sweep: its URL,
            // headers and body would all flow into a report and possibly an
            // issue. Reported as skipped so the absence is visible.
            if RegistrySecurity.isCredentialBearing(bundleID: recipe.bundleID) {
                return Finding(
                    recipeID: recipe.recipeID, registry: .vendor, bundleID: recipe.bundleID,
                    channel: recipe.channel.rawValue, status: .skipped,
                    failureDetail: "credential-bearing — never swept",
                    endpointHost: recipe.url.host ?? "-")
            }
            let source = VendorProbeSource()
            var attempt = 0
            var outcome = await source.probeDiagnostic(recipe)
            while attempt < options.infraRetries,
                  outcome.failure?.classification == .infra {
                attempt += 1
                try? await Task.sleep(for: .seconds(attempt))
                outcome = await source.probeDiagnostic(recipe)
            }
            var finding = classify(
                outcome, registry: .vendor, host: recipe.url.host ?? "-",
                pattern: recipe.versionPattern, attempts: attempt + 1,
                installed: installed[recipe.recipeID],
                sanity: { version, remote in
                    RecipeSanity.complaints(version: version, recipe: recipe)
                        + [RecipeSanity.crossChannelArtifact(recipe: recipe, remote: remote)]
                            .compactMap { $0 }
                })
            if let version = finding.version,
               let complaint = await brewComplaint(bundleID: recipe.bundleID, version: version) {
                finding = finding.adding(warning: complaint)
            }
            return finding
        }
    }

    // MARK: - GitHub rules

    private static func sweepGitHub(
        _ rules: [GitHubReleaseRule], options: VerifyOptions,
        installed: [String: InstalledVersion]
    ) async -> [Finding] {
        // All 13 rules share api.github.com, so host-grouping would serialize
        // them anyway. That is the correct behaviour — one shared rate limit.
        let source = GitHubReleasesSource(token: options.githubToken ?? GitHubToken.resolve())
        var out: [Finding] = []
        for (index, rule) in rules.enumerated() {
            if index > 0 { try? await Task.sleep(for: options.perHostDelay) }
            var attempt = 0
            var outcome = await source.resolveDiagnostic(rule)
            while attempt < options.infraRetries,
                  outcome.failure?.classification == .infra {
                attempt += 1
                try? await Task.sleep(for: .seconds(attempt))
                outcome = await source.resolveDiagnostic(rule)
            }
            out.append(classify(
                outcome, registry: .github, host: "api.github.com",
                pattern: rule.versionPattern, attempts: attempt + 1,
                installed: installed["vendor:\(rule.bundleID):\(rule.channel.rawValue)"],
                sanity: { _, _ in [] }))
        }
        return out
    }

    // MARK: - changelog recipes

    /// A changelog recipe fails the same way a probe does — the vendor restyles
    /// the page and the entry pattern stops matching — but until now it recorded
    /// nothing at all: the UI just silently fell back to embedding the raw page.
    private static func sweepChangelog(
        _ recipes: [ChangelogRecipe], options: VerifyOptions, versions: [String: String]
    ) async -> [Finding] {
        await byHost(recipes, host: { $0.source.host ?? "-" }, options: options) { recipe in
            let id = "changelog:\(recipe.bundleID):\(recipe.channel?.rawValue ?? "-")"
            let host = recipe.source.host ?? "-"
            // Templated recipes need a concrete version to resolve their URL —
            // use the one this run's probe just read, so the sweep checks the
            // page the app would actually open.
            let version = recipe.channel.flatMap { versions["\(recipe.bundleID):\($0.rawValue)"] }
                ?? versions[recipe.bundleID]
            // With no version at all, `resolvedSource` silently falls back to the
            // untemplated `source` — which for these vendors is a generic landing
            // page that has never parsed. Reporting that as breakage would be a
            // pure artifact of how the sweep was invoked, so say so instead.
            if recipe.sourceTemplate != nil, version == nil {
                return Finding(
                    recipeID: id, registry: .changelog, bundleID: recipe.bundleID,
                    channel: recipe.channel?.rawValue ?? "-", status: .skipped,
                    failureDetail: "version-templated: no version available "
                        + "(app not installed, and no version source ran this sweep)",
                    endpointHost: host)
            }
            let started = Date()
            let diagnostic = await ChangelogService.loadDiagnostic(recipe, version: version)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)

            guard let changelog = diagnostic.changelog,
                  let newest = changelog.entries.first else {
                let failure = classifyChangelogFailure(diagnostic, recipe: recipe, host: host)
                return Finding(
                    recipeID: id, registry: .changelog, bundleID: recipe.bundleID,
                    channel: recipe.channel?.rawValue ?? "-", status: failure.status,
                    failureKind: failure.kind, failureDetail: failure.detail,
                    endpointHost: host, pattern: failure.pattern, elapsedMs: elapsed,
                    bodySample: diagnostic.bodySample)
            }

            // Cross-check against what the version sources said. A changelog
            // stuck a whole release behind what the app is being offered means
            // the entry pattern is reading a stale or wrong part of the page.
            //
            // Compared on major.minor only, and that is load-bearing: matching on
            // the full string flagged six recipes, five of them behaving exactly
            // as intended. JetBrains keys its notes to the major release (`2026.2`
            // for build `2026.2.0.1`), Toolbox publishes marketing versions
            // against build-numbered installs, and a vendor being one patch
            // behind on their own blog is ordinary. Only a divergence bigger than
            // that says something is actually wrong.
            var warnings: [String] = []
            let top = newest.version
            if let version, let complaint = changelogLagComplaint(entry: top, detected: version) {
                warnings.append(complaint)
            }
            return Finding(
                recipeID: id, registry: .changelog, bundleID: recipe.bundleID,
                channel: recipe.channel?.rawValue ?? "-",
                status: warnings.isEmpty ? .ok : .warn,
                version: newest.version, warnings: warnings,
                endpointHost: host, pattern: recipe.entryPattern, elapsedMs: elapsed,
                bodySample: diagnostic.bodySample)
        }
    }

    /// Second opinion from Homebrew, for the ~35% of vendor bundle ids the cask
    /// catalog can resolve (measured against the live catalog, not assumed —
    /// `byBundleID` is derived from each cask's `uninstall: quit:` field, so
    /// coverage is partial by construction).
    ///
    /// **Deliberately one-directional.** A cask *behind* our probe is the normal
    /// state of the world: brew lags, and `auto_updates true` casks lag
    /// indefinitely because nobody bumps them. A cask *ahead* of us by a whole
    /// release is the interesting direction — it means the vendor shipped and
    /// our recipe didn't notice.
    ///
    /// This is the only cross-check that works on a CI runner, where no apps are
    /// installed and `remoteBehindInstalled` has nothing to compare against.
    static func brewComplaint(bundleID: String, version: String) async -> String? {
        guard let cask = try? await HomebrewCaskCatalog.shared.entry(forBundleID: bundleID),
              !cask.autoUpdates  // an auto-updating cask's version is decorative
        else { return nil }

        func majorMinor(_ v: String) -> String {
            v.split(separator: ".").prefix(2).joined(separator: ".")
        }
        let ours = majorMinor(version)
        let theirs = majorMinor(cask.version)
        guard ours != theirs, VersionComparator.isNewer(theirs, than: ours) else { return nil }
        return "Homebrew's cask `\(cask.token)` is at \(cask.version) while this recipe "
            + "reads \(version) — the probe may be stuck on a stale element"
    }

    /// Flag a changelog only when it trails the detected version at
    /// major.minor — see the call site for why the full-string comparison had to
    /// go.
    static func changelogLagComplaint(entry: String, detected: String) -> String? {
        // Plenty of recipes deliberately capture a headline into the `version`
        // group, because the vendor simply doesn't number their release notes —
        // Figma and Notion both title entries "AI credit user limits…". Comparing
        // a sentence to a version number produces confident nonsense, so anything
        // that isn't version-shaped is out of scope for this check.
        guard entry.first?.isNumber == true, detected.first?.isNumber == true else {
            return nil
        }
        // Date-encoded schemes need a different yardstick. Codex numbers both its
        // builds and its release notes `YY.MDD` (`26.803` is 2026-08-03), which
        // puts the date in the very slot this check compares on: every build cut
        // after the newest published note reads as a whole release behind, and the
        // notes are published weekly against builds that ship more often. Measured
        // in days instead, the same signal survives — a pattern stuck on a stale
        // section lands months out, not one publishing cycle.
        if let entryDay = buildDate(entry), let detectedDay = buildDate(detected) {
            let days = gmtCalendar.dateComponents([.day], from: entryDay, to: detectedDay).day ?? 0
            guard days > staleNotesDays else { return nil }
            return "newest changelog entry (\(entry)) trails the detected version (\(detected)) "
                + "by \(days) days — the entry pattern may be reading a stale section"
        }
        func majorMinor(_ version: String) -> String {
            version.split(separator: ".").prefix(2).joined(separator: ".")
        }
        let entryMM = majorMinor(entry)
        let detectedMM = majorMinor(detected)
        guard entryMM != detectedMM, VersionComparator.isNewer(detectedMM, than: entryMM)
        else { return nil }
        return "newest changelog entry (\(entry)) trails the detected version (\(detected)) "
            + "by a whole release — the entry pattern may be reading a stale section"
    }

    /// How far a date-numbered changelog may fall behind the shipped build before
    /// it counts as stale. Codex's app notes come out weekly-to-fortnightly (the
    /// widest gap on their page as of 2026-08-10 is 14 days), so this leaves the
    /// normal cadence four times over.
    static let staleNotesDays = 60

    /// Fixed to UTC: these versions carry a calendar date, not a local instant,
    /// and the runner's zone must not shift the day count.
    static let gmtCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// `26.803` → 2026-08-03, `26.1215` → 2026-12-15. Nil for anything that isn't
    /// a two-digit year followed by a valid `MDD`/`MMDD`.
    ///
    /// A version can of course be shaped like a date without being one. That
    /// misreading is one-directional and safe: it only ever widens the tolerance,
    /// so the cost is a warning that arrives late, never one that fires wrongly.
    static func buildDate(_ version: String) -> Date? {
        let parts = version.split(separator: ".")
        guard parts.count >= 2,
            parts[0].count == 2, parts[0].allSatisfy(\.isNumber), let year = Int(parts[0]),
            (3...4).contains(parts[1].count), parts[1].allSatisfy(\.isNumber),
            let monthDay = Int(parts[1])
        else { return nil }
        let components = DateComponents(
            year: 2000 + year, month: monthDay / 100, day: monthDay % 100)
        guard (1...12).contains(components.month!), (1...31).contains(components.day!)
        else { return nil }
        return gmtCalendar.date(from: components)
    }

    // MARK: - shared plumbing

    /// One request at a time per host, up to `hostConcurrency` hosts in flight.
    ///
    /// Grouping by host gives both politeness constraints at once, and for free:
    /// recipes that share a host (Mozilla's three channels, JetBrains' many
    /// tools) are naturally serialized instead of arriving as a burst.
    private static func byHost<T: Sendable>(
        _ items: [T], host: @Sendable (T) -> String, options: VerifyOptions,
        probe: @escaping @Sendable (T) async -> Finding
    ) async -> [Finding] {
        let groups = Dictionary(grouping: items, by: host).values.sorted {
            host($0[0]) < host($1[0])
        }
        let delay = options.perHostDelay

        var findings: [Finding] = []
        var next = 0
        await withTaskGroup(of: [Finding].self) { group in
            func addNext() {
                guard next < groups.count else { return }
                let batch = groups[next]
                next += 1
                group.addTask {
                    var out: [Finding] = []
                    for (index, item) in batch.enumerated() {
                        if index > 0 {
                            // Jitter so a host serving several recipes doesn't
                            // see a metronome.
                            try? await Task.sleep(
                                for: delay + .milliseconds(Int.random(in: 0...100)))
                        }
                        out.append(await probe(item))
                    }
                    return out
                }
            }
            for _ in 0..<min(options.hostConcurrency, groups.count) { addNext() }
            for await produced in group {
                findings.append(contentsOf: produced)
                addNext()
            }
        }
        return findings
    }

    /// Turn a `ProbeOutcome` into a `Finding`. Shared by the vendor and GitHub
    /// sweeps so both are judged by identical rules.
    static func classify(
        _ outcome: ProbeOutcome, registry: Registry, host: String, pattern: String?,
        attempts: Int, installed: InstalledVersion?,
        sanity: (String, RemoteVersion) -> [String]
    ) -> Finding {
        func make(
            _ status: FindingStatus, version: String? = nil, warnings: [String] = []
        ) -> Finding {
            Finding(
                recipeID: outcome.recipeID, registry: registry, bundleID: outcome.bundleID,
                channel: outcome.channel.rawValue, status: status, version: version,
                failureKind: outcome.failure?.kind, failureDetail: outcome.failure?.detail,
                warnings: warnings, endpointHost: host, pattern: pattern,
                attempts: attempts, elapsedMs: outcome.elapsedMs,
                bodySample: outcome.bodySample)
        }

        if let failure = outcome.failure {
            switch failure.classification {
            case .recipe: return make(.broken)
            case .infra: return make(.infra)
            case .notApplicable: return make(.skipped)
            }
        }
        guard let remote = outcome.remote,
              let version = remote.shortVersion ?? remote.version else {
            // Unreachable by construction (remote nil ⇒ failure non-nil), but a
            // sweep that silently drops a recipe is exactly the bug being fixed.
            return make(.broken)
        }

        // The judgment rules live in `RecipeSanity`, in the core next to the
        // registry they guard — a second copy here would drift from it.
        var warnings = outcome.warnings.map(\.kind)
        warnings.append(contentsOf: sanity(version, remote))
        if let installed, let complaint = RecipeSanity.remoteBehindInstalled(
            remote: remote, installedMarketing: installed.marketing,
            installedBuild: installed.build) {
            warnings.append(complaint)
        }
        return make(warnings.isEmpty ? .ok : .warn, version: version, warnings: warnings)
    }

    /// How long to wait for the local scan before deciding the cross-check isn't
    /// worth the run.
    static let scanTimeout = Duration.seconds(20)

    /// Index the locally installed apps by the recipe id they'd be checked
    /// under, so a recipe can find its own installed copy without re-deriving
    /// the channel gate.
    ///
    /// **Bounded, because this scan can block forever.** `AppScanner` reads
    /// TestFlight's SQLite database, which lives behind macOS's app-data
    /// privacy gate. On a machine with someone at the keyboard that surfaces a
    /// consent prompt; on a headless runner nothing ever answers it and the
    /// `open()` syscall simply never returns. The first CI run sat in
    /// `guarded_open_np` until the job timed out.
    ///
    /// The blocked thread can't be cancelled — it is stuck in a syscall — so
    /// this abandons it instead and moves on. The cross-check is a bonus signal;
    /// losing it costs one class of finding, while waiting for it costs the
    /// entire sweep.
    ///
    /// The scan runs on a plain `Thread`, not in a task group. A group looks
    /// like it would work — race the scan against a sleep, take whichever lands
    /// first — but `withTaskGroup` does not return until *every* child has
    /// finished, and `cancelAll()` cannot touch a thread parked in
    /// `guarded_open_np`. The warning printed on time and the sweep hung anyway;
    /// 2026-08-15 it sat there for ten minutes at 0.03s of CPU.
    ///
    /// `TestFlightInventory` now bounds that open itself, so this should no
    /// longer be reachable through TestFlight. It stays because it is the last
    /// guard around everything *else* `scan()` touches — other apps' containers,
    /// network volumes, a stalled automount.
    static func installedVersions() async -> [String: InstalledVersion] {
        let box = ScanBox()
        let done = DispatchSemaphore(value: 0)
        let worker = Thread {
            var out: [String: InstalledVersion] = [:]
            for app in AppScanner().scan() {
                guard let bundleID = app.bundleID else { continue }
                out["vendor:\(bundleID):\(app.releaseChannel.rawValue)"] =
                    InstalledVersion(marketing: app.shortVersion, build: app.buildVersion)
            }
            box.set(out)
            done.signal()
        }
        worker.start()

        // Wait off the cooperative pool so a stuck scan can never starve it.
        let timedOut = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                let seconds = Double(scanTimeout.components.seconds)
                cont.resume(returning: done.wait(timeout: .now() + seconds) == .timedOut)
            }
        }
        guard !timedOut, let scanned = box.take() else {
            FileHandle.standardError.write(Data("""
                ⚠︎ the local app scan did not finish within \(scanTimeout) — continuing \
                without the installed-copy cross-check.
                  Usually means a privacy prompt nobody can answer (TestFlight's \
                database is behind the app-data gate).\n
                """.utf8))
            return [:]
        }
        return scanned
    }

    /// A slot the scan thread fills and the caller reads, for the case where the
    /// caller has already given up.
    private final class ScanBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [String: InstalledVersion]?
        func set(_ v: [String: InstalledVersion]) {
            lock.lock(); defer { lock.unlock() }
            value = v
        }
        func take() -> [String: InstalledVersion]? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }
}

extension Finding {
    /// Attach a warning discovered after the fact (the baseline's history checks
    /// run once every finding exists), promoting `ok` to `warn`.
    public func adding(warning: String) -> Finding {
        Finding(
            recipeID: recipeID, registry: registry, bundleID: bundleID, channel: channel,
            status: status == .ok ? .warn : status, version: version,
            failureKind: failureKind, failureDetail: failureDetail,
            warnings: warnings + [warning], endpointHost: endpointHost, pattern: pattern,
            attempts: attempts, elapsedMs: elapsedMs, bodySample: bodySample)
    }
}
