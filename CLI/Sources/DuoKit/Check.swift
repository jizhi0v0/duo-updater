import Foundation
import DuoUpdaterCore

/// `duo list` and `duo check` — what is installed, and what has an update.
///
/// `list` is offline and instant; `check` is `list` plus the network. They share
/// their output shape so a `--json` consumer can treat them the same.
public enum Check {

    public struct Options: Sendable {
        public var queries: [String] = []
        public var json = false
        /// Show every app, not just the ones with an update. Implied by `list`.
        public var all = false
        /// Include apps the user ignored or whose offered version they skipped.
        public var includeHidden = false
        public var checkForUpdates = true
        /// Keep only apps answered by these sources, matched case-insensitively
        /// against `RemoteVersion.sourceName` ("Sparkle", "Homebrew", "Vendor",
        /// "GitHub", "App Store", …). Empty means every source.
        public var sources: Set<String> = []
        /// Ask TestFlight to refresh its local store before checking.
        ///
        /// Off by default and never implied: it starts an app the user did not
        /// start. See `TestFlightRefresh` for why a background launch is the only
        /// form of this we are willing to offer, and #478 for why the store goes
        /// stale in the first place.
        public var refreshTestFlight = false
        public init() {}
    }

    /// One row, in the shape both commands emit. `NDJSON` rather than one big
    /// array so a slow check prints rows as they resolve instead of after.
    struct Row: Encodable {
        let name: String
        let bundleID: String?
        let path: String
        let installedVersion: String?
        let installedBuild: String?
        let latestVersion: String?
        /// The build behind `latestVersion`, when the source reports one. Only
        /// interesting when the marketing version doesn't move — see `emitText`.
        var latestBuild: String? = nil
        let source: String?
        let status: String
        /// Whether the source reports something newer — NOT `latestVersion !=
        /// nil`, which is also true for an app that is already current and made
        /// `--all` report every checked app as an available update.
        let hasUpdate: Bool
        let hidden: Bool
        let route: String?
    }

    /// What to tell the user about a refresh attempt. Written to stderr so `--json`
    /// stays one object per line, and phrased so that "we launched TestFlight" is
    /// never left implicit — the user is entitled to know why an app appeared.
    static func describe(_ outcome: TestFlightRefresh.Outcome) -> String {
        switch outcome {
        case .refreshed(let after):
            // The moment the store last changed, NOT how long the command waited:
            // the wait runs on past it by `settleInterval` to be sure the sync has
            // finished. Measured 6.0s here against 14.0s wall clock, so saying
            // "took" would be wrong by more than half.
            let seconds = Double(after.components.seconds) + Double(after.components.attoseconds) / 1e18
            return String(format: "duo: TestFlight refreshed its data (new data landed after %.1fs)", seconds)
        case .changedWithoutSettling(let lastChange):
            // Says "may not have finished", never "refreshed". The row printed
            // immediately below this line can be the pre-sync one, and a user who
            // was told the refresh succeeded has no reason to look twice.
            let seconds = Double(lastChange.components.seconds)
                + Double(lastChange.components.attoseconds) / 1e18
            return String(
                format: "duo: TestFlight was still writing when we stopped waiting "
                      + "(last seen moving after %.1fs); the versions below may predate the sync",
                seconds)
        case .noChange:
            // One sentence for one route. It deliberately does not say "already
            // current": the store has no "last synced" of its own, so a sync that
            // did not happen looks exactly like one that had nothing to fetch.
            return "duo: TestFlight reloaded in the background; its data did not change"
        case .notSignedIn:
            return "duo: this Mac is not signed in to the App Store, which TestFlight signs in with, "
                + "so TestFlight was not started; it would only have asked you to sign in"
        case .accountTestsNothing:
            // The store cannot tell "signed out" from "signed in to an account
            // with no betas", so this names what it saw and guesses in brackets.
            return "duo: TestFlight's data shows no account testing a beta here (signed out?), "
                + "so TestFlight was not started; it would only have asked you to sign in"
        case .notInstalled:
            return "duo: TestFlight is not installed, so there is nothing to refresh"
        case .launchFailed:
            return "duo: could not launch TestFlight"
        }
    }

