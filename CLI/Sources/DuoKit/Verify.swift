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
    /// The vendor's own build id, for the sources that report one
    /// (`RemoteVersion.buildNamespace == .vendor`). Nil for every other app.
    let vendorBuild: String?
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

        // Drop rows for recipes that no longer exist. Deliberately keyed on the
        // REGISTRIES rather than on what this run swept: `--only` and
        // `--changelog` narrow the sweep, and pruning against a narrowed run
        // would delete every row the filter excluded.
        let live = Set(
            VendorProbeRegistry.recipes.map(\.recipeID)
                + ChangelogRecipeRegistry.recipes.map(\.recipeID)
                + GitHubReleaseRegistry.rules.map(\.recipeID))
        let pruned = baseline.prune(keeping: live)
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
               let complaint = await brewComplaint(bundleID: recipe.bundleID, version: version) {
                finding = finding.adding(warning: complaint)
            }
            if let note = await rolloutTrackComplaint(recipe, source: source) {
                finding = finding.observing(note)
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
            return finding
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
            // See the vendor sweep: counts requests, not probes.
            let tally = GatewayRetry.Tally()
            // What the endpoint answered, as opposed to what we asked it. This is
            // the only check here that can see an UPSTREAM rename: the redirect
            // makes detection keep working, so every other signal stays green while
            // the request quietly loses its token. See ``GitHubEndpointAudit``.
            let audit = GitHubEndpointAudit.Ledger()
            var attempt = 0
            var outcome = await GitHubEndpointAudit.$ledger.withValue(audit) {
                await GatewayRetry.$tally.withValue(tally) {
                    await source.resolveDiagnostic(rule)
                }
            }
            while attempt < options.infraRetries,
                  outcome.failure?.classification == .infra {
                attempt += 1
                try? await Task.sleep(for: .seconds(attempt))
                outcome = await GitHubEndpointAudit.$ledger.withValue(audit) {
                    await GatewayRetry.$tally.withValue(tally) {
                        await source.resolveDiagnostic(rule)
                    }
                }
            }
            var finding = classify(
                outcome, registry: .github, host: "api.github.com",
                pattern: rule.versionPattern,
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
                   bundleID: rule.bundleID, version: version,
                   publishedAt: outcome.remote?.publishedAt) {
                finding = finding.adding(warning: complaint)
            }
            for complaint in Self.endpointComplaints(audit.observations) {
                finding = finding.adding(warning: complaint)
            }
            out.append(finding)
        }
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
    private static func sweepChangelog(
        _ recipes: [ChangelogRecipe], options: VerifyOptions, versions: [String: String]
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
                   acknowledged: recipe.acknowledgedStaleEntry) {
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
    static func brewComplaint(
        bundleID: String, version: String, publishedAt: Date? = nil, now: Date = Date()
    ) async -> String? {
        guard let cask = try? await HomebrewCaskCatalog.shared.entry(forBundleID: bundleID),
              !cask.autoUpdates  // an auto-updating cask's version is decorative
        else { return nil }

        func majorMinor(_ v: String) -> String {
            v.split(separator: ".").prefix(2).joined(separator: ".")
        }
        let ours = majorMinor(version)
        let theirs = majorMinor(cask.version)
        if ours != theirs, VersionComparator.isNewer(theirs, than: ours) {
            return "Homebrew's cask `\(cask.token)` is at \(cask.version) while this recipe "
                + "reads \(version) — the probe may be stuck on a stale element"
        }
        return phantomVersionComplaint(
            caskToken: cask.token, caskVersion: cask.version, version: version,
            publishedAt: publishedAt, now: now)
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

    /// Flag a changelog only when it trails the detected version at
    /// major.minor — see the call site for why the full-string comparison had to
    /// go.
    static func changelogLagComplaint(
        entry: String, detected: String, acknowledged: String? = nil
    ) -> String? {
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
                let version = InstalledVersion(
                    marketing: app.shortVersion, build: app.buildVersion,
                    vendorBuild: app.vendorBuildVersion)
                out["vendor:\(bundleID):\(app.releaseChannel.rawValue)"] = version
                // An app whose bundle cannot name its own channel scans as
                // `.stable` no matter which train it is really on, so a copy of
                // UTM Beta would file itself under the stable rule's key — where
                // it is the wrong yardstick — and leave the beta rule with no
                // cross-check at all. The channel a check PROVED is the honest
                // key for those; it is only ever an addition, so an app with a
                // real local signal is untouched.
                if !app.channelIsAuthoritative,
                   let proven = ResolvedChannelStore.provenChannelSnapshot(for: app),
                   proven != app.releaseChannel {
                    out["vendor:\(bundleID):\(app.releaseChannel.rawValue)"] = nil
                    out["vendor:\(bundleID):\(proven.rawValue)"] = version
                }
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
    /// Marks a warning that describes the SWEEPING MACHINE rather than the
    /// recipe. Carried as a prefix on the string because `Finding` is the
    /// persisted report schema and a new field would have to be threaded
    /// through every construction site.
    ///
    /// It survives `Baseline.signature`, which keys on the first 40 characters,
    /// so a note stays one stable signature rather than a new one per sweep.
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
            elapsedMs: elapsedMs, bodySample: bodySample)
    }
}
