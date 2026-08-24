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
/// Best-effort by design: any failure (network, redirect, parse) degrades
/// silently to "unknown". It never throws to the engine and never reports a
/// version it isn't confident about, so it can't produce a false "update
/// available" or a spurious error.
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
        // Swallow every failure: a probe that can't answer must look like "this
        // source doesn't apply", not like an error or a confident result.
        guard let bundleID = app.bundleID,
              let outcome = await probeDiagnostic(for: app) else { return nil }
        // Record recipe health so a vendor changing their page surfaces in
        // diagnostics rather than silently degrading the app to "unknown". A
        // transient miss is cleared by the next successful check (success/miss are
        // compared by recency), so this only flags consistently-broken recipes.
        if outcome.remote != nil {
            await RecipeHealth.shared.recordSuccess(id: bundleID, source: name)
        } else {
            await RecipeHealth.shared.recordMiss(
                id: bundleID, source: name,
                detail: outcome.failure.map { "\($0.kind): \($0.detail)" }
                    ?? "probe resolved no version")
        }
        return outcome.remote
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
        let matching = candidates.filter { $0.channel == app.releaseChannel }
        guard !matching.isEmpty else {
            Log.source.info(
                "vendor probe skip \(bundleID, privacy: .public): no recipe for app channel \(app.releaseChannel.rawValue, privacy: .public)")
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
    public func probeDiagnostic(_ recipe: VendorProbeRecipe) async -> ProbeOutcome {
        await probeOutcome(recipe, allowInstall: true)
    }

    /// What a mode's fetch step yields on success: the text the version pattern
    /// runs against, the download URL that text resolved to, and the status code.
    private struct FetchedBody {
        let text: String
        let resolvedDownload: URL?
        let status: Int?
    }

    /// Run one recipe. Returns nil (→ "unknown") on any non-confident outcome.
    /// `allowInstall` false forces a detection-only result even when the recipe
    /// carries an install spec — used for apps whose install another channel owns
    /// (Toolbox-managed), where we want the version but not an in-place swap.
    ///
    /// Never throws: every failure is captured as a `ProbeFailure` on the
    /// outcome, so callers that only want the version read `outcome.remote` and
    /// get exactly the old best-effort `nil`.
    func probeOutcome(_ recipe: VendorProbeRecipe, allowInstall: Bool = true) async -> ProbeOutcome {
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

        let sample = ProbeOutcome.sample(body.text)

        // Default to the first match (the app's own field, which structured
        // bodies list first); only ascending-order feeds opt into highest-wins.
        let extractor = recipe.selectHighest
            ? VendorProbeRecipe.highestVersion
            : VendorProbeRecipe.extractVersion
        guard let version = extractor(body.text, recipe.versionPattern) else {
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
                from: body.text, pattern: recipe.versionPattern) {
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
        // build still drives the comparison. From the same body, so first-match.
        let display = recipe.displayVersionPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: body.text, pattern: $0)
        }

        // Optional authoritative publish time, from the same body (first match, so
        // it belongs to the entry `versionPattern` matched). An unparseable or
        // missing date is not a failure — it just means the Release Log falls back
        // to its estimated "≈" window, exactly as for recipes with no pattern.
        let publishedAt = ReleaseDate.parse(
            recipe.publishedAtPattern.flatMap {
                VendorProbeRecipe.extractVersion(from: body.text, pattern: $0)
            })

        var warnings: [ProbeWarning] = []
        var remote: RemoteVersion

        // If this recipe knows how to install in place, resolve the installer URL
        // (and any checksum) now — from the same body we already have. A failure
        // here just falls back to detection-only; it never blocks the version.
        if allowInstall, let spec = recipe.install {
            var resolved: (url: URL, checksum: String?)?
            var transient: TransientInstallURL?
            do {
                resolved = try await resolveInstall(spec, body: body.text, version: version)
            } catch let error as TransientInstallURL {
                transient = error
            } catch {
                resolved = nil
            }
            if let plan = resolved {
                remote = Self.makeRemoteVersion(
                    recipe: recipe, version: version, install: spec, plan: plan,
                    resolvedDownload: body.resolvedDownload, display: display,
                    publishedAt: publishedAt,
                    deltas: VendorAppcastDeltas.patches(
                        inBody: body.text, forVersion: version))
                // A recipe that names a checksum pattern but no longer matches one
                // still installs — unverified. Silent today; flag it.
                if spec.checksumPattern != nil, plan.checksum == nil {
                    warnings.append(.checksumPatternNoMatch)
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
                    publishedAt: publishedAt)
            }
        } else {
            remote = Self.makeRemoteVersion(
                recipe: recipe, version: version, install: nil, plan: nil,
                resolvedDownload: body.resolvedDownload, display: display,
                publishedAt: publishedAt)
        }

        return ProbeOutcome(
            recipeID: recipe.recipeID, bundleID: recipe.bundleID, channel: recipe.channel,
            remote: remote, failure: nil, warnings: warnings,
            httpStatus: body.status, bodySample: sample, elapsedMs: elapsed())
    }

    /// The per-mode fetch half of a probe, with each `return nil` in the original
    /// replaced by the specific reason it happened.
    private func fetchBody(_ recipe: VendorProbeRecipe) async -> Result<FetchedBody, ProbeFailure> {
        // The one place a `ProbeIdentity` is expanded. `endpoint` stays local to
        // this function so the machine's identifier reaches the request and
        // nothing else — `recipe.url` (the placeholder) is what every log line,
        // finding and outcome keeps carrying.
        var endpoint = recipe.url
        for identity in recipe.identities {
            guard let resolved = identity.resolve(endpoint) else {
                return .failure(.notApplicable("no device identity at \(identity.displayPath)"))
            }
            endpoint = resolved
        }

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
                do { (_, response) = try await session.data(for: request) }
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
                do { (_, response) = try await Self.noRedirectSession.data(for: request) }
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
            let data: Data
            let response: URLResponse
            do { (data, response) = try await activeSession.data(for: request) }
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

        if let spec, let plan {
            return RemoteVersion(
                shortVersion: shortVersion,
                version: buildVersion,
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
                downloadHeaders: spec.requestHeaders,
                changelogURL: recipe.changelogURL,
                publishedAt: publishedAt,
                // Only on the installable branch: a patch is an alternative route
                // to an artifact we are going to fetch, so it is meaningless on a
                // detection-only result that has no artifact to begin with.
                deltas: deltas
            )
        }

        return RemoteVersion(
            shortVersion: shortVersion,
            version: buildVersion,
            downloadURL: recipe.downloadURL ?? resolvedDownload,
            // Only the curated `downloadURL` is a page. `resolvedDownload` falls
            // back to the probe endpoint, which is an API/redirect that serves a
            // file — never something to open in a browser.
            pageURL: recipe.downloadURL,
            sourceName: sourceName,
            // No install spec: detection only — the user downloads by hand.
            requiresManualInstaller: true,
            changelogURL: recipe.changelogURL,
            publishedAt: publishedAt
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
                guard let (_, response) = try? await session.data(for: request),
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
        do { (data, response) = try await session.data(for: request) }
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
