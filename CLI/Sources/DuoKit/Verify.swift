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
    /// of these — see `Verify.filtered`. Spot-checking one app shouldn't cost 150
    /// requests.
    public var only: [String] = []
    public var registries: Set<Registry> = Set(Registry.allCases)
    public var hostConcurrency = 4
    public var perHostDelay: Duration = .milliseconds(250)
    public var infraRetries = 2
    public var showSamples = false
    /// Cross-check against the locally installed copy where there is one. Off on
    /// a CI runner, where nothing is installed.
    public var useInstalled = true
    /// Sweep even when this binary was not built from the checkout it is standing in.
    /// See `SourceStamp` for what that costs and why it is refused by default.
    public var allowStaleBinary = false
    public var githubToken: String?
    public var baselinePath: URL?
    public var jsonPath: URL?
    public var markdownPath: URL?
}

/// The installed version to compare a probe's answer against.
struct InstalledVersion: Sendable {
    let marketing: String?
    let build: String?
    /// The vendor's own build id, for the sources that report one
    /// (`RemoteVersion.buildNamespace == .vendor`). Nil for every other app.
    let vendorBuild: String?
}

/// What `--only` may name. The two ids every registry entry carries, so
/// `Verify.filtered` has one definition of "matches" instead of one per call
/// site — see that function for which half was missing.
protocol VerifySelectable {
    var bundleID: String { get }
    var recipeID: String { get }
}

extension VendorProbeRecipe: VerifySelectable {}
extension GitHubReleaseRule: VerifySelectable {}
extension ChangelogRecipe: VerifySelectable {}
extension MacAppStoreProbeCase: VerifySelectable {}
extension SparkleFeedCatalog.VerificationCase: VerifySelectable {}

/// A registry entry the Homebrew cross-check can speak for: it needs the channel
/// as well as the app, and takes both off the entry so no call site can pair a
/// rule with the wrong channel (#559).
protocol BrewCrossChecked: VerifySelectable {
    var channel: ReleaseChannel { get }
}

extension VendorProbeRecipe: BrewCrossChecked {}
extension GitHubReleaseRule: BrewCrossChecked {}

/// The cask fields the cross-check reads. `CaskEntry` has no public
/// initializer, so tests hand these in instead.
struct CaskFacts: Sendable {
    let token: String
    let version: String
    let autoUpdates: Bool
    /// Found under the `.app` filename rather than under the recipe's bundle id
    /// — a plausible match, not a declared one, so the complaint says so (#743).
    var matchedByAppFilename = false
}

public enum Verify {

