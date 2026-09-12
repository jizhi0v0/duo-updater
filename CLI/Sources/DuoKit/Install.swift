import Foundation
import DuoUpdaterCore

/// `duo install` — apply updates from the command line.
///
/// Runs the same `InstallCoordinator` the menu-bar app runs, gated by the same
/// `UpdatePolicy`, so what this installs and how is not a second opinion.
///
/// Two things it deliberately will not do:
///  - **App Store.** That route needs either the privileged helper (whose
///    `SMAppService.daemon` registration requires an app bundle) or the
///    Accessibility API driving App Store.app. A CLI has neither, so it says so
///    instead of failing halfway.
///  - **Take the lock by force.** If the menu-bar app is installing, this exits
///    rather than swapping a bundle underneath it.
public enum Install {

    public struct Options: Sendable {
        public var queries: [String] = []
        public var all = false
        public var dryRun = false
        public var assumeYes = false
        public var json = false
        /// Narrow the batch to updates that would take these routes. Empty means
        /// all of them.
        ///
        /// A filter, deliberately not an override. The route is derived from the
        /// source, and forcing a different one is how you install a build from
        /// the wrong channel — the single thing the whole source/channel design
        /// exists to prevent. "Only do the Homebrew ones tonight" is the real
        /// use; "install this vendor app through brew instead" is not something
        /// we should make possible.
        public var routes: Set<InstallCoordinator.Route> = []
        public init() {}
    }

    /// Resolve `--route` names to routes, or report the first unknown one.
    /// Matched case-insensitively so `appstore` works as well as `appStore` —
    /// the raw values are camelCase, which nobody types.
    public static func routes(named names: Set<String>) -> Result<Set<InstallCoordinator.Route>, UsageError> {
        var resolved: Set<InstallCoordinator.Route> = []
        for name in names {
            guard let route = InstallCoordinator.Route.allCases.first(
                where: { $0.rawValue.lowercased() == name.lowercased() })
            else {
                let known = InstallCoordinator.Route.allCases
                    .map { $0.rawValue.lowercased() }.sorted().joined(separator: ", ")
                return .failure(UsageError("unknown --route '\(name)'; expected one of: \(known)"))
            }
            resolved.insert(route)
        }
        return .success(resolved)
    }

    public static func run(_ options: Options) async -> Int32 {
        guard options.all || !options.queries.isEmpty else {
            FileHandle.standardError.write(Data(
                "duo: name an app, or pass --all\n".utf8))
            return 2
        }

        let settings = Settings.load()
        let apps = await Inventory.scan(settings)
        let selected: [InstalledApp]
        switch Inventory.select(apps, matching: options.queries) {
        case .success(let matched): selected = matched
        case .failure(let failure):
            FileHandle.standardError.write(Data("duo: \(failure)\n".utf8))
            return 2
        }

        // `--all` means "the updates I would see", which excludes ignored apps —
        // so don't spend a request on them either. A *named* app is honoured even
        // when hidden (see the loop below), and must therefore still be checked.
        let checkable = settings.appsWorthChecking(selected, named: !options.queries.isEmpty)
        print("Checking \(checkable.count) app\(checkable.count == 1 ? "" : "s")…")
        let results = await Inventory.checker(settings).check(checkable)

        let staged = stagedSelfUpdates(for: results)
        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: Check.runningBundlePaths(),
            stagedSelfUpdates: staged,
            elevationRequiredPaths: InPlaceSwap.elevationRequiredPaths(
                for: results.map(\.app.path)),
            runningBundleIDs: Check.runningBundleIDs())

        var plan: [Planned] = []
        var refusals: [(UpdateResult, String)] = []
        for result in results.sorted(by: { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }) {
            guard result.hasUpdate else { continue }
            // An explicitly named app is one the user asked for by name, so a
            // hidden one is honoured rather than silently skipped — but --all
            // means "the updates I would see", which excludes them.
            if settings.isHidden(result), options.queries.isEmpty { continue }
            switch classify(result, settings: settings, environment: environment) {
            case .install(let route):
                // Narrowed, not refused: an app excluded by --route was never
                // asked for, so listing it under "Skipping" would be noise.
                guard options.routes.isEmpty || options.routes.contains(route) else { continue }
                plan.append(Planned(result: result, route: route))
            case .refuse(let why, _):
                refusals.append((result, why))
            }
        }

        guard !plan.isEmpty || !refusals.isEmpty else {
            print("Nothing to install.")
            return 0
        }

        describe(plan, refusals: refusals)
        if options.dryRun { return plan.isEmpty ? 0 : 1 }
        guard !plan.isEmpty else { return 1 }
        guard options.assumeYes || confirm(count: plan.count) else {
            print("Cancelled.")
            return 0
        }

        // `confirm` blocks on stdin, so the running-app snapshot taken before the
        // plan was printed may be arbitrarily old by now — and under
        // `.deferWhenRunning` that is the difference between skipping an app and
        // replacing the bundle of one the user launched while reading the prompt.
        // Re-derive and drop anything that would now defer. Only ever removes work,
        // so a plan the user approved can never grow behind their back.
        if settings.updateSettings.vendorInstallPolicy == .deferWhenRunning {
            // Staging is re-read too: the confirmation prompt blocks on stdin, and
            // an app can finish staging its own update while the user reads it.
            let live = InstallEnvironment(
                isHelperEnabled: false,
                runningAppPaths: Check.runningBundlePaths(),
                stagedSelfUpdates: stagedSelfUpdates(for: plan.map(\.result)),
                elevationRequiredPaths: environment.elevationRequiredPaths,
                runningBundleIDs: Check.runningBundleIDs())
            let started = plan.filter {
                UpdatePolicy.defersToSelfUpdater(
                    $0.result, settings: settings.updateSettings, environment: live)
            }
            if !started.isEmpty {
                for planned in started {
                    print("Skipping \(planned.result.app.name): started while waiting for confirmation, "
                          + "and your vendor policy defers to its own updater.")
                }
                plan.removeAll { planned in
                    started.contains { $0.result.app.path == planned.result.app.path }
                }
                guard !plan.isEmpty else { return 0 }
            }
        }

