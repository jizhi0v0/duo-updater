import Testing
import Foundation
@testable import DuoUpdaterCore

/// HyperFrames (HeyGen): the scanner's `HFBuildLabel` read, the two `latest.json`
/// probes, and the What's New decoder. Recipes come from the registry, not restated.
struct HyperFramesRecipeTests {

    /// `https://static.heygen.ai/hyperframes-oss/desktop/latest.json`, 2026-10-06,
    /// verbatim except that the `x64`, `windows` and `windowsZip` blocks are cut.
    /// The `linux` and `deb` blocks are kept: each names a `build` of its own.
    private static let stableBody = #"""
        {"build":"b271","sha":"d6f5a5874e276a52b2a0bd27d26f8bac268658cd","url":"https://static.heygen.ai/hyperframes-oss/desktop/HyperFrames-b271-d6f5a5874.zip","bytes":430413126,"sha256":"cc8191876d777e7387b01d0515fe95a44f2c3d46ca7df4d75acef9da77d3d07a","delta":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/delta/manifest-b271.json","bytes":212950,"sha256":"05d107aa3622a9eb2c641486ad38bc86ea44c134ee5dd98074d2262f5c6fd409","blobs":"https://static.heygen.ai/hyperframes-oss/desktop/blobs"},"dmg":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/Install-HyperFrames-b271.dmg","bytes":473871755,"sha256":"f6999996ff32963874c53357efa692f4e15019585493e657289fac5cfa154935"},"arm64":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/HyperFrames-b271-d6f5a5874-arm64.zip","bytes":257427793,"sha256":"ccbb9eed4c9d996909223ba6db6ee88bacad780cbccc77bb941fb57289dff4fc","delta":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/delta/manifest-b271-arm64.json","bytes":205228,"sha256":"c2e2e37f571f462f7a119aa568a5f6fce2c10f43c039c4ac6b1484c1ce7b9051","blobs":"https://static.heygen.ai/hyperframes-oss/desktop/blobs"},"dmg":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/Install-HyperFrames-arm64-b271.dmg","bytes":284207366,"sha256":"82988bb1f4017cb655812efd2bee660168a6f0535ad8455c85608e953916efab"}},"linux":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/HyperFrames-x86_64-b271.AppImage","bytes":250317304,"sha256":"93ebaf3fd4c616c77a6cb663e74d971ca4e7e7e85ec25bd06f9702c39773bd10","build":"b271"},"deb":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/HyperFrames-amd64-b271.deb","bytes":200996272,"sha256":"ec291ca7ad255be1271d73a308a55748dbe91333e97d0ddbdfb30b99f23a8765","build":"b271"}}
        """#

    /// `…/desktop/canary/latest.json`, same day, cut the same way and further to the
    /// top level.
    private static let canaryBody = #"""
        {"build":"b272","sha":"4b44196dcb731d96432793650edcef9d563e2319","url":"https://static.heygen.ai/hyperframes-oss/desktop/canary/HyperFrames-b272-4b44196dc.zip","bytes":430232203,"sha256":"5feedb82e9498dd026ea75171e1937f34d7e7224a50fb670ab33f1e46225cf2c","linux":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/canary/HyperFrames-Canary-x86_64-b272.AppImage","bytes":250206712,"sha256":"dca96cb3f10b8ea629266ecbd439f0720719b2f8721af4807e329d30b0ea55d9","build":"b272"}}
        """#

    private static func recipe(_ bundleID: String) throws -> VendorProbeRecipe {
        let matches = VendorProbeRegistry.recipes.filter { $0.bundleID == bundleID }
        try #require(matches.count == 1)
        return matches[0]
    }

    private static func installPattern(_ recipe: VendorProbeRecipe) throws -> String {
        guard case .bodyPattern(let pattern)? = recipe.install?.urlSource else {
            Issue.record("expected a .bodyPattern install")
            throw CancellationError()
        }
        return pattern
    }

    // MARK: - the installed build

    /// Every build says `0.1.0` in both version keys; the label is the only thing
    /// that tells two builds apart. Anything but `b<digits>` reads as no build.
    @Test func theBuildComesFromTheLabelAndNothingElse() {
        #expect(AppScanner.hyperFramesBuildNumber([
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "0.1.0", "HFBuildLabel": "b271",
        ]) == "271")
        #expect(AppScanner.hyperFramesBuildNumber(["CFBundleVersion": "0.1.0"]) == nil)
        #expect(AppScanner.hyperFramesBuildNumber(["HFBuildLabel": "b"]) == nil)
        #expect(AppScanner.hyperFramesBuildNumber(["HFBuildLabel": "271"]) == nil)
        #expect(AppScanner.hyperFramesBuildNumber(["HFBuildLabel": "b27a"]) == nil)
        #expect(AppScanner.hyperFramesBuildNumber(["HFBuildLabel": "b２７１"]) == nil)
        #expect(AppScanner.hyperFramesBundleIDs
            == ["dev.hyperframes.desktop", "dev.hyperframes.desktop.canary"])
    }

    /// The wiring, through `AppScanner.readApp(at:)` on a bundle on disk: the label
    /// becomes the vendor build and the row's version, `CFBundleVersion` stays what
    /// the bundle says (the restart check compares it with `lsappinfo`), and the
    /// key means nothing on any other bundle id.
    @Test func theScannerFilesTheLabelAsTheVendorBuild() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hyperframes-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ name: String, id: String, label: String?) throws -> URL {
            let app = root.appendingPathComponent("\(name).app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var plist: [String: Any] = [
                "CFBundleIdentifier": id, "CFBundleName": name, "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "0.1.0",
            ]
            plist["HFBuildLabel"] = label
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return app
        }
        let scanner = AppScanner(locations: [], testflight: TestFlightInventory(macRows: []))

        let stable = try #require(scanner.readApp(
            at: try bundle("HyperFrames", id: "dev.hyperframes.desktop", label: "b270")))
        #expect(stable.vendorBuildVersion == "270")
        #expect(stable.shortVersion == "b270")
        #expect(stable.buildVersion == "0.1.0")

        let canary = try #require(scanner.readApp(
            at: try bundle("HyperFrames Canary", id: "dev.hyperframes.desktop.canary", label: "b272")))
        #expect(canary.vendorBuildVersion == "272")
        #expect(canary.releaseChannel == .canary)

        let unlabeled = try #require(scanner.readApp(
            at: try bundle("HyperFrames Old", id: "dev.hyperframes.desktop", label: nil)))
        #expect(unlabeled.vendorBuildVersion == nil)
        #expect(unlabeled.shortVersion == "0.1.0")

        let other = try #require(scanner.readApp(
            at: try bundle("Other", id: "com.example.other", label: "b270")))
        #expect(other.vendorBuildVersion == nil)
        #expect(other.shortVersion == "0.1.0")
    }

    // MARK: - the probes

    @Test func stableReadsTheTopLevelBuildAndItsUniversalZip() throws {
        let recipe = try Self.recipe("dev.hyperframes.desktop")
        #expect(recipe.channel == .stable)
        #expect(recipe.url.absoluteString == "https://static.heygen.ai/hyperframes-oss/desktop/latest.json")
        #expect(recipe.versionIsBuild)
        #expect(recipe.buildNamespace == .vendor)
        #expect(VendorProbeRecipe.extractVersion(from: Self.stableBody, pattern: recipe.versionPattern) == "271")
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.stableBody, pattern: try #require(recipe.displayVersionPattern)) == "b271")
        #expect(VendorProbeRecipe.extractVersion(from: Self.stableBody, pattern: try Self.installPattern(recipe))
            == "https://static.heygen.ai/hyperframes-oss/desktop/HyperFrames-b271-d6f5a5874.zip")
        #expect(recipe.install?.kind == .zip)
    }

    @Test func canaryReadsOnlyTheCanaryFolder() throws {
        let recipe = try Self.recipe("dev.hyperframes.desktop.canary")
        #expect(recipe.channel == .canary)
        #expect(recipe.url.absoluteString == "https://static.heygen.ai/hyperframes-oss/desktop/canary/latest.json")
        #expect(VendorProbeRecipe.extractVersion(from: Self.canaryBody, pattern: recipe.versionPattern) == "272")
        let pattern = try Self.installPattern(recipe)
        #expect(VendorProbeRecipe.extractVersion(from: Self.canaryBody, pattern: pattern)
            == "https://static.heygen.ai/hyperframes-oss/desktop/canary/HyperFrames-b272-4b44196dc.zip")
        // The stable file's zip is not under `canary/`, so the canary install
        // resolves nothing from it rather than the stable build.
        #expect(VendorProbeRecipe.extractVersion(from: Self.stableBody, pattern: pattern) == nil)
    }

    /// The zip's own sha256 from the top level, in hex — never the `delta` or
    /// `dmg` digests that follow it — and the install checks it as SHA-256.
    @Test func theChecksumIsTheUniversalZipsSHA256() throws {
        for (bundleID, body, digest) in [
            ("dev.hyperframes.desktop", Self.stableBody,
             "cc8191876d777e7387b01d0515fe95a44f2c3d46ca7df4d75acef9da77d3d07a"),
            ("dev.hyperframes.desktop.canary", Self.canaryBody,
             "5feedb82e9498dd026ea75171e1937f34d7e7224a50fb670ab33f1e46225cf2c"),
        ] {
            let install = try #require(try Self.recipe(bundleID).install)
            #expect(install.checksumFormat == .sha256Hex)
            let pattern = try #require(install.checksumPattern)
            #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pattern) == digest)
        }
        // Top-level digest gone: nothing, not the `delta`/`dmg`/`arm64` one after it.
        let pattern = try #require(try Self.recipe("dev.hyperframes.desktop").install?.checksumPattern)
        let noTopLevel = Self.stableBody.replacingOccurrences(
            of: #""bytes":430413126,"sha256":"cc8191876d777e7387b01d0515fe95a44f2c3d46ca7df4d75acef9da77d3d07a","#,
            with: #""bytes":430413126,"#)
        #expect(noTopLevel != Self.stableBody)
        #expect(VendorProbeRecipe.extractVersion(from: noTopLevel, pattern: pattern) == nil)
    }

    /// The `linux` and `deb` blocks carry a `build` of their own, which can be an
    /// EARLIER build than the release (the app's own comment on a recovery
    /// release). Moved ahead of the top level and given an older build, neither
    /// may be read.
    @Test func theLinuxBuildIsNeverTheVersion() throws {
        let recipe = try Self.recipe("dev.hyperframes.desktop")
        let body = #"{"linux":{"url":"https://static.heygen.ai/hyperframes-oss/desktop/HyperFrames-x86_64-b268.AppImage","build":"b268"},"#
            + Self.stableBody.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) == "271")
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try #require(recipe.displayVersionPattern))
            == "b271")
    }

    /// The thinner per-architecture zips end `-arm64.zip` / `-x64.zip`; the
    /// pattern is for the universal one only.
    @Test func thePerArchitectureZipIsNotTheInstall() throws {
        let pattern = try Self.installPattern(try Self.recipe("dev.hyperframes.desktop"))
        let archOnly = #"{"build":"b271","sha":"d6f5a5874e276a52b2a0bd27d26f8bac268658cd","url":"https://static.heygen.ai/hyperframes-oss/desktop/HyperFrames-b271-d6f5a5874-arm64.zip"}"#
        #expect(VendorProbeRecipe.extractVersion(from: archOnly, pattern: pattern) == nil)
    }

    /// Through the same `evaluate` the app uses: the build decides, and a copy with
    /// no label is "cannot tell" — never `271` against `0.1.0`.
    @Test func theVerdictIsOnTheBuild() {
        func app(_ build: String?) -> InstalledApp {
            InstalledApp(
                name: "HyperFrames", bundleID: "dev.hyperframes.desktop",
                shortVersion: build.map { "b\($0)" } ?? "0.1.0", buildVersion: "0.1.0",
                vendorBuildVersion: build,
                path: URL(fileURLWithPath: "/Applications/HyperFrames.app"),
                isMASApp: false, sparkleFeedURL: nil)
        }
        let remote = RemoteVersion(
            shortVersion: "b271", version: "271", buildNamespace: .vendor, downloadURL: nil,
            sourceName: "Vendor")
        #expect(UpdateChecker.evaluate(installed: app("270"), remote: remote) == .updateAvailable(latest: "b271"))
        #expect(UpdateChecker.evaluate(installed: app("271"), remote: remote) == .upToDate)
        #expect(UpdateChecker.evaluate(installed: app("272"), remote: remote) == .upToDate)
        // Ordered as numbers, as the app's own updater orders them.
        #expect(UpdateChecker.evaluate(installed: app("99"), remote: remote) == .updateAvailable(latest: "b271"))
        #expect(UpdateChecker.evaluate(installed: app(nil), remote: remote) == .unknown)
    }

    // MARK: - What's New

    /// `…/desktop/whats-new-b271.json`, 2026-10-06; `scenes` cut to one.
    private static let whatsNewB271 = #"""
        {
          "schema": 1,
          "build": "b271",
          "date": "2026-10-06",
          "title": "Grok joins your agents, and failed updates say why",
          "summary": "Pick Grok as your agent. A failed update's badge says why, and a blocked Claude Code install says why in plain words and how to finish it yourself.",
          "new": [
            "Grok is an agent you can pick beside Claude Code",
            "Linux has a .deb package; on a .deb install, Update opens the newest .deb in your browser"
          ],
          "improved": [
            "In a wide window, Framey rests beside Comment in your project and beside Send on Home",
            "Choosing Comment gets it ready; your next click on the video places the note",
            "Your first edit shows you once where Send is",
            "Framey can't be dragged, and a click on him reaches the control underneath"
          ],
          "fixed": [
            "The update badge says why an update failed when you hover or click it",
            "A blocked Claude Code install no longer shows the installer's raw output",
            "Framey stays off the update card"
          ],
          "scenes": [
            {
              "headline": "Grok joins your agents",
              "line": "Pick Grok in the agent menu, which shows whether it is installed and signed in",
              "image": "https://static.heygen.ai/hyperframes-oss/desktop/b271-grok-in-the-picker-2x.png"
            }
          ]
        }
        """#

    @Test func whatsNewReadsAsTheAppShowsIt() throws {
        let changelog = try #require(StructuredChangelogDecoder.decode(
            Self.whatsNewB271, format: .hyperFramesWhatsNew, channel: nil, maxEntries: 1))
        try #require(changelog.entries.count == 1)
        let entry = changelog.entries[0]
        #expect(entry.version == "b271")
        #expect(entry.date == "2026-10-06")
        #expect(entry.items.count == 10)
        #expect(entry.items.first?.hasPrefix("Pick Grok as your agent.") == true)
        #expect(entry.content.compactMap { if case .heading(let h) = $0 { h } else { nil } }
            == ["New", "Improved", "Fixed"])
        #expect(!entry.items.contains { $0.contains("Grok joins your agents") })
    }

    /// `…/desktop/canary/whats-new-b272.json`, 2026-10-06: `new` and `improved` are
    /// empty, so only "Fixed" is a heading.
    @Test func emptyListsHaveNoHeading() throws {
        let body = #"""
            {"schema":1,"build":"b272","date":"2026-10-06","title":"Sign-in finishes even if your browser blocks the app link","summary":"Signing in now finishes when your browser blocks the link back to HyperFrames, or when another copy of the app is open.","new":[],"improved":[],"fixed":["Sign-in finishes when your browser blocks the link back to the app","Sign-in reaches the copy you started it from when another copy is open"]}
            """#
        let entry = try #require(StructuredChangelogDecoder.decode(
            body, format: .hyperFramesWhatsNew, channel: nil, maxEntries: 1)?.entries.first)
        #expect(entry.version == "b272")
        #expect(entry.items.count == 3)
        #expect(entry.content.compactMap { if case .heading(let h) = $0 { h } else { nil } } == ["Fixed"])
    }

    /// Like the app: another schema, a build that is not `b<digits>`, or the
    /// `latest.json` the recipe falls back to, reads as nothing.
    @Test func otherDocumentsReadAsNothing() {
        let other = Self.whatsNewB271.replacingOccurrences(of: #""schema": 1"#, with: #""schema": 2"#)
        #expect(StructuredChangelogDecoder.decode(other, format: .hyperFramesWhatsNew, channel: nil, maxEntries: 1) == nil)
        let unlabeled = Self.whatsNewB271.replacingOccurrences(of: #""build": "b271""#, with: #""build": "271""#)
        #expect(StructuredChangelogDecoder.decode(unlabeled, format: .hyperFramesWhatsNew, channel: nil, maxEntries: 1) == nil)
        #expect(StructuredChangelogDecoder.decode(Self.stableBody, format: .hyperFramesWhatsNew, channel: nil, maxEntries: 1) == nil)
    }

    @Test func eachChannelReadsItsOwnWhatsNew() throws {
        let stable = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "dev.hyperframes.desktop"))
        #expect(stable.resolvedSource(forVersion: "b271").absoluteString
            == "https://static.heygen.ai/hyperframes-oss/desktop/whats-new-b271.json")
        let canary = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "dev.hyperframes.desktop.canary", channel: .canary))
        #expect(canary.resolvedSource(forVersion: "b272").absoluteString
            == "https://static.heygen.ai/hyperframes-oss/desktop/canary/whats-new-b272.json")
    }
}