    public static func run(_ options: VerifyOptions) async -> Int32 {
        // Before anything is counted or requested. The recipes below are the ones
        // compiled into THIS binary, and the whole report is worthless — while looking
        // entirely normal — if that is not the tree the reader has open.
        if case .stale(let reason) = SourceStamp.verdict() {
            guard options.allowStaleBinary else {
                die(SourceStamp.complaint(reason), code: 2)
            }
            print("\n  ⚠︎ \(reason).\n    Sweeping anyway because --allow-stale-binary was passed.\n")
        }

        let vendor = filtered(VendorProbeRegistry.recipes, options)
        let github = filtered(GitHubReleaseRegistry.rules, options)
        let changelog = filtered(ChangelogRecipeRegistry.recipes, options)
        let appStore = filtered(MacAppStoreProbeRegistry.cases, options)
        let feeds = filtered(SparkleFeedCatalog.verificationCases, options)

        // The pkg install specs the pkgarch sweep reads. Counted here like every
        // other registry: without it `duo verify --pkgarch` computes a total of
        // zero and dies with "nothing to verify - no recipe matches", blaming an
        // `--only` the user never typed.
        let pkgs = vendor.filter { $0.install?.kind == .pkg }
        // Written as a loop rather than a chain of ternaries: at six registries
        // the chained form exceeded the type checker's budget outright ("unable to
        // type-check this expression in reasonable time"), and a seventh registry
        // would hit it again.
        let counts: [(Registry, Int)] = [
            (.vendor, vendor.count), (.github, github.count),
            (.changelog, changelog.count), (.appStore, appStore.count),
            (.feed, feeds.count), (.pkgArch, pkgs.count),
        ]
        let total = counts.reduce(0) { sum, entry in
            sum + (options.registries.contains(entry.0) ? entry.1 : 0)
        }
        guard total > 0 else {
            die("nothing to verify — no recipe matches \(options.only.joined(separator: ", "))",
                code: 2)
        }

        let installed = options.useInstalled ? await installedVersions() : [:]
        print("""

          duo verify
          \(options.registries.contains(.vendor) ? "\(vendor.count) vendor probes  " : "")\
        \(options.registries.contains(.github) ? "\(github.count) GitHub rules  " : "")\
        \(options.registries.contains(.changelog) ? "\(changelog.count) changelogs  " : "")\
        \(options.registries.contains(.appStore) ? "\(appStore.count) App Store probes  " : "")\
        \(options.registries.contains(.feed) ? "\(feeds.count) Sparkle feeds  " : "")\
        \(options.registries.contains(.pkgArch) ? "\(pkgs.count) pkg architectures" : "")
          ─────────────────────────────────────────────
        """)
        // Said once, up front, rather than left for the reader to infer from a
        // column of `skipped`: this sweep reads the install URLs the vendor sweep
        // resolves, so on its own it has none. Making `--pkgarch` silently imply
        // `--vendor` would be worse - it would spend ~150 vendor requests the user
        // did not ask for.
        if options.registries.contains(.pkgArch), !options.registries.contains(.vendor) {
            print("  ⚠︎ --pkgarch reads the install URLs the vendor sweep resolves, "
                  + "and --vendor\n    was not selected, so every package reports skipped. "
                  + "Add --vendor.\n")
        }

        let started = Date()
        var findings: [Finding] = []

        // Vendor and GitHub first: their answers are the reference the changelog
        // sweep compares against, and they resolve the `{version}` that
        // templated changelog URLs need.
        let resolvedInstallURLs = ResolvedInstallURLs()
        if options.registries.contains(.vendor) {
            findings += await sweepVendor(
                vendor, options: options, installed: installed,
                collecting: resolvedInstallURLs)
            // The pages `sweepChangelog` will GET and parse below are excluded:
            // its answer is better evidence than a HEAD, and two checks on one URL
            // in one report can contradict each other. When the changelog registry
            // is not being swept there is no such answer coming, so nothing is
            // excluded and every page is asked.
            //
            // A version-templated recipe is NOT one of them, and that distinction
            // is the whole correctness of this set: its `source` is only a
            // fallback, and what `sweepChangelog` actually requests is
            // `resolvedSource(forVersion:)`. Excluding by `source` there would
            // remove a URL from this sweep that nothing else ever asks for —
            // three of them today (WeChat, Longbridge stable and preview) — and
            // leave exactly the silent rot #107 exists to end. On a runner with
            // nothing installed those recipes are `.skipped` and not fetched at
            // all, so the gap would be permanent rather than occasional.
            let fetchedByChangelogSweep: Set<String> = options.registries.contains(.changelog)
                ? Set(changelog.lazy.filter { $0.sourceTemplate == nil }
                    .map(\.source.absoluteString))
                : []
            findings = await foldingChangelogLinks(
                into: findings, recipes: vendor,
                alreadyFetched: fetchedByChangelogSweep, options: options)
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
            let versions = changelogVersions(known: knownVersions, installed: installed)
            findings += await sweepChangelog(
                changelog, options: options, versions: versions, versionSources: findings)
        }
        if options.registries.contains(.appStore) {
            findings += await sweepAppStore(appStore, options: options)
        }
        if options.registries.contains(.feed) {
            findings += await sweepFeeds(feeds, options: options)
        }
        // After the vendor sweep, always: it reads the install URLs that sweep
        // resolved. Selecting `--pkgarch` without `--vendor` therefore resolves
        // nothing and every package reports `skipped`, which is the honest answer
        // — the alternative is this sweep quietly re-probing every vendor.
        if options.registries.contains(.pkgArch) {
            findings += await sweepPackageArchitecture(
                vendor, urls: await resolvedInstallURLs.all(), options: options)
        }

        findings.sort { $0.recipeID < $1.recipeID }

        // Fold in history: version regressions, and the failure streak that
        // decides whether anything is worth reporting at all.
        var baseline = options.baselinePath.map(Baseline.load) ?? Baseline()
        findings = foldingBaselineComplaints(findings, into: &baseline)
        baseline.updatedAt = Date()

        // Drop rows for recipes that no longer exist. Deliberately keyed on the
        // REGISTRIES rather than on what this run swept: `--only` and
        // `--changelog` narrow the sweep, and pruning against a narrowed run
        // would delete every row the filter excluded.
        let pruned = baseline.prune(keeping: liveRecipeIDs())
        for id in pruned.removed {
            print("  baseline: dropped \(id) — no recipe produces this id any more")
        }
        for id in pruned.keptWithOpenIssue {
            print("  baseline: \(id) has no recipe but its issue is still open — kept")
        }

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

    /// Attach every history complaint the baseline has about each finding.
    ///
    /// Split out of `run` so the fold itself is testable. `reconcile` can return
    /// more than one complaint for one finding — a changelog page that collapses
    /// into a single entry also changes which version wins — and taking only the
    /// first would drop the complaint that explains the other. That is a bug a
    /// reader cannot see in `run`, because there is nothing there to compare
    /// against; it is one `.first` away at all times.
    static func foldingBaselineComplaints(
        _ findings: [Finding], into baseline: inout Baseline
    ) -> [Finding] {
        findings.map { finding in
            baseline.reconcile(finding).reduce(finding) { $0.adding(warning: $1) }
        }
    }

    /// Merge the local-scan fallback into the versions a live source resolved.
    /// Installed apps are indexed as `vendor:<bundle-id>:<channel>`; keep that
    /// channel in the changelog key so `--changelog` never templates an RC or
    /// Nightly URL with the installed Stable version. The bare bundle id remains
    /// for ordinary single-channel recipes whose `channel` is nil.
    static func changelogVersions(
        known: [String: String], installed: [String: InstalledVersion]
    ) -> [String: String] {
        var versions = known
        let prefix = "vendor:"
        for (key, value) in installed {
            guard key.hasPrefix(prefix), let marketing = value.marketing else { continue }
            let channelKey = String(key.dropFirst(prefix.count))
            if versions[channelKey] == nil { versions[channelKey] = marketing }

            guard let channelSeparator = channelKey.lastIndex(of: ":") else { continue }
            let bundleID = String(channelKey[..<channelSeparator])
            if versions[bundleID] == nil { versions[bundleID] = marketing }
        }
        return versions
    }

    /// A channel-scoped recipe may only use that channel's version. Falling back
    /// to the bare bundle-id value here turns a changelog-only Stable install into
    /// bogus RC/Nightly requests. Bare keys are exclusively for recipes whose
    /// channel is nil.
    static func changelogVersion(
        for recipe: ChangelogRecipe, versions: [String: String]
    ) -> String? {
        guard let channel = recipe.channel else { return versions[recipe.bundleID] }
        return versions["\(recipe.bundleID):\(channel.rawValue)"]
    }

    /// Why a version-templated recipe has no version to resolve its page with.
    ///
    /// Two different reasons. Either nothing gave a version (no probe or rule for
    /// this app ran, and no copy is installed), or one ran and came back empty
    /// — the probe was unreachable, broken, or skipped. The second must not read
    /// like the first: on a machine without the app, a family's changelog page
    /// then goes unchecked exactly while its probe is down, and "app not
    /// installed" says nothing about that.
    ///
    /// The finding stays `.skipped` either way. The changelog page was never
    /// requested, so `.infra` would claim a host was unreachable that nobody
    /// asked; it would also age this row's `consecutiveInfra` into
    /// `isInfraReportable` alongside the probe's own, filing a second issue for
    /// one vendor outage. `.skipped` records nothing in `Baseline` and is never
    /// reported by `Reconcile`, and the probe's row already carries the outage.
    ///
    /// A source matches the way `changelogVersion` looks versions up: a
    /// channel-scoped recipe only by its own channel, a channel-less one by any.
    static func templatedSkipDetail(
        for recipe: ChangelogRecipe, versionSources: [Finding]
    ) -> String {
        let ran = versionSources.filter { source in
            (source.registry == .vendor || source.registry == .github)
                && source.bundleID == recipe.bundleID
                && (recipe.channel.map { source.channel == $0.rawValue } ?? true)
        }
        guard !ran.isEmpty else {
            return "version-templated: no version available "
                + "(app not installed, and no version source ran this sweep)"
        }
        let outcomes = ran.map { source in
            "\(source.recipeID): \(source.status.rawValue)"
                + (source.failureKind.map { " (\($0))" } ?? "")
        }
        return "version-templated: version source did not produce a version this sweep: "
            + outcomes.joined(separator: "; ")
    }

    /// Both ids, not one: `--only` is documented as matching a bundle id OR a
    /// recipe id, and it matched the bundle id alone. For four of the five
    /// registries the recipe id contains the bundle id, so that looked like it
    /// worked; the GitHub rules are keyed on the repository slug, so no `--only`
    /// could ever name one by its recipe id — and nothing anywhere could select by
    /// channel, which is the other half of every recipe id.
    ///
    /// Taken from a protocol rather than a per-call-site closure because the
    /// closure is exactly the part that was wrong, and five of them are five
    /// chances to be wrong again in a way no test of this function would see.
    static func filtered<T: VerifySelectable>(
        _ items: [T], _ options: VerifyOptions
    ) -> [T] {
        guard !options.only.isEmpty else { return items }
        return items.filter { item in
            options.only.contains { needle in
                item.bundleID.localizedCaseInsensitiveContains(needle)
                    || item.recipeID.localizedCaseInsensitiveContains(needle)
            }
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
    /// The host a failed changelog finding is filed against: the release page's
    /// when that second request is what failed, else `host` (`recipe.source`'s).
    ///
    /// `Reconcile` turns a streak of `.infra` findings into an issue telling the
    /// reader to `dig` `endpointHost`. A feed-page recipe's appcast and notes page
    /// live on different hosts (Mac Mouse Fix: raw.githubusercontent.com and
    /// raw.githack.com), so filing a dead notes host under the appcast's would
    /// send that check to a host that is fine.
    static func failingHost(
        _ diagnostic: ChangelogService.ChangelogDiagnostic, host: String
    ) -> String {
        guard diagnostic.detailFetchFailed, let detailHost = diagnostic.detailURL?.host else {
            return host
        }
        return detailHost
    }

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
        // The appcast answered but offered no page this recipe accepts: its newest
        // usable item links nowhere, or somewhere `feedPagePattern` does not
        // cover. The second is the vendor moving its notes, and the entry pattern
        // never ran, so it is the page pattern that gets quoted.
        if diagnostic.detailURL == nil, let feedPagePattern = recipe.feedPagePattern {
            return ("noFeedPage",
                    "fetched the appcast on \(host) fine, but its newest item links no "
                        + "notes page the recipe's page pattern accepts",
                    .broken, feedPagePattern)
        }
        // The index answered but held no link: the INDEX pattern is the broken one.
        if diagnostic.detailURL == nil, let indexPattern = recipe.indexLinkPattern {
            return ("noDetailLink",
                    "fetched \(host) fine, but the index pattern found no release link",
                    .broken, indexPattern)
        }
        // Named after the page the pattern ran on. For a two-stage or feed-page
        // recipe that is `detailURL`, and `host` is the index or appcast host,
        // which never saw the entry pattern.
        return ("noEntriesExtracted",
                "fetched \(diagnostic.detailURL?.host ?? host) fine, but the entry pattern matched nothing",
                .broken, recipe.entryPattern)
    }

    // MARK: - vendor probes

    private static func sweepVendor(
        _ recipes: [VendorProbeRecipe], options: VerifyOptions,
        installed: [String: InstalledVersion],
        // Not optional and not defaulted: an omitted collector compiles and
        // silently collects nothing, leaving the pkgarch sweep reporting every
        // package as skipped with no error anywhere. Same rule as
        // `RowActions.live` in CLAUDE.md.
        collecting installURLs: ResolvedInstallURLs
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
            // One tally spanning every attempt, so `attempts` below counts the
            // requests this recipe actually cost rather than the probes we chose to
            // run. Without it a probe that 502s and recovers inside
            // `versionFeedData` reports one attempt for two requests — and reports
            // `ok`, hiding exactly the kind of flap this sweep exists to catch.
            let tally = GatewayRetry.Tally()
            var attempt = 0
            var outcome = await GatewayRetry.$tally.withValue(tally) {
                await source.probeDiagnostic(recipe, checkingInstallURL: true)
            }
            while attempt < options.infraRetries,
                  outcome.failure?.classification == .infra {
                attempt += 1
                try? await Task.sleep(for: .seconds(attempt))
                outcome = await GatewayRetry.$tally.withValue(tally) {
                    await source.probeDiagnostic(recipe, checkingInstallURL: true)
                }
            }
            var finding = classify(
                outcome, registry: .vendor, host: recipe.url.host ?? "-",
                pattern: recipe.versionPattern,
                attempts: attempt + 1 + tally.count, gatewayRetries: tally.count,
                installed: installed[recipe.recipeID],
                sanity: { version, remote in
                    RecipeSanity.complaints(version: version, recipe: recipe)
                        + [RecipeSanity.crossChannelArtifact(recipe: recipe, remote: remote)]
                            .compactMap { $0 }
                })
            if let version = finding.version,
               let complaint = await brewComplaint(for: recipe, version: version) {
                finding = finding.adding(warning: complaint)
            }
            if let note = await rolloutTrackComplaint(recipe, source: source) {
                finding = finding.observing(note)
            }
            if outcome.succeeded, let version = finding.version,
               let complaint = await edgeCopyComplaint(recipe, bareVersion: version, source: source) {
                finding = finding.adding(warning: complaint)
            }
            // "This one only detects, and its own answer names an installer." The
            // sweep could not previously ask that, which is how three recipes kept
            // a blocker that had stopped being true — see
            // `RecipeSanity.oneClickCandidate`. A note, never a warning: the
            // recipes that are detection-only on purpose must not be issued
            // against, and the baseline is what settles the ones already answered.
            // Only for a probe that ANSWERED. `bodySample` is populated on
            // failures too — that is its main job — so a vendor serving a CDN
            // error page with a `.zip` link on it would otherwise get "you could
            // install this" stapled to the failure someone is trying to read.
            if outcome.succeeded, let candidate = RecipeSanity.oneClickCandidate(
                recipe: recipe, bodySample: outcome.bodySample) {
                finding = finding.observing(
                    Finding.machineNotePrefix + "oneClickCandidate: " + candidate)
            }
            // Hand the pkgarch sweep the URL this probe already resolved. Doing it
            // here rather than re-probing is the difference between the 66–88 small
            // Range reads those 22 packages cost (three or four each, see
            // `PackageArchitectureProbe.headerLength`) and hitting 22 vendor
            // endpoints a second time in one run.
            await installURLs.record(
                recipe.recipeID, installArtifactURL(outcome))
            return finding
        }
    }

    /// Install URLs the vendor sweep already resolved, so the pkgarch sweep can
    /// read those packages without probing the same vendor endpoints a second
    /// time. Collected as a side effect rather than returned, because
    /// `sweepVendor` runs its recipes through `byHost`, whose contract is
    /// recipe-in/finding-out — widening that to carry an unrelated value would
    /// put this sweep's needs into every other sweep's signature.
    actor ResolvedInstallURLs {
        private var urls: [String: URL] = [:]
        func record(_ recipeID: String, _ url: URL?) {
            guard let url else { return }
            urls[recipeID] = url
        }
        func all() -> [String: URL] { urls }
    }

    /// Every recipe id the registries can still produce, which is what `Baseline`
    /// keeps and everything else it prunes.
    ///
    /// Extracted so it can be tested: an id missing here is not a compile error
    /// and not a failing sweep — it is an entry silently deleted on every run.
    /// For `pkgarch:` that meant a single-architecture warn's
    /// `consecutiveActionable` was wiped before it was saved, so it could never
    /// reach `actionableThreshold` and the sweep's only actionable branch was
    /// structurally unable to file an issue.
    ///
    /// Derived from the registries, never from this run's `--only` filter: a
    /// narrowed sweep must not prune the entries it did not look at.
    static func liveRecipeIDs() -> Set<String> {
        Set(
            VendorProbeRegistry.recipes.map(\.recipeID)
                + ChangelogRecipeRegistry.recipes.map(\.recipeID)
                + GitHubReleaseRegistry.rules.map(\.recipeID)
                + MacAppStoreProbeRegistry.cases.map(\.recipeID)
                + [MacAppStoreProbeRegistry.batchRecipeID]
                + SparkleFeedCatalog.verificationCases.map(\.recipeID)
                + VendorProbeRegistry.recipes
                    .filter { $0.install?.kind == .pkg }
                    .map { pkgArchID($0) })
    }

    /// The resolved install artifact, or nil when the probe fell back.
    ///
    /// ⚠️ `remote.downloadURL` is NOT always an installer. When the install plan
    /// fails to resolve, `VendorProbeSource.makeRemoteVersion` is called with
    /// `install: nil, plan: nil` and fills `downloadURL` with
    /// `recipe.downloadURL` — the vendor's HUMAN download page — or, for a recipe
    /// with no page, the probe endpoint itself (Discord PTB's update manifest).
    /// Handing either to the pkgarch sweep makes it range-read a page or a feed
    /// and file `notAFlatPackage` as `ok`: a green verdict on a recipe whose install spec
    /// just died, which is precisely the drift this is supposed to notice.
    ///
    /// The probe already says so in its own vocabulary, so read that rather than
    /// guessing from the URL's shape.
    static func installArtifactURL(_ outcome: ProbeOutcome) -> URL? {
        let unresolved: Set<String> = [
            ProbeWarning.installURLUnresolved.kind,
            ProbeWarning.installURLTransient(status: nil).kind,
            ProbeWarning.installURLNotFound(status: nil, host: nil).kind,
        ]
        guard !outcome.warnings.contains(where: { unresolved.contains($0.kind) })
        else { return nil }
        return outcome.remote?.downloadURL
    }

    /// A pkgarch finding's own id, namespaced like every other registry's
    /// (`appstore:`, `feed:`, `github:`, `vendor:`).
    ///
    /// ⚠️ Not `recipe.recipeID`. That is already `vendor:<bundle>:<channel>`, and
    /// `Baseline` keys its entries on the id alone — so reusing it would file this
    /// sweep's verdict and the vendor sweep's into ONE baseline entry for the same
    /// recipe, mixing their `consecutiveActionable` streaks and sharing the issue
    /// number attached to it. Two registries reporting on one recipe is exactly
    /// what the namespace is for.
    static func pkgArchID(_ recipe: VendorProbeRecipe) -> String {
        "pkgarch:\(recipe.bundleID):\(recipe.channel.rawValue)"
    }

    /// Read the declared `hostArchitectures` of every package the pkg install
    /// route would hand to macOS's installer.
    ///
    /// Statuses are deliberately quiet, because the measurement behind this sweep
    /// (#415) found the declaration has no discriminating power today:
    ///
    ///   - a **single-architecture** declaration is the one `warn`. It is the
    ///     event worth waking someone for — a package that used to be universal
    ///     now naming one architecture is how an Intel-only pkg would arrive.
    ///   - **universal** and **absent** are both `ok`. Absent is the norm, not a
    ///     defect: 7 of 22 declare nothing, including all three Edge channels.
    ///     Warning on it would file seven issues on day one and train the reader
    ///     to ignore the sweep — which `FindingStatus.infra`'s comment already
    ///     warns about.
    ///   - a URL that is not a flat package is `ok` too: `kind: .pkg` legitimately
    ///     covers a `.dmg` that `PackageInstaller` unwraps (Sunlogin), and a
    ///     vendor serving HTML there is the vendor sweep's finding to make, not
    ///     this one's — filing it twice would put two verdicts on one URL.
    ///
    /// The declaration is recorded on every finding, `ok` included, so the value
    /// lands in `report.json` and drift shows up as a diff rather than depending
    /// on someone re-reading a comment.
    private static func sweepPackageArchitecture(
        _ recipes: [VendorProbeRecipe], urls: [String: URL], options: VerifyOptions
    ) async -> [Finding] {
        let pkgs = recipes.filter { $0.install?.kind == .pkg }
        guard !pkgs.isEmpty else { return [] }
        return await byHost(pkgs, host: { urls[$0.recipeID]?.host ?? ($0.url.host ?? "-") },
                            options: options) { recipe in
            // Keyed by the VENDOR id, because that is what `sweepVendor` recorded
            // under. Only the finding gets the pkgarch namespace.
            let host = urls[recipe.recipeID]?.host ?? (recipe.url.host ?? "-")
            guard let url = urls[recipe.recipeID] else {
                // The vendor sweep did not resolve an install URL for this recipe
                // — it already filed why. Skipped, so the gap is visible without
                // being counted as this sweep's failure.
                return pkgArchFinding(recipe, host: host, outcome: nil, elapsedMs: 0)
            }
            let started = Date()
            let outcome = await PackageArchitectureProbe.declaration(at: url)
            return pkgArchFinding(recipe, host: host, outcome: outcome,
                                  elapsedMs: Int(Date().timeIntervalSince(started) * 1000))
        }
    }

    /// Turn one package's verdict into a `Finding`. Pure and non-private so the
    /// status mapping can be tested without a network: the `warn` branch is the
    /// only actionable one this sweep has and no real package produces it
    /// (measured — every declaration in the registry is universal), so a test
    /// that cannot construct it would leave the branch unexercised end to end.
    ///
    /// `outcome: nil` means the vendor sweep resolved no install URL.
    static func pkgArchFinding(
        _ recipe: VendorProbeRecipe, host: String,
        outcome: Result<PackageArchitectureProbe.Declaration, any Error>?, elapsedMs: Int
    ) -> Finding {
        guard let outcome else {
            return Finding(
                recipeID: pkgArchID(recipe), registry: .pkgArch, bundleID: recipe.bundleID,
                channel: recipe.channel.rawValue, status: .skipped,
                failureDetail: "no install URL resolved this run", endpointHost: host)
        }
        switch outcome {
        case .failure(let error):
            return Finding(
                recipeID: pkgArchID(recipe), registry: .pkgArch, bundleID: recipe.bundleID,
                channel: recipe.channel.rawValue, status: .infra,
                failureKind: "packageUnreadable", failureDetail: error.localizedDescription,
                endpointHost: host, elapsedMs: elapsedMs)
        case .success(let declaration):
            let single: Bool
            if case .single = declaration { single = true } else { single = false }
            return Finding(
                recipeID: pkgArchID(recipe), registry: .pkgArch, bundleID: recipe.bundleID,
                channel: recipe.channel.rawValue,
                status: single ? .warn : .ok,
                failureKind: single ? "singleArchitecturePackage" : nil,
                failureDetail: single
                    ? "declares \(declaration.value) — the pkg route runs no architecture gate"
                    : nil,
                warnings: ["hostArchitectures=\(declaration.value)"],
                endpointHost: host, elapsedMs: elapsedMs)
        }
    }

    /// Attach each vendor finding the verdict on its own `changelogURL`.
    ///
    /// A separate pass rather than a step inside `sweepVendor`, for two reasons.
    /// The pages are DEDUPLICATED — Chrome's four channels share one release-notes
    /// page, as do Firefox's trains — so doing it per recipe would ask some hosts
    /// the same question four times. And a changelog page almost never lives on
    /// the same host as the probe endpoint, so the per-host pacing `sweepVendor`
    /// applies to `edgeupdates.microsoft.com` says nothing about how hard we are
    /// leaning on `learn.microsoft.com`; the link sweep groups by its own hosts.
    ///
    /// Costs one request per distinct page (87 as of 2026-08-28) on top of the
    /// ~150 the sweep already makes. See `ChangelogLinkSweep` for why only 404 and
    /// 410 are allowed to accuse anyone.
    private static func foldingChangelogLinks(
        into findings: [Finding], recipes: [VendorProbeRecipe],
        alreadyFetched: Set<String>, options: VerifyOptions
    ) async -> [Finding] {
        let verdicts = await ChangelogLinkSweep.statuses(
            of: recipes, alreadyFetched: alreadyFetched, options: options)
        guard !verdicts.isEmpty else { return findings }
        // Keyed by recipe id, which is what a `Finding` carries — the same recipe
        // id `Baseline` and the issue history are keyed on.
        var pages: [String: URL] = [:]
        for recipe in recipes {
            if let url = recipe.changelogURL { pages[recipe.recipeID] = url }
        }
        // Only `ok` findings can carry this: `adding(warning:)` promotes `ok` to
        // `warn` and leaves every other status alone, so a verdict folded onto an
        // `infra` or `skipped` finding would be paid for and then never printed —
        // `Report.text` iterates the actionable statuses only. Not worth widening
        // the report for: a probe endpoint having a bad minute delays this page's
        // verdict by one sweep, and the sweep runs nightly.
        return findings.map { finding in
            guard finding.registry == .vendor,
                  let url = pages[finding.recipeID],
                  let verdict = verdicts[url.absoluteString],
                  let complaint = ChangelogLinkSweep.complaint(for: verdict, url: url)
            else { return finding }
            return complaint.hasPrefix(Finding.machineNotePrefix)
                ? finding.observing(complaint)
                : finding.adding(warning: complaint)
        }
    }

    /// The one question a normal probe cannot answer for a recipe whose track is
    /// picked by a value on disk: did we actually read that value, and is it
    /// still deciding anything?
    ///
    /// Only the combination is worth reporting. Falling back while the vendor's
    /// tracks are converged costs nothing — every value gets the same answer.
    /// Falling back while they have SPLIT means we are on the cautious track by
    /// accident, offering whatever that track holds to a machine whose own
    /// updater may well be on the other one. That is the failure
    /// `ChannelArtifactProof` describes for channel recipes, and it is otherwise
    /// silent all the way through: the version resolves, the URL resolves, the
    /// download is a real notarized build from the same vendor.
    ///
    /// Reported as a machine note, not a warning: it accuses nobody. The recipe
    /// is fine — this machine is the thing that cannot read its plan, and on a
    /// sweep box nobody signs into ChatGPT that is the permanent state. Letting
    /// it promote the finding to `.warn` would add an actionable streak and,
    /// after two sweeps inside one rollout window, file a public issue against a
    /// recipe that is working. `installURLTransient` is exempted from
    /// `actionable` in `classify` for the same reason.
    ///
    /// Costs two extra requests, and only for recipes that declare a track.
    private static func rolloutTrackComplaint(
        _ recipe: VendorProbeRecipe, source: VendorProbeSource
    ) async -> String? {
        guard let track = recipe.track,
              source.trackProvenance(recipe) == .fallback,
              case .diverged(let ours, let contrast)? =
                await source.rolloutTrackVerdict(recipe)
        else { return nil }
        return Finding.machineNotePrefix
            + "rolloutTrackDefaulted: no value at \(track.selector.displayPath), so this"
            + " machine is asking as `\(track.selector.fallback ?? "?")` while the vendor is"
            + " serving two tracks (\(ours) vs \(contrast) for \(track.contrastTrackName))"
    }

    /// Kimi's failure, asked of every recipe that reads an electron manifest: does
    /// the bare address answer the same version as the origin? See
    /// `RecipeSanity.readsElectronManifest` for why it is asked and of whom.
    ///
    /// A WARNING, not a note, unlike `rolloutTrackComplaint`: this one does accuse
    /// the recipe — it is reading an older version than the vendor publishes. A
    /// CDN still propagating a release can disagree for minutes, and that is why
    /// it is a warning rather than `.broken`: an issue needs the disagreement to
    /// survive into the next sweep, and Kimi's lasted days.
    ///
    /// Costs one extra request per such recipe, which the finding's `attempts` does
    /// NOT count — the finding is classified before this runs, and it sits outside
    /// the recipe's `GatewayRetry` tally, the same gap `rolloutTrackComplaint` has.
    /// A second fetch that fails says nothing: the sweep has already judged the
    /// recipe's real request, and this only compares two answers.
    ///
    /// ⚠️ The query rides the FIRST hop only. Granola's `api.granola.ai` answers
    /// with a redirect to a CloudFront URL that carries no query (request ledger,
    /// 2026-09-12: the queried request's next hop went out bare, and URLCache
    /// revalidated it as the same document), so for that recipe the two answers
    /// are the same fetch by construction and this can never disagree. That is
    /// still the right comparison — electron-updater's own request loses the
    /// query at the same redirect, so the app reads what the recipe reads — but
    /// "no complaint" there means "same as the app", not "same as the origin".
    static func edgeCopyComplaint(
        _ recipe: VendorProbeRecipe, bareVersion: String, source: VendorProbeSource
    ) async -> String? {
        guard RecipeSanity.readsElectronManifest(recipe) else { return nil }
        let origin = await source.probeDiagnostic(
            recipe.with(url: ElectronUpdateConfig.noCacheURL(for: recipe.url)))
        guard let remote = origin.remote,
              let version = remote.shortVersion ?? remote.version
        else { return nil }
        return RecipeSanity.edgeCopyComplaint(bare: bareVersion, origin: version)
    }

    // MARK: - GitHub rules

    private static func sweepGitHub(
        _ rules: [GitHubReleaseRule], options: VerifyOptions,
        installed: [String: InstalledVersion]
    ) async -> [Finding] {
        // Every GitHub rule shares api.github.com, so host-grouping would serialize
        // them anyway. That is the correct behaviour — one shared rate limit.
        var token = options.githubToken
        if token == nil { token = await GitHubToken.resolve() }
        let source = GitHubReleasesSource(
            token: token,
            validatorCache: GitHubConditionalCache.shared)
        var out: [Finding] = []
        for (index, rule) in rules.enumerated() {
            if index > 0 { try? await Task.sleep(for: options.perHostDelay) }
            // See the vendor sweep: counts requests, not probes.
            let tally = GatewayRetry.Tally()
            // What the endpoint answered, as opposed to what we asked it. This is
            // the only check here that can see an UPSTREAM rename: the redirect
            // makes detection keep working, so every other signal stays green while
            // the request quietly loses its token. See ``GitHubEndpointAudit``.
            let audit = GitHubEndpointAudit.Ledger()
            var attempt = 0
            // The copy on this machine, when there is one, is a far better anchor
            // for a line-anchored rule than "the newest tag" — the latter makes
            // the ceiling trivially the top of the list and measures nothing. See
            // `resolveDiagnostic(_:anchoredTo:)`.
            let anchor = installed["vendor:\(rule.bundleID):\(rule.channel.rawValue)"]?.marketing
            var outcome = await GitHubEndpointAudit.$ledger.withValue(audit) {
                await GatewayRetry.$tally.withValue(tally) {
                    await source.resolveDiagnostic(rule, anchoredTo: anchor)
                }
            }
            while attempt < options.infraRetries,
                  outcome.failure?.classification == .infra {
                attempt += 1
                try? await Task.sleep(for: .seconds(attempt))
                outcome = await GitHubEndpointAudit.$ledger.withValue(audit) {
                    await GatewayRetry.$tally.withValue(tally) {
                        await source.resolveDiagnostic(rule, anchoredTo: anchor)
                    }
                }
            }
            // Which pattern a report should quote. For a renamed macOS artifact the
            // TAG pattern is still matching every release, so quoting it sends the
            // reader to the wrong regex — `assetPatternNoMatch` is the one failure
            // that is about the install pattern instead.
            let reportedPattern: String
            if case .assetPatternNoMatch = outcome.failure, let install = rule.installAssetPattern {
                reportedPattern = install
            } else {
                reportedPattern = rule.versionPattern
            }
            var finding = classify(
                outcome, registry: .github, host: "api.github.com",
                pattern: reportedPattern,
                attempts: attempt + 1 + tally.count, gatewayRetries: tally.count,
                installed: installed["vendor:\(rule.bundleID):\(rule.channel.rawValue)"],
                // Issue #101: this used to pass `{ _, _ in [] }`. The vendor
                // sweep asked "did this install spec resolve its OWN channel's
                // build" and the GitHub sweep asked nothing, so a non-stable rule
                // that skipped the gate produced silence where a recipe produced
                // a finding — and the asymmetry was invisible at the point where
                // somebody adds a rule.
                sanity: { _, remote in
                    [RecipeSanity.crossChannelArtifact(rule: rule, remote: remote)]
                        .compactMap { $0 }
                })
            // The GitHub sweep never ran this cross-check — only the vendor sweep
            // did — so the one registry where a tag can outrun the macOS artifact
            // was also the one with no second opinion. GitHub releases carry a
            // publish date, which is exactly what the phantom check needs.
            if let version = finding.version,
               let complaint = await brewComplaint(
                   for: rule, version: version, publishedAt: outcome.remote?.publishedAt) {
                finding = finding.adding(warning: complaint)
            }
            for complaint in Self.endpointComplaints(audit.observations) {
                finding = finding.adding(warning: complaint)
            }
            out.append(finding)
        }
        // The store coalesces its disk writes over a couple of seconds; this
        // process is about to exit, so write now or lose the sweep's memos.
        await GitHubConditionalCache.shared.flush()
        return out
    }

    /// Turn what the endpoint answered into findings. Both of these are `.warn`
    /// rather than `.broken` on purpose: the rule still returns the right version
    /// today, so calling it broken would be wrong and would spend the streak
    /// machinery on something that is not an outage.
    ///
    /// One rule can produce several observations (`/releases/latest` plus the list
    /// fallback), so each complaint is emitted once however many requests it took.
    static func endpointComplaints(
        _ observations: [GitHubEndpointAudit.Observation]
    ) -> [String] {
        var complaints: [String] = []
        if let stale = observations.compactMap(\.staleSlug).first,
           let requested = observations.first?.requestedSlug {
            complaints.append(
                "staleSlug: the registry says \(requested), GitHub answers as "
                + "\(stale) — the rule is riding a rename redirect. Repoint it: "
                + "the redirect is not permanent (GitHub drops it if the old name "
                + "is ever reused) and, until then, following it costs the request "
                + "its Authorization header")
        } else if observations.contains(where: \.redirectedButUnnamed),
                  let requested = observations.first?.requestedSlug {
            // The redirect happened but nothing in the answer could name the
            // canonical repo — no release to read `html_url` from, which is every
            // non-2xx response and any empty release list. Say the weaker thing
            // rather than nothing: this is the case with the least information and
            // it must not also be the case with the least output.
            complaints.append(
                "staleSlugUnnamed: GitHub redirected this request away from "
                + "\(requested), so the registry's slug is out of date, but the "
                + "answer carried no release to name the repo it really is. "
                + "Resolve it with `gh api repos/\(requested) -q .full_name`")
        }
        if observations.contains(where: \.authSilentlyDropped) {
            complaints.append(
                "anonymousDespiteToken: this request carried a token and came back "
                + "x-ratelimit-limit: 60, the anonymous ceiling — the token is not "
                + "reaching the endpoint that answered, so this rule is competing "
                + "for the shared 60/hour per-IP budget")
        }
        return complaints
    }

    // MARK: - changelog recipes

    /// A changelog recipe fails the same way a probe does — the vendor restyles
    /// the page and the entry pattern stops matching — but until now it recorded
    /// nothing at all: the UI just silently fell back to embedding the raw page.
    ///
    /// `versionSources` is what this sweep's vendor and GitHub sweeps produced, so
    /// a templated recipe left without a version can say which of them ran and
    /// came back empty.
    static func sweepChangelog(
        _ recipes: [ChangelogRecipe], options: VerifyOptions, versions: [String: String],
        versionSources: [Finding], session: URLSession = .updates
    ) async -> [Finding] {
        await byHost(recipes, host: { $0.source.host ?? "-" }, options: options) { recipe in
            let id = recipe.recipeID
            let host = recipe.source.host ?? "-"
            // Templated recipes need a concrete version to resolve their URL —
            // use the one this run's probe just read, so the sweep checks the
            // page the app would actually open.
            let version = changelogVersion(for: recipe, versions: versions)
            // With no version at all, `resolvedSource` silently falls back to the
            // untemplated `source` — which for these vendors is a generic landing
            // page that has never parsed. Reporting that as breakage would be a
            // pure artifact of how the sweep was invoked, so say so instead —
            // and say which of the two reasons it is (`templatedSkipDetail`).
            if recipe.sourceTemplate != nil, version == nil {
                return Finding(
                    recipeID: id, registry: .changelog, bundleID: recipe.bundleID,
                    channel: recipe.channel?.rawValue ?? "-", status: .skipped,
                    failureDetail: templatedSkipDetail(for: recipe, versionSources: versionSources),
                    endpointHost: host)
            }
            let started = Date()
            // No update result here, so a `feedPagePattern` recipe resolves its
            // page from its own appcast inside `loadDiagnostic`.
            let diagnostic = await ChangelogService.loadDiagnostic(
                recipe, version: version, feedPage: nil, session: session)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)

            guard let changelog = diagnostic.changelog,
                  let newest = changelog.entries.first else {
                let failure = classifyChangelogFailure(diagnostic, recipe: recipe, host: host)
                return Finding(
                    recipeID: id, registry: .changelog, bundleID: recipe.bundleID,
                    channel: recipe.channel?.rawValue ?? "-", status: failure.status,
                    failureKind: failure.kind, failureDetail: failure.detail,
                    endpointHost: failingHost(diagnostic, host: host),
                    pattern: failure.pattern, elapsedMs: elapsed,
                    bodySample: diagnostic.bodySample)
            }

            // A windowed recipe that parses another train's notes. Nothing else in
            // this sweep can see it: the page answers, the pattern matches, and the
            // lag check below only fires when the newest entry TRAILS the installed
            // version — the other train's newer page leads it. Raycast's v1 archive
            // spent weeks here after the vendor moved it, recording 2.x versions
            // as healthy. No `version` or `entryCount` on the finding, so
            // the baseline does not record the other train's numbers as good.
            if let complaint = changelogWindowComplaint(
                recipe, entryVersions: changelog.entries.map(\.version)) {
                return Finding(
                    recipeID: id, registry: .changelog, bundleID: recipe.bundleID,
                    channel: recipe.channel?.rawValue ?? "-", status: .broken,
                    failureKind: "entriesOutsideVersionWindow", failureDetail: complaint,
                    endpointHost: failingHost(diagnostic, host: host),
                    pattern: recipe.entryPattern, elapsedMs: elapsed,
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
            // …but only against a version this recipe is FOR. A recipe scoped to an
            // older train legitimately trails the installed build: Raycast's v1
            // archive tops out at 1.104.0 while the machine running the sweep is on
            // 2.0.6.0, and `versions` only ever holds what is installed here. There
            // is no detected version for the other train to compare against, so the
            // honest move is to skip the cross-check rather than to invent a
            // complaint the recipe can never clear.
            if let version, recipe.covers(appVersion: version),
               let complaint = changelogLagComplaint(
                   entry: top, detected: version,
                   acknowledged: recipe.acknowledgedStaleEntry,
                   ordersByLineage: VendorProbeRegistry.ordersByLineage(bundleID: recipe.bundleID)) {
                warnings.append(complaint)
            }
            // And the reverse: this page ahead of every probe row for the app,
            // which is what a frozen probe looks like (#743). Against the SWEEP's
            // own readings, never against `version` above — that one falls back to
            // the installed copy, and "the changelog leads the machine I ran on"
            // is not a statement about the probe at all.
            if let complaint = changelogLeadsProbeComplaint(
                entry: top,
                probeVersionsByChannel: probeVersionsByChannel(
                    forBundleID: recipe.bundleID, among: versionSources),
                carriesOtherTrainEntries: recipe.carriesOtherTrainEntries,
                ordersByLineage: VendorProbeRegistry.ordersByLineage(bundleID: recipe.bundleID)) {
                warnings.append(complaint)
            }
            return Finding(
                recipeID: id, registry: .changelog, bundleID: recipe.bundleID,
                channel: recipe.channel?.rawValue ?? "-",
                status: warnings.isEmpty ? .ok : .warn,
                version: newest.version, warnings: warnings,
                endpointHost: host, pattern: recipe.entryPattern,
                entryCount: changelog.entries.count,
                entryVersions: changelog.entries.map(\.version),
                // Against the page requested, not one re-derived from a version:
                // a heading that resolves elsewhere is itself a slip, and must not
                // make an older version look like another page.
                headingMatchesPage: recipe.sourceTemplate == nil ? nil
                    : Baseline.templatedPage(recipe, forHeading: top) == diagnostic.resolvedURL,
                elapsedMs: elapsed,
                bodySample: diagnostic.bodySample)
        }
    }

    /// Second opinion from Homebrew, for the vendor bundle ids the cask catalog
    /// can resolve (measured against the live catalog, not assumed — the
    /// bundle-id key is built from each cask's `uninstall: quit:` field, so
    /// coverage is partial by construction: of the 228 bundle ids the two
    /// cross-checked registries held on 2026-09-18 — 138 vendor probes and 90
    /// GitHub rules, no overlap — 88 resolve by that key and 39 more by the `.app`
    /// fallback `liveCasks` adds, 39% to 55%).
    ///
    /// **Deliberately one-directional.** A cask *behind* our probe is the normal
    /// state of the world: brew lags, and `auto_updates true` casks lag
    /// indefinitely because nobody bumps them. A cask *ahead* of us by a whole
    /// release is the interesting direction — it means the vendor shipped and
    /// our recipe didn't notice.
    ///
    /// This is the only cross-check that works on a CI runner, where no apps are
    /// installed and `remoteBehindInstalled` has nothing to compare against.
    static func brewComplaint(
        for recipe: some BrewCrossChecked, version: String,
        publishedAt: Date? = nil, now: Date = Date(),
        casks lookup: @Sendable (String) async -> [CaskFacts] = liveCasks
    ) async -> String? {
        let casks = await lookup(recipe.bundleID)
        guard let pick = caskIndex(for: recipe.channel, amongTokens: casks.map(\.token)),
              case let cask = casks[pick],
              !cask.autoUpdates  // an auto-updating cask's version is decorative
        else { return nil }

        // `numericMajorMinor`, not a bare two-component split: brew spells some
        // versions `version,build` (`librewolf` ships `156.0,1`) and others
        // `version+revision`, and the suffix lands in the second component — so
        // the cask read as a whole release AHEAD of an identical version. The
        // phantom direction below had always stripped it; this one had not, and
        // only never fired because every cask carrying such a spelling was
        // reached through a key this function could not resolve.
        let ours = numericMajorMinor(version)
        let theirs = numericMajorMinor(cask.version)
        // Both complaints below rest on this cask being this app's, so both carry
        // the caveat when the key was guessed — not just the first one.
        let keyNote = cask.matchedByAppFilename ? caskKeyNote(cask.token, recipe.bundleID) : ""
        if ours != theirs, VersionComparator.isNewer(theirs, than: ours) {
            return "Homebrew's cask `\(cask.token)` is at \(cask.version) while this recipe "
                + "reads \(version) — the probe may be stuck on a stale element" + keyNote
        }
        return phantomVersionComplaint(
            caskToken: cask.token, caskVersion: cask.version, version: version,
            publishedAt: publishedAt, now: now).map { $0 + keyNote }
    }

    /// Every cask the live catalog lists for a bundle id; none when it can't load.
    ///
    /// Falls back to the `.app` filename key when the bundle id resolves nothing,
    /// which is the second half of #743. A cask records a bundle id only in its
    /// `uninstall: quit:` field, and the id it records is the vendor's, which need
    /// not be the one we measured off the shipped bundle: `workbuddy-cn` quits
    /// `com.tencent.workbuddy.mac` while our recipe is keyed
    /// `com.workbuddy.workbuddy`. The cask was right all along — 5.5.6 against the
    /// 5.3.14 our frozen probe kept reporting — and this cross-check simply could
    /// not see it. Worse, the miss is indistinguishable from "no cask exists",
    /// including to a human writing an app audit: both audits for that family
    /// recorded `无 cask` for a source that was merely mis-keyed.
    ///
    /// Measured over all 228 cross-checked bundle ids against the live catalog on
    /// 2026-09-18 — both registries, not just the vendor probes, since
    /// `GitHubReleaseRule` is `BrewCrossChecked` too: 39 resolve no cask by id and
    /// exactly one by filename. Ambiguous ones are already gone by then;
    /// `Telegram.app` is installed by both `telegram` (12.10) and
    /// `telegram-desktop` (7.2.9), which are different apps on different
    /// numbering, and the wrong pick reads as a five-major lead. Running the real
    /// `brewComplaint` over the 259 recipes and rules that have a baseline
    /// version, the 39 raise exactly two complaints between them, and both are
    /// the WorkBuddy CN rows this exists for.
    @Sendable static func liveCasks(bundleID: String) async -> [CaskFacts] {
        func facts(_ entries: [CaskEntry], byFilename: Bool) -> [CaskFacts] {
            entries.map {
                CaskFacts(token: $0.token, version: $0.version, autoUpdates: $0.autoUpdates,
                          matchedByAppFilename: byFilename)
            }
        }
        let byID = (try? await HomebrewCaskCatalog.shared.entries(forBundleID: bundleID)) ?? []
        guard byID.isEmpty, let filename = caskAppFilename(forBundleID: bundleID) else {
            return facts(byID, byFilename: false)
        }
        let byApp = (try? await HomebrewCaskCatalog.shared.entries(forAppFilename: filename)) ?? []
        return unambiguousCasks(facts(byApp, byFilename: true))
    }

    /// The `.app` filename to try for a bundle id whose own key resolves nothing.
    ///
    /// The last dot component, which is what a reverse-DNS id ends with and what
    /// vendors name the bundle after: `com.workbuddy.workbuddy` → `workbuddy.app`,
    /// matching `WorkBuddy.app` because the catalog's filename index is
    /// case-folded. A guess, and treated as one — see `unambiguousCasks` and the
    /// note every complaint carries.
    ///
    /// Nil when that component is a QUALIFIER rather than a name. Plenty of ids
    /// are `tld.vendor.name.channel` or `tld.vendor.name.platform`, and their last
    /// component says nothing about which app it is. Of those 228 ids, **52**
    /// derive one, across ten stems:
    ///
    ///     desktop ×16   app ×16   beta ×5   mac ×5   nightly ×3
    ///     dev ×2        client ×2  canary ×1  macos ×1  preview ×1
    ///
    /// No cask ships an artifact under any of those names today, which is the only
    /// reason none of them resolves, and "no vendor has yet named a bundle
    /// `App.app`" is not a property worth resting a filed issue on.
    ///
    /// `beta`, `nightly`, `dev`, `canary` and `preview` come from `ReleaseChannel`
    /// itself rather than a hand-copy, so a channel added there cannot quietly
    /// become a cask key. **The other five do not.** `macos` is the thin one —
    /// `com.raycast.macos` is the only id carrying it, which is exactly the shape
    /// somebody trims as dead weight. `client` is carried by two
    /// (`com.spotify.client`, `com.windscribe.client`), so losing either still
    /// leaves the stem earning its place.
    ///
    /// Every id above is pinned by name in
    /// `BrewCaskKeyTests.aQualifierIsNotAName`, so trimming a hand-written stem
    /// fails a test that names the app it would break rather than quietly putting
    /// Raycast back on the `macos.app` key. Read the counts from the table, not
    /// from this paragraph, when deciding whether a stem is still carried.
    static func caskAppFilename(forBundleID bundleID: String) -> String? {
        guard let last = bundleID.split(separator: ".").last, !last.isEmpty,
              !qualifierComponents.contains(last.lowercased())
        else { return nil }
        return "\(last).app"
    }

    /// Last components that qualify an app rather than name one: every release
    /// channel, plus the platform and generic words vendors append.
    /// Lowercased on both sides — `ReleaseChannel.guineaPig`'s raw value is
    /// camel-cased, so a set built from the raw values verbatim would miss it
    /// against a lowercased component and silently let one channel through.
    static let qualifierComponents: Set<String> =
        Set(ReleaseChannel.allCases.map { $0.rawValue.lowercased() })
            .union(["app", "desktop", "mac", "macos", "osx", "ios", "client", "gui"])

    /// Casks found under a filename, kept only when they are ONE cask and its own
    /// channel siblings (`gimp` + `gimp@dev`, `emacs-app` + `@nightly` +
    /// `@pretest`). Two unrelated tokens installing the same filename mean the
    /// filename does not identify an app, and a guess is not worth a wrong
    /// accusation: nothing is returned and the app is cross-checked no more than
    /// it was before.
    static func unambiguousCasks(_ casks: [CaskFacts]) -> [CaskFacts] {
        let families = Set(casks.map { $0.token.split(separator: "@").first.map(String.init) ?? $0.token })
        return families.count == 1 ? casks : []
    }

    /// Appended to any complaint raised through the filename fallback: the match
    /// is plausible rather than declared, and the reader has to be able to see
    /// that before acting on it — as well as see which cask to record in the
    /// app's audit, where "no cask" is what a key miss looks like.
    static func caskKeyNote(_ token: String, _ bundleID: String) -> String {
        // NOT "declares a different id": the catalog's bundle-id index is built
        // only from `uninstall: quit:`, and a cask with an `app` artifact and no
        // `uninstall` stanza at all is the ordinary shape — 36 of the 39 casks the
        // fallback reaches declare no quit id whatever, and only `mstystudio`,
        // `headlamp` and `workbuddy-cn` declare a competing one. All this branch
        // knows is that the cask does not claim OUR id.
        " (matched on the app filename, not on \(bundleID) — `\(token)` does not "
            + "declare that bundle id in its `uninstall quit:`, so confirm the two "
            + "are the same app)"
    }

    /// Which of a bundle's casks speaks for this channel — by position in `tokens`.
    ///
    /// Stable takes the first in catalog order. (That is this function's own
    /// choice — the catalog hands out every cask for a bundle id and picks none;
    /// `HomebrewCaskSource` makes a different choice, on the host and the
    /// Caskroom.) A non-stable
    /// channel takes only a cask named for it (`utm@beta` for `.beta`) and nothing
    /// otherwise: the catalog is in token order, so the first cask is the
    /// unsuffixed one (`utm` before `utm@beta`), and a beta rule measured
    /// against it reads "the beta is ahead of stable" — the normal state of a beta
    /// — as a phantom release. That is #559: `utm` sat at 4.7.5 while the beta rule
    /// read 5.0.5, which `utm@beta` also shipped.
    ///
    /// Both directions go, not just the phantom one. "The stable cask is a whole
    /// release ahead, so the probe is stuck" is no sounder across channels: an ESR
    /// sits a major behind stable on purpose (`thunderbird` 155 against ESR 140 in
    /// the same catalog). So a non-stable recipe with no cask of its own — CapCut's
    /// beta beside the plain `capcut` — is not cross-checked at all.
    static func caskIndex(for channel: ReleaseChannel, amongTokens tokens: [String]) -> Int? {
        guard channel != .stable else { return tokens.isEmpty ? nil : 0 }
        return tokens.firstIndex { $0.hasSuffix("@\(channel.rawValue)") }
    }

    /// How long a version we report may sit ahead of Homebrew before the gap
    /// stops looking like brew being slow and starts looking like the version
    /// not existing for macOS at all.
    ///
    /// Brew's normal lag on a live cask is hours to a couple of days, which is
    /// why the *ahead* direction was originally left unchecked — flagging it
    /// naively would fire on nearly every release for its first night. Ten days
    /// is past the point where any maintained cask has caught up, and the case
    /// this exists for never catches up: there is nothing to package.
    static let brewPickupDays = 10

    /// The check that would have caught LocalSend on day one.
    ///
    /// A phantom update is a version that is real, newer, and does not exist for
    /// this platform — a cross-platform project cutting a mobile-only point
    /// release out of a shared version number. Nothing fails: the endpoint
    /// answers, the tag parses, `lastGoodVersion` gets written, and the row shows
    /// an update that can never be installed and never clears. `duo verify` is
    /// structurally blind to it, because every check it runs asks "did the recipe
    /// parse something" rather than "is what it parsed true for macOS".
    ///
    /// The tell is the rest of the ecosystem declining to follow. Homebrew tracks
    /// the same upstream and packages only what it can actually install, so a
    /// non-auto-updating cask still sitting behind us well after publication says
    /// the artifact isn't there. Advisory, never fatal — it accuses a recipe of
    /// being *too* new, and the honest causes (a cask maintainer on holiday, a
    /// version scheme brew normalizes differently) deserve a human read.
    /// Takes the two cask fields it needs rather than a `CaskEntry`, which has no
    /// public initializer — widening the core's API so a test can build a fixture
    /// would be the tail wagging the dog.
    static func phantomVersionComplaint(
        caskToken: String, caskVersion: String, version: String,
        publishedAt: Date?, now: Date
    ) -> String? {
        // Without a publish date there is no way to tell a phantom from a release
        // that shipped an hour ago, and guessing wrong here means crying wolf on
        // every healthy recipe the night it updates. Sources that carry no date
        // simply opt out.
        guard let publishedAt else { return nil }
        let days = Calendar(identifier: .gregorian)
            .dateComponents([.day], from: publishedAt, to: now).day ?? 0
        guard days >= brewPickupDays else { return nil }
        // Brew spells some cask versions `version,build` (flameshot ships
        // `14.0.0,14.0`) and occasionally `version_revision`. Compared raw, the
        // suffix makes an identical version read as older and every one of those
        // casks becomes a false phantom — which is exactly what the first full
        // sweep with this check turned up. The upstream direction above dodges it
        // by only ever comparing major.minor.
        let caskUpstream = caskVersion.split(separator: ",").first.map(String.init) ?? caskVersion
        guard version != caskUpstream, VersionComparator.isNewer(version, than: caskUpstream)
        else { return nil }
        return "Homebrew's cask `\(caskToken)` is STILL at \(caskVersion) \(days) days after "
            + "\(version) was published — the newer version may not exist for macOS "
            + "(a platform-partial release), which would make this a permanent phantom update"
    }

    /// A recipe that declares a version window exists to keep one train's notes
    /// away from the other train's installs, so every entry its page yields must
    /// fall inside that window. Returns nil for a recipe with no window.
    ///
    /// Any entry outside counts, not just the newest: a page that carries both
    /// trains still shows a v1 user v2 notes. Entries whose `version` does not
    /// start with a digit are not judged — a headline has no position in a
    /// version window, the same scoping `changelogLagComplaint` applies.
    static func changelogWindowComplaint(
        _ recipe: ChangelogRecipe, entryVersions: [String]
    ) -> String? {
        guard recipe.declaresVersionWindow else { return nil }
        let outside = entryVersions.filter {
            $0.first?.isNumber == true && !recipe.covers(appVersion: $0)
        }
        guard !outside.isEmpty else { return nil }
        let window = "[\(recipe.minimumAppVersion ?? "0"), \(recipe.belowAppVersion ?? "∞"))"
        return "\(outside.count) of \(entryVersions.count) entries fall outside the recipe's "
            + "version window \(window) (\(outside.prefix(5).joined(separator: ", "))) — "
            + "the page is serving another train's notes"
    }

    /// Flag a changelog only when it trails the detected version at
    /// major.minor — see the call site for why the full-string comparison had to
    /// go.
    static func changelogLagComplaint(
        entry: String, detected: String, acknowledged: String? = nil,
        ordersByLineage: Bool = false
    ) -> String? {
        // Commit-hash versions have no order a string comparison can see (see
        // `BuildLineage`): "trails" between two hashes is a coin flip, and a
        // changelog whose newest release had no notes to show legitimately tops
        // out one build behind the version. Same reasoning as `Baseline`'s
        // "went BACKWARDS", which is scoped out for these recipes too.
        if ordersByLineage { return nil }
        // The vendor is the stale one and somebody has already read the live page
        // and said so — see `ChangelogRecipe.acknowledgedStaleEntry` for why this
        // is a version rather than an off switch. Scoped to the exact entry the
        // acknowledgement names, so it stops applying the moment the page moves in
        // EITHER direction: forward (the vendor published; worth one look) or
        // backward (the pattern slipped to an older section; worth a lot more).
        if let acknowledged, entry == acknowledged { return nil }
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

    /// The other direction: flag a changelog that reads AHEAD of every probe row
    /// for its app — which is what a **frozen probe** looks like from the outside.
    ///
    /// `changelogLagComplaint` above is deliberately one-directional and that is
    /// the gap this closes (#743). Every other history check compares a row
    /// against *its own* previous value, so a recipe that reads wrong
    /// *consistently* never moves and never complains: WorkBuddy's `.cn` pair sat
    /// green at 5.3.14 for weeks while the same sweep's changelog row held 5.5.6,
    /// both written with the identical `lastGoodAt`.
    ///
    /// **Above EVERY row, not above one of them.** Comparing against an arbitrary
    /// probe row reads a multi-channel app's other train as a disagreement —
    /// Thunderbird's changelog at 156.0 against its own ESR row at 140.16.0esr.
    /// Requiring the lead over all of them makes that case fall out for free: the
    /// stable row matches, so nothing is flagged.
    ///
    /// A naive reversal is ~80% false positives (measured over the committed
    /// baseline: 50 apps carry both a probe row and a changelog row, 4 have the
    /// changelog leading, 1 is a real bug). The other three are each a known,
    /// already-modelled situation, and this is where each is excluded:
    ///
    /// - **two numbering namespaces on one channel** — Claude for Desktop's GA
    ///   redirect and its Squirrel rollout endpoint are both `.stable` and answer
    ///   in different namespaces (2.2553.0 against 1.46388.4). "Above every row"
    ///   means nothing when the rows are not one ordered train, so a channel whose
    ///   rows disagree with EACH OTHER takes the whole app out of this check.
    ///   Across channels disagreement is normal and is handled above instead.
    /// - **another train's entries on the page** — Obsidian's insider builds
    ///   share its changelog with stable; see `ChangelogRecipe.carriesOtherTrainEntries`.
    /// - **one release spelled two ways** — Thunderbird Beta's page says
    ///   `157.0beta` where its probe says `157.0b2`. `numericMajorMinor` drops the
    ///   qualifier from both, which is sound for a check that only ever asks
    ///   whether a WHOLE release separates the two.
    ///
    /// Persistence is not enforced here: a publishing-order skew resolves in a
    /// sweep or two, and `Baseline.actionableThreshold` already holds a warning
    /// back until it has survived two sweeps before anything is filed.
    ///
    /// The first full live sweep with this check raised exactly one warning the
    /// baseline had not — HBuilderX, whose notes carry 5.26.2026091702 while its
    /// `release.json` went back to 5.24.2026081301 — so the complaint names that
    /// reading as well as the frozen-probe one. Its 5.26 dmg is still on the CDN
    /// and still answers, so the config was rolled back, not the release
    /// withdrawn; the message says "stopped offering" for that reason.
    static func changelogLeadsProbeComplaint(
        entry: String, probeVersionsByChannel: [String: [String]],
        carriesOtherTrainEntries: Bool = false, ordersByLineage: Bool = false
    ) -> String? {
        // Same scoping as `changelogLagComplaint`: hash builds have no order a
        // version string can show, and a headline captured into `version` is not a
        // version at all.
        if ordersByLineage || carriesOtherTrainEntries { return nil }
        guard entry.first?.isNumber == true else { return nil }
        let rows = probeVersionsByChannel.values.flatMap { $0 }
        guard !rows.isEmpty, rows.allSatisfy({ $0.first?.isNumber == true }) else { return nil }
        // A channel that answers in two namespaces cannot be led or trailed.
        for versions in probeVersionsByChannel.values
        where Set(versions.map(numericMajorMinor)).count > 1 {
            return nil
        }
        guard rows.allSatisfy({ leads(entry, $0) }) else { return nil }
        let listed = rows.sorted().joined(separator: ", ")
        // Both readings, because the first full live sweep with this check turned
        // up the second one: HBuilderX's notes carry 5.26.2026091702 while the
        // `release.json` the probe reads went back to 5.24.2026081301 (Homebrew's
        // cask agrees with the probe). Naming only the frozen-probe reading would
        // send whoever picks that up looking for a pattern that is fine.
        //
        // "stopped offering", not "pulled": HBuilderX's 5.26 dmg is still on the
        // CDN and still answers — only the config that points at it went back. A
        // reader told the release was withdrawn would check the artifact, find it,
        // and conclude the warning was wrong.
        return "newest changelog entry (\(entry)) reads AHEAD of every probe row "
            + "(\(listed)) — either the probe is stuck on a stale element, which no "
            + "history check can see because a consistently wrong reading never moves, "
            + "or the vendor stopped offering a release its notes still carry"
    }

    /// Whether `entry` is a whole release ahead of `probe`, by the same two
    /// yardsticks `changelogLagComplaint` uses in the other direction: days for a
    /// date-encoded scheme, major.minor for everything else.
    private static func leads(_ entry: String, _ probe: String) -> Bool {
        if let entryDay = buildDate(entry), let probeDay = buildDate(probe) {
            let days = gmtCalendar.dateComponents([.day], from: probeDay, to: entryDay).day ?? 0
            return days > staleNotesDays
        }
        let ours = numericMajorMinor(entry)
        let theirs = numericMajorMinor(probe)
        return ours != theirs && VersionComparator.isNewer(ours, than: theirs)
    }

    /// major.minor with each component cut at its first non-digit: `157.0beta` and
    /// `157.0b2` both become `157.0`, `140.16.0esr` becomes `140.16`, and brew's
    /// `156.0,1` / `3.22.3+105` spellings lose the suffix their own comparison
    /// would otherwise read as newer.
    ///
    /// Lossy on purpose, and only safe because every caller is asking whether a
    /// WHOLE release separates two readings. A prerelease qualifier never is one.
    static func numericMajorMinor(_ version: String) -> String {
        version.split(separator: ".").prefix(2)
            .map { $0.prefix(while: \.isNumber) }
            .joined(separator: ".")
    }

    /// This sweep's probe readings for one app, grouped by the channel each was
    /// read for.
    ///
    /// Only the registries that probe a VERSION — a changelog row is what we are
    /// checking and the App Store and feed sweeps answer about other things. An
    /// `infra` row is a network failure, not a reading, and carries no version
    /// anyway; the nil check covers it.
    static func probeVersionsByChannel(
        forBundleID bundleID: String, among findings: [Finding]
    ) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for finding in findings
        where finding.bundleID == bundleID
            && (finding.registry == .vendor || finding.registry == .github) {
            guard let version = finding.version, finding.status != .infra else { continue }
            out[finding.channel, default: []].append(version)
        }
        return out
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
        attempts: Int, gatewayRetries: Int, installed: InstalledVersion?,
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
                attempts: attempts, gatewayRetries: gatewayRetries,
                elapsedMs: outcome.elapsedMs, bodySample: outcome.bodySample)
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
        var warnings = outcome.warnings.map(\.display)
        warnings.append(contentsOf: sanity(version, remote))
        if let installed, let complaint = RecipeSanity.remoteBehindInstalled(
            remote: remote, installedMarketing: installed.marketing,
            installedBuild: installed.build, installedVendorBuild: installed.vendorBuild) {
            warnings.append(complaint)
        }
        // A vendor 5xx while resolving the installer URL is reported but is not
        // actionable: it accuses nobody, and treating it as one files an issue
        // against a recipe that is working. `td.telegram.org` 502s that HEAD in
        // bursts, which is what this exists for. Everything else keeps flipping
        // the finding to `.warn`, including a genuinely dead install URL.
        // `hasPrefix`, not `==`: a warning is published as `kind: detail`, and the
        // detail is what tells a 404 from a 403. Matching the whole string here
        // would silently stop exempting transients the moment one carried a
        // status — i.e. always — and start filing issues against vendors having
        // a bad minute.
        let transientKind = ProbeWarning.installURLTransient(status: nil).kind
        let actionable = warnings.filter { !$0.hasPrefix(transientKind) }
        return make(actionable.isEmpty ? .ok : .warn, version: version, warnings: warnings)
    }

    /// Index the locally installed apps by the recipe id they'd be checked
    /// under, so a recipe can find its own installed copy without re-deriving
    /// the channel gate.
    ///
    /// **Bounded, because this scan can block forever** — `BoundedScan` holds the
    /// mechanism and every reason for it. The cross-check is a bonus signal:
    /// losing it costs one class of finding, while waiting for it costs the
    /// entire sweep.
    ///
    /// `TestFlightInventory` now bounds its own open, so this should no longer be
    /// reachable through TestFlight. It stays because it is the last guard around
    /// everything *else* `scan()` touches — other apps' containers, network
    /// volumes, a stalled automount.
    ///
    /// The TestFlight store is read by `Inventory.readsTestFlight`'s rule, like every
    /// other `duo` scan. `AppScanner()`'s default reads it unconditionally, and this
    /// sweep is scheduled from launchd, where a job measured 2026-09-13 had no Full
    /// Disk Access to inherit; whether the scheduled sweep's own reads were refused
    /// was not measured. Only the detection setting is read
    /// (`Settings.loadTestFlightDetection`), never `Settings.load()`: that also reads
    /// the Keychain and may run `gh`, unbounded, which this sweep never did before.
    static func installedVersions() async -> [String: InstalledVersion] {
        let proofs = ResolvedChannelStore.Snapshot()
        let scanned = await Inventory.boundedRead(
            Settings.loadTestFlightDetection(), within: BoundedScan.timeout
        ) { reads in
            var out: [String: InstalledVersion] = [:]
            // Inside the closure: the store's open is what the bound races.
            for app in AppScanner(testflight: Inventory.testFlightStore(reads: reads)).scan() {
                guard let bundleID = app.bundleID else { continue }
                // An app whose bundle cannot name its own channel scans as
                // `.stable` no matter which train it is really on, so a copy of
                // UTM Beta would file itself under the stable rule's key — where
                // it is the wrong yardstick — and leave the beta rule with no
                // cross-check at all. Where a check has PROVEN the channel, that
                // is the honest key.
                //
                // Decided before writing, not by writing then correcting: two
                // copies of one app can be installed on different channels, and a
                // write-then-delete would let whichever came second erase the
                // other's entry.
                let channel = (app.channelIsAuthoritative
                    ? nil
                    : ResolvedChannelStore.provenChannelSnapshot(for: app, in: proofs))
                    ?? app.releaseChannel
                out["vendor:\(bundleID):\(channel.rawValue)"] = InstalledVersion(
                    marketing: app.shortVersion, build: app.buildVersion,
                    vendorBuild: app.vendorBuildVersion)
            }
            return out
        }
        guard let scanned else {
            FileHandle.standardError.write(Data("""
                ⚠︎ \(BoundedScan.gaveUpMessage(after: BoundedScan.timeout)) — continuing \
                without the installed-copy cross-check.\n
                """.utf8))
            return [:]
        }
        return scanned
    }
}

extension Finding {
    /// Marks a warning that describes the SWEEPING MACHINE rather than the
    /// recipe. Carried as a prefix on the string because `Finding` is the
    /// persisted report schema and a new field would have to be threaded
    /// through every construction site.
    ///
    /// It never reaches `Finding.signature` at all: that is computed over
    /// `publicWarnings`, which is defined as the warnings that do NOT carry this
    /// prefix. So a note can say something different every sweep — it names this
    /// machine's state — without the signature moving, which is the property the
    /// nudge rate limit depends on.
    public static let machineNotePrefix = "machine-note: "