        // One process at a time, machine-wide — the menu-bar app takes the same
        // claim around each of its installs. Refused rather than queued: the
        // holder may be part-way through a 400 MB download, and a CLI that looks
        // hung is worse than one that tells you who has it.
        do {
            try await ProcessInstallLock.shared.claim()
        } catch {
            FileHandle.standardError.write(Data("duo: \(error)\n".utf8))
            return 1
        }
        // Released explicitly rather than in a `defer` spawning a Task: the
        // process exits immediately after this, and a detached release may never
        // run. (The kernel drops the flock on exit either way — this keeps the
        // reference count honest for anything that runs in between.)
        let code = await apply(
            plan, settings: settings, routes: options.routes,
            json: options.json, keepBackups: settings.keepBackups)
        await ProcessInstallLock.shared.release()
        return code
    }


    /// The staged self-updates the policy needs, keyed the way it looks them up.
    ///
    /// Built rather than left empty: `canAutoInstall` and `requiresInstaller` both
    /// read `environment.stagedSelfUpdates[result.id]` to suppress a one-click when
    /// the app has already staged the latest. Handing them an empty map made the CLI
    /// offer installs the menu-bar app renders as Relaunch — the two hosts differing
    /// by construction rather than by design, which is the thing `UpdatePolicy`
    /// exists to prevent.
    ///
    /// One LaunchServices query for the whole sweep, mirroring
    /// `computeSelfUpdateStaging` in the app; the rest is a plist read per candidate.
    static func stagedSelfUpdates(for results: [UpdateResult]) -> [String: StagedSelfUpdate] {
        let candidates = results.map(\.app).filter(SelfUpdaterStaging.mayHaveStaging)
        guard !candidates.isEmpty else { return [:] }
        let parked = SelfUpdaterStaging.liveParkedSparkleInstallers()
        var map: [String: StagedSelfUpdate] = [:]
        for app in candidates {
            if let staged = SelfUpdaterStaging.staged(
                for: app, parkedInstallerBundleURLs: parked) {
                map[app.id] = staged
            }
        }
        return map
    }

    // MARK: - Planning

    struct Planned: Sendable {
        let result: UpdateResult
        let route: InstallCoordinator.Route
    }

    enum Decision {
        case install(InstallCoordinator.Route)
        /// `route` is the freshly-derived route when classification got far
        /// enough to compute one before refusing (currently only the App
        /// Store branch below) — `nil` for every earlier refusal, which never
        /// reaches a `route(for:requiresInstaller:)` call at all. `reconsider`
        /// forwards this into `ReconsiderOutcome.skip` so `--json`'s `route`
        /// field is never a stale guess (#404 review #5).
        case refuse(String, InstallCoordinator.Route?)
    }

    /// Whether we may install this, using exactly the app's policy.
    static func classify(
        _ result: UpdateResult, settings: Settings, environment: InstallEnvironment
    ) -> Decision {
        let canAuto = UpdatePolicy.canAutoInstall(
            result, settings: settings.updateSettings, environment: environment)
        let needsInstaller = UpdatePolicy.requiresInstaller(result, environment: environment)
        guard canAuto || needsInstaller else {
            if result.remote?.sourceName == "App Store" {
                return .refuse("App Store updates need the menu-bar app (the store's "
                    + "install path is not reachable from a CLI)", nil)
            }
            // #193 originally split this into two messages — "no artefact this
            // time" for a recognised source vs. "no route wired up yet" for one
            // `UpdatePolicy` has no case for — reasoning that the two situations
            // shouldn't share text. Reverted (see #192's follow-up review):
            // measured against what `UpdatePolicy.isRecognizedInstallSource`
            // actually excludes in production — Xcode Releases, Toolbox,
            // TestFlight — every one of them is PERMANENTLY, DELIBERATELY
            // artefact-less by design (Xcode's download 302s to an Apple-ID
            // login page; Toolbox/TestFlight hand the install to their own
            // app), not a policy gap waiting to be closed. "No route wired up
            // yet" was therefore never true for any source that could actually
            // reach this branch — it just relocated #193's original complaint
            // (a message asserting something false) to the other bucket. One
            // message, worded to be accurate for both "never has one" and
            // "doesn't have one this time" is available.
            return .refuse("detection only — this source publishes no installable artefact", nil)
        }
        if UpdatePolicy.defersToSelfUpdater(
            result, settings: settings.updateSettings, environment: environment) {
            return .refuse("running, and your vendor policy defers to its own updater "
                + "(quit it, or set Always download & replace)", nil)
        }
        // The app's own updater already has bytes coming down for this release.
        // Refused here rather than only in the menu-bar app for the same reason
        // `InstallCoordinator` owns the backup decision: a safety net the CLI
        // silently skips is not a safety net. Unlike the check above this ignores
        // `vendorInstallPolicy` — "always replace" is a statement about who applies
        // an update, not permission to pay for one transfer twice.
        // Its own updater already has a build parked for the next quit; installing
        // over it is undone when that lands. Asked here as well as in the menu-bar
        // app because a gate only one host honours is not a gate.
        if let staged = UpdatePolicy.stagedBlocksInstall(
            result,
            staged: SelfUpdaterStaging.staged(
                for: result.app, requireNewerThanInstalled: false)) {
            return .refuse("its own updater has \(result.stagedRelaunchLine(staged).to) staged for the next quit "
                + "— installing now would be undone (quit it to apply)", nil)
        }
        if let inFlight = SelfUpdaterStaging.inFlightDownload(for: result.app) {
            let megabytes = Double(inFlight.bytes) / 1_000_000
            return .refuse(String(
                format: "its own updater is downloading this release (%.1f MB so far) "
                    + "— left it to finish", megabytes), nil)
        }
        let route = InstallCoordinator.route(for: result, requiresInstaller: needsInstaller)
        if route == .appStore {
            return .refuse("App Store updates need the menu-bar app", route)
        }
        return .install(route)
    }

    // MARK: - Re-checking before an install actually starts

    /// What the defensive re-check immediately before ONE install concluded, and
    /// what to do about it.
    ///
    /// The plan is built once, from a scan that may be minutes old by the time any
    /// given item's turn comes: the user held the confirmation prompt, or an
    /// earlier item in the same batch took a while to download. Between that scan
    /// and now the app may have updated itself, been installed by hand, or its
    /// source may have moved to a different artifact — the same reasons
    /// `AppListModel.performInstall` re-checks before every menu-bar install (see
    /// `PreInstallGate`). #404: the CLI used to hand the stale plan straight to
    /// `InstallCoordinator`, skipping all of this.
    enum ReconsiderOutcome: Sendable, Equatable {
        /// A newer version was confirmed just now — install THIS `UpdateResult`
        /// (never `offered`: the disk read may differ, and the source may have
        /// moved to a different artifact) via this freshly re-derived route.
        case proceed(UpdateResult, InstallCoordinator.Route)
        /// The freshly re-derived route isn't one of `--route`'s names. Narrowed,
        /// not refused — the same rule the planning loop applies before the
        /// confirmation prompt: an app excluded by `--route` was never asked for.
        /// Unlike the planning loop, though, `apply` still says so out loud in
        /// text mode: the plan's route WAS requested, and only stopped matching
        /// because the re-check moved it — that is new information, not noise
        /// (#404 review #4).
        case notRequested(InstallCoordinator.Route)
        /// Nothing to install, and not a failure. `why` completes "Skipping
        /// <name>: <why>". Carries the freshly re-derived route when `classify`
        /// got far enough to produce one before refusing (`Decision.refuse`'s
        /// second value) — `nil` otherwise, rather than falling back to the
        /// plan's stale route, which could contradict `why` (#404 review #5: a
        /// route moving from Vendor to App Store used to emit
        /// `"route": "vendor"` alongside a `reason` about the App Store).
        case skip(String, InstallCoordinator.Route?)
        /// The re-check could not establish whether an update exists — a
        /// network blip, a rate limit, or a source `UpdatePolicy` has no case
        /// for. Retryable, and said so, rather than filed as "nothing to do".
        case cannotConfirm(String?)
        /// The source's answer walked backwards between the offer and the
        /// confirm — see `PreInstallDecision.answerRegressed`. Carries no
        /// message: the caller already holds both `UpdateResult`s, and the two
        /// version strings are the finding.
        case answerRegressed
        /// The re-scan found no bundle it could read at the plan's path right
        /// now. Deliberately its own case rather than `.cannotConfirm`: unlike a
        /// source query failing (a network blip, retryable), this is a fact
        /// about the local disk that a retry cannot change — either the app
        /// really is gone, or it never will be until whatever broke its
        /// Info.plist is fixed by hand. `why` states only what was observed,
        /// not which of those it was: `AppScanner.readApp` returns nil for both
        /// (#404 review #6).
        case unreadable(String)
    }

    /// The `.unreadable` wording, single-sourced: it used to appear twice in
    /// `reconsider` below — once in the guard that actually produces it, once
    /// in the `case .unreadable:` arm that can't (see the comment there) —
    /// verbatim, so a future reword could hit one copy and leave the other.
    /// `why` states only what was observed, not which of "uninstalled" or
    /// "Info.plist failed to parse" it was: `AppScanner.readApp` returns nil
    /// for both (#404 review #6).
    private static func unreadableMessage(path: String) -> String {
        "no readable bundle at \(path) right now — it may have been "
            + "uninstalled, or its Info.plist could not be parsed"
    }

    /// Pure classification — no I/O. `offered` is what the plan showed when the
    /// user (or `--yes`) approved it; `confirmed` is a fresh disk read and a
    /// fresh source query for the SAME app, taken right before backup/replace
    /// (`recheckOne`, called from `apply`) — `nil` when that re-scan found no
    /// bundle it could read (see `.unreadable` above). `environment` must be
    /// re-derived from the current machine state too (`liveEnvironment`), not the
    /// snapshot the plan was built from — a batch install can take minutes,
    /// during which another item's install can start or finish.
    static func reconsider(
        offered: UpdateResult, confirmed: UpdateResult?, settings: Settings,
        environment: InstallEnvironment, routes: Set<InstallCoordinator.Route>
    ) -> ReconsiderOutcome {
        let decision = PreInstallGate.decision(offered: offered, confirmed: confirmed)
        // `decision == .unreadable` exactly when `confirmed == nil` (see
        // `PreInstallGate.decision(offered:confirmed:)`), so this unwraps
        // `confirmed` for every arm below at once, rather than each of them
        // re-deriving the same fact.
        guard decision != .unreadable, let confirmed else {
            return .unreadable(unreadableMessage(path: offered.app.path.path))
        }
        switch decision {
        case .proceed:
            // The route can move too — the same source may now resolve a
            // different artifact (a vendor cutting a new release between the
            // scan and now is exactly the case `.proceed` covers) — so this
            // reclassifies from `confirmed` rather than reusing the plan's route.
            switch classify(confirmed, settings: settings, environment: environment) {
            case .install(let route):
                guard routes.isEmpty || routes.contains(route) else { return .notRequested(route) }
                return .proceed(confirmed, route)
            case .refuse(let why, let route):
                return .skip(why, route)
            }
        case .alreadyCurrent:
            // States only what was observed — the disk is at this version and
            // there is nothing newer to install. Not WHY: it could be the app's
            // own updater, a manual install, a vendor pulling the release the
            // plan was built against, or (with `--yes`) simply that there was
            // never a confirmation prompt to wait behind at all. The previous
            // wording ("updated to X while waiting for confirmation") asserted
            // the first of those unconditionally and was flatly false under
            // `--yes` (#404 review #1).
            return .skip(
                "already at \(confirmed.app.shortVersion ?? confirmed.app.buildVersion ?? "a build") "
                    + "on disk — nothing to install",
                nil)
        case .managedElsewhere:
            return .skip(
                "now managed elsewhere (App Store, Toolbox, or TestFlight) — install it there instead",
                nil)
        case .cannotConfirm(let message):
            return .cannotConfirm(message)
        case .answerRegressed:
            return .answerRegressed
        case .unreadable:
            // Unreachable: guarded above, before `confirmed` was unwrapped.
            return .unreadable(unreadableMessage(path: offered.app.path.path))
        }
    }

    /// What `apply`'s loop does with one item, once `reconsider` has spoken —
    /// either install it, or stop here. `#445`: this is the pure mapping the
    /// issue asked for, and it exists because `RowOutcome`'s five cases are
    /// exactly 1:1 with `apply`'s five counters. Before this, the ending for
    /// each `ReconsiderOutcome` case was assembled by hand at its own `case` in
    /// `apply` — the text printed, the `--json` reason, the route, and which
    /// counter got incremented were four separately-editable pieces of code
    /// for the same event, and nothing forced them to agree. Collapsing all
    /// four into one `Terminal` value, keyed by one `RowOutcome`, makes
    /// "the emitted row and the incremented counter disagree" (#436's defect)
    /// structurally impossible rather than merely reviewed-by-hand.
    enum ItemPlan: Equatable {
        /// Proceed to backup/replace with this (freshly re-derived) result and
        /// route — never the plan's stale `offered` (see `reconsider`'s doc
        /// comment on `.proceed`).
        case install(UpdateResult, InstallCoordinator.Route)
        /// Nothing more happens to this item this run.
        case end(Terminal)
    }

    /// One item's ending: the `RowOutcome` IS the counter to increment and the
    /// NDJSON category to emit — there is no second value to keep in sync with
    /// it. `route` is `nil` exactly when no freshly re-derived route exists to
    /// report (#404 review #5); `console` is the text-mode line this item
    /// prints, without the leading three-space indent `apply` adds uniformly
    /// (so the same string serves both the `print` and the
    /// `FileHandle.standardError.write` call sites, which historically added
    /// the indent themselves at each call).
    struct Terminal: Equatable {
        let outcome: RowOutcome
        let reason: String
        let route: InstallCoordinator.Route?
        let console: String
    }

    /// Pure — no I/O, mirroring `reconsider` and `classify`. `offered`/
    /// `confirmed` are the SAME two `UpdateResult`s `reconsider` itself was
    /// called with (not the version strings pulled out of them) — only
    /// `.answerRegressed` reads them, but taking the results rather than two
    /// `String?`s closes off a mis-wiring `apply`'s untested call site would
    /// otherwise be free to make: `offered` is non-optional and `confirmed`
    /// is `Optional`, so transposing them at the call site is a COMPILE
    /// ERROR, not a wrong-but-plausible message — the same reasoning
    /// `summaryLine(_ tally:)` closes off for its five counters, applied
    /// here to the one remaining pair of positional arguments. It also
    /// single-sources "`remote?.displayVersion` is the right field to read",
    /// which a `String?`-taking signature would have left the call site to
    /// know for itself. Every string below is copied verbatim from the
    /// `apply` call sites it replaces (see #404 reviews #2–#8, #435, #436) —
    /// this is a refactor of WHERE the wiring happens, not a rewording of
    /// what it says, and that includes the rationale comments, not just the
    /// user-facing text.
    static func itemPlan(
        for outcome: ReconsiderOutcome, offered: UpdateResult, confirmed: UpdateResult?
    ) -> ItemPlan {
        switch outcome {
        case .proceed(let result, let route):
            return .install(result, route)
        case .notRequested(let route):
            return .end(Terminal(
                outcome: .skipped,
                reason: "not requested: --route no longer includes it",
                route: route,
                console: "skipping: re-checked route is now \(route.rawValue), no longer requested"))
        case .skip(let why, let route):
            return .end(Terminal(outcome: .skipped, reason: why, route: route,
                                  console: "skipping: \(why)"))
        case .unreadable(let why):
            // Not counted as `failed`: like `.alreadyCurrent`/`.managedElsewhere`
            // (both folded into `.skip` by `reconsider` before this ever runs),
            // there is nothing here a retry would change — either the app
            // really is gone, or its Info.plist needs fixing by hand, and
            // re-running `duo install` answers neither.
            return .end(Terminal(outcome: .skipped, reason: why, route: nil,
                                  console: "skipping: \(why)"))
        case .cannotConfirm(let message):
            // `nil` route, not the plan's stale one: `reconsider` returns here
            // BEFORE ever calling `classify` on a fresh read, so there is no
            // freshly re-derived route to give — only the plan's stale one,
            // which is exactly the value #404 review #5 says not to fall back
            // to. Caught by code review after the first pass only fixed `.skip`.
            let reason = message ?? "no source covers this app"
            return .end(Terminal(
                outcome: .failed, reason: reason, route: nil,
                console: "failed: the pre-install re-check could not confirm an update: \(reason)"))
        case .answerRegressed:
            // Both versions in the message, because the pair IS the finding:
            // either number alone reads as an ordinary check. Same rule
            // `AppListModel.performInstall` follows for the same case.
            let was = offered.remote?.displayVersion ?? "?"
            let now = confirmed?.remote?.displayVersion ?? "?"
            // `nil` for the same reason as `.cannotConfirm` above: no fresh
            // route was ever derived for a regressed answer either.
            return .end(Terminal(
                outcome: .failed,
                reason: "answer regressed: offered \(was), confirmed \(now)",
                route: nil,
                console: "failed: the update source answered \(was), then \(now) — nothing was installed."))
        }
    }

    static func describe(_ plan: [Planned], refusals: [(UpdateResult, String)]) {
        if !plan.isEmpty {
            print("\nWill install:")
            for item in plan {
                print("  \(item.result.app.name)  \(item.result.app.shortVersion ?? "?")"
                    + "  →  \(item.result.remote?.displayVersion ?? "?")"
                    + "  [\(item.route.rawValue)]")
            }
        }
        if !refusals.isEmpty {
            print("\nSkipping:")
            for (result, why) in refusals {
                print("  \(result.app.name)  —  \(why)")
            }
        }
        print("")
    }

    /// Ask before replacing anything. With no terminal there is nobody to ask,
    /// so a piped or scripted run must pass `--yes` explicitly rather than
    /// having consent assumed for it.
    static func confirm(count: Int) -> Bool {
        guard isatty(STDIN_FILENO) == 1 else {
            FileHandle.standardError.write(Data(
                "duo: not a terminal — pass --yes to install without confirmation\n".utf8))
            return false
        }
        print("Install \(count) update\(count == 1 ? "" : "s")? [y/N] ", terminator: "")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
        else { return false }
        return answer == "y" || answer == "yes"
    }

    // MARK: - Re-checking before an install actually starts (I/O)

    /// Re-read this one bundle off disk and re-query its source, right before
    /// backup/replace. Scoped to the single bundle (`AppScanner.scan(bundlesAt:)`),
    /// not a sweep of every scan location — the same reasoning as
    /// `AppListModel.recheckMany` (issue #226): a batch install re-checking every
    /// remaining item by sweeping the whole machine would make the disk work scale
    /// with the plan size for no benefit.
    ///
    /// `testflight`/`toolbox`/`checker` are built ONCE for the whole batch by
    /// `apply`, not per item — see that function's doc comment (#404 review #8).
    /// This function still does its own per-item work: the bundle re-scan and the
    /// source re-query, which is the entire point of the re-check and must not be
    /// hoisted alongside the shared plumbing.
    ///
    /// TestFlight-free: this must never block
    /// on TestFlight's local database, which lives behind the Sequoia app-data TCC
    /// gate — with nobody at a prompt mid-install that would hang the batch. The
    /// next full `duo check`/`duo install` re-applies TestFlight tagging from
    /// scratch; this single-app recheck just scans without it, so a TestFlight
    /// build never resolves as `.updateAvailable` here even if it has one.
    ///
    /// Returns `nil` when there is nothing to re-confirm against: the plan's
    /// bundle is missing, its Info.plist failed to parse (`AppScanner.readApp`
    /// returns nil for both — it cannot say which), or the resolved bundle now
    /// has a different identity than the plan's (mirroring
    /// `AppListModel.recheckMany`'s own guard: "a bundle that now resolves
    /// elsewhere reads as gone, not as a row under another id" — `InstalledApp.id`
    /// is the resolved path). `reconsider` turns `nil` into `.unreadable`
    /// (#404 review #6, #7).
    static func recheckOne(
        _ result: UpdateResult,
        testflight: TestFlightInventory, toolbox: ToolboxInventory, checker: UpdateChecker
    ) async -> UpdateResult? {
        let apps = AppScanner(toolbox: toolbox, testflight: testflight)
            .scan(bundlesAt: [result.app.path])
        guard let app = apps.first, app.id == result.app.id else { return nil }
        // `freshening: true`, matching `recheckMany`: a recheck is the user (or
        // `--yes`) insisting on a live answer, and must not be satisfied out of a
        // source's own memo — see `UpdateChecker.check`'s doc comment.
        let checked = await checker.check([app], freshening: true)
        return checked.first ?? UpdateResult(app: app, remote: nil, status: .unknown)
    }

    /// The machine state `classify`/`UpdatePolicy` need, re-derived fresh for
    /// THIS app right before its install — not the snapshot the plan (or an
    /// earlier item's `.deferWhenRunning` re-check) was built from. A batch
    /// install can take minutes; another item finishing or a self-updater
    /// starting mid-batch must be visible to the item whose turn has just come up.
    static func liveEnvironment(for result: UpdateResult, plannedElevation: Set<String>) -> InstallEnvironment {
        InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: Check.runningBundlePaths(),
            stagedSelfUpdates: stagedSelfUpdates(for: [result]),
            elevationRequiredPaths: plannedElevation,
            runningBundleIDs: Check.runningBundleIDs())
    }

    // MARK: - Applying

    static func apply(
        _ plan: [Planned], settings: Settings, routes: Set<InstallCoordinator.Route>,
        json: Bool, keepBackups: Bool
    ) async -> Int32 {
        if json { NDJSON.begin("install") }
        let coordinator = InstallCoordinator()
        // `elevationRequiredPaths` is a fact about the install locations, which
        // don't move between plan and apply — computed once, like the plan's own
        // `environment` was, rather than re-stat'd per item.
        let elevationRequiredPaths = InPlaceSwap.elevationRequiredPaths(for: plan.map(\.result.app.path))
        // Built ONCE for the whole batch, not once per item: `ToolboxInventory()`
        // synchronously reads and parses its state.json, and `Inventory.checker`
        // resolves the whole source stack (GitHub token, Alcove, …) — a plan of N
        // items must not pay for N reads and N resolves just to answer "is this
        // one app still what the plan thinks it is?" N times (the same shape
        // `AppListModel.recheckMany`'s doc comment warns about, #226). Each
        // item's OWN re-scan and source query — the actual point of this issue —
        // still happen per item, inside `recheckOne`; only the shared plumbing
        // around them is hoisted here (#404 review #8).
        let recheckTestflight = TestFlightInventory(macRows: [], accessible: false)
        // The same sentinel for the second witness, and for a sharper reason than
        // symmetry: `Inventory.checker`'s default argument would otherwise read the
        // notification store here, and with a TestFlight inventory carrying no
        // frontiers the answer can only ever be "not behind" — a database read whose
        // result is unusable by construction, on the one path that exists to avoid
        // paying for reads.
        let recheckAnnouncements = TestFlightAnnouncements(announcements: [], accessible: false)
        let recheckToolbox = ToolboxInventory()
        let recheckChecker = Inventory.checker(
            settings, testflight: recheckTestflight,
            announcements: recheckAnnouncements, toolbox: recheckToolbox,
            appStoreSignedIn: nil)
        // One counter per `RowOutcome`, and the only place that maps one to the
        // other (#445) — see `Tally.record`. Before this, `apply` kept five
        // separate `var`s and incremented one by hand next to each exit from
        // the loop below, which let the emitted row and the incremented
        // counter disagree (#436's defect).
        var tally = Tally()
        // Only items whose bundle was ACTUALLY replaced
        // (`InstallCoordinator.Outcome.applied`) — a `.notRequested`, `.skip`,
        // `.unreadable`, `.cannotConfirm`, or `.answerRegressed` item was never
        // touched, so its bundle running is not "still running the OLD code"
        // (the phrase below), it is just running, same as before `duo install`
        // was called at all. And a `.installer` route, or an install that threw,
        // means `coordinator.perform` returned (or failed) WITHOUT putting the
        // new version on disk — `applied` is exactly the signal for that, and is
        // more precise than "the call didn't throw" (#404 review #2).
        var attempted: [(name: String, path: URL)] = []
        for item in plan {
            let name = item.result.app.name
            if !json { print("→ \(name)") }

            // Defensive re-check: the app may already be current — updated by its
            // own updater, or installed by hand — since the plan was built, or the
            // source may have changed its mind. Re-read the bundle and re-query
            // the source before touching anything. See `PreInstallGate` / #404.
            let confirmed = await recheckOne(
                item.result, testflight: recheckTestflight, toolbox: recheckToolbox,
                checker: recheckChecker)
            let live = liveEnvironment(
                for: confirmed ?? item.result, plannedElevation: elevationRequiredPaths)
            let reconsidered = reconsider(
                offered: item.result, confirmed: confirmed, settings: settings,
                environment: live, routes: routes)
            let outcome = itemPlan(for: reconsidered, offered: item.result, confirmed: confirmed)

            let toInstall: UpdateResult
            let route: InstallCoordinator.Route
            switch outcome {
            case .install(let result, let derivedRoute):
                toInstall = result
                route = derivedRoute
            case .end(let end):
                // Every ending's `console` line was written without its
                // leading indent (see `Terminal`'s doc comment); reproduced
                // here so the printed text is byte-for-byte what the old,
                // per-case call sites wrote. A `.failed` ending goes to
                // stderr unconditionally, matching what `.cannotConfirm` and
                // `.answerRegressed` always did; every other ending prints to
                // stdout only when `!json`, matching what `.notRequested`,
                // `.skip`, and `.unreadable` always did.
                if end.outcome == .failed {
                    FileHandle.standardError.write(Data("   \(end.console)\n".utf8))
                } else if !json {
                    print("   \(end.console)")
                }
                emitSkipped(name: name, route: end.route, reason: end.reason,
                            outcome: end.outcome, json: json)
                tally.record(end.outcome)
                continue
            }

            // The same rollback point the menu-bar app takes, honouring the same
            // preference. Not fatal when it fails — but said out loud, because
            // the alternative is discovering the safety net is gone only when a
            // later rollback finds nothing.
            if keepBackups, InstallCoordinator.wantsBackup(route) {
                switch await InstallCoordinator.backUp(toInstall.app, route: route) {
                case .saved:
                    if !json { print("   backed up \(toInstall.app.shortVersion ?? "current")") }
                case .savedWithoutRuntimeState(let omitted):
                    if !json {
                        print("   backed up \(toInstall.app.shortVersion ?? "current")"
                            + " — without \(omitted) file(s) the app wrote inside its own"
                            + " bundle, which it will recreate")
                    }
                case .unreadable(let path):
                    if !json {
                        print("   no rollback point: \(path) is not readable by you")
                        print("   (common for .pkg apps, which are often root-owned)")
                    }
                case .failed:
                    if !json { print("   could not back up — installing without a rollback point") }
                }
            }
            do {
                let installOutcome = try await coordinator.perform(
                    toInstall, route: route,
                    progress: { stage in
                        guard !json else { return }
                        if let text = describe(stage) { print("   \(text)") }
                    })
                // Only when the bundle is actually on disk now: an `.installer`
                // route returns here with `applied == false` while the system
                // installer window is still open, and the "still running the old
                // code" summary below must not call that app's running copy
                // stale (#404 review #2). `rowOutcome(forApplied:)` is the same
                // function `installedPayload` uses for `emit`'s `--json` row
                // (#445) — one decision, not two independently-swappable copies
                // of the same ternary.
                let category = rowOutcome(forApplied: installOutcome.applied)
                if installOutcome.applied {
                    attempted.append((name: name, path: toInstall.app.path))
                }
                tally.record(category)
                emit(name: name, route: route, outcome: installOutcome, json: json)
            } catch is AuthorizationDeclinedError {
                // Dismissing the password panel is a decision, not a failure — it
                // does not count toward `failed`, and it is remembered so neither
                // `duo` nor the menu bar re-raises the panel for this copy until
                // the user asks. Written to the same suite the app reads. Still
                // counted and still emitted (`emitSkipped`): the old code left
                // this item out of every counter and out of the `--json` stream,
                // so it vanished from the summary entirely (#404 review #3).
                //
                // Bound to one local value used for both calls below (#445) — not
                // pulled into a `rowOutcome(for: Error)` function, unlike
                // `rowOutcome(forApplied:)` above: there is only this one call
                // site for this classification (nothing else in `Install.swift`
                // maps an error to a `RowOutcome`), so a pure function here would
                // add a testable unit without removing any real duplication —
                // and `apply` itself stays untested either way (real I/O). Left
                // review-only, uncovered; see the PR description.
                let category: RowOutcome = .declined
                Settings.recordDeclinedElevation(toInstall.app)
                tally.record(category)
                emitSkipped(name: name, route: route,
                            reason: "administrator access was declined",
                            outcome: category, json: json)
                FileHandle.standardError.write(Data("""
                       skipped: administrator access was declined, so \(name) will no \
                    longer be offered as a one-click. Undo it from the app's row menu, \
                    or with `defaults delete com.duoupdater.app \
                    \(UpdateSettings.declinedElevationKeysKey)`.\n
                    """.utf8))
            } catch {
                // Same reasoning as the `AuthorizationDeclinedError` arm above:
                // one local value, used for both calls, and left as a literal
                // rather than a pure function for the same reason.
                let category: RowOutcome = .failed
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                tally.record(category)
                FileHandle.standardError.write(Data("   failed: \(message)\n".utf8))
                // The one ending a `--json` consumer most needs to see. Every
                // other way an approved item can end without being installed
                // now leaves a row; a failure leaving none would mean the
                // stream undercounts exactly the failures, which is the
                // opposite of the property `emitSkipped` was added for.
                emitSkipped(name: name, route: route, reason: message, outcome: category, json: json)
                if error is AppManagementRequiredError {
                    FileHandle.standardError.write(Data("""
                           Grant App Management to this binary in System Settings ▸ \
                        Privacy & Security ▸ App Management, then try again. \
                        `duo doctor` shows the current state.\n
                        """.utf8))
                }
            }
        }
        if !json {
            print("\n" + summaryLine(tally))
            // The bundle on disk is new; the process still running is not. The
            // menu-bar app restarts these itself per the user's preference; the
            // CLI does not quit your apps behind your back, but it must not leave
            // you believing the update is already live either. Sampled after the
            // batch, so an app that exited during it is not named.
            let running = Check.runningBundlePaths()
            let stale = attempted
                .filter { running.contains(UpdatePolicy.runtimeBundlePath($0.path)) }
                .map(\.name)
            if !stale.isEmpty {
                print("\nStill running the old code: \(stale.joined(separator: ", "))")
                print("  duo restart \(stale.joined(separator: " "))")
            }
        }
        return tally.failed == 0 ? 0 : 1
    }

    /// The text-mode summary line, pulled out as a pure function so its exact
    /// counting and phrasing is testable without driving a real install. Zero
    /// counts are omitted (a plan with nothing skipped/declined shouldn't say
    /// "0 skipped, 0 declined" every time) — `declined` did not exist before
    /// #404 review #3, when a declined-elevation item was silently left out of
    /// every counter and this line, and so vanished from the summary entirely.
    ///
    /// `openedInstaller` is the fifth bucket, added by #435: an `.installer`
    /// route's `perform` returns without throwing, yet `applied == false` — the
    /// bytes are fetched and verified and a system installer window is open,
    /// but nothing has replaced the app on disk yet. Before this it was folded
    /// into `installed`, which made "N installed" false at the exact moment it
    /// printed. Counting it as `installed` is wrong for that reason; folding it
    /// into `skipped` would also be wrong, in the other direction — real work
    /// (a full download, a verified package) already happened, unlike an
    /// actual skip. Every item in the plan lands in exactly one of the five:
    /// `installed + failed + skipped + declined + openedInstaller == plan.count`.
    static func summaryLine(
        installed: Int, failed: Int, skipped: Int, declined: Int, openedInstaller: Int
    ) -> String {
        "\(installed) installed, \(failed) failed"
            + (skipped > 0 ? ", \(skipped) skipped" : "")
            + (declined > 0 ? ", \(declined) declined" : "")
            + (openedInstaller > 0 ? ", \(openedInstaller) opened in the installer" : "") + "."
    }

    /// Same line, from a `Tally` — the overload `apply` actually calls (#445).
    /// Forwards to the five-argument form above rather than duplicating its
    /// phrasing, so `apply` no longer has five positional arguments it could
    /// mis-wire (the issue's mutation "passing `openedInstaller: 0` at the call
    /// site" is no longer expressible once the call site only has a `Tally`).
    static func summaryLine(_ tally: Tally) -> String {
        summaryLine(
            installed: tally.installed, failed: tally.failed, skipped: tally.skipped,
            declined: tally.declined, openedInstaller: tally.openedInstaller)
    }

    /// The machine-readable category every `--json` row (`emit`'s and
    /// `emitSkipped`'s alike) carries, alongside `applied` — which is kept
    /// exactly as it was, so an existing reader does not break; `outcome` is
    /// additive, not a replacement (#436). Before this, `emitSkipped` wrote the
    /// same `{applied: false, reason: …}` shape for a real failure, a skip, and
    /// a decline alike, and only the English prose in `reason` told them apart
    /// — rewording a message would silently reclassify a row. A small enum
    /// rather than a raw string, so a typo at a call site cannot reach the
    /// stream as a new, unrecognised category — the same principle as
    /// `RowActions.live` in the menu-bar app: a call site must say which
    /// bucket it is, not fall into a defaulted guess.
    enum RowOutcome: String {
        case installed
        /// The `.installer` route only, today: bytes fetched and verified, a
        /// system installer window is open, nothing replaced yet. See
        /// `summaryLine` for why this is neither `.installed` nor `.skipped`.
        case openedInstaller
        case skipped
        case declined
        case failed
    }

    /// One counter per `RowOutcome`, and the ONLY place that maps a
    /// `RowOutcome` to a counter (#445). Before this, `apply` kept five
    /// separate `var`s and incremented one by hand next to each exit from its
    /// loop — a call site could increment a DIFFERENT counter than the
    /// `RowOutcome` it just emitted (exactly #436's defect: a real failure
    /// counted as a skip), and nothing but reading every call site by hand
    /// would catch it. `record` is the single place that wiring happens now.
    struct Tally: Sendable, Equatable {
        private(set) var installed = 0
        private(set) var openedInstaller = 0
        private(set) var skipped = 0
        private(set) var declined = 0
        private(set) var failed = 0

        mutating func record(_ outcome: RowOutcome) {
            switch outcome {
            case .installed: installed += 1
            case .openedInstaller: openedInstaller += 1
            case .skipped: skipped += 1
            case .declined: declined += 1
            case .failed: failed += 1
            }
        }
    }

    /// The `applied` → `RowOutcome` decision, single-sourced (#445): before
    /// this, `installedPayload` computed `outcome.applied ? .installed :
    /// .openedInstaller` and `apply`'s loop duplicated the identical branch
    /// for its own counter, so a mutation swapping one branch's two arms
    /// (#435's fix) was two separate, independently-swappable pieces of code.
    /// Both call sites now go through this one function.
    static func rowOutcome(forApplied applied: Bool) -> RowOutcome {
        applied ? .installed : .openedInstaller
    }

    static func emit(
        name: String, route: InstallCoordinator.Route,
        outcome: InstallCoordinator.Outcome, json: Bool
    ) {
        if json {
            NDJSON.emit(installedPayload(name: name, route: route, outcome: outcome))
        } else if let package = outcome.stagedPackageURL {
            print("   opened the installer for you: \(package.lastPathComponent)")
            print("   finish it in the window macOS just opened.")
        } else {
            print("   installed.")
        }
    }

    /// The row `emit` writes for an item `InstallCoordinator.perform` returned
    /// from without throwing — pulled out as a pure function, mirroring
    /// `skippedPayload`, so the `outcome` category is testable directly rather
    /// than only by capturing stdout. `outcome` (the JSON field) is keyed off
    /// `outcome.applied` (the parameter), NOT off `route == .installer`:
    /// `applied` is the documented signal ("is the new version on disk now"),
    /// and today `.installer` is the only route whose `perform` returns
    /// without throwing yet `applied == false` — verified against
    /// `InstallCoordinator.performRoute` rather than assumed (#435).
    static func installedPayload(
        name: String, route: InstallCoordinator.Route, outcome: InstallCoordinator.Outcome
    ) -> [String: Any] {
        let category = rowOutcome(forApplied: outcome.applied)
        var payload: [String: Any] = [
            "app": name, "route": route.rawValue,
            "bytesDownloaded": outcome.bytesDownloaded,
            "applied": outcome.applied,
            "outcome": category.rawValue,
        ]
        // Omitted rather than null when there is no staged package: a `.pkg`
        // is the only route that produces one, and `NSNull` in a stream of
        // otherwise-typed values trips naive readers.
        if let staged = outcome.stagedPackageURL { payload["stagedPackage"] = staged.path }
        return payload
    }

    /// The `--json` record for an item the pre-install re-check did NOT install
    /// (`reconsider` returned anything but `.proceed`, or the install was declined).
    /// Without this, `emit` firing only on success means these items vanish from
    /// the NDJSON stream with no trace — the same shape as `emit`'s row
    /// (`app`/`applied`), plus `reason` in place of the byte count and staged-
    /// package fields that only an actual install produces. `route` is omitted
    /// rather than defaulted to the plan's stale value when the caller has none
    /// to give — a wrong route in the same row as an accurate `reason` is worse
    /// than a missing field (#404 review #5). Text-mode printing is the caller's
    /// job: each outcome has its own wording, so this only ever writes the JSON
    /// line.
    ///
    /// `outcome` is a required parameter, not defaulted (#436): every call site
    /// in `apply` already knows which `RowOutcome` bucket it is about to
    /// record (`#445`: it is the same value passed to `tally.record(...)`
    /// right alongside), so this asks it to say so once more, in a form a
    /// `--json` consumer can read back — the same reasoning CLAUDE.md gives
    /// for `RowActions.live` taking no defaults: a new call site should have to
    /// say which bucket it is rather than silently landing in a wrong one.
    static func emitSkipped(
        name: String, route: InstallCoordinator.Route?, reason: String,
        outcome: RowOutcome, json: Bool
    ) {
        guard json else { return }
        NDJSON.emit(skippedPayload(name: name, route: route, reason: reason, outcome: outcome))
    }

    /// The row `emitSkipped` writes, pulled out as a pure function so both the
    /// route-omission rule (#404 review #5) and the `outcome` category (#436)
    /// are testable directly. `route` is left out of the payload entirely when
    /// the caller has none to give, rather than defaulted to something that
    /// could contradict `reason`; `outcome` has no default for the same reason.
    static func skippedPayload(
        name: String, route: InstallCoordinator.Route?, reason: String, outcome: RowOutcome
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "app": name, "applied": false, "reason": reason, "outcome": outcome.rawValue,
        ]
        if let route { payload["route"] = route.rawValue }
        return payload
    }

    /// Progress worth a line of terminal output. The fine-grained download
    /// fractions are dropped rather than reprinted — a CLI that emits a hundred
    /// lines of percentages is unreadable in a scrollback.
    static func describe(_ stage: InstallStage) -> String? {
        switch stage {
        case .downloading(let fraction) where fraction == 0: return "downloading…"
        case .downloading:                                   return nil
        case .runningCommand(let line):                      return line
        default:                                             return String(describing: stage)
        }
    }
}
