import Foundation
import Testing
@testable import DuoUpdaterCore

struct PersonalGitHubSourceTests {
    typealias Source = PersonalGitHubSource

    @Test func trackSelectionPreservesTagsAndSameCycle() throws {
        let repo = try JSONDecoder().decode(Source.Repository.self, from: Data(#"{"id":1,"owner":{"id":2},"full_name":"example/demo"}"#.utf8))
        let rows = ["v2.4.0-rc0", "v2.4.0", "v2.5.0", "v2.6.0-nightly.2", "latest"].enumerated().map {
            Source.Release(id: Int64($0.offset), tag_name: $0.element, prerelease: false, draft: false, body: nil, assets: [])
        }
        let snapshot = Source.Snapshot(repository: repo, releases: rows, checked: Date(), truncated: true)
        #expect(snapshot.matches(track: .stable, installed: nil, includeStable: false).map(\.tag_name) == ["v2.5.0", "v2.4.0"])
        #expect(snapshot.matches(track: .preview, installed: "2.4.0-rc.1", includeStable: true).map(\.tag_name) == ["v2.4.0", "v2.4.0-rc0"])
        #expect(snapshot.matches(track: .nightly, installed: nil, includeStable: false).map(\.tag_name) == ["v2.6.0-nightly.2"])
        #expect(rows[0].tagIssue == .stableFlagOnPreviewTag)
        #expect(rows[4].tagIssue == .unrecognized)
        #expect(Source.Version("v2.4.0-rc0")! < Source.Version("2.4.0")!)
        #expect(Source.Version("2.4.0")! < Source.Version("2.5.0-beta.1")!)
    }

    @Test func supportedAssetAndRepositoryNames() {
        for input in ["https://elsewhere.test/org/repo", "https://user@github.com/org/repo", "org/repo?token=a", "../repo", "org/."] {
            #expect(Source.slug(input) == nil)
        }
        #expect(Source.slug("https://github.com/org/repo.git/") == "org/repo")
        #expect(Source.slug("https://www.github.com/org/repo/releases/tag/v1.2") == "org/repo")
        let zip = Source.Asset(id: 1, name: "Demo-Lite-arm64.zip", size: 100, digest: nil, updated_at: "")
        #expect(zip.matchesMac)
        #expect(zip.matches(filename: "lite"))
        #expect(!zip.matches(filename: ".*"))
        #expect(!zip.supportsLocalCheck)
        let universal = Source.Asset(id: 9, name: "Helios-universal-x64-arm64.zip", size: 32,
                                     digest: "sha256:" + String(repeating: "0", count: 64), updated_at: "")
        #expect(universal.matchesMac && universal.supportsLocalCheck)
        for name in ["Demo-linux-arm64.zip", "Demo-Windows-arm64.zip", "Demo-x86_64.dmg", "Demo-arm64.zip.sha256"] {
            #expect(!Source.Asset(id: 1, name: name, size: 1, digest: nil, updated_at: "").matchesMac)
        }
    }

    @Test func wrappedAppIsUniqueAndSiblingInstallerRejected() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: scratch) }
        let input = scratch.appendingPathComponent("input")
        let app = input.appendingPathComponent("Wrapper/Demo.app/Contents")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: app.appendingPathComponent("Info.plist"))
        // AppleDouble v2 with one 32-byte empty FinderInfo entry. It belongs
        // to Info.plist and must never become an extra unsealed bundle file.
        var sidecar = Data([0, 5, 22, 7, 0, 2, 0, 0])
        sidecar.append(Data(repeating: 0, count: 16))
        sidecar.append(contentsOf: [0, 1, 0, 0, 0, 9, 0, 0, 0, 38, 0, 0, 0, 32])
        sidecar.append(Data(repeating: 0, count: 32))
        try sidecar.write(to: app.appendingPathComponent("._Info.plist"))
        for unsafe in [false, true] {
            if unsafe { try Data().write(to: input.appendingPathComponent("Setup.pkg")) }
            let archive = scratch.appendingPathComponent("fixture-\(unsafe).zip")
            let output = scratch.appendingPathComponent("output-\(unsafe)")
            try fm.createDirectory(at: output, withIntermediateDirectories: false)
            let zip = try await ChildProcess.run("/usr/bin/zip", ["-qr", archive.path, "."], workingDirectory: input, onCancel: .terminateChild)
            #expect(zip.succeeded)
            if unsafe {
                #expect(throws: (any Error).self) { try PersonalSourceZIP.unpack(archive, into: output) }
            } else {
                let extracted = try PersonalSourceZIP.unpack(archive, into: output)
                #expect(extracted.lastPathComponent == "Demo.app")
                #expect(!fm.fileExists(atPath: extracted.appendingPathComponent("Contents/._Info.plist").path))
            }
        }
    }
}

private final class PersonalGitHubFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        var status = 200
        let body: String
        if url.host != "api.github.com" || request.value(forHTTPHeaderField: "Authorization") != nil || request.value(forHTTPHeaderField: "Cookie") != nil {
            status = 400
            body = ""
        } else {
            switch url.path {
            case "/repos/demo/fixture":
                body = #"{"id":40,"full_name":"demo/fixture","owner":{"id":12}}"#
            case "/repositories/40/releases":
                body = #"[{"id":5,"tag_name":"v2.1","prerelease":false,"draft":false,"body":"Plain <b>release notes</b>","assets":[{"id":7,"name":"App-Lite-arm64.zip","size":30,"digest":null,"updated_at":"2026-11-25"}]}]"#
            default:
                status = 404
                body = ""
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

extension PersonalGitHubSourceTests {
    @Test func anonymousClientResolvesRepositoryBeforeReleases() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PersonalGitHubFixture.self]
        let client = PersonalGitHubClient(configuration: config)
        let snapshot = try await client.fetch("https://github.com/demo/fixture")
        #expect(snapshot.repository.id == 40)
        #expect(snapshot.repository.owner.id == 12)
        #expect(snapshot.releases.first?.assets.first?.id == 7)
        #expect(snapshot.releases.first?.body == "Plain <b>release notes</b>")
        #expect(!snapshot.truncated)
        await #expect(throws: (any Error).self) { try await client.fetch("demo/missing") }
    }
}
