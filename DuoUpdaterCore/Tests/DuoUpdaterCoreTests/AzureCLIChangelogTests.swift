import Foundation
import Testing
@testable import DuoUpdaterCore

struct AzureCLIChangelogTests {
    // Trimmed from Microsoft's official release-notes-azure-cli.md.
    static let fixture = """
    ---
    title: Release notes & updates – Azure CLI
    ---
    # Azure CLI release notes
    ## November 03, 2026

    Version 2.92.0

    ### AKS
    * `az aks nodepool update`: Allow upgrading Windows2022 node pools to Windows2025 with `--os-sku`
    ### Packaging
    * `az version`: Detect Homebrew casks with symlinked prefixes

    ## October 06, 2026

    Version 2.91.0

    ### ACR
    * `az acr import`: Warn when a regional source endpoint falls back to the source registry's home region
    """

    @Test func selectsExactVersionAndPreservesMarkdown() throws {
        let log = try #require(AzureCLIChangelog.parse(Self.fixture, version: "2.92.0"))
        #expect(log.itemSyntax == .markdown)
        #expect(log.entries.count == 1)
        #expect(log.entries[0].date == "November 03, 2026")
        #expect(log.entries[0].items.count == 2)
        #expect(log.entries[0].items[1].contains("`az version`"))
        #expect(log.entries[0].content.contains(.heading("AKS")))
        let previous = try #require(AzureCLIChangelog.parse(Self.fixture, version: "2.91.0"))
        #expect(previous.entries[0].items.count == 1)
        #expect(previous.entries[0].date == "October 06, 2026")
        #expect(AzureCLIChangelog.parse(Self.fixture, version: "2.93.0") == nil)
        #expect(AzureCLIChangelog.parse("# Not release notes", version: "2.92.0") == nil)
        #expect(AzureCLIChangelog.parse(Self.fixture.replacingOccurrences(of: "\n", with: "\r\n"), version: "2.92.0") == log)
    }

    private final class Document: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard request.url == AzureCLIChangelog.source else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(AzureCLIChangelogTests.fixture.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @Test func serviceFetchesDocumentAndInvalidatesOldCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Document.self]
        let service = BrewFormulaReleaseService(session: URLSession(configuration: configuration), cacheDirectory: directory)
        let result = await service.release(for: "azure-cli", version: "2.92.0", token: nil)
        #expect(result.changelog?.entries.first?.version == "2.92.0")
        #expect(result.pageURL == AzureCLIChangelog.page)
        #expect(await service.cached(for: "azure-cli", version: "2.92.0") == result)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json.removeValue(forKey: "dedicatedSource")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        #expect(await service.cached(for: "azure-cli", version: "2.92.0") == nil)
        let missing = await service.release(for: "azure-cli", version: "2.93.0", token: nil)
        #expect(missing.changelog == nil)
        #expect(missing.pageURL == AzureCLIChangelog.page)
        #expect(await service.cached(for: "azure-cli", version: "2.93.0") == nil)
        #expect(BrewFormulaReleaseService.hasDedicatedNotes(for: "azure-cli"))
        #expect(!BrewFormulaReleaseService.hasDedicatedNotes(for: "other/azure-cli"))
    }

    @Test func caskAndFormulaNotesHaveSeparateDiskEntries() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = BrewFormulaReleaseService(cacheDirectory: directory)
        let formula = FormulaRelease(changelog: nil, pageURL: URL(string: "https://example.com/formula"))
        let cask = FormulaRelease(changelog: nil, pageURL: URL(string: "https://example.com/cask"))
        await service.persist(formula, name: "codex", version: "1.0")
        await service.persist(cask, name: "codex", version: "1.0", kind: .cask)
        await service.persist(cask, name: "codex", version: "2.0", kind: .cask)

        #expect(await service.cached(for: "codex", version: "1.0") == formula)
        #expect(await service.cached(for: "codex", version: "1.0", kind: .cask) == nil)
        #expect(await service.cached(for: "codex", version: "2.0", kind: .cask) == cask)
        #expect(BrewFormulaReleaseService.hasCaskNotes(for: "codex"))
        #expect(!BrewFormulaReleaseService.hasCaskNotes(for: "other/tap/codex"))
    }
}
