import Foundation
import Testing

@testable import DuoUpdaterCore

/// The "Version History" section of `mounty.app`, fetched 2026-10-16: the first
/// three releases, 1.10 / 1.9 (a two-part version after a smaller one), and the
/// first release 1.1, whose notes are `<p>` paragraphs, verbatim; the releases
/// between them are cut. The closing `</div>` and the Disqus block after it stay,
/// because the last entry's body must stop there.
private let mountyVersionHistoryFixture = #"""
    <hr id="versions"/>

    <div class="row">
        <div class="col-md-12">
            <h2>Version History</h2>
            <h4>Version 2.4 - 29th of December 2023 - <a href="releases/Mounty-2.4.dmg">download</a></h4>
            <ul>
                <li>credits page updated</li>
            </ul>
            <h4>Version 2.3 - 4th of November 2023 - <a href="releases/Mounty-2.3.dmg">download</a></h4>
            <ul>
                <li>corrections and additions to Italian translation, thanks to Walter Ferlazzo from JAW Software</li>
                <li>fixed some potential memory leaks</li>
            </ul>
            <h4>Version 2.2 - 23th of September 2023 - <a href="releases/Mounty-2.2.dmg">download</a></h4>
            <ul>
                <li>password to remount in r/w mode is now stored in keychain for your convenience</li>
                <li>tested with latest macOS Sonoma, works so far :)</li>
            </ul>
            <h4>Version 1.10 - 29th of Nov 2020 - <a href="releases/Mounty-1.10.dmg">download</a></h4>
            <ul>
                <li>this version is only compatible with macOS 11 Big Sur and up</li>
                <li>remove deprecations: update of notification framework</li>
                <li>added disclaimer on first startup</li>
            </ul>
            <h4>Version 1.9 - 21th of Sep 2018 - <a href="releases/Mounty-1.9.dmg">download</a></h4>
            <ul>
                <li>last version compatible with macOS Catalina and earlier</li>
                <li>bug fix for crash when Volume does not contain UUID (e.g. MBR Disk)</li>
                <li>Note: Old devices which does not contain UUID cannot be tracked for auto-mount</li>
                <li>Russian Credits Page added (again, thanks to Anton)</li>
            </ul>
            <h4>Version 1.1 - 27th of July 2014 - <a href="releases/Mounty-1.1.dmg">download</a></h4>
            <p>The Appstore Sandbox restrictions does not allow sandboxed apps to re-mount external volumes.
                We have rejected Mounty from Mac Appstore for that reason and decided to distribute it for free, without
                Sandbox capability.</p>
            <p>Mounty uses Apple's Notification Center to issue notification whenever a NTFS volume to re-mount is
                detected.
                If you want to re-mount a volume from a notification please change the alert style to "Alert" for Mounty
                from Notification Center Settings
                in System Settings application.</p>
        </div>
    </div>

    <hr/>

    <div class="row">
        <div class="col-md-12" id="disqus_thread">
            <noscript>Please enable JavaScript to view the <a href="http://disqus.com/?ref_noscript">comments powered by Disqus.</a></noscript>
        </div>
    </div>
"""#

private func mountyProbe() throws -> VendorProbeRecipe {
    try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "com.cu4uc.mounty" })
}

@Test func mountyReadsTheNewestVersionHistoryHeading() throws {
    let recipe = try mountyProbe()
    #expect(recipe.channel == .stable)
    #expect(recipe.selectHighest)
    let versions = try NSRegularExpression(pattern: recipe.versionPattern)
        .matches(in: mountyVersionHistoryFixture,
                 range: NSRange(mountyVersionHistoryFixture.startIndex..., in: mountyVersionHistoryFixture))
        .compactMap { Range($0.range(at: 1), in: mountyVersionHistoryFixture) }
        .map { String(mountyVersionHistoryFixture[$0]) }
    #expect(versions == ["2.4", "2.3", "2.2", "1.10", "1.9", "1.1"])
    #expect(VendorProbeRecipe.highestVersion(
        from: mountyVersionHistoryFixture, pattern: recipe.versionPattern) == "2.4")
    // The next major, and a heading the vendor might write for a prerelease.
    let next = #"<h4>Version 3.0 - 1st of May 2027 - <a href="releases/Mounty-3.0.dmg">download</a></h4>"#
    #expect(VendorProbeRecipe.extractVersion(from: next, pattern: recipe.versionPattern) == "3.0")
    for heading in [
        #"<h4>Version 2.5b1 - 1st of May 2027 - <a href="x">download</a></h4>"#,
        #"<h4>Version 2.5 beta - 1st of May 2027 - <a href="x">download</a></h4>"#,
        #"<h4>Version 2.5-rc1 - 1st of May 2027 - <a href="x">download</a></h4>"#,
    ] {
        #expect(VendorProbeRecipe.extractVersion(from: heading, pattern: recipe.versionPattern) == nil,
                "\(heading)")
    }
}

/// One-click from the vendor's own host, built from the resolved version.
@Test func mountyInstallsTheVersionedDmgFromTheVendorsHost() throws {
    let spec = try #require(try mountyProbe().install)
    #expect(spec.kind == .dmg)
    guard case .versionTemplate(let template) = spec.urlSource else {
        Issue.record("expected a version template, got \(spec.urlSource)")
        return
    }
    #expect(template.replacingOccurrences(of: "{version}", with: "2.4")
        == "https://mounty.app/releases/Mounty-2.4.dmg")
}

@Test func mountyChangelogReadsEveryReleaseAndStopsBeforeComments() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.cu4uc.mounty"))
    let log = try #require(ChangelogExtractor.extract(from: mountyVersionHistoryFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["2.4", "2.3", "2.2", "1.10", "1.9", "1.1"])
    #expect(log.entries.first?.date == "29th of December 2023")
    #expect(log.entries[0].items == ["credits page updated"])
    #expect(log.entries[1].items == [
        "corrections and additions to Italian translation, thanks to Walter Ferlazzo from JAW Software",
        "fixed some potential memory leaks",
    ])
    #expect(log.entries[4].items.count == 4)
    // 1.1's notes are paragraphs; the Disqus noscript after the section is not.
    let first = try #require(log.entries.last)
    #expect(first.items.count == 2)
    #expect(first.items.allSatisfy { !$0.contains("Disqus") })
}
