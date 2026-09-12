import Foundation

extension UpdateChecker {
    /// A TestFlight row's verdict from the build TestFlight's store names as the
    /// latest, against the copy on disk. One function for the check (`check`'s
    /// TestFlight branch, after the gates that can refuse any verdict) and for a
    /// rescan (`ScanRowAssembly.merged`), so the two compare the same way. Only
    /// the check runs those gates: a rescan answers from the build the last check
    /// read, and until the next round it can call a copy current that the check's
    /// announcement witness would have refused. The rescan used to keep whatever
    /// the last check said, and TestFlight installs its betas itself between
    /// checks (#478).
    ///
    /// - `.testFlightManaged` when the installed build is newer than the store's
    ///   latest: whatever else is true, that latest is not an upper bound for this
    ///   copy, so neither an update nor "up to date" may be claimed. The caller
    ///   drops the remote, so a version called unusable is not the one shown.
    /// - `.updateAvailable` when the store's latest is newer, labelled with its
    ///   marketing version alone, even when it did not move: a beta that keeps its
    ///   version across builds is the common case, and the row shows both builds
    ///   through `UpdateResult.buildBump`, which only recognizes a build bump when
    ///   `latest` IS the marketing version. A blank marketing version falls back to
    ///   the build, so the row never names nothing.
    /// - `.upToDate` otherwise.
    ///
    /// Compares `VersionSide` pairs, not bare build strings: a major version that
    /// restarts build numbering (TestFlight allows it, since build uniqueness is
    /// per marketing version) is still an update.
    public static func testFlightVerdict(
        installed app: InstalledApp, latestShortVersion: String?, latestBuild: String
    ) -> UpdateStatus {
        let marketing = latestShortVersion.flatMap { $0.isEmpty ? nil : $0 }
        let installedSide = VersionSide(marketing: app.shortVersion, build: app.buildVersion)
        let latestSide = VersionSide(marketing: marketing, build: latestBuild)
        if VersionComparator.isNewer(installedSide, than: latestSide) { return .testFlightManaged }
        return VersionComparator.isNewer(latestSide, than: installedSide)
            ? .updateAvailable(latest: marketing ?? latestBuild)
            : .upToDate
    }
}

extension UpdateChecker {
    /// Which of TestFlight's rows may answer for this app — decided HERE, not
    /// inside the inventory, and the two buckets are mutually exclusive on purpose.
    /// A wrapped iPhone/iPad bundle's builds are filed under the iOS platform and it
    /// can never install a mac build; a native Mac app can hold iOS rows of its own
    /// and must never be offered one. Measured 2026-09-09 on one machine: Paste is
    /// on the mac track at 29808607 with an iOS track at 29814462, and Claudo — a
    /// wrapped bundle — had 0.3.384 (1300) installed with 1301 offered, both iOS
    /// rows, which the mac-only lookup could not see at all (#476).
    ///
    /// ⚠️ This also lets a wrapped bundle reach `.upToDate`, which it could not
    /// before: with no mac rows it always landed on `.testFlightManaged` and claimed
    /// nothing. That immunity was an accident of the bug, not a safeguard — but it
    /// did mean these rows could never inherit the staleness this database has
    /// (measured six weeks old on one machine while pushes kept arriving). What
    /// closes that is the freshness gate in #478, for every TestFlight row at once,
    /// not a special case here.
    ///
    /// One function because there are two callers now: `check`'s TestFlight branch,
    /// and `TestFlightSyncPolicy.evidence`, which asks the same question of the same
    /// store in order to decide whether that store is worth re-syncing. Two copies
    /// of a platform split would be two places to get a wrapped bundle wrong.
    public static func testFlightLatest(
        for app: InstalledApp, in inventory: TestFlightInventory
    ) -> TestFlightInventory.App? {
        app.isiOSAppOnMac
            ? inventory.latestIOS(forBundleID: app.bundleID)
            : inventory.latest(forBundleID: app.bundleID)
    }
}
