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
            case .refuse(let why):
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
        let code = await apply(plan, json: options.json, keepBackups: settings.keepBackups)
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
        case refuse(String)
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
                    + "install path is not reachable from a CLI)")
            }
            // Two different reasons read identically as "neither flag is true",
            // and #193 was this text conflating them: a source `UpdatePolicy`
            // has never heard of (Xcode Releases, Toolbox — no case in
            // `canAutoInstall`/`requiresInstaller`, so always `default: false`)
            // is not the same situation as a recognised source (Vendor, GitHub,
            // Electron, Homebrew) that simply resolved to no artifact THIS
            // time (no asset pattern matched, no known archive extension, a
            // manual-installer cask). The first has no install path even in
            // principle; the second is one manifest edit away from working.
            // Before #192 wired Electron into the switches, every Electron app
            // fell into the first bucket while this text described the second —
            // sending anyone who read it to the wrong layer entirely.
            if UpdatePolicy.isRecognizedInstallSource(result.remote?.sourceName) {
                return .refuse("detection only — this app has no installable artefact we vet")
            }
            return .refuse("detection only — no install route is wired up for this source yet")
        }
        if UpdatePolicy.defersToSelfUpdater(
            result, settings: settings.updateSettings, environment: environment) {
            return .refuse("running, and your vendor policy defers to its own updater "
                + "(quit it, or set Always download & replace)")
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
                + "— installing now would be undone (quit it to apply)")
        }
        if let inFlight = SelfUpdaterStaging.inFlightDownload(for: result.app) {
            let megabytes = Double(inFlight.bytes) / 1_000_000
            return .refuse(String(
                format: "its own updater is downloading this release (%.1f MB so far) "
                    + "— left it to finish", megabytes))
        }
        let route = InstallCoordinator.route(for: result, requiresInstaller: needsInstaller)
        if route == .appStore {
            return .refuse("App Store updates need the menu-bar app")
        }
        return .install(route)
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

    // MARK: - Applying

    static func apply(_ plan: [Planned], json: Bool, keepBackups: Bool) async -> Int32 {
        if json { NDJSON.begin("install") }
        let coordinator = InstallCoordinator()
        var failed = 0
        for item in plan {
            let name = item.result.app.name
            if !json { print("→ \(name)") }
            // The same rollback point the menu-bar app takes, honouring the same
            // preference. Not fatal when it fails — but said out loud, because
            // the alternative is discovering the safety net is gone only when a
            // later rollback finds nothing.
            if keepBackups, InstallCoordinator.wantsBackup(item.route) {
                switch await InstallCoordinator.backUp(item.result.app, route: item.route) {
                case .saved:
                    if !json { print("   backed up \(item.result.app.shortVersion ?? "current")") }
                case .savedWithoutRuntimeState(let omitted):
                    if !json {
                        print("   backed up \(item.result.app.shortVersion ?? "current")"
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
                let outcome = try await coordinator.perform(
                    item.result, route: item.route,
                    progress: { stage in
                        guard !json else { return }
                        if let text = describe(stage) { print("   \(text)") }
                    })
                emit(name: name, route: item.route, outcome: outcome, json: json)
            } catch is AuthorizationDeclinedError {
                // Dismissing the password panel is a decision, not a failure — it
                // does not count toward `failed`, and it is remembered so neither
                // `duo` nor the menu bar re-raises the panel for this copy until
                // the user asks. Written to the same suite the app reads.
                Settings.recordDeclinedElevation(item.result.app)
                FileHandle.standardError.write(Data("""
                       skipped: administrator access was declined, so \(name) will no \
                    longer be offered as a one-click. Undo it from the app's row menu, \
                    or with `defaults delete com.duoupdater.app \
                    \(UpdateSettings.declinedElevationKeysKey)`.\n
                    """.utf8))
            } catch {
                failed += 1
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                FileHandle.standardError.write(Data("   failed: \(message)\n".utf8))
                if error is AppManagementRequiredError {
                    FileHandle.standardError.write(Data("""
                           Grant App Management to this binary in System Settings ▸ \
                        Privacy & Security ▸ App Management, then try again. \
                        `duo doctor` shows the current state.\n
                        """.utf8))
                }
            }
        }
        let installed = plan.count - failed
        if !json {
            print("\n\(installed) installed, \(failed) failed.")
            // The bundle on disk is new; the process still running is not. The
            // menu-bar app restarts these itself per the user's preference; the
            // CLI does not quit your apps behind your back, but it must not leave
            // you believing the update is already live either. Sampled after the
            // batch, so an app that exited during it is not named.
            let running = Check.runningBundlePaths()
            let stale = plan
                .filter { running.contains(UpdatePolicy.runtimeBundlePath($0.result.app.path)) }
                .map(\.result.app.name)
            if !stale.isEmpty {
                print("\nStill running the old code: \(stale.joined(separator: ", "))")
                print("  duo restart \(stale.joined(separator: " "))")
            }
        }
        return failed == 0 ? 0 : 1
    }

    static func emit(
        name: String, route: InstallCoordinator.Route,
        outcome: InstallCoordinator.Outcome, json: Bool
    ) {
        if json {
            var payload: [String: Any] = [
                "app": name, "route": route.rawValue,
                "bytesDownloaded": outcome.bytesDownloaded,
                "applied": outcome.applied,
            ]
            // Omitted rather than null when there is no staged package: a `.pkg`
            // is the only route that produces one, and `NSNull` in a stream of
            // otherwise-typed values trips naive readers.
            if let staged = outcome.stagedPackageURL { payload["stagedPackage"] = staged.path }
            NDJSON.emit(payload)
        } else if let package = outcome.stagedPackageURL {
            print("   opened the installer for you: \(package.lastPathComponent)")
            print("   finish it in the window macOS just opened.")
        } else {
            print("   installed.")
        }
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
