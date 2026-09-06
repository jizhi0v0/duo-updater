import Foundation

/// Orchestrates update checking across sources with bounded concurrency.
/// Sources are consulted in priority order; the first that returns a version
/// for an app wins. Network fan-out is capped so we don't open hundreds of
/// sockets at once.
public struct UpdateChecker: Sendable {

    public let sources: [any UpdateSource]
    public let maxConcurrency: Int
    /// When set, Toolbox-managed apps are version-checked (live JetBrains API,
    /// falling back to Toolbox's local cache); the action stays "open Toolbox".
    /// When nil they're simply labelled managed without a version.
    public let toolbox: ToolboxSource?

    /// When set, TestFlight-managed apps are version-checked against TestFlight's
    /// local cache; the action stays "open TestFlight". When nil they're simply
    /// labelled `.testFlightManaged` without a version.
    public let testflight: TestFlightInventory?

    /// The same store the GitHub source writes its channel proofs to. Held here
    /// so a check that FAILED can still label the row with what an earlier one
    /// proved; nil simply means no such memory (the default, and every app whose
    /// bundle can name its own channel is unaffected either way).
    public let channelStore: ResolvedChannelStore?

    public init(
        sources: [any UpdateSource],
        maxConcurrency: Int = 12,
        toolbox: ToolboxSource? = nil,
        testflight: TestFlightInventory? = nil,
        channelStore: ResolvedChannelStore? = nil
    ) {
        self.sources = sources
        self.maxConcurrency = max(1, maxConcurrency)
        self.toolbox = toolbox
        self.testflight = testflight
        self.channelStore = channelStore
    }

