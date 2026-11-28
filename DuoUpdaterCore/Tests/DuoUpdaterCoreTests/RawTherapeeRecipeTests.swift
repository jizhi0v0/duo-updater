import Foundation
import Testing

@testable import DuoUpdaterCore

struct RawTherapeeRecipeTests {
    private static let legacyID = "com.rawtherapee.RawTherapee"
    private static let currentID = "com.rawtherapee.rawtherapee5"
    private static let release511 = #"<a href="RawTherapee_macOS_12.3_Universal_5.11.zip">RawTherapee_macOS_12.3_Universal_5.11.zip</a>"#
    private static let release512 = #"<a href="RawTherapee_macOS_15.4_Universal_5.12.zip">RawTherapee_macOS_15.4_Universal_5.12.zip</a>"#
    private static let release513 = #"<a href="RawTherapee_MacOS_26.0_Universal_5.13.zip">RawTherapee_MacOS_26.0_Universal_5.13.zip</a>"#
    private static let checksum512 = #"<a href="RawTherapee_macOS_15.4_Universal_5.12.zip.sha256">RawTherapee_macOS_15.4_Universal_5.12.zip.sha256</a>"#
    private static let otherAssets = #"""
        <a href="RawTherapee_5.8.dmg">RawTherapee_5.8.dmg</a>
        <a href="RawTherapee_macOS_12.3_Universal_5.99-rc1.zip">RC</a>
        <a href="RawTherapee_macOS_12.3_x86_64_5.99.zip">Intel</a>
        """#
    private static let listing = [release511, release513, otherAssets, release512, checksum512]
        .joined(separator: "\n")

    private static func checker(os: String, url: URL) -> UpdateChecker {
        let recipes = com_rawtherapee_rawtherapee5.set.probes.map { $0.with(url: url) }
        return UpdateChecker(sources: [VendorProbeSource(recipes: recipes, hostOSVersion: os)])
    }

    private static func copy(
        _ version: String, id: String = legacyID, channel: ReleaseChannel = .stable
    ) -> InstalledApp {
        InstalledApp(
            name: "RawTherapee", bundleID: id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Fixture/RawTherapee.app"), isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: channel)
    }

    @Test(arguments: ["15.0", "15.3.2", "15.4", "15.7.9", "26.0", "27.2"])
    func stableCopiesUseTheHighestCompatibleListedRelease(os: String) async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.listing, contentType: "text/html")
        defer { server.stop() }
        let checker = Self.checker(os: os, url: server.url)
        let expected: String
        if os == "15.0" || os == "15.3.2" {
            expected = "5.11"
        } else if os.hasPrefix("15.") {
            expected = "5.12"
        } else {
            expected = "5.13"
        }
        let result = await checker.check(Self.copy("5.10"))
        #expect(result.status == .updateAvailable(latest: expected))
        #expect(result.remote?.vendorInstallerKind == nil)
        #expect(result.remote?.requiresManualInstaller == true)
        #expect(await checker.check(Self.copy(expected)).status == .upToDate)
        #expect(result.remote?.pageURL?.absoluteString == "https://rawtherapee.com/downloads/\(expected)/")
    }

    @Test func currentIDIsLatestAndNightlyCannotUseTheStableArchive() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.listing, contentType: "text/html")
        defer { server.stop() }
        let checker = Self.checker(os: "27.2", url: server.url)

        let previous = await checker.check(Self.copy("5.12"))
        #expect(previous.status == .updateAvailable(latest: "5.13"))
        #expect(await checker.check(Self.copy("5.13", id: Self.currentID)).status == .upToDate)
        let nightlyVersion = "5.13-42-g3458b9a18"
        let nightly = ReleaseChannel.detect(
            name: "RawTherapee", bundleID: Self.legacyID, keystoneChannel: nil, version: nightlyVersion)
        #expect(nightly == .nightly)
        #expect(await checker.check(Self.copy(nightlyVersion, channel: nightly)).status == .unknown)
        #expect(await checker.check(Self.copy(nightlyVersion)).status == .unknown)
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: Self.legacyID, channel: nightly, version: nightlyVersion) == nil)
        #expect(ReleaseChannel.detect(
            name: "RawTherapee", bundleID: Self.legacyID, keystoneChannel: nil, version: "5.12") == .stable)
        #expect(ReleaseChannel.detect(
            name: "RawTherapee", bundleID: Self.currentID, keystoneChannel: nil, version: "5.13") == .stable)
        #expect(ReleaseChannel.detect(
            name: "Another App", bundleID: "com.example.other", keystoneChannel: nil, version: nightlyVersion) == .stable)
    }

    @Test(arguments: [legacyID, currentID])
    func aNewCompatiblePatchWinsOverIncompatibleHigherVersions(id: String) async throws {
        let body = """
            \(Self.release513)
            <a href="RawTherapee_macOS_15.4_Universal_5.12.1.zip">5.12.1</a>
            <a href="RawTherapee_macOS_15.5_Universal_5.12.2.zip">5.12.2</a>
            \(Self.release512)
            <a href="RawTherapee_macOS_unknown_Universal_5.99.zip">Invalid minimum</a>
            """
        let server = try RecipeVerificationTests.StubServer(body: body, contentType: "text/html")
        defer { server.stop() }
        let selected = await Self.checker(os: "15.4.2", url: server.url).check(Self.copy("5.12", id: id))
        #expect(selected.status == .updateAvailable(latest: "5.12.1"))
        #expect(selected.remote?.pageURL?.absoluteString == "https://rawtherapee.com/downloads/5.12.1/")
        #expect(selected.remote?.vendorInstallerKind == nil)
    }

    @Test func absentCompatibleArchivesCannotBorrowAChecksumOrAnIncompatibleRelease() async throws {
        let server = try RecipeVerificationTests.StubServer(
            body: [Self.release513, Self.checksum512, Self.release511].joined(separator: "\n"),
            contentType: "text/html")
        defer { server.stop() }
        let checker = Self.checker(os: "15.7.9", url: server.url)
        #expect(await checker.check(Self.copy("5.10")).status == .updateAvailable(latest: "5.11"))
        #expect(await checker.check(Self.copy("5.11")).status == .upToDate)

        let release514 = #"<a href="RawTherapee_macOS_27.0_Universal_5.14.zip">5.14</a>"#
        let noCompatible = try RecipeVerificationTests.StubServer(
            body: [Self.release513, Self.checksum512, release514, Self.otherAssets].joined(separator: "\n"),
            contentType: "text/html")
        defer { noCompatible.stop() }
        let missing = await Self.checker(os: "15.7.9", url: noCompatible.url).check(Self.copy("5.11"))
        guard case .outsideOSWindow(let refusal) = missing.status else {
            Issue.record("Expected the newer 5.14 release to be refused on Sequoia, got \(missing.status)")
            return
        }
        #expect(refusal.bound == .floor(minimum: "27.0"))
        #expect(refusal.version == "5.14")
        #expect(missing.remote == nil)
    }

    @Test func notesKeepPublishedHeadingsAndNestedItemsWithoutInstallationText() throws {
        let body = #"""
            <h1 class="page-title">RawTherapee v5.13</h1>
            Download RawTherapee version 5.13 released on  July 26, 2026.
            <h2 id="new-features"><a aria-label="Permalink to New Features" href="#new-features">New Features</a></h2>
            <ul><li>Gamut Compression improvements:
            <ul><li>Limits are adjustable.</li></ul></li></ul>
            <h2 id="other-important-changes-since-512"><a aria-label="Permalink to Other Important Changes Since 5.12" href="#other-important-changes-since-512">Other Important Changes Since 5.12</a></h2>
            <ul><li>The default working profile is now Rec2020.</li></ul>
            <h2 id="libraw"><a aria-label="Permalink to LibRaw" href="#libraw">LibRaw</a></h2>
            <p>The bundles include LibRaw.</p>
            <h2 id="installation-instructions"><a aria-label="Permalink to Installation Instructions">Installation Instructions</a></h2>
            <p>Installation text is separate.</p>
            """#
        for recipe in com_rawtherapee_rawtherapee5.set.changelogs {
            #expect(recipe.resolvedSource(forVersion: "5.12").absoluteString == "https://rawtherapee.com/downloads/5.12/")
            let entry = try #require(ChangelogExtractor.extract(from: body, using: recipe)?.entries.first)
            #expect(entry.version == "5.13")
            #expect(entry.content == [
                .heading("New Features"), .note("Gamut Compression improvements:"), .note("Limits are adjustable."),
                .heading("Other Important Changes Since 5.12"), .note("The default working profile is now Rec2020."),
                .heading("LibRaw"), .note("The bundles include LibRaw."),
            ])
            #expect(ChangelogExtractor.extract(
                from: body.replacingOccurrences(of: "version 5.13 released", with: "version 5.12 released"),
                using: recipe) == nil)
        }
    }
}
