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

    public init(
        sources: [any UpdateSource],
        maxConcurrency: Int = 12,
        toolbox: ToolboxSource? = nil,
        testflight: TestFlightInventory? = nil
    ) {
        self.sources = sources
        self.maxConcurrency = max(1, maxConcurrency)
        self.toolbox = toolbox
        self.testflight = testflight
    }

    /// Check every app, returning results in the same order as the input.
    public func check(_ apps: [InstalledApp]) async -> [UpdateResult] {
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

        return results.compactMap { $0 }
    }

    /// Check one app across all sources in priority order.
    /// One app's check, with every request it makes filed against that app.
    ///
    /// The attribution is set here because this is the one place that knows both
    /// the app and the whole span of work done for it — a source may fetch a
    /// feed, follow a redirect and then probe a vendor endpoint, and all of it
    /// belongs to this app. Setting it any deeper would mean threading an id
    /// through every update source.
    public func check(_ app: InstalledApp) async -> UpdateResult {
        await RequestAttribution.withApp(app.id) { await performCheck(app) }
    }

    private func performCheck(_ app: InstalledApp) async -> UpdateResult {
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

        for source in sources {
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
        // somewhere real: three sources can run for a store copy — the store lookup
        // itself, `XcodeReleasesSource` (bundle-id gate only, and Xcode ships on the
        // store), and `SparkleAppcastSource` (feed-url gate only; Keka is a store
        // copy carrying a `SUFeedURL`). Only Homebrew, GitHub and the vendor probe
        // carry `guard !app.isMASApp`. None of those three is a *borrowed* read the
        // way Toolbox's is — each one IS this row's update check — so a failure
        // there has to read as a failed check. Painting it "Managed by the App
        // Store" would show the user the same row they get when the store is
        // quietly keeping the app current.
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
        Log.check.info("\(label, privacy: .public): no source applied → \(String(describing: status), privacy: .public)")
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
            return VersionComparator.isNewer(Self.normalizedBuild(rv), than: Self.normalizedBuild(iv))
                ? .updateAvailable(latest: remote.displayVersion ?? rv)
                : .upToDate
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