    /// Why `--refresh-testflight` did not start TestFlight, or nil when it may.
    ///
    /// The app starts a sync only when it may read the store afterwards
    /// (`AppListModel`: `intent.refreshesTestFlight, mayReadTestFlight`), and `duo`
    /// takes the same rule, `Inventory.readsTestFlight`: a refresh this run cannot
    /// read is an app launched for nothing, and the refresh itself reads the store
    /// and the App Store sign-in before starting anything. Said, not silently
    /// skipped — the flag asked for a launch, and the user is owed the reason
    /// there was none.
    static func refreshSkipped(
        _ detection: TestFlightDetection, fullDiskAccess: @autoclosure () -> TCCAuthStatus
    ) -> String? {
        guard !Inventory.readsTestFlight(detection, fullDiskAccess: fullDiskAccess()) else { return nil }
        return detection.readsStore
            ? "duo: TestFlight was not started — without Full Disk Access, duo can't read"
                + " what it would refresh"
            : "duo: TestFlight was not started — detection is off, so nothing would read"
                + " what it refreshed (Duo Updater ▸ Settings ▸ General)"
    }

    /// A row worth acting on: an update the user has not hidden.
    static func isActionable(_ row: Row) -> Bool { row.hasUpdate && !row.hidden }

    /// The (installed, latest) build pair to show when the marketing version stays
    /// put, mirroring `UpdateResult.buildBump` on the row shape this command emits.
    static func buildBump(_ row: Row) -> (installed: String, remote: String)? {
        guard row.latestVersion == row.installedVersion,
              let installed = row.installedBuild.map(UpdateResult.strippingBuildPrefix),
              let remote = row.latestBuild.map(UpdateResult.strippingBuildPrefix),
              installed != remote
        else { return nil }
        return (installed, remote)
    }

    public static func run(_ options: Options) async -> Int32 {
        let settings = Settings.load()
        // Before the scan, not just before the check. `AppScanner` reads the
        // TestFlight store too — that is where a bundle gets tagged
        // `isTestFlightApp`, and for a wrapped iPhone/iPad app the store is the
        // evidence (#456), the receipt being unavailable. Refreshing after the scan
        // would leave this run's tagging on the stale store and only fix the
        // version comparison, so a beta installed since the last sync would still
        // be read as something else until the next invocation.
        if options.refreshTestFlight {
            if let skipped = refreshSkipped(
                settings.testFlightDetection, fullDiskAccess: Inventory.fullDiskAccess) {
                FileHandle.standardError.write(Data((skipped + "\n").utf8))
            } else {
                let outcome = await TestFlightRefresh().run()
                FileHandle.standardError.write(Data((describe(outcome) + "\n").utf8))
            }
        }
        // nil when the scan was given up on: an empty list would read as a Mac
        // with nothing to update (or, for `list`, nothing installed), and the run
        // would end in "Everything is up to date." or "No apps found."
        let scanned = await Inventory.scanIfFinished(settings)
        let apps = scanned ?? []
        let selected: [InstalledApp]
        switch Inventory.select(apps, matching: options.queries) {
        case .success(let matched): selected = matched
        case .failure(let message):
            FileHandle.standardError.write(Data("duo: \(message)\n".utf8))
            return 2
        }

        // An ignored app is not asked after — its row would be filtered out below
        // anyway, so the request buys nothing. Two things override that, and both
        // are the user asking about this app specifically: naming it, and asking
        // for hidden rows. `list` asks no source at all, so it never filters here.
        let checkable = options.checkForUpdates
            ? settings.appsWorthChecking(
                selected, named: !options.queries.isEmpty, includeHidden: options.includeHidden)
            : selected

        let results: [UpdateResult]
        var gap: TestFlightGap?
        if options.checkForUpdates {
            // Built here rather than inside `checker` so the run can say afterwards
            // whether each read got in — the checker itself never reports it.
            let testflight = Inventory.testFlightStore(settings)
            let announcements = Inventory.testFlightAnnouncements(settings)
            results = await Inventory.checker(
                settings, testflight: testflight, announcements: announcements
            ).check(checkable)
            gap = testFlightGap(
                readsStore: settings.testFlightDetection.readsStore,
                storeOpened: testflight.accessible,
                storeExists: FileManager.default.fileExists(
                    atPath: TestFlightInventory.defaultDatabaseURL.path),
                announcementsOpened: announcements.accessible,
                announcementsExist: FileManager.default.fileExists(
                    atPath: TestFlightAnnouncements.defaultDatabaseURL.path),
                fullDiskAccess: Inventory.fullDiskAccess,
                betasPresent: results.contains { $0.app.isTestFlightApp || $0.app.isiOSAppOnMac },
                sourcesAdmitTestFlight: admitsTestFlight(options.sources))
        } else {
            results = selected.map { UpdateResult(app: $0, remote: nil, status: .unknown) }
        }

        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: runningBundlePaths(),
            stagedSelfUpdates: [:],
            elevationRequiredPaths: InPlaceSwap.elevationRequiredPaths(
                for: results.map(\.app.path)),
            runningBundleIDs: runningBundleIDs())

