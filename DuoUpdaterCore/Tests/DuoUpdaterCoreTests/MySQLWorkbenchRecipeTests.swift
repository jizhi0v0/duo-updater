import Foundation
import Testing

@testable import DuoUpdaterCore

/// The download table of `dev.mysql.com/downloads/workbench/?os=33` (the macOS
/// tab), fetched 2026-10-16, verbatim: one dmg row and one zip row.
private let workbenchMacDownloadsFixture = #"""
<table border="0" cellpadding="2" cellspacing="0" class="table04">
                            <tr class="alt">
                        <td class="col1"><b>macOS (ARM, 64-bit), DMG Archive</b></td>
                    <td class="col3">26.7.0</td>
        <td class="col4">301.0M</td>
        <td class="col5">
                            <div class="button03"><a href="/downloads/file/?id=559071">Download</a></div>
                        </td>
    </tr>
    <tr class="alt">
        <td class="sub-text">(mysql-workbench-26.7.0-macos-arm64.dmg)</td>
        <td class="sub-text" style="text-align:right;" colspan="4">
            MD5: <code class="md5">bb0f5e5bcba12d4add0a35957ce47355</code> |
            <a class="signature" href="/downloads/gpg/?file=mysql-workbench-26.7.0-macos-arm64.dmg&p=8"
                target="_blank">Signature</a>            </td>
    </tr>
                                <tr >
                        <td class="col1"><b>macOS (ARM, 64-bit), ZIP Archive</b></td>
                    <td class="col3">26.7.0</td>
        <td class="col4">293.8M</td>
        <td class="col5">
                            <div class="button03"><a href="/downloads/file/?id=559072">Download</a></div>
                        </td>
    </tr>
    <tr >
        <td class="sub-text">(mysql-workbench-26.7.0-macos-arm64.zip)</td>
        <td class="sub-text" style="text-align:right;" colspan="4">
            MD5: <code class="md5">5b6fc29f8673f27d73e16933eecefbca</code> |
            <a class="signature" href="/downloads/gpg/?file=mysql-workbench-26.7.0-macos-arm64.zip&p=8"
                target="_blank">Signature</a>            </td>
    </tr>
            </table>
