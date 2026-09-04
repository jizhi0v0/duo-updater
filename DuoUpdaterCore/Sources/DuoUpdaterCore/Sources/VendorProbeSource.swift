import Foundation

/// Last-resort source for apps with a self-baked auto-updater and no App Store,
/// Sparkle, or Homebrew coverage. For each such app we maintain a bespoke
/// "probe recipe" (see `VendorProbeRecipe`) that reads the latest version
/// straight from the vendor's own download endpoint.
///
/// Wired as the **final** source in the checker so it only runs when the three
/// standard sources have all missed — vendor probes are slow, fragile, and
/// should never pre-empt a reliable source.
///
/// Never reports a version it isn't confident about, so it can't produce a
/// false "update available". What it does NOT do is stay quiet about failing:
/// a recipe that applied and could not answer throws ``ProbeFailed``, which
/// `UpdateChecker` turns into an `.error` row (a retryable "Failed" badge)
/// rather than the dead "—" that means *no source covers this app at all*.
/// Only `.notApplicable` — no recipe, wrong channel, wrong host, no device
/// identity on this Mac — still degrades to nil, because there is nothing there
/// to retry.
public struct VendorProbeSource: UpdateSource {
    static let sourceName = "Vendor"
    public let name = VendorProbeSource.sourceName

    /// Keyed by bundle id → the recipes for that id, one per release channel.
    /// Most apps have a single (stable) recipe; channels that share a bundle id
    /// (e.g. Android Studio stable + Canary) list several and are disambiguated
    /// by the installed app's detected channel.
    private let recipes: [String: [VendorProbeRecipe]]
    private let session: URLSession

    /// Cancels every redirect so the 3xx response is returned as-is. No stored
    /// state, so `@unchecked Sendable` is safe and required for the static below.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate,
        @unchecked Sendable
    {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    /// Session that does NOT follow redirects, shared across all
    /// ``VendorProbeSource`` instances and refreshes. Allocated once — creating
    /// a new `URLSession` per `init` (which happens on every ``AppListModel``
    /// `recheck`) discarded the connection pool and forced cold TCP handshakes
    /// on every retry.
    ///
    /// Cookie acceptance is disabled: the session is process-lifetime static, so
    /// any `Set-Cookie` headers from a 3xx vendor endpoint would otherwise
    /// accumulate for the entire run.
    private static let noRedirectSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }()

    /// Thrown by the `.redirect` install source when the vendor answered with a
    /// 5xx/429, or not at all, on every attempt — as opposed to answering with
    /// something that says the recipe is wrong.
    struct TransientInstallURL: Error {
        let status: Int?
    }

    /// The same rule `ProbeFailure.category` applies to version probes: 5xx and
    /// 429 are the vendor having a bad day, anything else in 4xx is us.
    static func isTransientStatus(_ code: Int) -> Bool {
        code >= 500 || code == 429
    }

