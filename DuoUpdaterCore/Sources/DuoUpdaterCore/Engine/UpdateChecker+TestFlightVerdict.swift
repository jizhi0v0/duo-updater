import Foundation

extension UpdateChecker {
    /// A TestFlight row's verdict from the build TestFlight's store names as the
    /// latest, against the copy on disk. One function for the check (`check`'s
    /// TestFlight branch, after the gates that can refuse any verdict) and for a
    /// rescan (`ScanRowAssembly.merged`), so the two cannot answer one copy
    /// differently. The rescan used to keep whatever the last check said, and
    /// TestFlight installs its betas itself between checks (#478).
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
