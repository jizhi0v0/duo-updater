import Foundation
import DuoUpdaterCore

/// Scanning and checking, shared by `duo list` and `duo check`.
public enum Inventory {

    /// Whether `duo` may read TestFlight's store at all: the menu-bar app's rule
    /// (`AppListModel.performRefresh`'s `mayReadTestFlight`), detection on AND
    /// Full Disk Access admitting another app's data.
    ///
    /// **Why not just try.** Without the grant the read cannot succeed, and trying
    /// is not free: the app stopped attempting it because on macOS 27 a refused
    /// read posts a "Data Access Blocked" notice (`TCCPreflight.admitsOtherAppsData`,
    /// README). Measured 2026-09-13 on 27.0 with `duo list` started directly by
    /// launchd: the attempt reached `tccd` as a
    /// `kTCCServiceSystemPolicyAppDataDetailed` request attributed to
    /// `com.duoupdater.cli` and was denied; a `stat` of the same path reached `tccd`
    /// not at all. `.unknown` still reads, as it does for a refresh the user asked
    /// for — a `duo` command is one.
    ///
    /// Pure, so the rule is testable; the live status is `fullDiskAccess` below.
    static func readsTestFlight(
        _ detection: TestFlightDetection, fullDiskAccess: @autoclosure () -> TCCAuthStatus
    ) -> Bool {
        detection.readsStore && TCCPreflight.admitsOtherAppsData(fullDiskAccess: fullDiskAccess())
    }

    /// This process's Full Disk Access, asked once — lazily, so a run with
    /// detection off never opens the probe's files.
    ///
    /// Once, not per read, because the scan and the checker each decide whether to
    /// read the store, and they must decide the same way within a run (see
    /// `testFlightStore`); a grant arriving between the two would otherwise tag
    /// betas the checker then cannot answer. `duo check` also names this status as
    /// the reason in its note, so the note and the decision cannot disagree either.
    static let fullDiskAccess: TCCAuthStatus = TCCPreflight.fullDiskAccessStatus()

    /// TestFlight's store, or the sentinel that stands for "not read", according to
    /// `readsTestFlight`. One function so the scan and the checker cannot disagree
    /// about it within a single run — a scan that read it would tag wrapped
    /// iPhone/iPad betas as TestFlight rows (#456) that the checker then had no
    /// store to answer.
    ///
    /// `fullDiskAccess` and `open` are the live status and the live read, passed in
    /// so a test can count opens: a sentinel and a refused read look identical from
    /// outside (both `accessible == false`), so only the count tells them apart.
    static func testFlightStore(
        _ settings: Settings,
        fullDiskAccess: @autoclosure () -> TCCAuthStatus = Inventory.fullDiskAccess,
        open: () -> TestFlightInventory = { TestFlightInventory() }
    ) -> TestFlightInventory {
        readsTestFlight(settings.testFlightDetection, fullDiskAccess: fullDiskAccess())
            ? open()
            : TestFlightInventory(macRows: [], accessible: false)
    }

    /// TestFlight's notifications, or the "not read" sentinel, by the same rule as
    /// `testFlightStore`. Separate because `duo check` needs to know, after the
    /// check, whether each of the two reads got in (`Check.testFlightGap`). The app
    /// does not read this one without the store either: it only ever qualifies
    /// what the store says, and it sits in another app's container too.
    static func testFlightAnnouncements(
        _ settings: Settings,
        fullDiskAccess: @autoclosure () -> TCCAuthStatus = Inventory.fullDiskAccess,
        open: () -> TestFlightAnnouncements = { TestFlightAnnouncements() }
    ) -> TestFlightAnnouncements {
        readsTestFlight(settings.testFlightDetection, fullDiskAccess: fullDiskAccess())
            ? open()
            : TestFlightAnnouncements(announcements: [], accessible: false)
    }

    public static func scan(_ settings: Settings) async -> [InstalledApp] {
        await scanIfFinished(settings) ?? []
    }

    /// `scan`, but nil when the scan was given up on rather than an empty list —
    /// for `duo check` and `duo list`, which must not follow an abandoned scan with
    /// "Everything is up to date." or "No apps found." The other commands (install, restart, backups, doctor, ignore)
    /// still take the empty list, and what each prints after it has not been
    /// reviewed for the same claim.
    static func scanIfFinished(_ settings: Settings) async -> [InstalledApp]? {
        let extraLocations = settings.customScanPaths.map { URL(fileURLWithPath: $0) }
        return await scanIfFinished(timeout: BoundedScan.timeout) {
            // ⚠️ `testFlightStore` opens the database, and that open is the thing
            // the timeout exists to race — so it has to be INSIDE this closure.
            // It used to be, invisibly: `AppScanner`'s `testflight:` default was
            // evaluated at the call site. Naming it explicitly one line further
            // out reads identically and quietly moves the one blocking call out
            // from under the only thing bounding it.
            AppScanner(
                extraLocations: extraLocations, testflight: testFlightStore(settings)).scan()
        }
    }

    /// The bounded scan, with the scanner passed in so a test can wedge it.
    /// `BoundedScan` holds the thread-and-timeout half and the reasons for it;
    /// what belongs here is only what `duo` should say when the scan is given up
    /// on, which is not what the sweep says about the same event.
    static func scan(
        timeout: Duration, _ body: @escaping @Sendable () -> [InstalledApp]
    ) async -> [InstalledApp] {
        await scanIfFinished(timeout: timeout, body) ?? []
    }