    /// A browser-like UA — several vendor sites reject unfamiliar agents.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public init(
        recipes: [VendorProbeRecipe] = VendorProbeRegistry.recipes,
        session: URLSession = .updates
    ) {
        // Group by bundle id; each group holds that id's per-channel recipes.
        self.recipes = Dictionary(grouping: recipes, by: { $0.bundleID })
        self.session = session
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // A Mac App Store copy updates through the store, full stop. The vendor's
        // own download endpoint serves a *different distribution* that happens to
        // share a bundle id — Developer ID signed, unsandboxed, no receipt — and
        // it routinely runs ahead of the store build (WhatsApp: the store had
        // 26.32.75 while `web.whatsapp.com` redirected to `WhatsApp-2.26.33.19.dmg`).
        // Offering that as an update is a phantom update, and installing it would
        // swap away the `_MASReceipt` and the app's store entitlements.
        //
        // Same gate, same reasoning as `GitHubReleasesSource` and
        // `HomebrewCaskSource`, and it has to live here rather than in source
        // ordering for the same reason: `MacAppStoreSource` going first only wins
        // while it ANSWERS. `UpdateChecker` falls through on a thrown error too, not
        // just on a miss, so one flaky iTunes lookup hands the app to this source —
        // which is exactly how WhatsApp got pinned to 26.33.19 while a proxy was
        // down. Better "unknown" than a cross-distribution offer.
        //
        // Deliberately in `latestVersion` and not in `probeDiagnostic`: the recipe
        // sweeps (`duo verify`, the live channel tests) build synthetic apps and
        // must keep exercising every recipe regardless of how it happens to be
        // installed on the machine running them.
        guard !app.isMASApp else {
            // Only say "skip" when there was something to skip. The guard sits above
            // the recipe lookup (deliberately — it must hold whether or not one
            // exists), so without this every store app on the machine logged a line
            // per round for a source that was never going to touch it, reading as if
            // a recipe had been declined.
            if let bundleID = app.bundleID, recipes[bundleID] != nil {
                Log.source.info(
                    "vendor probe skip \(bundleID, privacy: .public): App Store copy, the store owns its updates")
            }
            return nil
        }
        // nil here is the ONE thing the row's "—" is allowed to mean: no recipe for
        // this bundle id, none for its channel, none this host can use, or the app
        // is Toolbox-managed. `probeDiagnostic` decides that before any request.
        guard let bundleID = app.bundleID,
              let outcome = await probeDiagnostic(for: app) else { return nil }
        guard let remote = outcome.remote else {
            let detail = outcome.failure.map { "\($0.kind): \($0.detail)" }
                ?? "probe resolved no version"
            // Record recipe health so a vendor changing their page is attributable
            // in diagnostics and not just a row that went quiet. A transient miss is
            // cleared by the next successful check (success/miss are compared by
            // recency), so this only flags consistently-broken recipes. Recorded for
            // the `.notApplicable` case below too: "this Mac has no such identity"
            // is exactly the kind of standing miss the sweep wants to see.
            await RecipeHealth.shared.recordMiss(id: bundleID, source: name, detail: detail)

            // A recipe that cannot apply on THIS machine is not a failure and has
            // nothing to retry: the device-identity and rollout-track selectors
            // answer `.notApplicable` when this Mac has no such identity, which is
            // the same "this source doesn't cover you" the gates above return nil
            // for. Everything else — a timeout, a 404, a pattern that stopped
            // matching — is a check that FAILED, and a failed check is not an
            // unsupported app.
            guard outcome.failure?.classification != .notApplicable else {
                Log.source.info(
                    "vendor probe not applicable \(bundleID, privacy: .public): \(detail, privacy: .public)")
                return nil
            }
            // `.notice`, not `.info`: `.info` from a third-party subsystem is never
            // written to disk, so the one line explaining why a row stopped
            // answering would not survive to be read afterwards.
            Log.source.notice(
                "vendor probe failed \(outcome.recipeID, privacy: .public): \(detail, privacy: .public)")
            throw ProbeFailed(bundleID: bundleID, failure: outcome.failure)
        }
        // The recipe answered — clears any standing miss on the next comparison.
        await RecipeHealth.shared.recordSuccess(id: bundleID, source: name)
        return remote
    }

    /// A recipe applied to this app and could not produce a version.
    ///
    /// Exists so `UpdateChecker` can tell a *failed check* from an *unsupported
    /// app*. Both used to arrive as nil, and the row rendered the same dead "—"
    /// for "nothing here covers this app" and "the vendor's endpoint timed out" —
    /// the second reads as the first, so a fixable outage looked like a permanent
    /// verdict with no retry offered. Thrown, it becomes `.error(_)`: a retryable
    /// badge, a row in the failed-check banner, and a `duo check` status that says
    /// what went wrong.
    ///
    /// Throwing does not change which source answers. `UpdateChecker` continues to
    /// the next source on a throw exactly as it does on a nil, and this source is
    /// last in the stack — the error only surfaces when nothing else answered.
    public struct ProbeFailed: LocalizedError {
        public let bundleID: String
        public let failure: ProbeFailure?

        /// The cause, never the app. `AppListModel.failedCheckSummary` groups
        /// failed rows by identical text to name one reason for a whole cluster
        /// ("The request timed out." across every row behind one dead network),
        /// and a message carrying the bundle id can never group with anything.
        /// The row already says which app it is.
        ///
        /// `.transport` unwraps to the bare `URLError` message so it groups with
        /// the other sources, which throw the `URLError` itself.
        public var errorDescription: String? {
            switch failure {
            case .transport(_, let message): return message
            case .some(let failure): return failure.detail
            case nil: return "the vendor probe resolved no version"
            }
        }
    }

    /// Everything that happened probing `app`, or nil when this source does not
    /// apply to it at all — no recipe for its bundle id, no recipe for its
    /// channel, or it is Toolbox-managed.
    ///
    /// The distinction nil carries is the point: `latestVersion(for:)` collapses
    /// "no recipe matched your channel" and "the vendor rewrote their page" into
    /// the same nil, which is exactly how a broken recipe hides. A caller that
    /// needs to tell those apart — the live channel tests, `duo verify` — asks
    /// here instead.
    public func probeDiagnostic(for app: InstalledApp) async -> ProbeOutcome? {
        // A Toolbox-managed JetBrains IDE updates through Toolbox. Probing the
        // vendor endpoint here would offer a cross-channel install — exactly what
        // we forbid — so defer to Toolbox even when a recipe matches the bundle.
        // The exception is an app our recipe tracks more reliably than Toolbox's
        // own verdict (Android Studio Canary/Beta, where Toolbox's local cache is
        // flaky/cross-track); see `InstalledApp.prefersVendorProbeOverToolbox`.
        guard !app.isToolboxManaged || app.prefersVendorProbeOverToolbox else {
            return nil
        }
        guard let bundleID = app.bundleID, let candidates = recipes[bundleID] else {
            return nil  // no recipe for this app — not applicable
        }
        // Channel gate: pick the recipe whose channel matches the installed app's,
        // and refuse if none does. When channels share a bundle id (e.g. Android
        // Studio's stable and Canary both carry `com.google.android.studio`), this
        // selects the right endpoint; when only a stable recipe exists, a detected
        // Beta/Canary install finds no match and is skipped rather than offered —
        // and one-click installed — a cross-channel build. Better "unknown" than
        // crossing channels.
        let channelMatched = candidates.filter { $0.channel == app.releaseChannel }
        guard !channelMatched.isEmpty else {
            Log.source.info(
                "vendor probe skip \(bundleID, privacy: .public): no recipe for app channel \(app.releaseChannel.rawValue, privacy: .public)")
            return nil
        }
        // Installed-version gate: a vendor can keep several MAJOR-VERSION
        // generations under one shared bundle id, each independently maintained
        // and each a separate product (Carbon Copy Cloner 5/6/7 all report
        // `com.bombich.ccc` — see `VendorProbeRecipe.installedVersionPattern`).
        // Drop the recipes that don't match the generation actually installed
        // BEFORE the multi-endpoint merge below, for the same reason the host
        // gate does: `best(of:)` takes the highest version among what's left, and
        // a newer generation's marketing string genuinely sorts higher than an
        // older one's, which would out-rank it every time otherwise — offering a
        // paid major-version upgrade as if it were the next point release.
        // Recipes with no `installedVersionPattern` — all but a handful — pass
        // unchanged.
        let installedMatched = channelMatched.filter { $0.matchesInstalled(version: app.shortVersion) }
        guard !installedMatched.isEmpty else {
            Log.source.info(
                "vendor probe skip \(bundleID, privacy: .public): no recipe for installed version \(app.shortVersion ?? "nil", privacy: .public)")
            return nil
        }
        // Host gate: a vendor can keep two trains open because the newer one
        // dropped hardware or OS versions the older one still serves (Raycast v2
        // is arm64 + macOS 26 only; v1 stays universal). Drop the recipes this Mac
        // cannot run BEFORE the multi-endpoint merge below — `best(of:)` answers
        // with the highest version and is only sound while every endpoint left in
        // the running serves a build this machine may legitimately install. Without
        // this the newer train out-ranks the older one on a machine that can only
        // use the older one, and the app is stuck reporting an update it can never
        // apply. Recipes with no `hostRequirement` — all but a handful — pass
        // unchanged.
        let matching = installedMatched.filter {
            $0.runs(onOS: SparkleAppcastSource.numericSystemVersion(), arch: HostArch.current)
        }
        guard !matching.isEmpty else {
            Log.source.info(
                "vendor probe skip \(bundleID, privacy: .public): recipe(s) for channel \(app.releaseChannel.rawValue, privacy: .public) require a host this Mac isn't")
            return nil
        }
        // For a Toolbox-managed app we only borrowed the probe to learn the version
        // RELIABLY (Toolbox's cache is flaky — see `prefersVendorProbeOverToolbox`);
        // the INSTALL must still go through Toolbox, never an in-place bundle swap
        // that would desync Toolbox's state and (for Android Studio) drag a ~1.5 GB
        // dmg off a drop-prone CDN. So resolve detection-only here.
        let allowInstall = !app.prefersVendorProbeOverToolbox

        guard matching.count > 1 else {
            return await probeOutcome(matching[0], allowInstall: allowInstall)
        }
        // One channel, several endpoints: probe them all and answer with the
        // highest version any of them stands behind. See `Self.best`.
        var outcomes: [ProbeOutcome] = []
        for recipe in matching {
            outcomes.append(await probeOutcome(recipe, allowInstall: allowInstall))
        }
        return Self.best(of: outcomes)
    }

    /// Pick the answer when a channel has more than one endpoint.
    ///
    /// This exists because a vendor can publish two *equally legitimate* views of
    /// "latest" that disagree, and neither is a fallback for the other. Claude is
    /// the case in hand: a public GA redirect (what the download button serves)
    /// and a staged-rollout endpoint keyed by this machine's device id (what the
    /// app's own updater acts on). Which is ahead flips over the life of a
    /// release — the rollout endpoint leads while a build ramps, the GA pointer
    /// catches up at the end — so "prefer endpoint A" is wrong half the time.
    ///
    /// Taking the highest is only sound because of a precondition the recipe
    /// author must uphold: **every endpoint listed for one channel must serve a
    /// build this machine may legitimately install.** Under that rule the highest
    /// is a real, current release, and the loser is simply the staler view. It
    /// would NOT be sound for endpoints that see different audiences (a beta feed
    /// next to a stable one) — that is what `channel` is for.
    ///
    /// A failing endpoint doesn't suppress a working one: failures only win when
    /// every endpoint failed, and then the first is reported so the health record
    /// and log still name a concrete reason. Each recipe is additionally swept on
    /// its own by `duo verify`, which is where a silently-broken loser surfaces.
    ///
    /// **Ties go to the richer answer, not to registry order.** Two endpoints
    /// naming the same version are not interchangeable: for Claude only the
    /// rollout endpoint states a `pub_date`, and the whole ramp is exactly the
    /// window in which that date is obtainable. Ranking by position let the
    /// bare GA answer win the moment GA caught up, and since
    /// `ReleaseTimelineStore.record` logs each version once at first sighting,
    /// a version that converged before we looked loses its real publish time
    /// permanently — it lands in the timeline as an estimated "≈" window with no
    /// way to correct it later. (1.30096.5 was lost this way on 2026-08-15.)
    static func best(of outcomes: [ProbeOutcome]) -> ProbeOutcome? {
        guard let first = outcomes.first else { return nil }
        var winner: ProbeOutcome?
        for outcome in outcomes {
            guard let candidate = Self.comparable(outcome.remote) else { continue }
            guard let incumbent = Self.comparable(winner?.remote) else {
                winner = outcome
                continue
            }
            if VersionComparator.isNewer(candidate, than: incumbent) {
                winner = outcome
            } else if candidate == incumbent, Self.isRicher(outcome, than: winner) {
                winner = outcome
            }
        }
        return winner ?? first
    }

    /// Tie-break between two outcomes naming the same version: keep the one that
    /// carries facts the other doesn't. An authoritative publish time first (it
    /// is the one that expires — see `best(of:)`), then a resolved installer, so
    /// a detection-only endpoint can't displace an installable one.
    private static func isRicher(_ candidate: ProbeOutcome, than incumbent: ProbeOutcome?) -> Bool {
        guard let incumbent else { return true }
        let gained = { (keep: (RemoteVersion) -> Bool) in
            candidate.remote.map(keep) == true && incumbent.remote.map(keep) != true
        }
        if gained({ $0.publishedAt != nil }) { return true }
        if incumbent.remote?.publishedAt != nil { return false }
        return gained({ $0.downloadURL != nil })
    }

    /// The string `best(of:)` ranks by. `makeRemoteVersion` puts a build-number
    /// recipe's value in `version` and a marketing recipe's in `shortVersion`, so
    /// this reads whichever the recipe filled — which is also why endpoints
    /// sharing a channel must agree on `versionIsBuild` (a build compared against
    /// a marketing string is the phantom-update bug that flag exists to prevent).
    /// `VendorProbeRegistryTests` enforces that agreement.
    private static func comparable(_ remote: RemoteVersion?) -> String? {
        remote.flatMap { $0.version ?? $0.shortVersion }
    }

    /// Run one recipe and report everything that happened, including the parts
    /// `latestVersion(for:)` discards.
    ///
    /// This lives on `VendorProbeSource` rather than in a verification tool on
    /// purpose: it must share the exact same redirect-blocking session, browser
    /// user agent, cache policy and HTTPS normalization as the shipping path. A
    /// reimplementation elsewhere would drift and start reporting failures the
    /// app never sees — and, worse, passes for recipes the app can't actually
    /// resolve.
    /// Run one recipe for the sweep, which unlike an update check wants every
    /// half-broken thing named rather than worked around.
    ///
    /// `checkingInstallURL` defaults to FALSE, and the default is the whole
    /// point: this method is the entry point for the recipe unit tests as well
    /// as the nightly, and it shares `probeOutcome` with the ordinary update
    /// path. Defaulting it on would put an extra request per app on every user's
    /// every check, and would send dozens of existing tests at live download
    /// hosts. Only `duo verify` passes true.
    public func probeDiagnostic(
        _ recipe: VendorProbeRecipe, checkingInstallURL: Bool = false
    ) async -> ProbeOutcome {
        await probeOutcome(recipe, allowInstall: true, checkInstallURL: checkingInstallURL)
    }

    /// Where this machine's track value came from — read off disk, or the
    /// recipe's declared fallback. Nil when the recipe has no track, or when the
    /// expansion fails outright.
    ///
    /// Deliberately narrow. The expanded URL stays inside this type, so a caller
    /// that wants to know "are we on the cautious track by default?" gets that
    /// answer and not a string with the machine's identifier in it.
    public func trackProvenance(_ recipe: VendorProbeRecipe) -> ProbeIdentity.Provenance? {
        guard recipe.track != nil, case .success(let resolved) = resolveEndpoint(recipe)
        else { return nil }
        return resolved.trackProvenance
    }

    /// Ask one recipe's endpoint twice — once as this machine, once as
    /// `RolloutTrack.contrastValue` — and report whether the vendor is serving
    /// two different answers right now. Nil for a recipe with no track.
    ///
    /// **Verification-time only.** It doubles the requests for the recipe, which
    /// is nothing inside a sweep that already makes ~150 and wrong inside the
    /// app's periodic check. It is also the only thing that can tell a healthy
    /// track selection from an irrelevant one: while a vendor's tracks are
    /// converged, every value gives the same answer, so our own answer looking
    /// right proves nothing about whether we chose right.
    public func rolloutTrackVerdict(_ recipe: VendorProbeRecipe) async -> RolloutTrackVerdict? {
        guard let track = recipe.track else { return nil }
        guard case .success(let mine) = resolveEndpoint(recipe),
              case .success(let contrast) = resolveEndpoint(
                recipe, trackOverride: track.contrastValue)
        else { return .indeterminate }
        // This machine already sits on the contrast track, so asking again as
        // the contrast establishes nothing. Not a finding — being an enterprise
        // account is not a defect.
        guard mine.url != contrast.url else { return .indeterminate }

        // Sequential on purpose. `Verify.byHost` walks one host's recipes one at
        // a time with a delay and jitter so "a host serving several recipes
        // doesn't see a metronome"; firing these two together would make the one
        // endpoint we ask about a track also the one endpoint we burst. The cost
        // is a single extra round trip on a path that only runs in a sweep.
        guard let ours = await trackVersion(recipe, at: mine.url),
              let theirs = await trackVersion(recipe, at: contrast.url)
        else { return .indeterminate }
        return ours == theirs
            ? .converged(ours)
            : .diverged(ours: ours, contrast: theirs)
    }

    /// The version one already-expanded endpoint reports, by the same extractor
    /// AND the same entry-scoping (`scopedBody`) a real probe uses — so a
    /// divergence means the tracks differ, not that two code paths read the body
    /// differently. No registry recipe carries both `track` and
    /// `entryStartPattern` today, but nothing should stop one from doing so
    /// safely, and a `rolloutTrackVerdict` that read the wrong slice would
    /// report a phantom `.diverged` straight into `duo verify`.
    private func trackVersion(_ recipe: VendorProbeRecipe, at endpoint: URL) async -> String? {
        guard case .success(let body) = await fetchBody(recipe, endpoint: endpoint)
        else { return nil }
        let extractor = recipe.selectHighest
            ? VendorProbeRecipe.highestVersion
            : VendorProbeRecipe.extractVersion
        return extractor(Self.scopedBody(recipe, body.text).text, recipe.versionPattern)
    }

    /// The text a recipe's first-match patterns (`versionPattern`,
    /// `displayVersionPattern`, `publishedAtPattern`, and the install spec's
    /// `.bodyPattern`-family URL) should actually run against: the winning
    /// entry when `entryStartPattern` slices the body and a version-pattern
    /// match picks one (see `VendorProbeRecipe.highestVersionEntry`), otherwise
    /// `body` verbatim — today's behaviour for every recipe that doesn't set
    /// `entryStartPattern`, and the fallback when slicing produces no winner.
    ///
    /// The single choke point every reader of the fetched body goes through,
    /// so a recipe with `entryStartPattern` set can't have one reader (say, a
    /// future addition) forget to scope while the others do.
    private static func scopedBody(_ recipe: VendorProbeRecipe, _ body: String) -> Scope {
        guard let pattern = recipe.entryStartPattern else {
            return Scope(text: body, fellBack: false)
        }
        guard let entry = VendorProbeRecipe.highestVersionEntry(
            in: body, entryStartPattern: pattern, versionPattern: recipe.versionPattern,
            selectHighest: recipe.selectHighest)
        else { return Scope(text: body, fellBack: true) }
        return Scope(text: entry, fellBack: false)
    }

    /// The text every reader runs against, plus whether getting it meant giving
    /// up on `entryStartPattern`.
    ///
    /// `fellBack` is the whole reason this isn't a bare `String`: reverting to
    /// whole-body first-match is a silent revert to the pre-#76 bug, and the
    /// caller turns it into `ProbeWarning.entryPatternNoMatch` so the nightly
    /// sweep sees it the first time a vendor reformats their feed rather than
    /// whenever two release trains next happen to overlap. False for a recipe
    /// that sets no `entryStartPattern` at all — that is not a fallback, it is
    /// the normal path for every recipe in the registry but two.
    private struct Scope {
        let text: String
        let fellBack: Bool
    }

    /// What a mode's fetch step yields on success: the text the version pattern
    /// runs against, the download URL that text resolved to, and the status code.
    private struct FetchedBody {
        let text: String
        let resolvedDownload: URL?
        let status: Int?
    }

    /// Run one recipe. `allowInstall` false forces a detection-only result even
    /// when the recipe carries an install spec — used for apps whose install
    /// another channel owns (Toolbox-managed), where we want the version but not
    /// an in-place swap.
    ///
    /// Never throws, and never answers with nothing at all: every non-confident
    /// outcome comes back as an outcome carrying a `ProbeFailure`. That pairing is
    /// a precondition the rest of the file relies on — `ProbeOutcome.failure` is
    /// non-nil exactly when `remote` is nil — so a new early return here needs a
    /// `ProbeFailure` naming its reason, never a bare "no version".
    ///
    /// Deciding what that reason MEANS is `latestVersion(for:)`'s job, and it is
    /// not the old best-effort nil: only `.notApplicable` still degrades to nil
    /// (the silent "—"), and every other classification is thrown and rendered as
    /// a retryable `.error` row. See ``ProbeFailure``.
    func probeOutcome(
        _ recipe: VendorProbeRecipe,
        allowInstall: Bool = true,
        checkInstallURL: Bool = false
    ) async -> ProbeOutcome {
        let started = DispatchTime.now()
        func elapsed() -> Int {
            Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
        }
        func fail(_ failure: ProbeFailure, status: Int? = nil, sample: String? = nil) -> ProbeOutcome {
            ProbeOutcome(
                recipeID: recipe.recipeID, bundleID: recipe.bundleID, channel: recipe.channel,
                remote: nil, failure: failure, httpStatus: status,
                bodySample: sample, elapsedMs: elapsed())
        }

        let body: FetchedBody
        switch await fetchBody(recipe) {
        case .failure(let failure):
            // A status-code failure is worth keeping the code for even though
            // there's no body to sample.
            if case .httpStatus(let code) = failure { return fail(failure, status: code) }
            return fail(failure)
        case .success(let fetched):
            body = fetched
        }

        // A recipe with `entryStartPattern` set names a feed that lists several
        // entries and is ordered by something other than version (publication
        // date, for Android Studio's preview feed): slice the body at that
        // pattern and narrow every first-match read below to the ONE entry whose
        // own version compares highest, so `version`, `display`, `publishedAt`
        // and the install URL can never land on different releases. Falls back
        // to the whole body — today's behaviour — when the recipe sets no such
        // pattern, or when slicing/matching doesn't produce a winner.
        // Sliced once: `fellBack` says slicing was asked for and produced no
        // winner, so everything below just reverted to whole-body first-match.
        // See `ProbeWarning.entryPatternNoMatch` for why that must not stay silent.
        let scoped = Self.scopedBody(recipe, body.text)
        let scope = scoped.text

        // The sample a human (or `duo triage`) sees to fix a broken pattern must
        // be the SAME text the extractors below actually ran against — sampling
        // `body.text` here would show a scoped recipe's reader a slice that isn't
        // where its answer came from, and worse, silently hand `duo triage` the
        // pre-#76 whole-body semantics for exactly the recipes this fix changed
        // (`Triage.swift` validates a proposed pattern with
        // `VendorProbeRecipe.extractVersion(from: finding.bodySample, ...)`).
        // Safe on the failure path below too: whenever extraction fails, `scope`
        // is already `body.text` by construction — `highestVersionEntry` only
        // ever returns a winner it already confirmed `versionPattern` matches,
        // so a scoped `scope` can't reach the miss branch.
        let sample = ProbeOutcome.sample(scope)

        // Default to the first match (the app's own field, which structured
        // bodies list first); only ascending-order feeds opt into highest-wins.
        let extractor = recipe.selectHighest
            ? VendorProbeRecipe.highestVersion
            : VendorProbeRecipe.extractVersion
        guard let version = extractor(scope, recipe.versionPattern) else {
            // Before accusing the recipe: is this the vendor's own error envelope?
            // A body that says "I could not compute your answer" is not a schema
            // change, and reporting it as one puts a red Failed row on every
            // affected Mac and files an issue under a recipe that is fine. Infra
            // instead — which `duo verify` retries, and only reports once it has
            // persisted for `Baseline.infraWindow`. Checked against `body.text`
            // rather than `scope` deliberately: the envelope is a property of the
            // whole response, and a scoped recipe whose slicing found no winner
            // has `scope == body.text` anyway.
            //
            // Says "in N bytes" and NOT "after a retry", because reaching here
            // does not prove one happened: `versionFeedData` spends its single
            // retry on a gateway 5xx first (a 503 whose retry returns the envelope
            // has seen the envelope exactly once), refuses to repeat a POST at
            // all, and is not on the `.redirectFilename`/`.zipEntryPlist` paths.
            // A log line asserting a retry nobody made is the kind of evidence
            // that sends the next outage's triage the wrong way.
            //
            // Only a recipe that declares `transientBodyPattern` can reach this;
            // for every other one the guard is false and nothing below changes.
            if recipe.matchesTransientBody(body.text) {
                // `.notice`, not `.error`: nobody has to go fix anything, but the
                // line has to survive to disk (`.info` from a third-party subsystem
                // does not) or a user asking why their row went red finds nothing.
                Log.source.notice(
                    "vendor probe \(recipe.bundleID, privacy: .public) [\(recipe.channel.rawValue, privacy: .public)]: vendor error envelope in \(body.text.utf8.count) bytes")
                return fail(
                    .vendorErrorEnvelope(sampleBytes: body.text.utf8.count),
                    status: body.status, sample: sample)
            }
            // Ask the vendor before blaming the recipe. A track between releases
            // and a recipe that stopped working both arrive here with no version,
            // and only the vendor can tell them apart — CapCut states it by
            // emptying `lastest_beta_number` when no beta is open. Reported as
            // `.notApplicable`, which returns nil rather than throwing: no red
            // row and no Retry button, because there is nothing to retry until
            // the vendor opens the track again.
            //
            // Checked here, after the pattern already failed, so a publishing
            // track can never be talked into looking closed.
            if recipe.matchesTrackClosed(body.text) {
                Log.source.notice(
                    "vendor probe \(recipe.bundleID, privacy: .public) [\(recipe.channel.rawValue, privacy: .public)]: vendor publishes no current build on this track")
                return fail(
                    .notApplicable(
                        "no current build on the \(recipe.channel.rawValue) track"),
                    status: body.status, sample: sample)
            }
            // Symmetric with `GitHubReleasesSource`, which has logged its
            // pattern misses since day one. A probe that fetched fine and matched
            // nothing is the exact shape of a vendor rewriting their page, and
            // until now it left no trace in the log at all.
            Log.source.error(
                "vendor probe \(recipe.bundleID, privacy: .public) [\(recipe.channel.rawValue, privacy: .public)]: \(body.text.utf8.count) bytes fetched, none matched /\(recipe.versionPattern, privacy: .public)/")
            // Before reporting a bare miss, try the one diagnosis that is cheap
            // and accounts for the most common way these die: the vendor changed
            // the number of segments in their version string. Saying so — with the
            // value the pattern would have read — turns a "go read the page"
            // investigation into a one-line fix.
            if let would = VendorProbeRecipe.versionIfSegmentCountRelaxed(
                from: scope, pattern: recipe.versionPattern) {
                return fail(
                    .versionSegmentCountChanged(
                        wouldMatch: would, sampleBytes: body.text.utf8.count),
                    status: body.status, sample: sample)
            }
            return fail(
                .versionPatternNoMatch(sampleBytes: body.text.utf8.count),
                status: body.status, sample: sample)
        }

        // Optional clean marketing string to show instead of an ugly build id
        // (e.g. Android Studio's "2026.1.2 RC 1" vs "AI-261.…"). Display only; the
        // build still drives the comparison. From the same scope, so first-match
        // within it belongs to the entry `versionPattern` matched.
        let display = recipe.displayVersionPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: scope, pattern: $0)
        }
        // Optional authoritative publish time, from the same scope (first match,
        // so it belongs to the entry `versionPattern` matched). A recipe that
        // declares no `publishedAtPattern` at all is not a failure — the
        // Release Log falls back to its estimated "≈" window, quietly. A
        // recipe that DOES declare one but gets no match, or a match
        // `ReleaseDate` can't parse at either tier, hits the same fallback but
        // warns: both silently disable `duo verify`'s age-gated phantom-update
        // check, and without the warning a declared-but-dead pattern reads
        // identically to never having declared one at all (issue #288).
        //
        // #300: routed through `publishedFields`, the same day/minute split
        // every other source uses, so a recipe whose pattern captures a bare
        // calendar day (Kiro's and Shottr's `publishedAtPattern` candidates,
        // both `"2025-12-17"`-shaped — see `VendorProbeRecipe`) gets a real
        // `vendorDay` instead of being warned about as unreadable.
        let publishedAtValue = recipe.publishedAtPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: scope, pattern: $0)
        }
        let publishedFields = ReleaseDate.publishedFields(from: publishedAtValue)

        var warnings: [ProbeWarning] = []
        if scoped.fellBack { warnings.append(.entryPatternNoMatch) }
        // A display pattern that found nothing leaves the row showing the raw
        // build id — and, for a recipe whose changelog URL is templated off that
        // string, a 404 where the release notes were. See `.displayPatternNoMatch`.
        if recipe.displayVersionPattern != nil, display == nil {
            warnings.append(.displayPatternNoMatch)
        }
        if recipe.publishedAtPattern != nil, publishedAtValue == nil {
            warnings.append(.publishedAtPatternNoMatch)
        } else if let publishedAtValue,
                  publishedFields.publishedAt == nil, publishedFields.vendorDay == nil {
            warnings.append(.publishedAtUnreadable(publishedAtValue))
        }
        var remote: RemoteVersion

        // If this recipe knows how to install in place, resolve the installer URL
        // (and any checksum) now — from the same scope we already narrowed the
        // version to (so a `.bodyPattern` install URL can't resolve against a
        // different entry than the version it's paired with). A failure here
        // just falls back to detection-only; it never blocks the version.
        if allowInstall, let spec = recipe.install {
            var resolved: (url: URL, checksum: String?)?
            var transient: TransientInstallURL?
            do {
                resolved = try await resolveInstall(spec, body: scope, version: version)
            } catch let error as TransientInstallURL {
                transient = error
            } catch {
                resolved = nil
            }
            if let plan = resolved {
                remote = Self.makeRemoteVersion(
                    recipe: recipe, version: version, install: spec, plan: plan,
                    resolvedDownload: body.resolvedDownload, display: display,
                    publishedAt: publishedFields.publishedAt, vendorDay: publishedFields.vendorDay,
                    // Deliberately `body.text`, not `scope`: this parses the WHOLE
                    // response as a Sparkle appcast document (`SparkleAppcastParser`)
                    // rather than reading a pattern out of it, so an entry-scoped
                    // fragment would not parse as XML at all. It is safe on its own
                    // terms regardless of scoping — it re-matches `version` against
                    // the parsed items itself and returns `[]` on anything but
                    // exactly one match.
                    //
                    // Do not read the `entryStartPattern` population as "JSON
                    // feeds that could never parse as an appcast anyway": WeChat's
                    // is a real Sparkle appcast, sliced at `<item>`, so this line
                    // now hands a parseable document to a parser that will parse
                    // it. That is still correct — whole-body is exactly what this
                    // call wants, and the feed carries no `sparkle:deltas` at all
                    // (measured 2026-08-30) — but it holds for the reason stated
                    // above, not because nothing here could parse.
                    deltas: VendorAppcastDeltas.patches(
                        inBody: body.text, forVersion: version, feedURL: recipe.url))
                // A recipe that names a checksum pattern but no longer matches one
                // still installs — unverified. Silent today; flag it.
                if spec.checksumPattern != nil, plan.checksum == nil {
                    warnings.append(.checksumPatternNoMatch)
                }
                // Resolving proved the URL is well-formed, not that the vendor
                // still serves it. For every source but `.redirect` those are
                // different claims, and the difference is invisible until a user
                // presses Update — the install-time signature gates never even
                // run, because a 404 delivers no bytes for them to judge.
                //
                // Note the URL probed is `plan.url`, i.e. AFTER `preferHTTPS` — the
                // same string the installer would download. Probing the pre-rewrite
                // URL would be testing something nobody fetches.
                //
                // No source is exempt, `.redirect` included. Resolving a redirect
                // DOES prove its final URL answered — but it proves it with THIS
                // type's browser-like agent and without `spec.requestHeaders`
                // (see the resolve above), and the installer sends
                // `Downloader.userAgent` plus those headers. SourceForge answers
                // 403 to one and 200 to the other, so "already proven" was a proof
                // about a request nobody makes: precisely the bug this probe was
                // written to catch, one boolean away from being blessed. 26 extra
                // HEADs a night is the cheaper side of that trade.
                if checkInstallURL,
                   let warning = Self.warning(
                       for: await installURLReachability(plan.url, spec: spec),
                       host: plan.url.host) {
                    warnings.append(warning)
                }
            } else {
                // Version still reads, one-click is dead. The app shows this app
                // as up-to-date-detectable but no longer installable, with no
                // signal anywhere — so name it.
                warnings.append(
                    transient.map { .installURLTransient(status: $0.status) }
                        ?? .installURLUnresolved)
                remote = Self.makeRemoteVersion(
                    recipe: recipe, version: version, install: nil, plan: nil,
                    resolvedDownload: body.resolvedDownload, display: display,
                    publishedAt: publishedFields.publishedAt, vendorDay: publishedFields.vendorDay)
            }
        } else {
            remote = Self.makeRemoteVersion(
                recipe: recipe, version: version, install: nil, plan: nil,
                resolvedDownload: body.resolvedDownload, display: display,
                publishedAt: publishedFields.publishedAt, vendorDay: publishedFields.vendorDay)
        }

        return ProbeOutcome(
            recipeID: recipe.recipeID, bundleID: recipe.bundleID, channel: recipe.channel,
            remote: remote, failure: nil, warnings: warnings,
            httpStatus: body.status, bodySample: sample, elapsedMs: elapsed())
    }

    /// What a recipe's placeholders expand to, and where the track value came
    /// from. `trackProvenance` is nil for a recipe with no `track`.
    struct ResolvedEndpoint {
        let url: URL
        let trackProvenance: ProbeIdentity.Provenance?
    }

    /// The one place a `ProbeIdentity` or a `RolloutTrack` is expanded. The
    /// result stays local to the caller so the machine's identifier reaches the
    /// request and nothing else — `recipe.url` (the placeholders) is what every
    /// log line, finding and outcome keeps carrying.
    ///
    /// `trackOverride` substitutes a literal for the track's own value instead
    /// of reading it, which is how the verification sweep asks the endpoint what
    /// a *different* track would be told. It is held to the same pattern and
    /// character gate as a read value; a recipe author's typo must not reach the
    /// wire either.
    func resolveEndpoint(
        _ recipe: VendorProbeRecipe, trackOverride: String? = nil
    ) -> Result<ResolvedEndpoint, ProbeFailure> {
        var endpoint = recipe.url
        for identity in recipe.identities {
            guard let resolved = identity.resolve(endpoint) else {
                return .failure(.notApplicable("no device identity at \(identity.displayPath)"))
            }
            endpoint = resolved
        }

        var provenance: ProbeIdentity.Provenance?
        if let track = recipe.track {
            if let override = trackOverride {
                guard let resolved = track.selector.resolve(endpoint, substituting: override)
                else {
                    return .failure(.notApplicable(
                        "'\(override)' is not a value \(recipe.bundleID)'s track accepts"))
                }
                endpoint = resolved
                provenance = nil
            } else {
                guard let resolved = track.selector.resolved(endpoint) else {
                    return .failure(.notApplicable(
                        "no rollout track at \(track.selector.displayPath)"))
                }
                endpoint = resolved.url
                provenance = resolved.provenance
            }
        }
        return .success(ResolvedEndpoint(url: endpoint, trackProvenance: provenance))
    }

    /// The per-mode fetch half of a probe, with each `return nil` in the original
    /// replaced by the specific reason it happened.
    private func fetchBody(_ recipe: VendorProbeRecipe) async -> Result<FetchedBody, ProbeFailure> {
        switch resolveEndpoint(recipe) {
        case .failure(let failure): return .failure(failure)
        case .success(let resolved): return await fetchBody(recipe, endpoint: resolved.url)
        }
    }

    /// `fetchBody` against an endpoint whose placeholders are already expanded.
    private func fetchBody(
        _ recipe: VendorProbeRecipe, endpoint: URL
    ) async -> Result<FetchedBody, ProbeFailure> {
        switch recipe.mode {
        case .redirectFilename:
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 15
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            Self.apply(recipe.requestHeaders, to: &request)

            if recipe.followRedirects {
                // HEAD + follow: the version lives in the final resolved URL's
                // filename (e.g. "ToDesk_4.7.6.0.dmg").
                request.httpMethod = "HEAD"
                let response: URLResponse
                do { (_, response) = try await session.versionFeedData(
                    for: request, label: "VendorProbe HEAD \(recipe.bundleID)") }
                catch { return .failure(Self.transportFailure(error)) }
                guard let http = response as? HTTPURLResponse else {
                    return .failure(.nonHTTPResponse)
                }
                guard (200..<400).contains(http.statusCode) else {
                    return .failure(.httpStatus(http.statusCode))
                }
                guard let finalURL = response.url else {
                    return .failure(.malformedResolvedURL("response carried no final URL"))
                }
                return .success(FetchedBody(
                    text: finalURL.lastPathComponent, resolvedDownload: finalURL,
                    status: http.statusCode))
            } else {
                // GET + don't follow: read the version out of the 3xx `Location`
                // header itself (following would just download the target). Some
                // endpoints — e.g. Claude's `dmg/latest/redirect` — 307 only on
                // GET, reject HEAD with 405, and expose the version nowhere but
                // the Location path, so `text` is the full redirect target.
                request.httpMethod = "GET"
                let response: URLResponse
                do { (_, response) = try await Self.noRedirectSession.versionFeedData(
                    for: request, label: "VendorProbe redirect \(recipe.bundleID)") }
                catch { return .failure(Self.transportFailure(error)) }
                guard let http = response as? HTTPURLResponse else {
                    return .failure(.nonHTTPResponse)
                }
                guard (300..<400).contains(http.statusCode) else {
                    return .failure(.httpStatus(http.statusCode))
                }
                guard let location = http.value(forHTTPHeaderField: "Location") else {
                    return .failure(.redirectMissingLocation)
                }
                guard let finalURL = URL(string: location, relativeTo: endpoint)?.absoluteURL
                else { return .failure(.malformedResolvedURL(location)) }
                return .success(FetchedBody(
                    text: finalURL.absoluteString, resolvedDownload: finalURL,
                    status: http.statusCode))
            }

        case .responseBody:
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 15
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            Self.apply(recipe.requestHeaders, to: &request)
            // An update service that only answers a POST (Omaha). The body is
            // fixed by the recipe — nothing about this machine goes into it.
            if let body = recipe.requestBody {
                request.httpMethod = "POST"
                request.httpBody = Data(body.json.utf8)
                request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
            }

            // When not following redirects we want the 3xx itself (its small body
            // / Location), so widen the accepted range and use the blocking session.
            let activeSession = recipe.followRedirects ? session : Self.noRedirectSession
            let okRange = recipe.followRedirects ? (200..<300) : (200..<400)
            // A vendor that reports its own outage inside a 200 gets the same one
            // retry a gateway 5xx gets, through the same helper — so the delay, the
            // "never retry a POST" guard and the sweep's request tally stay in one
            // place instead of growing a second copy here. Nil for every recipe that
            // declares no envelope, which is all of them but CapCut's: the predicate
            // is not built and `versionFeedData` never consults it.
            var transientBody: (@Sendable (Data) -> Bool)?
            if recipe.transientBodyPattern != nil {
                transientBody = { data in
                    recipe.matchesTransientBody(String(decoding: data, as: UTF8.self))
                }
            }
            let data: Data
            let response: URLResponse
            do { (data, response) = try await activeSession.versionFeedData(
                for: request, label: "VendorProbe \(recipe.bundleID)",
                retryableBody: transientBody) }
            catch { return .failure(Self.transportFailure(error)) }
            guard let http = response as? HTTPURLResponse else {
                return .failure(.nonHTTPResponse)
            }
            guard okRange.contains(http.statusCode) else {
                return .failure(.httpStatus(http.statusCode))
            }
            return .success(FetchedBody(
                text: String(decoding: data, as: UTF8.self),
                resolvedDownload: recipe.downloadURL ?? recipe.url,
                status: http.statusCode))

        case .zipEntryPlist(let entry, let key):
            // The version lives in a bundled Info.plist inside a (small) zip —
            // see `Mode.zipEntryPlist`. We extract the one entry and read `key`;
            // `text` becomes that value so the shared `versionPattern` validates
            // it exactly like any other mode.
            return await zipEntryPlistValue(url: endpoint, entry: entry, key: key)
                .map { FetchedBody(
                    text: $0, resolvedDownload: recipe.downloadURL ?? recipe.url,
                    status: nil) }
        }
    }

    /// Layer a recipe's own headers over the defaults set just above, so a recipe
    /// can override even `User-Agent` (SourceForge 403s the browser-like default
    /// — see `VendorProbeRecipe.requestHeaders`).
    /// What one reachability probe of a resolved installer URL concluded.
    enum InstallURLReachability: Sendable, Equatable {
        case ok
        /// The vendor answered 4xx to both a HEAD and a ranged GET.
        case gone(status: Int?)
        /// 5xx/429, or the request never completed. The vendor's problem, not
        /// the recipe's — aged by the same machinery as `installURLTransient`.
        case transient(status: Int?)
    }

    /// The verdict a reachability result carries into the sweep, or nil when the
    /// URL is fine.
    ///
    /// Pulled out as a pure function on purpose: the probe itself can only be
    /// exercised over a live socket, and a mapping that decides whether an issue
    /// gets filed should be checkable without one.
    static func warning(
        for result: InstallURLReachability, host: String? = nil
    ) -> ProbeWarning? {
        switch result {
        case .ok: return nil
        case .gone(let status): return .installURLNotFound(status: status, host: host)
        case .transient(let status): return .installURLTransient(status: status)
        }
    }

    /// Ask whether a resolved installer URL is still served, without downloading
    /// it. Sweep-only: see `probeDiagnostic(_:checkingInstallURL:)`.
    ///
    /// Two requests deep on purpose. A bare HEAD is not enough evidence to accuse
    /// a vendor of moving an artifact: some download hosts answer HEAD with 403 or
    /// 405 and serve the same URL perfectly to a GET, so a HEAD-only rule would
    /// file issues against recipes that work. So a 4xx HEAD is downgraded to a
    /// question, and a ranged GET answers it — `bytes=0-0` because these URLs are
    /// installers and a plain GET would pull hundreds of megabytes per recipe per
    /// sweep.
    ///
    /// A server that ignores `Range` and starts streaming the whole file is
    /// handled by taking the response head from `bytes(for:)` and cancelling the
    /// task before the stream is ever iterated, so the body is never read.
    ///
    /// The request must be byte-for-byte the request `Downloader` would make, or
    /// it is not answering the question. That is not a nicety — it is the one
    /// thing this method got wrong first, and the mistake was invisible in a
    /// curl spot check:
    ///
    /// Probing with this type's browser-like `userAgent` (right for VERSION
    /// endpoints, several of which reject unfamiliar agents) accused TigerVNC
    /// and GrandPerspective of losing their installers. Both were fine.
    /// SourceForge's edge answers **403 to a browser-like UA and 200 to
    /// `DuoUpdater/0.1`** — the reverse of the usual WAF, measured 2026-08-30 on
    /// the same URL in the same second with the UA as the only variable — and
    /// `Downloader` sends `DuoUpdater/0.1`. So the download works and the probe
    /// said it was gone.
    ///
    /// Hence: mirror `Downloader.swift` — its UA, its `Accept-Encoding: identity`
    /// — and then `spec.requestHeaders`, which is what it layers on top and what
    /// carries the per-vendor WAF workarounds — in the registry today that is
    /// Oray's `Referer`, and nothing else. (Not Alcove's `Authorization`: that
    /// lives on `RemoteVersion.downloadHeaders` in a source that is in no
    /// registry and never swept, so it does not reach here and does not need to.)
    /// Deliberately NOT `recipe.requestHeaders`: those belong to
    /// the version endpoint and the downloader never sends them, so honouring
    /// them here would make the probe pass URLs the real install cannot fetch.
    func installURLReachability(
        _ url: URL, spec: VendorInstallSpec
    ) async -> InstallURLReachability {
        func request(_ method: String, range: Bool) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 20
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.setValue(Downloader.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if range { request.setValue("bytes=0-0", forHTTPHeaderField: "Range") }
            Self.apply(spec.requestHeaders, to: &request)
            return request
        }

        var lastStatus: Int?
        // Same shape as the `.redirect` resolve above: retry the transient kinds a
        // few times before believing them, so one 502 in a burst does not cost a
        // recipe its green.
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
            }
            guard let (_, response) = try? await session.countedData(
                for: request("HEAD", range: false), purpose: .versionCheck),
                  let http = response as? HTTPURLResponse
            else { lastStatus = nil; continue }
            lastStatus = http.statusCode
            if (200..<400).contains(http.statusCode) { return .ok }
            if Self.isTransientStatus(http.statusCode) { continue }

            // 4xx. Could be a real 404, could be a host that simply refuses HEAD.
            //
            // `bytes(for:)`, not `data(for:)`: this returns once the response HEAD
            // is in, leaving the body unread, and we cancel before touching the
            // stream. `data(for:)` buffers the whole response first — so a host
            // that answers 4xx to HEAD and then IGNORES `Range` would have pulled
            // an entire installer into memory, which is both a hundreds-of-MB
            // stall and a straight violation of this sweep's "never downloads an
            // installer" contract (`Verify.swift`'s header).
            guard let (stream, ranged) = try? await session.bytes(for: request("GET", range: true)),
                  let rangedHTTP = ranged as? HTTPURLResponse
            else {
                // No answer at all. NOT `.gone`: the asymmetry matters, because
                // `.gone` files a public issue accusing a vendor of deleting an
                // artifact. A timeout, a reset or a TLS failure here is the same
                // event the HEAD path above treats as transient, and the honest
                // verdict for "we never got an answer" is that we do not know.
                // `lastStatus` still holds the HEAD's status for the report.
                continue
            }
            stream.task.cancel()
            if (200..<400).contains(rangedHTTP.statusCode) { return .ok }
            if Self.isTransientStatus(rangedHTTP.statusCode) {
                lastStatus = rangedHTTP.statusCode
                continue
            }
            // 416 means the range was refused, not that the artifact is missing —
            // the URL plainly exists to have rejected a range against it. 501 is
            // the same answer from a server that will not implement `Range` at
            // all. Either way this probe has run out of ways to ask, and guessing
            // "deleted" from a Range complaint is exactly the false accusation the
            // GET fallback exists to prevent.
            if rangedHTTP.statusCode == 416 || rangedHTTP.statusCode == 501 {
                lastStatus = rangedHTTP.statusCode
                continue
            }
            return .gone(status: rangedHTTP.statusCode)
        }
        return .transient(status: lastStatus)
    }

    private static func apply(_ headers: [String: String], to request: inout URLRequest) {
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    /// Classify a thrown networking error. `URLError` covers DNS, TLS, timeouts
    /// and dropped connections — all "try again", never "fix the recipe".
    private static func transportFailure(_ error: Error) -> ProbeFailure {
        let urlError = error as? URLError
        return .transport(
            urlErrorCode: urlError?.errorCode ?? (error as NSError).code,
            urlError?.localizedDescription ?? error.localizedDescription)
    }

    /// Assemble the `RemoteVersion` a recipe yields from an already-extracted
    /// version (and, when installing, a resolved download plan). Pure and offline
    /// so the version-routing contract — in particular `versionIsBuild`, which
    /// decides whether the engine compares against the installed marketing or
    /// build version — is unit-testable without hitting the network.
    static func makeRemoteVersion(
        recipe: VendorProbeRecipe,
        version: String,
        install spec: VendorInstallSpec?,
        plan: (url: URL, checksum: String?)?,
        resolvedDownload: URL?,
        display: String? = nil,
        publishedAt: Date? = nil,
        vendorDay: Date? = nil,
        deltas: [DeltaPatch] = []
    ) -> RemoteVersion {
        // A build-number recipe routes the value into `version` (compared against
        // the installed `CFBundleVersion`); `shortVersion` stays nil so a build
        // string can never be mismatched against a shorter marketing version —
        // UNLESS the recipe supplies an explicit display string (a clean marketing
        // version), in which case it rides in `shortVersion` for the UI only. The
        // engine still compares builds: `evaluate` prefers `version` whenever the
        // installed app has a `buildVersion`, which a `versionIsBuild` app always
        // does — so a display marketing string here never drives the comparison.
        let shortVersion = recipe.versionIsBuild ? display : version
        let buildVersion = recipe.versionIsBuild ? version : nil
        // Only meaningful alongside a build. A detection-only marketing answer is
        // in no build namespace at all, and stamping one on it would let a future
        // reader think the comparison was namespaced when it wasn't.
        let namespace: InstalledApp.BuildNamespace =
            recipe.versionIsBuild ? recipe.buildNamespace : .bundle

        if let spec, let plan {
            return RemoteVersion(
                shortVersion: shortVersion,
                version: buildVersion,
                buildNamespace: namespace,
                downloadURL: plan.url,
                // The install plan's URL is the artifact we fetch — handing it to
                // a browser downloads a pkg instead of opening a page. The recipe's
                // own `downloadURL` is the vendor's human-facing download page, and
                // it used to be dropped entirely on this branch, so "Open page"
                // silently started a download (ToDesk, UU Remote).
                pageURL: recipe.downloadURL,
                sourceName: sourceName,
                // pkg → hand to the system installer; archives → in-place swap.
                requiresManualInstaller: spec.kind == .pkg,
                vendorInstallerKind: spec.kind,
                expectedSHA512: plan.checksum,
                nestedArchivePath: spec.nestedArchivePath,
                downloadHeaders: spec.requestHeaders,
                changelogURL: recipe.changelogURL,
                publishedAt: publishedAt,
                vendorDay: vendorDay,
                // Only on the installable branch: a patch is an alternative route
                // to an artifact we are going to fetch, so it is meaningless on a
                // detection-only result that has no artifact to begin with.
                deltas: deltas
            )
        }

        return RemoteVersion(
            shortVersion: shortVersion,
            version: buildVersion,
            buildNamespace: namespace,
            downloadURL: recipe.downloadURL ?? resolvedDownload,
            // Only the curated `downloadURL` is a page. `resolvedDownload` falls
            // back to the probe endpoint, which is an API/redirect that serves a
            // file — never something to open in a browser.
            pageURL: recipe.downloadURL,
            sourceName: sourceName,
            // No install spec: detection only — the user downloads by hand.
            requiresManualInstaller: true,
            changelogURL: recipe.changelogURL,
            publishedAt: publishedAt,
            vendorDay: vendorDay
        )
    }

    /// Resolve an install spec into a concrete (url, checksum) pair. The body is
    /// the probe response we already fetched, reused for `bodyPattern` extraction.
    private func resolveInstall(
        _ spec: VendorInstallSpec, body: String, version: String
    ) async throws -> (url: URL, checksum: String?)? {
        let checksum = spec.checksumPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: body, pattern: $0)
        }

        switch spec.urlSource {
        case .fixed(let url):
            return (Self.preferHTTPS(url), checksum)

        case .versionTemplate(let template):
            // `version` is what the probe resolved (after `selectHighest`), so the
            // URL always names the release that was actually compared.
            let filled = template.replacingOccurrences(of: "{version}", with: version)
            guard let url = URL(string: filled) else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .bodyPattern(let pattern):
            guard
                let raw = VendorProbeRecipe.extractVersion(from: body, pattern: pattern),
                let url = URL(string: raw)
            else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .bodyPatternLast(let pattern):
            guard
                let raw = VendorProbeRecipe.lastMatch(from: body, pattern: pattern),
                let url = URL(string: raw)
            else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .bodyPatternHighestVersioned(let pattern):
            guard
                let raw = VendorProbeRecipe.highestVersionedURL(from: body, pattern: pattern),
                let url = URL(string: raw)
            else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .bodyPatternRelative(let pattern, let base):
            guard
                let raw = VendorProbeRecipe.extractVersion(from: body, pattern: pattern),
                let url = URL(string: raw, relativeTo: base)?.absoluteURL
            else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .bodyTemplate(let template, let fields):
            var filled = template
            for (i, pattern) in fields.enumerated() {
                guard let value = VendorProbeRecipe.extractVersion(from: body, pattern: pattern)
                else { return nil }
                filled = filled.replacingOccurrences(of: "{\(i)}", with: value)
            }
            guard let url = URL(string: filled) else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .redirect(let url):
            // The only install source that makes its own request, so it is the only
            // one that can fail for reasons that have nothing to do with the recipe.
            // `td.telegram.org` returns 502 to this HEAD in bursts — verified by
            // interleaving it with curl against the same URL in the same seconds,
            // which also came back 502, so it is the vendor and not URLSession.
            // Retry a few times, then say which kind of failure it was.
            var lastStatus: Int?
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
                }
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 15
                request.cachePolicy = URLRequest.versionFeedCachePolicy
                request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                guard let (_, response) = try? await session.countedData(for: request, purpose: .versionCheck),
                      let http = response as? HTTPURLResponse
                else { lastStatus = nil; continue }
                lastStatus = http.statusCode
                guard (200..<400).contains(http.statusCode) else {
                    // 4xx means the URL we were given is wrong — that IS the recipe,
                    // and retrying cannot help. Stop and report it as unresolved.
                    if !Self.isTransientStatus(http.statusCode) { return nil }
                    continue
                }
                guard let finalURL = response.url else { return nil }
                return (Self.preferHTTPS(finalURL), checksum)
            }
            throw TransientInstallURL(status: lastStatus)
        }
    }

    /// Download a (small) zip and read one property-list entry's string value —
    /// the runtime behind `Mode.zipEntryPlist`. Used for vendors (Spotify) whose
    /// only cheap version surface is a stub-installer archive whose bundled app's
    /// Info.plist tracks the latest client version. Every failure degrades the
    /// probe to "unknown" rather than guessing; the `Result` says which one.
    private func zipEntryPlistValue(
        url: URL, entry: String, key: String
    ) async -> Result<String, ProbeFailure> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.versionFeedData(
            for: request, label: "VendorProbe zip \(url.host ?? "?")") }
        catch { return .failure(Self.transportFailure(error)) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.nonHTTPResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(.httpStatus(http.statusCode))
        }

        // `unzip` needs a seekable file (the zip's central directory lives at the
        // end), so stage the archive in a temp file and extract just the one entry
        // to stdout. The entry is a small plist — well under the pipe buffer — so a
        // read-then-wait can't deadlock.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vendorprobe-\(UUID().uuidString).zip")
        do { try data.write(to: tmp) }
        catch { return .failure(.archiveExtractionFailed("cannot stage archive: \(error.localizedDescription)")) }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-p", tmp.path, entry]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() }
        catch { return .failure(.archiveExtractionFailed("cannot run unzip: \(error.localizedDescription)")) }
        let plistData = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            return .failure(.archiveExtractionFailed(
                "unzip exited \(proc.terminationStatus) extracting '\(entry)'"))
        }
        guard !plistData.isEmpty else {
            return .failure(.archiveExtractionFailed("'\(entry)' extracted empty"))
        }

        // Parse as a property list (Spotify's is a binary plist, `bplist00`) and
        // read the requested key as a string.
        guard
            let obj = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil),
            let dict = obj as? [String: Any]
        else { return .failure(.archiveExtractionFailed("'\(entry)' is not a property list")) }
        guard let value = dict[key] as? String else {
            return .failure(.plistKeyMissing(entry: entry, key: key))
        }
        return .success(value)
    }

    /// Upgrade/normalize download URLs to HTTPS. Our vendor hosts all support TLS,
    /// and App Transport Security blocks plain-http loads anyway; if a host
    /// somehow lacked https the download would just fail and degrade to
    /// detection-only — never wrong data. VLC's appcast points at the
    /// `get.videolan.org` mirror gateway, which may redirect to plaintext mirrors;
    /// the same archive is available directly from VideoLAN's HTTPS archive host.
    private static func preferHTTPS(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        if comps.host?.lowercased() == "get.videolan.org",
           comps.path.hasPrefix("/vlc/") {
            comps.host = "downloads.videolan.org"
            comps.path = "/pub/videolan" + comps.path
        }
        guard comps.scheme == "http" else { return comps.url ?? url }
        comps.scheme = "https"
        return comps.url ?? url
    }
}
