import Foundation
import Testing

@testable import DuoUpdaterCore

@Suite struct LICEcapRecipeTests {
    @Test func scansTheBuildOnlyAppButStillExcludesUnversionedHelpers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scanner = AppScanner(locations: [], testflight: TestFlightInventory(macRows: []))

        func bundle(_ name: String, id: String, build: String, short: String? = nil) throws -> URL {
            let app = directory.appendingPathComponent(name + ".app", isDirectory: true)
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var fields = ["CFBundleIdentifier": id, "CFBundleVersion": build, "CFBundleName": name]
            fields["CFBundleShortVersionString"] = short
            let plist = try PropertyListSerialization.data(
                fromPropertyList: fields, format: .xml, options: 0)
            try plist.write(to: contents.appendingPathComponent("Info.plist"))
            return app
        }

        let copy = try bundle("LICEcap", id: com_cockos_LICEcap.bundleID, build: "1.31")
        #expect(AppScanner.hasRow(copy))
        let installed = try #require(scanner.readApp(at: copy))
        #expect(installed.shortVersion == "1.31")
        #expect(installed.buildVersion == "1.31")
        let explicit = try bundle("LICEcap Explicit", id: com_cockos_LICEcap.bundleID, build: "221", short: "2.0")
        #expect(scanner.readApp(at: explicit)?.shortVersion == "2.0")
        let invalid = try bundle("LICEcap Invalid", id: com_cockos_LICEcap.bundleID, build: " ")
        #expect(!AppScanner.hasRow(invalid))
        #expect(scanner.readApp(at: invalid) == nil)
        let helper = try bundle("Helper", id: "com.example.helper", build: "1.31")
        #expect(!AppScanner.hasRow(helper))
        #expect(scanner.readApp(at: helper) == nil)
    }

    @Test func offersTheCurrentMacDownloadAndComparesTheBundleBuild() async throws {
        let recipe = try #require(com_cockos_LICEcap.set.probes.first)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DownloadPageFixture.self]
        let source = VendorProbeSource(
            recipes: [recipe], session: URLSession(configuration: config))

        let old = Self.app(short: "1.30", build: "1.31")
        let remote = try #require(try await source.latestVersion(for: old))
        #expect(remote.shortVersion == "1.32")
        #expect(remote.version == "1.32")
        #expect(remote.downloadURL?.absoluteString == "https://www.cockos.com/licecap/licecap132.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(UpdateChecker.evaluate(installed: old, remote: remote) == .updateAvailable(latest: "1.32"))
        #expect(UpdateChecker.evaluate(
            installed: Self.app(short: "1.31", build: "1.32"), remote: remote) == .upToDate)
    }

    @Test(arguments: [
        "",
        #"<A href="licecap131.dmg">LICEcap v1.32 for macOS</a> (Jun 8 2022) (876kb DMG)<br>"#,
        #"<A href="https://unrelated.invalid/licecap132.dmg">LICEcap v1.32 for macOS</a> (Jun 8 2022) (876kb DMG)<br>"#,
    ])
    func malformedCurrentMacLinkNeverFallsBackToTheArchive(currentMacLink: String) throws {
        let recipe = try #require(com_cockos_LICEcap.set.probes.first)
        let html = Self.html.replacingOccurrences(of: Self.currentMacLink, with: currentMacLink)
        #expect(VendorProbeRecipe.extractVersion(from: html, pattern: recipe.versionPattern) == nil)
    }

    @Test func macReleaseHistoryPreservesPlatformLabelsAndItems() throws {
        let recipe = try #require(com_cockos_LICEcap.set.changelogs.first)
        let entries = try #require(ChangelogExtractor.extract(from: Self.html, using: recipe)).entries
        #expect(entries.map(\.version) == ["1.32", "1.31", "1.30"])
        #expect(entries.first?.date == "Jun 8 2022")
        #expect(entries.first?.items == [
            "Windows: Prevent positioning window offscreen [issue 72]",
            "Windows: sign installer/executable",
        ])
        #expect(entries[1].items == [
            "macOS: Big Sur support (thanks https://github.com/ganjarpanji)",
            "macOS: Apple Silicon (M1) native support",
            "macOS: now requires macOS 10.7 or later (10.6 users can use v1.30 for eternity)",
        ])
        #expect(entries.last?.items.count == 3)
    }

    private static func app(short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: "LICEcap", bundleID: com_cockos_LICEcap.bundleID, shortVersion: short,
            buildVersion: build, path: URL(fileURLWithPath: "/Applications/ZZFixture-LICEcap.app"),
            isMASApp: false, sparkleFeedURL: nil)
    }

    private final class DownloadPageFixture: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url, url.absoluteString == "https://www.cockos.com/licecap/",
                  let response = HTTPURLResponse(
                      url: url, statusCode: 200, httpVersion: nil,
                      headerFields: ["Content-Type": "text/html; charset=utf-8"])
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(LICEcapRecipeTests.html.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    // Cockos's current section and the first two release entries in its archive.
    private static let currentMacLink =
        #"<A href="licecap132.dmg">LICEcap v1.32 for macOS</a> (Jun 8 2022) (876kb DMG)<br>"#
    private static let html = #"""
        <B>Download</B><BR><BR>
        <A href="licecap132-install.exe">LICEcap v1.32 for Windows</a> (Jun 8 2022) (250kb installer)<BR>
        \#(currentMacLink)
        <ul>
          <li>Windows: Prevent positioning window offscreen [issue 72]
          <li>Windows: sign installer/executable
        </ul>

        <b>Source code</b><ul>
        Official GitHub mirror: <a href="https://www.github.com/justinfrankel/licecap.git">github.com/justinfrankel/licecap</a>
        </ul>
        <a href="#" onClick="document.getElementById('old').style.display='inline';return false">Old versions</a><div id="old" style="display:none"><ul>
        <A href="licecap131.dmg">LICEcap v1.31 for macOS</a> (Feb 17 2021) (876kb DMG)
        <ul>
          <li>macOS: Big Sur support (thanks https://github.com/ganjarpanji)
          <li>macOS: Apple Silicon (M1) native support
          <li>macOS: now requires macOS 10.7 or later (10.6 users can use v1.30 for eternity)
        </ul>
        <A href="licecap130.dmg">LICEcap v1.30 for macOS</a> (Apr 4 2020) (540kb DMG)
        <ul>
          <li>macOS: fixed macOS 10.15+ save dialog default extension issue
          <li>macOS: notarized for macOS 10.15+
          <li>macOS: drop 32-bit support
        </ul>
        """#
}
