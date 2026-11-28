import Foundation
import Testing

@testable import DuoUpdaterCore

@Suite struct TaskPaperRecipeTests {
    private static let sourceURL = "https://www.taskpaper.com/releases/"
    private static let directID = "com.hogbaysoftware.TaskPaper3.direct"

    @Test func stableProbeUsesTheMatchingOfficialDownload() async throws {
        let recipe = try #require(com_hogbaysoftware_TaskPaper3_direct.set.probes.first)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseFixture.self]
        let source = VendorProbeSource(
            recipes: [recipe], session: URLSession(configuration: configuration))

        let offered = try await source.latestVersion(for: Self.app(version: "3.9.3"))
        let remote = try #require(offered)
        #expect(remote.shortVersion == "3.9.4")
        #expect(remote.downloadURL?.absoluteString ==
            "https://www.taskpaper.com/assets/app/TaskPaper-3.9.4.dmg")
        #expect(remote.vendorInstallerKind == .dmg)

        // A mislabeled Preview copy with the direct ID must still miss the stable probe.
        #expect(try await source.latestVersion(for: Self.app(version: "3.9.4 Preview")) == nil)
        #expect(try await source.latestVersion(for: Self.app(
            version: "3.9.3", bundleID: "com.hogbaysoftware.TaskPaper3")) == nil)
    }

    @Test(arguments: [
        "/assets/app/TaskPaper-3.9.3.dmg",
        "/assets/app/TaskPaper-Preview.dmg",
        "https://unrelated.invalid/assets/app/TaskPaper-3.9.4.dmg",
    ])
    func rejectsAnUnpairedCurrentHeadingEvenWithAnOlderValidEntry(download: String) throws {
        let recipe = try #require(com_hogbaysoftware_TaskPaper3_direct.set.probes.first)
        let html = Self.html.replacingOccurrences(of: "/assets/app/TaskPaper-3.9.4.dmg", with: download)
        #expect(VendorProbeRecipe.extractVersion(from: html, pattern: recipe.versionPattern) == nil)
    }

    @Test func releaseNotesRetainVersionsAndHistoricalSections() throws {
        let recipe = try #require(com_hogbaysoftware_TaskPaper3_direct.set.changelogs.first)
        let entries = try #require(ChangelogExtractor.extract(from: Self.html, using: recipe)).entries
        #expect(entries.map(\.version) == ["3.9.4", "3.9.3", "3.5"])
        #expect(entries.first?.date == "Nov 6, 2025")
        #expect(entries.first?.items == ["Require macOS 11", "Fixed crash on macOS 26.1"])
        #expect(entries.last?.content == [
            .note("This is a free update, just re-enter your existing license key if prompted."),
            .heading("App"),
            .note("New Icon, thanks @sdw!"),
            .heading("Sidebar"),
            .note("New sidebar interface"),
        ])
        #expect(recipe.excludedChannels.contains(.preview))
    }

    private static func app(version: String, bundleID: String = directID) -> InstalledApp {
        InstalledApp(
            name: "TaskPaper", bundleID: bundleID, shortVersion: version, buildVersion: "484",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-TaskPaper.app"), isMASApp: false,
            sparkleFeedURL: nil, releaseChannel: .stable)
    }

    private final class ReleaseFixture: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url, url.absoluteString == TaskPaperRecipeTests.sourceURL,
                  let response = HTTPURLResponse(
                      url: url, statusCode: 200, httpVersion: nil,
                      headerFields: ["Content-Type": "text/html; charset=utf-8"])
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(TaskPaperRecipeTests.html.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    // Excerpts from the vendor page, including the historical paragraph headings.
    private static let html = #"""
        <h1>Releases</h1>
        <h2>
            TaskPaper 3.9.4 – Nov 6, 2025
            <a class="btn btn-sm" href="/assets/app/TaskPaper-3.9.4.dmg"><span class="m-0 icon icon-download"></span>Download</a>
        </h2>
        <ul><li>Require macOS 11</li><li>Fixed crash on macOS 26.1</li></ul>
        <h2>
            TaskPaper 3.9.3 – Nov 12, 2024
            <a class="btn btn-sm" href="/assets/app/TaskPaper-3.9.3.dmg">Download</a>
        </h2>
        <ul><li>Fixed text selection drawing glitches</li></ul>
        <h2>
            TaskPaper 3.5 – Oct 11, 2016
            <a class="btn btn-sm" href="/assets/app/TaskPaper-3.5.dmg">Download</a>
        </h2>
        <p>This is a free update, just re-enter your existing license key if prompted.</p>
        <p>App</p>
        <ul><li>New Icon, thanks @sdw!</li></ul>
        <p>Sidebar</p>
        <ul><li>New sidebar interface</li></ul>
        <h2>Historical</h2>
        <p>Download old and unsupported versions of TaskPaper.</p>
        """#
}