    /// Attach a note without touching the status — see `machineNotePrefix`. A
    /// finding that accuses nobody must not accumulate an actionable streak, so
    /// this deliberately does NOT promote `ok` to `warn`; `Report` surfaces
    /// notes in their own section instead.
    public func observing(_ note: String) -> Finding {
        Finding(
            recipeID: recipeID, registry: registry, bundleID: bundleID, channel: channel,
            status: status, version: version,
            failureKind: failureKind, failureDetail: failureDetail,
            warnings: warnings + [note], endpointHost: endpointHost, pattern: pattern,
            attempts: attempts, gatewayRetries: gatewayRetries,
            // Every field forwarded, for the reason spelled out on
            // `adding(warning:)` below — and this one shipped without
            // `entryCount`, so a finding that picked up a machine note lost
            // "entries parsed" from `report.json`. Silently: every argument here
            // has a default. It happened a second time with `entryVersions`,
            // added by the very change that reads it to judge a BACKWARDS
            // complaint, so the field was dropped from exactly the complaining
            // rows it exists to explain. `findingRebuildsForwardEveryField`
            // pins the whole list now instead of trusting this comment.
            entryCount: entryCount, entryVersions: entryVersions,
            headingMatchesPage: headingMatchesPage,
            elapsedMs: elapsedMs, bodySample: bodySample)
    }

    /// Attach a warning discovered after the fact (the baseline's history checks
    /// run once every finding exists), promoting `ok` to `warn`.
    public func adding(warning: String) -> Finding {
        Finding(
            recipeID: recipeID, registry: registry, bundleID: bundleID, channel: channel,
            status: status == .ok ? .warn : status, version: version,
            failureKind: failureKind, failureDetail: failureDetail,
            warnings: warnings + [warning], endpointHost: endpointHost, pattern: pattern,
            attempts: attempts, gatewayRetries: gatewayRetries,
            // Every field forwarded, including the ones nothing here reads. A
            // rebuild that drops one silently deletes it from `report.json` for
            // exactly the findings that carry a complaint — the ones most worth
            // reading.
            entryCount: entryCount, entryVersions: entryVersions,
            headingMatchesPage: headingMatchesPage,
            elapsedMs: elapsedMs, bodySample: bodySample)
    }
}
