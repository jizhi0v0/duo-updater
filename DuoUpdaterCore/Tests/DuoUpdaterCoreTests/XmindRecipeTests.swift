import Foundation
import Testing

@testable import DuoUpdaterCore

@Suite struct XmindRecipeTests {
    private static let stableAsset =
        "https://dl3.xmind.app/Xmind-for-macOS-27.01.05089-202611160640.dmg"
    private static let betaAsset =
        "https://dl3.xmind.app/Xmind-for-macOS-25.10.03031-beta-202506290704.dmg"

    @Test(arguments: [ReleaseChannel.stable, .beta])
    func comparesTheBundleVersionAndRetainsTheOriginalInstallLocation(channel: ReleaseChannel) throws {
        let recipe = try #require(net_xmind_vana_app.set.probes.first { $0.channel == channel })
        let isStable = channel == .stable
        let location = isStable ? Self.stableAsset : Self.betaAsset
        let version = isStable ? "27.01.05089" : "25.10.03031-beta"
        let build = isStable ? "202611160640" : "202506290704"
        let otherTrack = isStable ? Self.betaAsset : Self.stableAsset
        let otherVersion = isStable ? "25.10.03031-beta" : "27.01.05089"

        #expect(recipe.followRedirects == false)
        #expect(recipe.matchesInstalled(version: version))
        #expect(!recipe.matchesInstalled(version: otherVersion))
        #expect(!recipe.matchesInstalled(version: nil))
        #expect(recipe.versionIsBuild)
        #expect(recipe.buildNamespace == .vendor)
        #expect(VendorProbeRecipe.extractVersion(from: location, pattern: recipe.versionPattern) == build)
        let displayPattern = try #require(recipe.displayVersionPattern)
        #expect(VendorProbeRecipe.extractVersion(from: location, pattern: displayPattern) == version)
        #expect(VendorProbeRecipe.extractVersion(from: otherTrack, pattern: recipe.versionPattern) == nil)
        #expect(recipe.install?.kind == .dmg)
        guard case let .bodyPattern(pattern) = recipe.install?.urlSource else {
            Issue.record("Expected the installer to use the original Location.")
            return
        }
        #expect(VendorProbeRecipe.extractVersion(from: location, pattern: pattern) == location)
    }