        var rows: [Row] = []
        for result in results.sorted(by: { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }) {
            let hidden = settings.isHidden(result)
            if hidden && !options.includeHidden { continue }
            if !options.all && !result.hasUpdate { continue }
            if !options.sources.isEmpty {
                // An app no source answered for has no source to match, so a
                // `--source` filter excludes it rather than letting it through.
                let source = result.remote?.sourceName.lowercased() ?? ""
                guard options.sources.contains(source) else { continue }
            }
            rows.append(Row(
                name: result.app.name,
                bundleID: result.app.bundleID,
                path: result.app.path.path,
                installedVersion: result.installedDisplay,
                installedBuild: result.app.buildVersion,
                latestVersion: result.remote?.displayVersion,
                latestBuild: result.remote?.version,
                source: result.remote?.sourceName,
                status: describe(result.status),
                hasUpdate: result.hasUpdate,
                hidden: hidden,
                route: options.checkForUpdates
                    ? route(result, settings: settings, environment: environment)
                    : nil))
        }

        return finish(
            rows, command: options.checkForUpdates ? "check" : "list", json: options.json,
            scanAbandoned: scanned == nil, testFlightGap: gap)
    }

    /// What this run could not read of TestFlight's side, among the apps it
    /// checked. nil when nothing was missed, or when nothing it checked looks like
    /// a beta.
    enum TestFlightGap: Equatable {
        /// The user turned detection off, so nothing was read.
        case detectionOff
        /// TestFlight's own store is on disk and did not open.
        case storeUnread(fullDiskAccessMissing: Bool)
        /// The store opened; TestFlight's notifications, the witness that refuses
        /// an up-to-date verdict from a store TestFlight has not caught up, did not.
        case announcementsUnread(fullDiskAccessMissing: Bool)

        /// Whether a run that found no update may still say everything is current.
        /// Detection off keeps the summary it always had: the user chose it, and
        /// the note beneath says so.
        var leavesVerdictsUnproven: Bool { self != .detectionOff }
    }

    /// Which of TestFlight's two reads this run went without, and whether missing
    /// Full Disk Access is the known reason.
    ///
    /// **Why this exists.** With detection on and the reads refused — on macOS 27
    /// another team's container is refused outright (release note 161835690), and
    /// a `duo` started by launchd has no grant to inherit — a beta comes back
    /// `testflight` with no version, is filtered out of the default listing, and
    /// the run printed "Everything is up to date." with nothing on stderr and exit 0.
    /// Reproduced 2026-09-13 on 27.0 from a `launchctl submit` job against a beta
    /// the same binary reported an update for from a terminal.
    ///
    /// Without Full Disk Access the store is no longer opened at all
    /// (`Inventory.readsTestFlight`), so "did not open" now usually means "was not
    /// attempted". The note says "can't read", which is true of both, and the
    /// status it names is the one that decided (`Inventory.fullDiskAccess`).
    ///
    /// **Missing ≠ refused.** `accessible` is false for a store that is not there
    /// at all as well as for one that would not open, and a Mac that has never run
    /// TestFlight must not be told its betas were not checked. A refused container
    /// still answers `stat` — measured in the same job: `stat` succeeded, `open`
    /// returned `EPERM` — so existence tells the two apart; it is the same test the
    /// readers themselves use for "missing".
    ///
    /// **The cause is Full Disk Access only when the app's own test says so**
    /// (`TCCPreflight.admitsOtherAppsData`, which asks `FullDiskAccessProbe`). A
    /// store that did not open with the grant in place — its open timed out, say —
    /// is reported without a reason rather than with a plausible one.
    ///
    /// The trigger keeps the detection-off note's two predicates, for its reasons:
    /// with the store unread, `isTestFlightApp` is whatever the receipt environment
    /// said (`AppScanner.readApp`), and that misses two classes the store would have
    /// caught: a wrapped iPhone/iPad bundle, which carries no receipt at all and is
    /// recognized from the database alone, and a store copy whose installed build
    /// the database also lists. Measured on one Mac: 8 rows answer as TestFlight
    /// with detection on, 7 carry the tag with it off — and the missing one,
    /// ScreenCam, is NOT wrapped (no `WrappedBundle`, a real `_MASReceipt`), so
    /// `isiOSAppOnMac` does not recover it either while adding every wrapped App
    /// Store app as a false positive. Between them the two predicates cover what is
    /// visible without the read. A store copy on a beta track is invisible to both,
    /// so on a Mac whose only beta is one of those no note appears — a miss, and a
    /// smaller one than a confident wrong count. For the same reason the note
    /// carries no count.
    ///
    /// **`--source` decides whether betas are in question at all.** A run filtered
    /// to, say, `homebrew` never shows a TestFlight row, so a TestFlight gap is not
    /// something it missed — telling it "not every app could be checked in full"
    /// about apps it asked not to see is wrong. Only an unfiltered run, or one that
    /// names `testflight`, has one. This applies to detection off too, whose note
    /// used to print for any filter.
    static func testFlightGap(
        readsStore: Bool,
        storeOpened: Bool, storeExists: Bool,
        announcementsOpened: Bool, announcementsExist: Bool,
        fullDiskAccess: @autoclosure () -> TCCAuthStatus,
        betasPresent: Bool,
        sourcesAdmitTestFlight: Bool
    ) -> TestFlightGap? {
        guard betasPresent, sourcesAdmitTestFlight else { return nil }
        guard readsStore else { return .detectionOff }
        let unread = storeExists && !storeOpened
        // The notifications only ever refuse a verdict the store gave
        // (`TestFlightAnnouncements.isBehind` needs the store's frontier), so
        // without an open store there was nothing for them to witness.
        let unwitnessed = storeOpened && announcementsExist && !announcementsOpened
        guard unread || unwitnessed else { return nil }
        let missing = !TCCPreflight.admitsOtherAppsData(fullDiskAccess: fullDiskAccess())
        return unread
            ? .storeUnread(fullDiskAccessMissing: missing)
            : .announcementsUnread(fullDiskAccessMissing: missing)
    }

    /// Whether a `--source` filter can show a TestFlight row: no filter, or one
    /// naming it. `ArgParser.list` has already lowercased the names.
    static func admitsTestFlight(_ sources: Set<String>) -> Bool {
        sources.isEmpty || sources.contains("testflight")
    }

    /// The stderr line for a gap. The Full Disk Access sentence is the app's own
    /// (`RowActionViews`: "Without Full Disk Access, Duo Updater can't read the
    /// builds TestFlight offers you, so it can't say whether this beta is current"),
    /// with `duo` in it, because the two should explain one permission one way.
    ///
    /// Where to grant it names the terminal because that is what was measured:
    /// the same `duo` binary read the store from a shell and was refused from
    /// launchd, so from a shell the grant in effect was not duo's own
    /// (`TCCPreflight.isResponsibleForItself` documents the same attribution).
    static func note(_ gap: TestFlightGap) -> String {
        let grant = "(System Settings ▸ Privacy & Security ▸ Full Disk Access;"
            + " run from a terminal, it is the terminal app that needs it)"
        switch gap {
        case .detectionOff:
            return "duo: TestFlight betas were not checked — detection is off"
                + " (Duo Updater ▸ Settings ▸ General)."
        case .storeUnread(fullDiskAccessMissing: true):
            return "duo: TestFlight betas were not checked — without Full Disk Access,"
                + " duo can't read the builds TestFlight offers you, so it can't say"
                + " whether a beta is current \(grant)."
        case .storeUnread(fullDiskAccessMissing: false):
            return "duo: TestFlight betas were not checked — TestFlight's database"
                + " could not be read, so duo can't say whether a beta is current."
        case .announcementsUnread(fullDiskAccessMissing: true):
            return "duo: a TestFlight beta shown as current may not be — without Full"
                + " Disk Access, duo can't read TestFlight's notifications, which"
                + " announce builds its database has not recorded yet \(grant)."
        case .announcementsUnread(fullDiskAccessMissing: false):
            return "duo: a TestFlight beta shown as current may not be — TestFlight's"
                + " notifications could not be read, and they announce builds its"
                + " database has not recorded yet."
        }
    }

    /// Everything a run prints once its rows are decided, and its exit status —
    /// the part of `run` that does not touch the machine, with the two streams
    /// passed in so a test can read what a user would see.
    ///
    /// The note goes to stderr so it cannot corrupt the NDJSON on stdout, and in
    /// both modes: without `--all` the affected rows are filtered out of the JSON
    /// entirely, so a machine reader has no other way to know they were missed.
    /// After the result rather than before it — a caveat read in that order, a
    /// contradiction in the other — which takes an explicit flush in the real
    /// stream: stdout is fully buffered when it is a pipe, so without one the note
    /// lands first in `duo check | tee`, measured, while a terminal shows the
    /// intended order.
    ///
    /// **Exit status is unchanged by a gap or an abandoned scan** (decided
    /// 2026-09-13, kept deliberately): 1 when a row is
    /// actionable, else 0. A new code for "incomplete" would break every
    /// `duo check; [ $? -eq 1 ]` already written, and detection off — the other way
    /// to miss betas — has exited 0 with a note since it existed. The stderr lines,
    /// and a summary that no longer says everything is current, carry it instead.
    ///
    /// `scanAbandoned`: `Inventory.scanIfFinished` gave up, so no app was listed or
    /// checked, and its own stderr line has already said why. Both commands say so
    /// in place of their empty-result line.
    static func finish(
        _ rows: [Row], command: String, json: Bool,
        scanAbandoned: Bool, testFlightGap gap: TestFlightGap?,
        out: (String) -> Void = { print($0) },
        err: (String) -> Void = { line in
            fflush(stdout)
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    ) -> Int32 {
        let checked = command == "check"
        if json {
            emitJSON(rows, command: command)
        } else {
            let incomplete: Incomplete? = scanAbandoned
                ? .scanAbandoned
                : (gap?.leavesVerdictsUnproven == true ? .verdictsUnproven : nil)
            emitText(rows, checked: checked, incomplete: incomplete, print: out)
        }
        if checked, let gap { err(note(gap)) }
        // Exit 1 signals "there is something to do", so `duo check && echo clean`
        // works. A hidden row is by definition not something to do.
        return rows.contains(where: isActionable) ? 1 : 0
    }

    /// How this update *would* be applied, from the same policy the app uses.
    ///
    /// The environment is deliberately conservative here: the CLI has not yet
    /// registered the privileged helper (`SMAppService.daemon` needs a bundle,
    /// which a standalone binary does not have), and it does not track staged
    /// self-updates, so both are reported as unavailable rather than assumed.
    /// That makes `duo check` understate the App Store `.full` route rather than
    /// promise a one-click it cannot deliver.
    static func route(
        _ result: UpdateResult, settings: Settings, environment: InstallEnvironment
    ) -> String? {
        guard result.hasUpdate else { return nil }
        if UpdatePolicy.defersToSelfUpdater(
            result, settings: settings.updateSettings, environment: environment) {
            return "self-updater"
        }
        if UpdatePolicy.canAutoInstall(
            result, settings: settings.updateSettings, environment: environment) {
            return "in-place"
        }
        if UpdatePolicy.requiresInstaller(result, environment: environment) {
            return "installer"
        }
        return "manual"
    }

    /// Bundle paths with a live process, normalised the same way the app does so
    /// a hot-swapped bundle still matches.
    static func runningBundlePaths() -> Set<String> {
        Set(RunningApps.bundleURLs().map(UpdatePolicy.runtimeBundlePath))
    }

    static func runningBundleIDs() -> Set<String> { RunningApps.bundleIDs() }

    static func describe(_ status: UpdateStatus) -> String {
        switch status {
        case .upToDate:                    return "up-to-date"
        case .updateAvailable(let latest): return "update \(latest)"
        case .unknown:                     return "unknown"
        case .appStoreManaged:             return "app-store"
        case .toolboxManaged:              return "toolbox"
        case .testFlightManaged:           return "testflight"
        case .error(let message):          return "error: \(message)"
        }
    }

    // MARK: - Output

    static func emitJSON(_ rows: [Row], command: String) {
        NDJSON.begin(command)
        for row in rows { NDJSON.row(row) }
    }

    /// Why an empty result may not be reported as the usual empty-result line.
    enum Incomplete: Equatable {
        /// The app scan was given up on, so nothing was listed or checked.
        case scanAbandoned
        /// Some checked app could not be answered in full
        /// (`TestFlightGap.leavesVerdictsUnproven`). `check` only — `list` asks
        /// no source, so it has no verdicts to leave unproven.
        case verdictsUnproven
    }

    /// `incomplete`: an empty result is then "nothing found" rather than
    /// "everything is current", or — after an abandoned scan — "nothing looked at"
    /// rather than "nothing installed". `print` is the stream, for tests.
    static func emitText(
        _ rows: [Row], checked: Bool, incomplete: Incomplete? = nil,
        print: (String) -> Void = { Swift.print($0) }
    ) {
        guard !rows.isEmpty else {
            guard checked else {
                print(incomplete == .scanAbandoned
                    ? "No apps listed: the app scan was abandoned (see above)."
                    : "No apps found.")
                return
            }
            switch incomplete {
            case nil:
                print("Everything is up to date.")
            case .verdictsUnproven:
                print("No updates found, but not every app could be checked in full (see below).")
            case .scanAbandoned:
                print("No apps were checked: the app scan was abandoned (see above).")
            }
            return
        }
        let nameWidth = min(38, rows.map(\.name.count).max() ?? 10)
        for row in rows {
            let name = row.name.count > nameWidth
                ? String(row.name.prefix(nameWidth - 1)) + "…"
                : row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            // Same marketing version on both sides (Surge 6.9.0 → 6.9.0, a
            // JetBrains EAP) reads as a no-op unless the builds are shown — the
            // build is what actually moved. Same rule the menu bar applies via
            // `UpdateResult.buildBump`; the two must not describe an update
            // differently.
            let bump = Self.buildBump(row)
            let installed = bump.map { "\(row.installedVersion ?? "?") (\($0.installed))" }
                ?? (row.installedVersion ?? "?")
            var line = "  \(name)  \(installed)"
            if let latestRaw = row.latestVersion {
                let latest = bump.map { "\(latestRaw) (\($0.remote))" } ?? latestRaw
                line += row.hasUpdate ? "  →  \(latest)" : "  (latest \(latest))"
            }
            var tags: [String] = []
            if let source = row.source { tags.append(source) }
            if let route = row.route, route != "manual" { tags.append(route) }
            if row.hidden { tags.append("hidden") }
            if !tags.isEmpty { line += "  [\(tags.joined(separator: ", "))]" }
            print(line)
        }
        let actionable = rows.filter(isActionable).count
        if checked {
            print("\n  \(actionable) update\(actionable == 1 ? "" : "s") available "
                + "of \(rows.count) app\(rows.count == 1 ? "" : "s") shown.")
        }
    }
}
