import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// Which apps a run spends a network request on.
///
/// Ignoring an app used to hide its row while still paying for its check every
/// cycle — `duo help` promised "hide an app from update checks" and only half of
/// that was true. The saving is real but narrow, and the two ways of asking about
/// an app by hand have to keep working, or `duo install <ignored-app>` — which is
/// documented to honour a named app even when hidden — would have nothing to
/// install.
@Suite struct CheckScopeTests {

    private func app(_ name: String, path: String) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: "com.example.\(name.lowercased())",
            shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    private func settings(ignored: [InstalledApp] = [], skipped: [InstalledApp: String] = [:]) -> Settings {
        Settings(
            updateSettings: UpdateSettings(
                appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning),
            ignoredKeys: Set(ignored.map { InstallPreferenceKey.key(for: $0) }),
            skippedVersions: Dictionary(
                uniqueKeysWithValues: skipped.map { (InstallPreferenceKey.key(for: $0.key), $0.value) }),
            customScanPaths: [], maxConcurrency: 12, keepBackups: true,
            githubToken: nil, alcove: nil)
    }

    @Test func anIgnoredAppIsNotWorthARequest() {
        let watched = app("Watched", path: "/Applications/Watched.app")
        let ignored = app("Ignored", path: "/Applications/Ignored.app")
        let scope = settings(ignored: [ignored]).appsWorthChecking([watched, ignored])

        #expect(scope.map(\.name) == ["Watched"])
    }

    /// Skipping a version is not ignoring an app: whether the version on offer is
    /// still the one the user skipped can only be answered by asking, so a skipped
    /// app has to keep being checked. Dropping it here would hide 3.4 because the
    /// user declined 3.3.
    @Test func aSkippedVersionIsStillChecked() {
        let skipped = app("Skipped", path: "/Applications/Skipped.app")
        let scope = settings(skipped: [skipped: "3.3"]).appsWorthChecking([skipped])

        #expect(scope.map(\.name) == ["Skipped"])
    }

    /// `duo install Ignored` is documented to honour the name. It can only do that
    /// if the check ran for it.
    @Test func namingAnAppChecksItEvenWhenIgnored() {
        let ignored = app("Ignored", path: "/Applications/Ignored.app")
        let scope = settings(ignored: [ignored]).appsWorthChecking([ignored], named: true)

        #expect(scope.map(\.name) == ["Ignored"])
    }

    /// `--include-hidden` exists to show those rows, and a row with no check
    /// behind it would print as "unknown" — the flag would look broken.
    @Test func includeHiddenChecksTheHiddenRowsItIsAboutToPrint() {
        let ignored = app("Ignored", path: "/Applications/Ignored.app")
        let scope = settings(ignored: [ignored]).appsWorthChecking([ignored], includeHidden: true)

        #expect(scope.map(\.name) == ["Ignored"])
    }
}
