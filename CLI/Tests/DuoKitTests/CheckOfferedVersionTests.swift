import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `duo check`'s update line formats its two sides alike, as the menu bar's does
/// (`OfferedVersionLineTests`): a build on one side only is dropped. Arc's feed
/// sends "1.169.0 (88758)" as its version, with 88758 as its build; the scanner
/// names Xcode "27.0 (27A266a)" and the App Store answers "27.1".
@Suite struct CheckOfferedVersionTests {

    private func arc(installed: String, installedBuild: String) -> Check.Row {
        Check.Row(
            name: "Arc", bundleID: "company.thebrowser.Browser", path: "/Applications/Arc.app",
            installedVersion: installed, installedBuild: installedBuild,
            latestVersion: "1.169.0 (88758)", latestBuild: "88758",
            source: "Sparkle", status: "update 1.169.0 (88758)",
            hasUpdate: true, hidden: false, route: "sparkle")
    }

    private func line(_ row: Check.Row) -> String? {
        var lines: [String] = []
        Check.emitText([row], checked: true, print: { lines.append($0) })
        return lines.first { $0.contains(row.name) }
    }

    @Test func xcodesBuildOnTheInstalledSideOnlyIsDropped() throws {
        let row = Check.Row(
            name: "Xcode", bundleID: "com.apple.dt.Xcode", path: "/Applications/Xcode.app",
            installedVersion: "27.0 (27A266a)", installedBuild: "27A266a",
            latestVersion: "27.1", latestBuild: nil,
            source: "App Store", status: "update 27.1",
            hasUpdate: true, hidden: false, route: "manual")
        let text = try #require(line(row))
        #expect(text.contains("Xcode  27.0  →  27.1  ["), "\(text)")
    }

    @Test func aBuildTheFeedRepeatsIsNotShownOnOneSideOnly() throws {
        let text = try #require(line(arc(installed: "1.168.0", installedBuild: "88413")))
        #expect(text.contains("1.168.0  →  1.169.0  ["), "\(text)")
    }

    @Test func aSameMarketingBumpShowsBothBuilds() throws {
        let text = try #require(line(arc(installed: "1.169.0", installedBuild: "88700")))
        #expect(text.contains("1.169.0 (88700)  →  1.169.0 (88758)  ["), "\(text)")
    }
}
