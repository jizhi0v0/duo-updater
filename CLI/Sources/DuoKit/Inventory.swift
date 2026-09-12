import Foundation
import DuoUpdaterCore

/// Scanning and checking, shared by `duo list` and `duo check`.
public enum Inventory {

    /// `AppScanner` reads TestFlight's SQLite database, which lives behind the
    /// Sequoia app-data TCC gate. With nobody at the keyboard to answer the
    /// prompt the `open()` never returns — the first CI sweep hung until the job
    /// timed out. A scan that takes this long is a permission wall, not a slow
    /// disk, so it is abandoned rather than waited on.
    static let scanTimeout = Duration.seconds(20)

    /// TestFlight's store, or the sentinel that stands for "not read", according to
    /// the user's setting. One function so the scan and the checker cannot disagree
    /// about it within a single run — a scan that read it would tag wrapped
    /// iPhone/iPad betas as TestFlight rows (#456) that the checker then had no
    /// store to answer.
    static func testFlightStore(_ settings: Settings) -> TestFlightInventory {
        settings.testFlightDetection.readsStore
            ? TestFlightInventory()
            : TestFlightInventory(macRows: [], accessible: false)
    }

    public static func scan(_ settings: Settings) async -> [InstalledApp] {
        let extraLocations = settings.customScanPaths.map { URL(fileURLWithPath: $0) }
        let testflight = testFlightStore(settings)
        return await withTaskGroup(of: [InstalledApp]?.self) { group in
            group.addTask { AppScanner(extraLocations: extraLocations, testflight: testflight).scan() }
            group.addTask {
                try? await Task.sleep(for: scanTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if first == nil {
                FileHandle.standardError.write(Data("""
                    duo: the app scan did not finish within 20s. This is almost always \
                    the TestFlight database waiting on an "access data from other apps" \
                    prompt — grant it once in System Settings ▸ Privacy & Security.\n
                    """.utf8))
            }
            return first ?? []
        }
    }

    /// Build the checker the same way the menu-bar app does, so a version
    /// difference between `duo check` and the app is a bug rather than a
    /// configuration difference.
    ///
    /// `testflight`/`toolbox`/`appStoreSignedIn` default to a fresh real read; the
    /// pre-install re-check (`Install.apply`) passes in the TestFlight-free
    /// sentinel and the single `ToolboxInventory` it built once for the whole
    /// batch — see that function's doc comment (#404 review #8).
    /// `testflight`/`announcements` default to nil rather than to a live read, so
    /// the read can be resolved from `settings` — a default argument is evaluated at
    /// the call site and cannot see the parameter it would have to consult. Passing
    /// either explicitly still wins, which is what the pre-install re-check does.
    public static func checker(
        _ settings: Settings,
        testflight: TestFlightInventory? = nil,
        announcements: TestFlightAnnouncements? = nil,
        toolbox: ToolboxInventory = ToolboxInventory(),
        appStoreSignedIn: Bool? = AppStoreSignIn.isSignedIn()
    ) -> UpdateChecker {
        let reads = settings.testFlightDetection.readsStore
        let testflight = testflight ?? testFlightStore(settings)
        let announcements = announcements
            ?? (reads ? TestFlightAnnouncements() : TestFlightAnnouncements(announcements: [], accessible: false))
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
