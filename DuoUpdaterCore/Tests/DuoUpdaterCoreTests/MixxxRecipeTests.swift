import Foundation
import Testing
@testable import DuoUpdaterCore

struct MixxxRecipeTests {
    private let stableURL = "https://downloads.mixxx.org/releases/2.5.6/mixxx-2.5.6-macosarm.dmg"
    private let sha256 = "f724cd8b0048a60963f11694acbffb2438a89c1cf732117559ac3031f8486e27"

    @Test func stableArmButtonPairsVersionAndDigest() throws {
        let recipe = try #require(org_mixxx_mixxx.set.probes.first)
        let downloadPage = """
            <a class="button button-primary package-macosintel" href="https://downloads.mixxx.org/releases/2.5.6/mixxx-2.5.6-macosintel.dmg">Download (Intel)</a>
            <a class="button button-primary package-macosarm" href="\(stableURL)" data-os="macOS 11 or later (ARM)">Download (ARM)</a>
            <ul class="download-meta">
              <li title="\(sha256)">
                <img class="icon" src="fingerprint.svg" alt="SHA256 Checksum" />
                <a href="\(stableURL).sha256sum" target="_blank">SHA256</a>
              </li>
            </ul>
            <a class="button button-primary package-macosarm" href="https://downloads.mixxx.org/snapshots/2.6/mixxx-2.6-beta-505-g71c5dee15c-macosarm.dmg">Download (ARM)</a>
            """
        let entryStart = try #require(recipe.entryStartPattern)
        let entry = try #require(VendorProbeRecipe.highestVersionEntry(
            in: downloadPage, entryStartPattern: entryStart, versionPattern: recipe.versionPattern,
            selectHighest: recipe.selectHighest))
        #expect(VendorProbeRecipe.extractVersion(from: entry, pattern: recipe.versionPattern) == "2.5.6")

        let spec = try #require(recipe.install)
        let checksum = try #require(spec.checksumPattern)
        #expect(VendorProbeRecipe.extractVersion(from: entry, pattern: checksum) == sha256)
        #expect(spec.checksumFormat == .sha256Hex)
        #expect(spec.kind == .dmg)
        guard case .versionTemplate(let template) = spec.urlSource else {
            Issue.record("Expected a versioned stable archive")
            return
        }
        #expect(template.replacingOccurrences(of: "{version}", with: "2.5.6") == stableURL)

        let mismatchedPath = downloadPage.replacingOccurrences(of: "/2.5.6/mixxx-", with: "/2.5.7/mixxx-")
        #expect(VendorProbeRecipe.highestVersionEntry(
            in: mismatchedPath, entryStartPattern: entryStart, versionPattern: recipe.versionPattern,
            selectHighest: recipe.selectHighest) == nil)
        let checksumOutsideCard = entry.replacingOccurrences(of: #"<ul class="download-meta">"#,
            with: #"<ul class="download-meta"></ul><ul class="download-meta">"#)
        #expect(VendorProbeRecipe.extractVersion(from: checksumOutsideCard, pattern: checksum) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: checksumOutsideCard, pattern: recipe.versionPattern) == nil)

        let staleDigest = entry.replacingOccurrences(
            of: "\(stableURL).sha256sum", with: "https://downloads.mixxx.org/releases/2.5.4/mixxx-2.5.4-macosarm.dmg.sha256sum")
        #expect(VendorProbeRecipe.extractVersion(from: staleDigest, pattern: recipe.versionPattern) == nil)
        let staleDigestBeforeCurrent = entry.replacingOccurrences(
            of: #"<ul class="download-meta">"#,
            with: """
                <ul class="download-meta">
                <li title="\(String(repeating: "a", count: 64))">
                  <img alt="SHA256 Checksum" />
                  <a href="https://downloads.mixxx.org/releases/2.5.4/mixxx-2.5.4-macosarm.dmg.sha256sum">SHA256</a>
                </li>
                """)
        #expect(VendorProbeRecipe.extractVersion(
            from: staleDigestBeforeCurrent, pattern: recipe.versionPattern) == nil)
        let missingDigest = entry.replacingOccurrences(of: sha256, with: "")
        #expect(VendorProbeRecipe.extractVersion(from: missingDigest, pattern: recipe.versionPattern) == nil)
    }

    @Test func manualKeepsReleasedVersionsAndOriginalHeadings() throws {
        let html = #"""
            <h2><a class="reference external" href="https://github.com/mixxxdj/mixxx/milestone/56">2.5.7</a> (unreleased)<a class="headerlink" href="#unreleased"></a></h2>
            <ul><li><p>Unreleased change.</p></li></ul>
            <h2><a class="reference external" href="https://github.com/mixxxdj/mixxx/milestone/53">2.5.6</a> (2026-03-25)<a class="headerlink" href="#v2-5-6"></a></h2>
            <section id="id2">
            <h3>Library<a class="headerlink" href="#id2"></a></h3>
            <ul class="simple"><li><p>History: allow track file export</p></li></ul></section>
            <h2><a class="reference external" href="https://github.com/mixxxdj/mixxx/milestone/53">2.5.5</a> (skipped)<a class="headerlink" href="#skipped"></a></h2>
            <ul><li><p>Skipped change.</p></li></ul>
            <h2><a class="reference external" href="https://github.com/mixxxdj/mixxx/milestone/52">2.5.4</a> (2025-12-12)<a class="headerlink" href="#v2-5-4"></a></h2>
            <ul><li><p>Updated controller mappings.</p></li></ul>
            """#
        let recipe = try #require(org_mixxx_mixxx.set.changelogs.first)
        #expect(recipe.channel == .stable)
        let entries = try #require(ChangelogExtractor.extract(from: html, using: recipe)).entries
        #expect(entries.map(\.version) == ["2.5.6", "2.5.4"])
        #expect(entries.first?.content == [.heading("Library"), .note("History: allow track file export")])
        #expect(entries.last?.items == ["Updated controller mappings."])
    }

    @Test func snapshotChannelsDoNotFallBackToStableNotes() {
        for channel in [ReleaseChannel.beta, .alpha, .nightly] {
            #expect(ChangelogRecipeRegistry.recipe(forBundleID: MixxxBuild.bundleID, channel: channel) == nil)
        }
    }

    @Test func scannerSeparatesUtf16BuildDescriptionsFromSharedDatabaseKeys() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MixxxRecipeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        func bundle(
            _ version: String, gitInfo: String, encoding: String.Encoding = .utf16LittleEndian,
            bundleID: String = MixxxBuild.bundleID
        ) throws -> URL {
            let app = root.appendingPathComponent("\(UUID().uuidString)/Mixxx.app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(
                at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            let plist = [
                "CFBundleIdentifier": bundleID, "CFBundleName": "Mixxx", "CFBundlePackageType": "APPL",
                "CFBundleExecutable": "Mixxx", "CFBundleShortVersionString": version, "CFBundleVersion": version,
            ]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            var bytes = Data("refreshRate\0\(version)-beta\0WaveformType\0".utf8)
            bytes.append(try #require("\0\(gitInfo)\0".data(using: encoding)))
            try bytes.write(to: contents.appendingPathComponent("MacOS/Mixxx"))
            return app
        }

        let scanner = AppScanner(locations: [], testflight: TestFlightInventory(macRows: []))
        let stable = try bundle("2.5.4", gitInfo: "HEAD\0" + "2.5.4", encoding: .utf8)
        let beta = try bundle("2.6.0", gitInfo: "2.6\0" + "2.6-beta-505-g71c5dee15c")
        let alpha = try bundle("2.7.0", gitInfo: "main\0" + "2.7-alpha-450-gf8d7c4e818")
        let maintenance = try bundle("2.5.4", gitInfo: "2.5\0" + "2.5.4-1-g08b6aeb3ee", encoding: .utf8)
        let unfamiliar = try bundle("2.6.0", gitInfo: "2.6\0" + "unrecognised-layout")
        let unrelated = try bundle("2.6.0", gitInfo: "2.6-beta-505-g71c5dee15c", bundleID: "org.example.other")
        let missing = try bundle("2.6.0", gitInfo: "2.6-beta-505-g71c5dee15c")
        try FileManager.default.removeItem(at: missing.appendingPathComponent("Contents/MacOS/Mixxx"))
        let stableCopy = try #require(scanner.readApp(at: stable))
        let unclassifiedCopy = try #require(scanner.readApp(at: missing))
        #expect(stableCopy.releaseChannel == .stable)
        #expect(stableCopy.recipeBundleID == MixxxBuild.bundleID)
        #expect(unclassifiedCopy.bundleID == MixxxBuild.bundleID)
        #expect(unclassifiedCopy.recipeBundleID == nil)
        #expect(scanner.readApp(at: beta)?.releaseChannel == .beta)
        #expect(scanner.readApp(at: alpha)?.releaseChannel == .alpha)
        #expect(scanner.readApp(at: maintenance)?.releaseChannel == .nightly)
        #expect(try #require(scanner.readApp(at: unfamiliar)).recipeBundleID == nil)
        #expect(scanner.readApp(at: unrelated)?.releaseChannel == .stable)
    }
}