"""#

@Test func mysqlWorkbenchReadsTheMacDmgRowOnly() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.oracle.mysqlworkbench" })
    #expect(VendorProbeRecipe.extractVersion(
        from: workbenchMacDownloadsFixture, pattern: recipe.versionPattern) == "26.7.0")
    // 8.0's files are `mysql-workbench-community-…`: the other app, never read here.
    #expect(VendorProbeRecipe.extractVersion(
        from: "(mysql-workbench-community-8.0.47-macos-arm64.dmg)",
        pattern: recipe.versionPattern) == nil)
    // A suffixed filename is not a GA version.
    #expect(VendorProbeRecipe.extractVersion(
        from: "(mysql-workbench-26.8.0-rc-macos-arm64.dmg)",
        pattern: recipe.versionPattern) == nil)
    let install = try #require(recipe.install)
    #expect(install.kind == .dmg)
    guard case .versionTemplate(let template) = install.urlSource else {
        Issue.record("expected a version template")
        return
    }
    #expect(template.replacingOccurrences(of: "{version}", with: "26.7.0")
        == "https://cdn.mysql.com/Downloads/MySQLGUITools/mysql-workbench-26.7.0-macos-arm64.dmg")
}

// MARK: - 8.0 copies: the vendor's rewrite, behind the confirmation

private func workbench(id: String, version: String) -> InstalledApp {
    InstalledApp(
        name: "MySQLWorkbench", bundleID: id, shortVersion: version, buildVersion: "1",
        path: URL(fileURLWithPath: "/Applications/ZZFixture-MySQLWorkbench.app"),
        isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
}

private func offer(_ version: String, source: String = "Vendor") -> RemoteVersion {
    RemoteVersion(shortVersion: version, version: nil, downloadURL: nil, sourceName: source)
}

/// 8.0.46.CE and 8.0.47.CE (the strings the real 8.0 bundles report) are filed
/// under 26.x's id, so the 26.x probe answers them and nothing is keyed by the
/// 8.0 id. A copy on the 8.0 id at 26.7.0 or later is not the hand-over measured.
@Test func mysqlWorkbench80CopiesAreFiledUnderTheRewrite() {
    for version in ["8.0.46.CE", "8.0.47.CE"] {
        #expect(workbench(id: "com.oracle.workbench.MySQLWorkbench", version: version)
            .recipeBundleID == "com.oracle.mysqlworkbench")
    }
    #expect(workbench(id: "com.oracle.workbench.MySQLWorkbench", version: "26.7.0")
        .recipeBundleID == "com.oracle.workbench.MySQLWorkbench")
    #expect(!VendorProbeRegistry.recipes.contains {
        $0.bundleID == "com.oracle.workbench.MySQLWorkbench" })
    let team = "VB5E2TV963"
    #expect(BundleIDMigration.migration(
        installed: "com.oracle.workbench.MySQLWorkbench", downloaded: "com.oracle.mysqlworkbench",
        installedVersion: "8.0.47.CE", installedTeam: team, downloadedTeam: team) != nil)
}

/// The rewrite marker puts the 8.0 → 26 offer behind the major-upgrade
/// confirmation even though the answer comes from a license-neutral source.
@Test func aVendorRewriteIsAMajorUpgradeWhateverTheSource() {
    let old = workbench(id: "com.oracle.workbench.MySQLWorkbench", version: "8.0.47.CE")
    for source in ["Vendor", "GitHub", "App Store"] {
        let result = UpdateResult(
            app: old, remote: offer("26.7.0", source: source),
            status: .updateAvailable(latest: "26.7.0"))
        #expect(result.isVendorRewrite)
        #expect(result.isMajorUpgrade)
    }
    // Nothing to confirm when nothing is offered.
    let current = UpdateResult(app: old, remote: offer("26.7.0"), status: .upToDate)
    #expect(!current.isVendorRewrite)
    #expect(!current.isMajorUpgrade)
    // An 8.0 point release (Homebrew's cask is at 8.0.47) is not the rewrite.
    let pointRelease = UpdateResult(
        app: workbench(id: "com.oracle.workbench.MySQLWorkbench", version: "8.0.46.CE"),
        remote: offer("8.0.47", source: "Homebrew"), status: .updateAvailable(latest: "8.0.47"))
    #expect(!pointRelease.isVendorRewrite)
    #expect(!pointRelease.isMajorUpgrade)
    // A 26.x copy updating within 26.x is an ordinary Vendor update.
    let new = UpdateResult(
        app: workbench(id: "com.oracle.mysqlworkbench", version: "26.7.0"),
        remote: offer("26.8.0"), status: .updateAvailable(latest: "26.8.0"))
    #expect(!new.isVendorRewrite)
    #expect(!new.isMajorUpgrade)
}

/// A plain rename keeps today's behaviour: WhatCable's old id, offered a new
/// major from a license-neutral source, is not flagged.
@Test func anUnmarkedMigrationIsNotARewrite() {
    #expect(BundleIDMigration.all.filter(\.isRewrite).map(\.from)
        == ["com.oracle.workbench.MySQLWorkbench"])
    let renamed = InstalledApp(
        name: "WhatCable", bundleID: "com.bitmoor.whatcable", shortVersion: "0.5.14",
        buildVersion: "1", path: URL(fileURLWithPath: "/Applications/ZZFixture-WhatCable.app"),
        isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    let result = UpdateResult(
        app: renamed, remote: offer("1.0.0", source: "GitHub"),
        status: .updateAvailable(latest: "1.0.0"))
    #expect(renamed.recipeBundleID == "uk.whatcable.whatcable")
    #expect(!result.isVendorRewrite)
    #expect(!result.isMajorUpgrade)
    let unmarked = BundleIDMigration(
        from: "com.example.old", to: "com.example.new", teamID: "TEAM000001",
        lastFromVersion: "1.0", firstToVersion: "2.0")
    #expect(!unmarked.isRewrite)
    #expect(BundleIDMigration.rewrite(
        installed: "com.example.old", installedVersion: "1.0", in: [unmarked]) == nil)
}

/// The one answer the app's Update All and `duo install` both read: the rewrite
/// is asked as a rewrite, a license-boundary major as that, anything else not at
/// all. Mutation: return nil from `UpdatePolicy.installConfirmation` → red.
@Test func theRewriteAndALicenseBoundaryEachNeedTheirOwnConfirmation() {
    let rewrite = UpdateResult(
        app: workbench(id: "com.oracle.workbench.MySQLWorkbench", version: "8.0.47.CE"),
        remote: offer("26.7.0"), status: .updateAvailable(latest: "26.7.0"))
    #expect(UpdatePolicy.installConfirmation(for: rewrite) == .vendorRewrite)
    let major = UpdateResult(
        app: workbench(id: "com.oracle.mysqlworkbench", version: "26.7.0"),
        remote: offer("27.0.0", source: "Homebrew"), status: .updateAvailable(latest: "27.0.0"))
    #expect(UpdatePolicy.installConfirmation(for: major) == .licenseBoundary)
    let minor = UpdateResult(
        app: workbench(id: "com.oracle.mysqlworkbench", version: "26.7.0"),
        remote: offer("26.8.0", source: "Homebrew"), status: .updateAvailable(latest: "26.8.0"))
    #expect(UpdatePolicy.installConfirmation(for: minor) == nil)
}
