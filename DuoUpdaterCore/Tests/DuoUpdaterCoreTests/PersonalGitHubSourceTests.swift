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
        var headers = [String: String]()
        let auth = request.value(forHTTPHeaderField: "Authorization")
        if url.host == "release-assets.githubusercontent.com", url.path == "/example", auth == nil {
            body = "CDN"
        } else if url.host != "api.github.com" || request.value(forHTTPHeaderField: "Cookie") != nil {
            status = 400
            body = ""
        } else {
            switch url.path {
            case "/repos/demo/fixture" where auth == nil:
                body = #"{ "private":false,"visibility":"public","id":40,"full_name":"demo/fixture","owner":{"id":12}}"#
            case "/repos/demo/limited" where auth == nil:
                status = 403
                headers = ["X-RateLimit-Remaining":"0","X-RateLimit-Reset":String(Int(Date().timeIntervalSince1970) + 600)]
                body = ""
            case "/repos/demo/limited" where auth == "Bearer fixture":
                body = #"{"private":false,"visibility":"public","id":41,"full_name":"demo/limited","owner":{"id":12}}"#
            case "/repos/demo/private" where auth == "Bearer fixture":
                body = #"{"private":true,"visibility":"private","id":42,"full_name":"demo/private","owner":{"id":12}}"#
            case "/repos/demo/internal" where auth == "Bearer fixture":
                body = #"{"private":false,"visibility":"internal","id":42,"full_name":"demo/internal","owner":{"id":12}}"#
            case "/repositories/41/releases/assets/7" where auth == "Bearer fixture":
                status = 302
                headers = ["Location":"https://release-assets.githubusercontent.com/example"]
                body = ""
            case "/repositories/40/releases" where auth == nil, "/repositories/41/releases" where auth == "Bearer fixture":
                body = #"[{"id":5,"tag_name":"v2.1","prerelease":false,"draft":false,"body":"Plain <b>release notes</b>","assets":[{"id":7,"name":"App-Lite-arm64.zip","size":30,"digest":null,"updated_at":"2026-11-25"}]}]"#
            default:
                status = 404
                body = ""
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
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

private actor SourceTestLogin {
    var token: String?
    func enable() { token = "fixture" }
}

extension PersonalGitHubSourceTests {
    @Test func accountCanContinueAfterAnonymousLimitAndOnlyReadPublicReleases() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PersonalGitHubFixture.self]
        let login = SourceTestLogin()
        let client = PersonalGitHubClient(configuration: config, resolveToken: { await login.token })
        do {
            _ = try await client.fetch("demo/limited")
            Issue.record("Expected an anonymous limit")
        } catch let error as Source.Failure {
            #expect(error.disposition == .anonymousLimit)
        }
        await login.enable()
        let snapshot = try await client.fetch("demo/limited")
        #expect(snapshot.releases.first?.tag_name == "v2.1")
        for slug in ["demo/private", "demo/internal"] {
            do {
                _ = try await client.fetch(slug)
                Issue.record("Expected nonpublic repository to be rejected")
            } catch let error as Source.Failure {
                #expect(error.disposition == .reviewSource)
            }
        }
        // Only an authenticated API request and an anonymous CDN request reach
        // the deliberately mismatched published digest in this fixture.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let asset = Source.Asset(id: 7, name: "app.zip", size: 3, digest: "sha256:" + String(repeating: "0", count: 64), updated_at: "")
        do {
            _ = try await client.downloadZIP(repository: snapshot.repository, asset: asset, into: directory)
            Issue.record("Expected fixture digest mismatch")
        } catch let error as Source.Failure {
            #expect(error.disposition == .blocked)
        }
    }
}