    @Test(arguments: [("2026071207060", true), ("2026071300580", false), ("2026071301000", false)])
    func datesDistinguishRepacksOfTheSameMarketingVersion(rawBuild: String, hasUpdate: Bool) throws {
        let recipe = try #require(net_xmind_vana_app.set.probes.first)
        let version = "26.04.01341"
        let location = "https://dl3.xmind.app/Xmind-for-macOS-\(version)-202607130058.dmg"
        let build = try #require(VendorProbeRecipe.extractVersion(from: location, pattern: recipe.versionPattern))
        let remote = VendorProbeSource.makeRemoteVersion(
            recipe: recipe, version: build, install: nil, plan: nil, resolvedDownload: nil, display: version)
        let vendorBuild = AppScanner.xmindArchiveBuild(bundleID: recipe.bundleID, bundleBuild: rawBuild)
        let installed = InstalledApp(
            name: "Xmind", bundleID: recipe.bundleID, shortVersion: version, buildVersion: rawBuild,
            vendorBuildVersion: vendorBuild, path: URL(fileURLWithPath: "/Applications/Xmind.app"),
            isMASApp: false, sparkleFeedURL: nil)
        #expect(UpdateChecker.evaluate(installed: installed, remote: remote) ==
                (hasUpdate ? .updateAvailable(latest: version) : .upToDate))
    }

    @Test func newerTimestampCannotOfferAnOlderMarketingVersion() throws {
        let recipe = try #require(net_xmind_vana_app.set.probes.first)
        let remote = VendorProbeSource.makeRemoteVersion(
            recipe: recipe, version: "202611170640", install: nil, plan: nil, resolvedDownload: nil,
            display: "27.01.05088")
        let installed = InstalledApp(
            name: "Xmind", bundleID: recipe.bundleID, shortVersion: "27.01.05089",
            buildVersion: "2026111606400", vendorBuildVersion: "202611160640",
            path: URL(fileURLWithPath: "/Applications/Xmind.app"), isMASApp: false, sparkleFeedURL: nil)
        #expect(UpdateChecker.evaluate(installed: installed, remote: remote) == .upToDate)
    }

    @Test(arguments: [
        "http://dl3.xmind.app/Xmind-for-macOS-27.01.05089-202611160640.dmg",
        "https://dl3.xmind.app.invalid/Xmind-for-macOS-27.01.05089-202611160640.dmg",
        "https://dl3.xmind.app/desktop-beta/Xmind-for-macOS-27.01.05089-202611160640.dmg",
        "https://dl3.xmind.app/Xmind-for-macOS-27.01.05089-202611160640.dmg?track=beta",
        "https://dl3.xmind.app/Xmind-for-Windows-27.01.05089-202611160640.exe",
    ])
    func stableProbeRejectsOtherLocations(location: String) throws {
        let recipe = try #require(net_xmind_vana_app.set.probes.first { $0.channel == .stable })
        #expect(VendorProbeRecipe.extractVersion(from: location, pattern: recipe.versionPattern) == nil)
    }

    @Test func recognizesTheBetaSuffixOnlyForThisBundle() {
        let bundleID = net_xmind_vana_app.bundleID
        #expect(ReleaseChannel.detect(name: "Xmind", bundleID: bundleID, keystoneChannel: nil,
                                      version: "25.10.03031-beta") == .beta)
        #expect(ReleaseChannel.detect(name: "Xmind", bundleID: bundleID, keystoneChannel: nil,
                                      version: "27.01.05089") == .stable)
        #expect(ReleaseChannel.detect(name: "Other", bundleID: "com.example.other", keystoneChannel: nil,
                                      version: "25.10.03031-beta") == .stable)
    }

    @Test func notesKeepDatesAndSectionsWithoutCrossingCardsOrDuplicatingResponsiveMarkup() throws {
        let recipe = try #require(net_xmind_vana_app.set.changelogs.first)
        let releases = Self.newestEntry + Self.previousEntry + Self.newestEntry + Self.previousEntry
        let entries = try #require(ChangelogExtractor.extract(from: releases, using: recipe)).entries

        #expect(recipe.excludedChannels.contains(.beta))
        #expect(entries.map(\.version) == ["27.01.05089", "27.01.05087"])
        #expect(entries.map(\.date) == ["Nov 17, 2026", "Nov 4, 2026"])
        #expect(entries.first?.content == [.heading("Fixes"), .note("Fixed other known issues.")])
        #expect(entries.last?.content == [
            .heading("Major Updates"),
            .note("Link Previews and Embeds: Display web preview cards and embedded content directly on your map;"),
            .heading("Improvements"),
            .note("Added support for dot grid backgrounds;"),
        ])
    }

    @Test func betaNotesUseTheVersionedNativeManifestAndDecodeItsSeparateItems() throws {
        let recipe = try #require(net_xmind_vana_app.set.changelogs.first { $0.channel == .beta })
        let manifest = #"""
            {"version":"25.10.03031-beta","updateSize":264.2,"releaseNotes":"1. New Relationship shapes;\n2. Grid-based Skeletons;\n3. New topic shapes for flowcharts.","releaseNotes-cn":"Unrelated translation"}
            """#
        let entry = try #require(ChangelogExtractor.extract(from: manifest, using: recipe)?.entries.first)
        #expect(recipe.excludedChannels.contains(.stable))
        #expect(entry.version == "25.10.03031-beta")
        #expect(entry.items.count == 3)
        #expect(entry.items.first == "New Relationship shapes;")
        #expect(entry.items.last == "New topic shapes for flowcharts.")
    }

    @Test(arguments: ["vana_macosx", "vana_sme_macosx", "vana_macosx_custom", nil] as [String?])
    func oneClickRequiresThePublicPackageIdentity(releaseType: String?) throws {
        let gate = try #require(net_xmind_vana_app.set.oneClickGates.first)
        let app = TestScratch.directory("xmind-edition").appendingPathComponent("Xmind.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        if let releaseType {
            let payload = try JSONSerialization.data(withJSONObject: ["releaseType": releaseType])
            let header = try JSONSerialization.data(withJSONObject: [
                "files": ["package.json": ["size": payload.count, "offset": "0"]],
            ])
            let padded = (header.count + 3) / 4 * 4
            func word(_ value: Int) -> Data {
                withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
            }
            let asar = word(4) + word(8 + padded) + word(4 + padded) + word(header.count)
                + header + Data(count: padded - header.count) + payload
            try asar.write(to: resources.appendingPathComponent("app.asar"))
        }

        let installed = InstalledApp(
            name: "Xmind", bundleID: net_xmind_vana_app.bundleID, shortVersion: "27.01.05088",
            buildVersion: "2026111107060", path: app, isMASApp: false,
            sparkleFeedURL: nil, releaseChannel: .stable)
        #expect(gate.admits(installed) == (releaseType == "vana_macosx"))
    }

    // Trimmed desktop cards from the public page. The extra list is page chrome
    // outside the RichTextContainer, and the test repeats the responsive copy.
    private static let newestEntry = #"""
        <div data-framer-name="Publish date" data-framer-component-type="RichTextContainer">
          <p class="framer-text">Nov 17, 2026</p>
        </div></div><div data-framer-component-type="RichTextContainer">
          <h2 class="framer-text">Xmind 27.01.05089</h2>
        </div></div></div><div data-framer-component-type="RichTextContainer">
          <h3 dir="auto" class="framer-text">Fixes</h3>
          <ul><li data-preset-tag="p"><p>Fixed other known issues.</p></li></ul>
        </div>
        <ul><li>Desktop</li></ul>
        """#

    private static let previousEntry = #"""
        <div data-framer-name="Publish date" data-framer-component-type="RichTextContainer">
          <p class="framer-text">Nov 4, 2026</p>
        </div></div><div data-framer-component-type="RichTextContainer">
          <h2 class="framer-text">Xmind 27.01.05087</h2>
        </div></div></div><div data-framer-component-type="RichTextContainer">
          <h3 dir="auto" class="framer-text">Major Updates</h3>
          <ul><li data-preset-tag="p"><p><strong>Link Previews and Embeds:</strong> Display web preview cards and embedded content directly on your map;</p></li></ul>
          <h3 dir="auto" class="framer-text">Improvements</h3>
          <ul><li data-preset-tag="p"><p>Added support for dot grid backgrounds;</p></li></ul>
        </div>
        """#
}
