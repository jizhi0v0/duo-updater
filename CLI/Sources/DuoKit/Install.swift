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
        public init() {}
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

        print("Checking \(selected.count) app\(selected.count == 1 ? "" : "s")…")
        let results = await Inventory.checker(settings).check(selected)

        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: Check.runningBundlePaths(),
            stagedSelfUpdates: [:])

        var plan: [Planned] = []
        var refusals: [(UpdateResult, String)] = []
        for result in results.sorted(by: { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }) {
            guard result.hasUpdate else { continue }
            // An explicitly named app is one the user asked for by name, so a
            // hidden one is honoured rather than silently skipped — but --all
            // means "the updates I would see", which excludes them.
            if settings.isHidden(result), options.queries.isEmpty { continue }
            switch classify(result, settings: settings, environment: environment) {
            case .install(let route): plan.append(Planned(result: result, route: route))
            case .refuse(let why):    refusals.append((result, why))
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
        let code = await apply(plan, json: options.json)
        await ProcessInstallLock.shared.release()
        return code
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
            return .refuse("detection only — this app has no installable artefact we vet")
        }
        if UpdatePolicy.defersToSelfUpdater(
            result, settings: settings.updateSettings, environment: environment) {
            return .refuse("running, and your vendor policy defers to its own updater "
                + "(quit it, or set Always download & replace)")
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

    static func apply(_ plan: [Planned], json: Bool) async -> Int32 {
        let coordinator = InstallCoordinator()
        var failed = 0
        for item in plan {
            let name = item.result.app.name
            if !json { print("→ \(name)") }
            do {
                let outcome = try await coordinator.perform(
                    item.result, route: item.route,
                    progress: { stage in
                        guard !json else { return }
                        if let text = describe(stage) { print("   \(text)") }
                    })
                emit(name: name, route: item.route, outcome: outcome, json: json)
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
        }
        return failed == 0 ? 0 : 1
    }

    static func emit(
        name: String, route: InstallCoordinator.Route,
        outcome: InstallCoordinator.Outcome, json: Bool
    ) {
        if json {
            let payload: [String: Any] = [
                "app": name, "route": route.rawValue,
                "bytesDownloaded": outcome.bytesDownloaded,
                "applied": outcome.applied,
                "stagedPackage": outcome.stagedPackageURL?.path as Any,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
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