    /// Check every app, returning results in the same order as the input.
    ///
    /// `freshening` is for the caller that is about to re-check exactly this
    /// array because the user insisted (or a channel switch was observed) and
    /// does not want a memoized answer standing in for a live one — see
    /// `AppListModel.recheckMany`. Default `false` is what every periodic
    /// sweep, the CLI, and the verify harness rely on: without it, every
    /// source's memo would be dropped on every ordinary check, which defeats
    /// the reason `AppStorePageCache` exists.
    public func check(_ apps: [InstalledApp], freshening: Bool = false) async -> [UpdateResult] {
        // Drop each source's memoized answer for exactly this array, before the
        // prewarm below.
        //
        // ⚠️ That ordering is defensive, NOT load-bearing today, and an earlier
        // version of this comment claimed otherwise ("prewarm would refill what
        // this just dropped"). It would not: the only source implementing
        // either hook fills a different store in each — `prewarm` populates
        // `AppStoreLookupCache` (batched iTunes lookups), `invalidateMemo`
        // clears `AppStorePageCache` (product-page scrapes). Swapping these two
        // statements is currently unobservable, and the mutation was run: all
        // tests stay green. It is written this way so that a source which one
        // day memoizes during `prewarm` doesn't refill what was just dropped —
        // and whoever adds one owes this a test.
        if freshening {
            for source in sources { await source.invalidateMemo(for: apps) }
        }
        // Give every source a chance to do its cheaper-in-bulk work — e.g.
        // MacAppStoreSource batching iTunes lookups — before the per-app
        // fan-out below starts making the individual requests that work would
        // save. This is the one call site with the whole app list in hand at
        // once (a single-app recheck still arrives here as a one-element array,
        // so it still prewarms — for just that one app, same as any live
        // lookup would). Explicitly drained rather than left to `withTaskGroup`
        // to auto-await, so it's unambiguous that every source's prewarm has
        // finished — not merely been scheduled — before the fan-out begins.
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { await source.prewarm(apps) }
            }
            for await _ in group {}
        }

        var results = [UpdateResult?](repeating: nil, count: apps.count)

        await withTaskGroup(of: (Int, UpdateResult).self) { group in
            var next = 0
            var inFlight = 0

            func addTask(_ index: Int) {
                let app = apps[index]
                group.addTask {
                    (index, await self.check(app))
                }
            }

            // Prime the window.
            while next < apps.count && inFlight < maxConcurrency {
                addTask(next); next += 1; inFlight += 1
            }
            // Drain and refill. Stop scheduling new work once the enclosing task
            // is cancelled (e.g. a superseded refresh) so we don't run the whole
            // remaining fan-out to completion for results no one will use.
            while let (index, result) = await group.next() {
                results[index] = result
                inFlight -= 1
                if Task.isCancelled {
                    group.cancelAll()
                    continue  // keep draining in-flight tasks, schedule no more
                }
                if next < apps.count {
                    addTask(next); next += 1; inFlight += 1
                }
            }
        }

        // One write per pass, not one per proof: a pass proves a channel for at
        // most a couple of rows, and each is a line in a file nobody reads until
        // the next launch.
        //
        // Every production path lands here, including the one-row rechecks — they
        // go through `recheckMany`, which calls this array form with one element.
        // The single-app `check(_:)` is reached only from the loop above and from
        // the channel-verify harness, so no caller is left holding an unwritten
        // proof.
        await channelStore?.flush()

        return results.compactMap { $0 }
    }

    /// Check one app across all sources in priority order, then label the result
    /// with any channel an earlier check proved about this copy.
    ///
    /// The annotation is a separate step, and deliberately the LAST one, because
    /// the failure paths below all return `remote: nil` — the row that most needs
    /// its identity kept is the one that has no fresh evidence to carry it.
    ///
    /// Every request made along the way is filed against this app. This is the
    /// one place that knows both the app and the whole span of work done for it
    /// — a source may fetch a feed, follow a redirect and then probe a vendor
    /// endpoint, and all of it belongs here. Setting the attribution any deeper
    /// would mean threading an id through every update source.
    public func check(_ app: InstalledApp) async -> UpdateResult {
        await RequestAttribution.withApp(app.id) {
            var result = await runSources(for: app)
            if result.remote?.releaseChannel == nil,
               let proven = await channelStore?.channel(for: app) {
                result.provenChannel = proven
            }
            return result
        }
    }

    private func runSources(for app: InstalledApp) async -> UpdateResult {
        // JetBrains Toolbox owns its apps' updates end to end (some even ship a
        // Sparkle feed of their own, e.g. Air/Fleet). We never consult another
        // source for these — that would risk a cross-channel install. Instead we
        // read Toolbox's own local cache to show whether an update exists; the
        // action stays "open Toolbox". No data → just labelled managed.
        let label = "\(app.name) [\(app.bundleID ?? "no-bundle-id")] v\(app.shortVersion ?? "?")"
        Log.check.debug("check start: \(label, privacy: .public)")

        if app.isToolboxManaged && !app.prefersVendorProbeOverToolbox {
            if let verdict = await toolbox?.verdict(for: app) {
                let remote = RemoteVersion(
                    shortVersion: verdict.latestVersion,
                    // Carry the build id so the row can disambiguate a same-marketing
                    // EAP/nightly bump (2026.2 → 2026.2) by its build number.
                    version: verdict.latestBuild,
                    downloadURL: nil,
                    sourceName: "Toolbox",
                    requiresManualInstaller: true,
                    changelogURL: verdict.changelogURL)
                let status: UpdateStatus = verdict.hasUpdate
                    ? .updateAvailable(latest: verdict.latestVersion)
                    : .upToDate
                Log.check.info("\(label, privacy: .public): Toolbox → \(verdict.latestVersion, privacy: .public) (hasUpdate=\(verdict.hasUpdate, privacy: .public))")
                return UpdateResult(app: app, remote: remote, status: status)
            }
            Log.check.debug("\(label, privacy: .public): Toolbox-managed, no verdict")
            return UpdateResult(app: app, remote: nil, status: .toolboxManaged)
        }

        // TestFlight owns its betas' updates the same way Toolbox does. Never probe
        // another source (the App Store lookup would compare against the stable
        // track); read TestFlight's cached latest build instead. The action stays
        // "open TestFlight".
        if app.isTestFlightApp {
            if let latest = testflight?.latest(forBundleID: app.bundleID) {
                let installedBuild = app.buildVersion ?? ""
                let hasUpdate = VersionComparator.isNewer(latest.latestBuild, than: installedBuild)
                // Beta builds often keep the same marketing version across builds,
                // so disambiguate with the build number when the short string matches.
                let display = (latest.latestShortVersion == app.shortVersion)
                    ? "\(latest.latestShortVersion) (\(latest.latestBuild))"
                    : latest.latestShortVersion
                let remote = RemoteVersion(
                    shortVersion: latest.latestShortVersion,
                    version: latest.latestBuild,
                    downloadURL: nil,
                    sourceName: "TestFlight",
                    requiresManualInstaller: true)
                let status: UpdateStatus = hasUpdate
                    ? .updateAvailable(latest: display)
                    : .upToDate
                Log.check.info("\(label, privacy: .public): TestFlight → \(latest.latestBuild, privacy: .public) (hasUpdate=\(hasUpdate, privacy: .public))")
                return UpdateResult(app: app, remote: remote, status: status)
            }
            Log.check.debug("\(label, privacy: .public): TestFlight-managed, no cached build")
            return UpdateResult(app: app, remote: nil, status: .testFlightManaged)
        }

        var lastError: String?

        // One line for the row, not one per silenced source. `VendorProbeSource`
        // learned this: a per-source line for sources that were never going to
        // touch the row "reads as if a recipe had been declined", and here it
        // would be every store app times every declining source, every round.
        if app.isMASApp {
            let silenced = sources.filter { !$0.answersAppStoreCopies }.count
            if silenced > 0 {
                Log.check.debug("\(label, privacy: .public): \(silenced, privacy: .public) non-store sources silenced, the store owns this copy")
            }
        }

        for source in sources {
            // A store copy is answered by the store, or by nobody.
            //
            // Not by source ordering: `MacAppStoreSource` is first, but this loop
            // falls through on a THROWN error as well as on a miss, and the store
            // lookup misses often enough (region-locked storefront, a 404) that the
            // fall-through is ordinary. That is how a store WhatsApp was offered the
            // direct 26.33.19 dmg over its own 26.32.75.
            //
            // `answersAppStoreCopies` defaults to false, so this covers sources
            // nobody has thought about yet — including the four that had no guard
            // when this landed (Sparkle, Xcode, Electron, Alcove). See its doc
            // comment for why the default carries the weight.
            if app.isMASApp, !source.answersAppStoreCopies { continue }
            do {
                guard let remote = try await source.latestVersion(for: app) else {
                    Log.check.debug("\(label, privacy: .public): \(source.name, privacy: .public) miss")
                    continue  // source doesn't apply; try the next one
                }
                let status = Self.evaluate(installed: app, remote: remote)
                Log.check.info("\(label, privacy: .public): \(source.name, privacy: .public) → \(remote.displayVersion ?? "?", privacy: .public) [\(String(describing: status), privacy: .public)]")
                return UpdateResult(app: app, remote: remote, status: status)
            } catch {
                lastError = error.localizedDescription
                Log.check.error("\(label, privacy: .public): \(source.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        // A Toolbox-managed row outranks a failed read, and only this one does.
        //
        // Toolbox is the *installer* for these apps; the only reason a source ran at
        // all is `prefersVendorProbeOverToolbox` — Android Studio Canary/Beta, where
        // we borrow the vendor probe for a version Toolbox's own cache reports
        // unreliably. The action is "open Toolbox" either way, and it is valid
        // whether or not that borrowed read came back. Reporting `.error` instead
        // takes the Toolbox button off the row and offers a Retry for a version
        // number, which is the one thing the user does not need in order to act.
        // (Before vendor probes threw, this arrived as a nil and landed on
        // `.toolboxManaged` below — this keeps that.)
        //
        // Deliberately NOT extended to `.appStoreManaged`/`.testFlightManaged`.
        //
        // A MAS row that reaches `.error` was answered by nobody and failed
        // somewhere real: the gate at the top of the loop means the only source
        // that ran for it was `MacAppStoreSource` — the lookup for the app the
        // store DOES own. That is not a *borrowed* read the way Toolbox's is; it
        // IS this row's update check, so a failure has to read as a failed check.
        // Painting it "Managed by the App Store" would show the user the same row
        // they get when the store is quietly keeping the app current.
        //
        // True by construction of the gate PLUS the registry: it stops holding the
        // moment a second source declares `answersAppStoreCopies`.
        // `SourceStorePolicyTests.exactlyOneSourceAnswersStoreCopies` is what makes
        // that loud, and is the thing to read before changing this paragraph.
        //
        // It used to be an inventory of which sources happened to carry
        // `guard !app.isMASApp`, kept accurate by hand and re-checked whenever a
        // source was added. It was wrong twice: once by naming one source when
        // three could run, and then, in the commit that fixed that, by citing
        // Keka as a store copy carrying a `SUFeedURL` — Keka is Developer
        // ID-signed with no `_MASReceipt`, so `isMASApp` was false for it under
        // the very same derivation both then and now.
        //
        // TestFlight returns before the loop and never gets here at all.
        if let lastError, !app.isToolboxManaged {
            Log.check.error("\(label, privacy: .public): all sources exhausted, last error → .error(\(lastError, privacy: .public))")
            return UpdateResult(app: app, remote: nil, status: .error(lastError))
        }
        if let lastError {
            Log.check.error("\(label, privacy: .public): \(lastError, privacy: .public) — Toolbox owns this app, reporting it as managed")
        }
        // Apps whose updates a known channel already owns aren't "unknown" —
        // they're managed elsewhere. Toolbox takes precedence over the store flag
        // (a JetBrains IDE is never a MAS app, but be explicit about ordering).
        let status: UpdateStatus
        if app.isToolboxManaged {
            status = .toolboxManaged
        } else if app.isTestFlightApp {
            status = .testFlightManaged
        } else if app.isMASApp {
            status = .appStoreManaged
        } else {
            status = .unknown
        }
        // "nothing applied" for an ordinary row; for a store row the non-store
        // sources were not inapplicable, they were forbidden — the line above says
        // how many.
        Log.check.info("\(label, privacy: .public): no source answered → \(String(describing: status), privacy: .public)")
        return UpdateResult(app: app, remote: nil, status: status)
    }

    /// Re-derive a Toolbox row's status without a network call, for the same
    /// background-rescan path as `evaluate` — which a Toolbox row can't use, since
    /// its verdict is a Toolbox build compare, not a compare against the on-disk
    /// `shortVersion` (marketing for the IDEs, a divergent runtime track for
    /// Air/Fleet). Toolbox installs its apps itself, between our checks, and the
    /// rescan that picks up the new bundle would otherwise leave the cached
    /// "update available" standing beside it — the row reading "262.132.21 →
    /// 262.132.21" until the next check. `state.json` settles that offline: both
    /// sides here are Toolbox build ids in one namespace (`toolboxInstalledBuild`
    /// is its `buildNumber`; `remote.version` carries the verdict's `latestBuild`).
    ///
    /// One-way by design — it can only settle a row to up-to-date, never raise an
    /// update. The verdict is the only thing that accounts for pins, channels and
    /// retained older majors, none of which a bare build compare reproduces, so
    /// anything short of "the installed build caught up" keeps `cached`.
    public static func evaluateToolbox(
        cached: UpdateStatus, installed: InstalledApp, remote: RemoteVersion
    ) -> UpdateStatus {
        guard let installedBuild = installed.toolboxInstalledBuild,
              let latestBuild = remote.version,
              !VersionComparator.isNewer(latestBuild, than: installedBuild)
        else { return cached }
        return .upToDate
    }

    /// Decide whether `remote` is newer than what's installed. Prefer comparing
    /// build versions (Sparkle's canonical key) when both sides have one; fall
    /// back to the marketing version otherwise.
    ///
    /// A build that says "newer" is not on its own evidence of DIRECTION, so where
    /// the source has stated that its marketing string is the bundle's own
    /// (`RemoteVersion.marketingMatchesBundle`) a build-based verdict is refused
    /// when the marketing version says backwards — see the block comment below
    /// and #368.
    ///
    /// Public so a UI layer can cheaply RE-evaluate a freshly-rescanned app
    /// against an already-fetched remote (no network) — e.g. to notice an app
    /// updated itself in the background.
    public static func evaluate(installed: InstalledApp, remote: RemoteVersion) -> UpdateStatus {
        // A remote build stated in the VENDOR's namespace can only be compared
        // against the vendor's own value. Falling back to the marketing branch
        // here would be the failure this namespace exists to prevent: for a
        // Firefox beta the marketing string is frozen at "155.0" for the whole
        // cycle, so the fallback answers "up to date" every time and looks like a
        // working check. Say we cannot tell instead.
        if remote.buildNamespace == .vendor, remote.version != nil,
           installed.vendorBuildVersion == nil {
            return .unknown
        }

        // Prefer comparing build versions (Sparkle's canonical key) when both
        // sides have one.
        if let rv = remote.version, let iv = installed.buildVersion(in: remote.buildNamespace) {
            // JetBrains stamps CFBundleVersion with a product-code prefix
            // ("IU-262.6653.22") while a vendor build id is bare ("262.7132.23").
            // Strip a leading "<LETTERS>-" run from both so they compare in one
            // namespace — otherwise the tokenizer ranks the bare side above the
            // prefixed one unconditionally (a text run sorts below a number), which
            // would show a perpetual phantom update even right after installing.
            guard VersionComparator.isNewer(Self.normalizedBuild(rv), than: Self.normalizedBuild(iv))
            else { return .upToDate }

            // The build says newer. Ask the marketing version whether that means
            // FORWARD, but only where the source has stated its string is the
            // bundle's own (`marketingMatchesBundle`) — a build number moving is
            // not, by itself, evidence of direction.
            //
            // A vendor whose builds run monotonically ACROSS two trains hands a
            // prerelease copy a stable build that is numerically newer and three
            // releases older, and every gate downstream passes it: the package is
            // the vendor's, signed, notarized, and the only downgrade guard in the
            // repo (`SignatureVerifier.verifyNoArchitectureDowngrade`) is about
            // architecture. Measured on coteditor.com/appcast.xml, 2026-09-06: a
            // copy on 7.1.0-beta.3 (build 840) whose build the vendor has trimmed
            // out of the feed falls back to the default channel and is offered
            // 7.0.9 (build 843). Installing it also ends the beta train — the copy
            // then matches the STABLE item, so the channel inference reads it
            // `.stable` from then on. See #368.
            //
            // Deliberately one-way: this can only settle a row to `.upToDate`,
            // never raise an update, so the worst it can do to a source that
            // states the flag wrongly is stop offering — never install something
            // it should not have. The remote still travels with the row, so the
            // version readout, the release notes and the timeline are unaffected.
            if remote.marketingMatchesBundle,
               VersionComparator.isMarketingDowngrade(
                   offered: remote.shortVersion, from: installed.shortVersion) {
                return .upToDate
            }
            return .updateAvailable(latest: remote.displayVersion ?? rv)
        }

        // Otherwise fall back to the marketing (short) version.
        guard let rs = remote.shortVersion, let isv = installed.shortVersion else {
            return .unknown
        }
        if !VersionComparator.isNewer(rs, than: isv) {
            return .upToDate
        }

        // The remote looks newer by marketing version alone — but some vendors
        // fold the build INTO the version string: Oray reports "16.5.0.30757"
        // while the installed bundle splits it into short "16.5.0" + build
        // "30757". Re-check against the installed short+build; if that isn't older
        // than the remote, the app is actually current — otherwise the row would
        // show a perpetual "update" even right after a successful install. Guarded
        // to a plain-numeric build tail not already part of the short version, so
        // normal apps (whose build duplicates/dot-extends the short version) are
        // unaffected — they never reach here unless genuinely behind.
        if let build = installed.buildVersion,
           !build.isEmpty, !build.contains("."), !isv.hasSuffix(build) {
            let combined = "\(isv).\(build)"
            if !VersionComparator.isNewer(rs, than: combined) {
                return .upToDate
            }
        }

        return .updateAvailable(latest: remote.displayVersion ?? rs)
    }

    /// Drop a leading product-code run like "IU-"/"AI-" from a build number so a
    /// prefixed CFBundleVersion ("IU-262.6653.22") compares against a bare vendor
    /// build ("262.7132.23"). Plain builds ("45830", "262.7132.23", "1.2.3-beta")
    /// pass through untouched — only a pure-letter segment before the first hyphen
    /// is treated as a prefix.
    static func normalizedBuild(_ build: String) -> String {
        guard let dash = build.firstIndex(of: "-"), dash != build.startIndex,
              build[..<dash].allSatisfy(\.isLetter) else { return build }
        return String(build[build.index(after: dash)...])
    }
}