    /// The bounded scan, nil when it was given up on. The message is printed here
    /// either way, so both spellings of `scan` say the same thing about it.
    static func scanIfFinished(
        timeout: Duration, _ body: @escaping @Sendable () -> [InstalledApp]
    ) async -> [InstalledApp]? {
        guard let scanned = await BoundedScan.result(within: timeout, body) else {
            FileHandle.standardError.write(Data(
                "duo: \(BoundedScan.gaveUpMessage(after: timeout)).\n".utf8))
            return nil
        }
        return scanned
    }

    /// Build the checker the same way the menu-bar app does, so a version
    /// difference between `duo check` and the app is a bug rather than a
    /// configuration difference.
    ///
    /// `testflight`/`toolbox` default to a fresh real read; the pre-install
    /// re-check (`Install.apply`) passes in the TestFlight-free sentinel and the
    /// single `ToolboxInventory` it built once for the whole batch — see that
    /// function's doc comment (#404 review #8).
    ///
    /// App Store sign-in is read only when the TestFlight store was, as the app
    /// does (`AppListModel`'s recheck: `testflight.accessible ? AppStoreSignIn…`).
    /// It only ever refuses a TestFlight verdict, a store not read already gives
    /// none, and `Accounts4.sqlite` is behind Full Disk Access too (measured
    /// 2026-09-13: `EPERM` from a `launchctl submit` job). `appStoreSignIn` is the
    /// read, passed in so a test can count it without touching the host's database.
    /// `testflight`/`announcements` default to nil rather than to a live read, so
    /// the read can be resolved from `settings` — a default argument is evaluated at
    /// the call site and cannot see the parameter it would have to consult. Passing
    /// either explicitly still wins, which is what the pre-install re-check does.
    public static func checker(
        _ settings: Settings,
        testflight: TestFlightInventory? = nil,
        announcements: TestFlightAnnouncements? = nil,
        toolbox: ToolboxInventory = ToolboxInventory(),
        appStoreSignIn: () -> Bool? = { AppStoreSignIn.isSignedIn() }
    ) -> UpdateChecker {
        let testflight = testflight ?? testFlightStore(settings)
        let announcements = announcements ?? testFlightAnnouncements(settings)
        let appStoreSignedIn = testflight.accessible ? appStoreSignIn() : nil
        return UpdateChecker(
            sources: SourceStack.make(
                githubToken: settings.githubToken, alcove: settings.alcove,
                channelStore: ResolvedChannelStore.shared),
            maxConcurrency: settings.maxConcurrency,
            toolbox: ToolboxSource(inventory: toolbox),
            testflight: testflight,
            announcements: announcements,
            appStoreSignedIn: appStoreSignedIn,
            channelStore: ResolvedChannelStore.shared)
    }

    /// Why an app argument could not be turned into exactly one install.
    public struct SelectionFailure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Narrow `apps` to those the user named, resolving each argument as an
    /// install path, then a bundle id, then a case-insensitive name prefix.
    ///
    /// An ambiguous prefix is an error, never a guess: these arguments go on to
    /// name something we will replace on disk, and picking the "obvious" one of
    /// two Visual Studio Codes is how the wrong app gets overwritten.
    public static func select(
        _ apps: [InstalledApp], matching queries: [String]
    ) -> Result<[InstalledApp], SelectionFailure> {
        guard !queries.isEmpty else { return .success(apps) }
        var selected: [InstalledApp] = []
        for query in queries {
            let path = URL(fileURLWithPath: query).standardizedFileURL.path
            if let exact = apps.first(where: { $0.path.standardizedFileURL.path == path }) {
                selected.append(exact)
                continue
            }
            let byBundle = apps.filter { $0.bundleID == query }
            if !byBundle.isEmpty {
                selected.append(contentsOf: byBundle)
                continue
            }
            let byName = apps.filter {
                $0.name.lowercased().hasPrefix(query.lowercased())
            }
            switch byName.count {
            case 0:
                return .failure(SelectionFailure(description: "no installed app matches '\(query)'"))
            case 1:
                selected.append(byName[0])
            default:
                // Version included because the name alone often can't separate the
                // candidates: two Xcode betas are both called "Xcode" and both report
                // 27.0, and it is the build that says which is which.
                let names = byName.map { app in
                    let version = app.shortVersion.map { " \($0)" } ?? ""
                    return "  \(app.name)\(version) — \(app.path.path)"
                }.joined(separator: "\n")
                // "Name one exactly" is not advice that can work when the matches
                // share a name — naming it exactly matches all of them again.
                let hint = Set(byName.map(\.name)).count == 1
                    ? "They share a name, so pass the path of the one you mean."
                    : "Name one exactly, or pass its path."
                return .failure(SelectionFailure(description:
                    "'\(query)' matches \(byName.count) apps:\n\(names)\n" + hint))
            }
        }
        // Same app named twice (by path and by id) should be acted on once.
        var seen = Set<String>()
        return .success(selected.filter { seen.insert($0.id).inserted })
    }
}
