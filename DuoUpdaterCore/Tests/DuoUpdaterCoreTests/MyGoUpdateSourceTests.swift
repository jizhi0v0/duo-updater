import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

// MARK: - Reading the feed and key out of the binary

/// `MyGoUpdateConfig.find` over bytes laid out as Go's linker lays out
/// `__TEXT,__rodata`: string literals packed with no terminator, and each `-X`
/// value a symbol of its own followed by a NUL (`cmd/link` `addstrdata`).
struct MyGoUpdateConfigTests {

    static let feed = "https://github.com/acme/app/releases/latest/download/update-darwin-arm64.json"
    static let key = Data((0..<32).map { UInt8($0 &* 7 &+ 3) }).base64EncodedString()

    /// Packed Go literals, as they sit around the `-X` strings: the module's
    /// `h1:` hash is 44 base64 characters with no NUL after it, and a
    /// NUL-terminated base64 blob of another length is no key either.
    static let literals = Array(
        "github.com/egoist/mygoh1:Vs2FDcg+h0SShYSlL8vpxhFeSbMfylVeV31naaTPeoU=mygo: checking for updates"
            .utf8)
        + [0] + Array(Data(repeating: 9, count: 64).base64EncodedString().utf8) + [0]

    static func rodata(_ strings: [String], literals: [UInt8] = literals) -> Data {
        var bytes = literals
        for s in strings { bytes += [0, 0] + Array(s.utf8) + [0] }
        return Data(bytes + Array("trailing literal".utf8))
    }

    @Test func findsTheFeedAndKeyMyGoLinked() {
        let config = MyGoUpdateConfig.find(in: Self.rodata([Self.feed, Self.key]))
        #expect(config == MyGoUpdateConfig(feed: Self.feed, publicKey: Self.key))
        #expect(config?.isTagged == false)
        #expect(config?.manifestURL == URL(string: Self.feed))
    }

    /// Mutation: drop the uniqueness guard → the app is covered with whichever
    /// key the scan met last.
    @Test func twoKeysOrTwoFeedsLeaveTheAppUncovered() {
        let other = Data(repeating: 1, count: 32).base64EncodedString()
        #expect(MyGoUpdateConfig.find(in: Self.rodata([Self.feed, Self.key, other])) == nil)
        let otherFeed = "https://cdn.example.com/app/update-darwin-amd64.json"
        #expect(MyGoUpdateConfig.find(in: Self.rodata([Self.feed, otherFeed, Self.key])) == nil)
        // The same string twice is one value.
        #expect(MyGoUpdateConfig.find(in: Self.rodata([Self.feed, Self.key, Self.key])) != nil)
    }

    /// Mutations: drop the trailing-NUL requirement → the `h1:` hash in
    /// `literals` becomes a second key; drop the preceding-byte check → a key
    /// glued to more base64 is read as one.
    @Test func onlyAStandaloneNulTerminatedKeyIsAKey() {
        #expect(MyGoUpdateConfig.find(in: Self.rodata([Self.feed])) == nil)
        #expect(MyGoUpdateConfig.find(in: Self.rodata([Self.feed, "Q" + Self.key])) == nil)
        #expect(MyGoUpdateConfig.find(in: Self.rodata([Self.feed, Self.key])) != nil)
        // 44 characters that do not decode to 32 bytes.
        let notAKey = String(repeating: "A", count: 42) + "=="
        #expect(MyGoUpdateConfig.find(in: Self.rodata([Self.feed, notAKey])) == nil)
    }

    @Test func onlyADarwinManifestIsAFeed() {
        let linux = "https://github.com/acme/app/releases/latest/download/update-linux-amd64.json"
        #expect(MyGoUpdateConfig.find(in: Self.rodata([linux, Self.key])) == nil)
        #expect(MyGoUpdateConfig.find(in: Self.rodata(["https://acme.dev/update.json", Self.key])) == nil)
    }

    /// A literal packed right before the feed glues onto it; the feed starts at
    /// its own scheme.
    @Test func theFeedStartsAtItsScheme() {
        var bytes = Self.literals + Array("abc".utf8) + Array(Self.feed.utf8) + [0]
        bytes += [0] + Array(Self.key.utf8) + [0]
        #expect(MyGoUpdateConfig.find(in: Data(bytes))?.feed == Self.feed)
    }

    @Test func aTaggedFeedKeepsItsPlaceholder() {
        let tagged = "https://github.com/acme/app/releases/download/desktop-v{version}/update-darwin-universal.json"
        let config = MyGoUpdateConfig.find(in: Self.rodata([tagged, Self.key]))
        #expect(config?.feed == tagged)
        #expect(config?.isTagged == true)
        #expect(config?.manifestURL == nil)
    }

    /// Reads exactly the section it is pointed at, and refuses a size no real
    /// section has.
    @Test func readsTheNamedSectionOfTheFile() throws {
        let section = Self.rodata([Self.feed, Self.key])
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZMyGoRodata-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let other = Self.rodata(["https://elsewhere.example/update-darwin-arm64.json", Self.key])
        try (other + section + other).write(to: file)
        let range = MachOImports.FileRange(offset: UInt64(other.count), size: UInt64(section.count))
        #expect(MyGoUpdateConfig.read(binaryAt: file, rodata: range)?.feed == Self.feed)
        #expect(MyGoUpdateConfig.read(
            binaryAt: file,
            rodata: .init(offset: 0, size: MyGoUpdateConfig.maxSectionBytes + 1)) == nil)
    }
}

// MARK: - The source

@Suite(.serialized)
struct MyGoUpdateSourceTests {
    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var routes: [String: (status: Int, body: String)] = [:]
        nonisolated(unsafe) static var requests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else { return }
            Self.requests.append(request)
            let route = Self.routes[url.absoluteString] ?? (404, "")
            let response = HTTPURLResponse(
                url: url, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(route.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func source(team: String? = nil, token: String? = nil) -> MyGoUpdateSource {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return MyGoUpdateSource(
            githubToken: token, session: URLSession(configuration: configuration),
            teamIdentifier: { _ in team })
    }

    static let key = MyGoUpdateConfigTests.key
    static let feed = "https://github.com/acme/app/releases/latest/download/update-darwin-arm64.json"
    static let archive = "https://github.com/acme/app/releases/download/v1.2.0/app-1.2.0-darwin-arm64.tar.gz"

    /// Pulse's manifest shape (2026-10-13), trimmed.
    static func manifest(signature: String? = "SIG-120", size: Int = 6343718) -> String {
        let sig = signature.map { #""signature": "\#($0)","# } ?? ""
        return #"""
        {
          "version": "1.2.0",
          "notes": "- An Apps page lists what is installed.\n- About moves to ⌘0.",
          "date": "2026-10-11T10:12:38Z",
          "url": "\#(archive)",
          "size": \#(size),
          \#(sig)
          "deltas": [
            {"from": "1.1.0", "url": "https://github.com/acme/app/releases/download/v1.2.0/app-1.1.0-to-1.2.0-darwin-arm64.delta", "size": 1301845, "signature": "SIG-DELTA"}
          ],
          "previous": [
            {"version": "1.1.0", "url": "https://github.com/acme/app/releases/download/v1.1.0/app-1.1.0-darwin-arm64.tar.gz", "size": 1, "signature": "SIG-110"}
          ]
        }
        """#
    }

    private func app(_ id: String, feed: String = feed, version: String = "1.1.0") -> InstalledApp {
        InstalledApp(
            name: "Acme", bundleID: id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZMyGo-\(id).app"),
            isMASApp: false, sparkleFeedURL: nil,
            myGoUpdate: MyGoUpdateConfig(feed: feed, publicKey: Self.key))
    }

    @Test func readsTheReleaseTheAppsOwnUpdaterReads() async throws {
        FixtureProtocol.routes = [Self.feed: (200, Self.manifest())]
        FixtureProtocol.requests = []

        let remote = try #require(try await source().latestVersion(for: app("com.zz.mygo.read")))
        #expect(remote.sourceName == "MyGo")
        #expect(remote.shortVersion == "1.2.0" && remote.version == "1.2.0")
        #expect(remote.marketingMatchesBundle)
        #expect(remote.downloadURL == URL(string: Self.archive))
        #expect(remote.downloadSize == 6343718)
        #expect(remote.vendorInstallerKind == .tarGz)
        #expect(remote.myGoSignature == MyGoSignature(publicKey: Self.key, signature: "SIG-120"))
        #expect(remote.pageURL == URL(string: "https://github.com/acme/app/releases/tag/v1.2.0"))
        #expect(remote.publishedAt != nil)
        #expect(remote.deltas.count == 1)
        #expect(remote.deltas.first?.format == .myGo)
        #expect(remote.deltas.first?.publicKey == Self.key)
        #expect(remote.deltas.first?.edSignature == "SIG-DELTA")
        let entry = try #require(remote.structuredChangelog?.entries.first)
        #expect(entry.version == "1.2.0")
        #expect(entry.items == ["An Apps page lists what is installed.", "About moves to ⌘0."])
        #expect(FixtureProtocol.requests.map(\.url?.absoluteString) == [Self.feed])

        let status = UpdateChecker.evaluate(installed: app("com.zz.mygo.read"), remote: remote)
        #expect(status == .updateAvailable(latest: "1.2.0"))
    }

    /// Mutation: invert the Team test → an ad-hoc copy is offered on the
    /// Team-ID route, which then refuses every download it is offered.
    @Test func trustFollowsTheInstalledCopysSignature() async throws {
        FixtureProtocol.routes = [Self.feed: (200, Self.manifest())]
        let adHoc = try await source(team: nil).latestVersion(for: app("com.zz.mygo.adhoc"))
        #expect(adHoc?.installTrust == .myGoSignatureOnly)
        let signed = try await source(team: "GJE9R5VE87").latestVersion(for: app("com.zz.mygo.team"))
        #expect(signed?.installTrust == .developerID)
    }

    @Test func anAppThatLinksNoFeedIsNotAsked() async throws {
        FixtureProtocol.requests = []
        let plain = InstalledApp(
            name: "Plain", bundleID: "com.zz.mygo.none", shortVersion: "1", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/ZZPlain.app"), isMASApp: false, sparkleFeedURL: nil)
        #expect(try await source().latestVersion(for: plain) == nil)
        #expect(FixtureProtocol.requests.isEmpty)
    }

    /// MyGo's own updater treats these as no update (`checkUpdate`,
    /// `installUpdate`); so does this source, loudly.
    @Test func anIncompleteOrMissingManifestIsAFailure() async throws {
        FixtureProtocol.routes = [Self.feed: (200, Self.manifest(signature: nil))]
        await #expect(throws: MyGoUpdateSource.Failure.manifestIncomplete) {
            _ = try await source().latestVersion(for: app("com.zz.mygo.unsigned"))
        }
        FixtureProtocol.routes = [Self.feed: (200, Self.manifest(size: 0))]
        await #expect(throws: MyGoUpdateSource.Failure.manifestIncomplete) {
            _ = try await source().latestVersion(for: app("com.zz.mygo.nosize"))
        }
        FixtureProtocol.routes = [:]
        await #expect(throws: MyGoUpdateSource.Failure.manifestStatus(404)) {
            _ = try await source().latestVersion(for: app("com.zz.mygo.gone"))
        }
        FixtureProtocol.routes = [Self.feed: (200, "<html>not a manifest</html>")]
        await #expect(throws: MyGoUpdateSource.Failure.manifestUnreadable) {
            _ = try await source().latestVersion(for: app("com.zz.mygo.html"))
        }
    }

    static let tagged =
        "https://github.com/acme/app/releases/download/desktop-v{version}/update-darwin-arm64.json"
    static let releasesPage1 = "https://api.github.com/repos/acme/app/releases?per_page=100&page=1"

    /// The highest published release with the prefix — neither a draft nor a
    /// prerelease — whatever order the list is in. Mutations: drop the draft or
    /// prerelease test, or the prefix test → another release's manifest is read;
    /// take the first match instead of the highest → the backport listed ahead
    /// of 1.2.0 is offered as the latest.
    @Test func aTaggedFeedResolvesToTheNewestPublishedReleaseWithItsPrefix() async throws {
        let releases = """
            [
              {"tag_name": "desktop-v2.0.0", "draft": true, "prerelease": false},
              {"tag_name": "desktop-v1.9.0-beta.1", "draft": false, "prerelease": true},
              {"tag_name": "cli-v5.0.0", "draft": false, "prerelease": false},
              {"tag_name": "desktop-v1.1.1", "draft": false, "prerelease": false},
              {"tag_name": "desktop-v1.2.0", "draft": false, "prerelease": false},
              {"tag_name": "desktop-v1.1.0", "draft": false, "prerelease": false}
            ]
            """
        let manifest = "https://github.com/acme/app/releases/download/desktop-v1.2.0/update-darwin-arm64.json"
        FixtureProtocol.routes = [Self.releasesPage1: (200, releases), manifest: (200, Self.manifest())]
        FixtureProtocol.requests = []

        let remote = try await source(token: "TOKEN").latestVersion(
            for: app("com.zz.mygo.tagged", feed: Self.tagged))
        #expect(remote?.shortVersion == "1.2.0")
        #expect(FixtureProtocol.requests.map(\.url?.absoluteString) == [Self.releasesPage1, manifest])
        #expect(FixtureProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer TOKEN")
        // The manifest itself goes to github.com, which needs no token.
        #expect(FixtureProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aTaggedFeedWithNoPublishedReleaseIsAFailure() async throws {
        FixtureProtocol.routes = [Self.releasesPage1: (200, #"[{"tag_name": "cli-v1", "draft": false, "prerelease": false}]"#)]
        await #expect(throws: MyGoUpdateSource.Failure.noTaggedRelease(prefix: "desktop-v")) {
            _ = try await source().latestVersion(for: app("com.zz.mygo.notag", feed: Self.tagged))
        }
        FixtureProtocol.routes = [Self.releasesPage1: (403, #"{"message": "API rate limit exceeded"}"#)]
        await #expect(throws: MyGoUpdateSource.Failure.releasesStatus(403)) {
            _ = try await source().latestVersion(for: app("com.zz.mygo.limited", feed: Self.tagged))
        }
    }

    @Test func taggedFeedsAreTakenApartAsMyGoBuildsThem() {
        let feed = MyGoUpdateSource.TaggedFeed(Self.tagged)
        #expect(feed?.repo == "acme/app")
        #expect(feed?.prefix == "desktop-v")
        #expect(feed?.name == "update-darwin-arm64.json")
        // What `url.PathEscape` escapes in a tag (measured with go1.27.2): a
        // slash, `;` and `,` among others; `+` and `@` it keeps.
        #expect(feed?.manifestURL(tag: "desktop-v1.2.0+a/b;c,d@e")?.absoluteString
            == "https://github.com/acme/app/releases/download/desktop-v1.2.0+a%2Fb%3Bc%2Cd@e/update-darwin-arm64.json")
        #expect(MyGoUpdateSource.TaggedFeed(
            "https://cdn.example.com/releases/download/v{version}/update-darwin-arm64.json") == nil)
        #expect(MyGoUpdateSource.TaggedFeed(Self.feed) == nil)
    }

    /// Leafmark's notes carry its whole history under `### <version>` headings
    /// (0.9.2, 2026-10-13). Mutations: drop the "opens on this release" test →
    /// notes about another version are filed under this one; drop the count
    /// test → one version heading is read as a history.
    @Test func notesThatCarryTheHistoryAreSplitByVersion() throws {
        let history = """
            ### 0.9.2

            Rounded corners now match.

            #### 问题修复
            - Quotes use a 10px radius.

            ### 0.9.1

            #### 使用体验
            - Faster export.

            ### [v0.9.0]
            - First cut.
            """
        let split = try #require(MyGoUpdateSource.changelog(notes: history, version: "0.9.2", date: "2026-10-13"))
        #expect(split.entries.map(\.version) == ["0.9.2", "0.9.1", "0.9.0"])
        #expect(split.entries.first?.date == "2026-10-13")
        #expect(split.entries.first?.items.contains("Quotes use a 10px radius.") == true)
        #expect(split.entries[1].items.contains("Faster export.") && split.entries[1].date == nil)

        // Sections that are not versions stay one entry.
        let sectioned = "## New\n- An Apps page.\n## Fixed\n- A crash."
        #expect(MyGoUpdateSource.changelog(notes: sectioned, version: "1.2.0", date: nil)?.entries.map(\.version) == ["1.2.0"])
        // A history that does not open on this release is not split: it is not
        // known to be about this version.
        let stale = "### 0.9.1\n- a\n### 0.9.0\n- b"
        #expect(MyGoUpdateSource.changelog(notes: stale, version: "0.9.2", date: nil)?.entries.count == 1)
        // One version heading is the release's own title, not a history.
        let titled = "## 1.2.0\n- An Apps page."
        #expect(MyGoUpdateSource.changelog(notes: titled, version: "1.2.0", date: nil)?.entries.count == 1)
        #expect(MyGoUpdateSource.changelog(notes: "  \n", version: "1.2.0", date: nil) == nil)
    }

    @Test func onlyAnArchiveOnAGitHubReleaseHasAReleasePage() {
        #expect(MyGoUpdateSource.releasePage(for: URL(string: Self.archive)!)
            == URL(string: "https://github.com/acme/app/releases/tag/v1.2.0"))
        #expect(MyGoUpdateSource.releasePage(
            for: URL(string: "https://cdn.getmoshi.app/desktop-go/moshi-go-0.5.16-darwin-arm64.tar.gz")!) == nil)
    }

    @Test func theSourceSitsRightAfterSparkle() {
        let names = SourceStack.make(githubToken: nil).map(\.name)
        let sparkle = names.firstIndex(of: "Sparkle")
        #expect(sparkle != nil)
        #expect(names.firstIndex(of: "MyGo") == sparkle.map { $0 + 1 })
    }
}

// MARK: - Policy and the installer's gate for an ad-hoc MyGo app

@Suite(.serialized)
struct MyGoAdHocTrustTests {

    private static func offer(
        trust: InstallTrust, signature: String? = "SIG", kind: VendorInstallerKind = .tarGz,
        url: URL = URL(string: "https://example.com/app-1.2.0-darwin-arm64.tar.gz")!,
        deltas: [DeltaPatch] = []
    ) -> UpdateResult {
        let app = InstalledApp(
            name: "ZZMyGoAdHoc", bundleID: bundleID, shortVersion: "1.1.0", buildVersion: "1.1.0",
            path: URL(fileURLWithPath: "/Applications/ZZMyGoAdHoc-Installed.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: "1.2.0", version: "1.2.0", downloadURL: url,
            sourceName: MyGoUpdateSource.sourceName, vendorInstallerKind: kind, installTrust: trust,
            myGoSignature: MyGoSignature(publicKey: "KEY", signature: signature), deltas: deltas)
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "1.2.0"))
    }

    private static func settings(allowing: Bool) -> UpdateSettings {
        UpdateSettings(
            appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite,
            allowsDigestOnlyInstalls: allowing)
    }

    private static let environment = InstallEnvironment(
        isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])

    /// Not behind the setting for apps without a developer signature: the key is
    /// the installed copy's own, as for the app's own updater. Mutations: put the
    /// setting test back → not offered while off; drop the signature test →
    /// offered with nothing to check it against.
    @Test func anAdHocMyGoUpdateIsOfferedWhenSignedWhateverTheSetting() {
        let off = Self.settings(allowing: false), on = Self.settings(allowing: true)
        for settings in [off, on] {
            #expect(UpdatePolicy.canAutoInstall(Self.offer(trust: .myGoSignatureOnly), settings: settings, environment: Self.environment))
            #expect(!UpdatePolicy.canAutoInstall(
                Self.offer(trust: .myGoSignatureOnly, signature: nil), settings: settings, environment: Self.environment))
        }
        // A Developer ID MyGo app is the ordinary route, whatever the setting.
        for settings in [off, on] {
            #expect(UpdatePolicy.canAutoInstall(Self.offer(trust: .developerID), settings: settings, environment: Self.environment))
        }
        #expect(UpdatePolicy.digestOnlyOffer(Self.offer(trust: .myGoSignatureOnly), settings: off) == .offered)
        #expect(UpdatePolicy.digestOnlyOffer(Self.offer(trust: .myGoSignatureOnly, signature: nil), settings: off) == .noPublishedDigest)
        #expect(UpdatePolicy.digestOnlyOffer(Self.offer(trust: .myGoSignatureOnly, signature: nil), settings: on) == .noPublishedDigest)
        #expect(UpdatePolicy.digestOnlyOffer(Self.offer(trust: .myGoSignatureOnly), settings: on) == .offered)
        #expect(UpdatePolicy.digestOnlyOffer(Self.offer(trust: .developerID), settings: on) == nil)
        // Never the system installer: a package has no bundle for the ad-hoc gates.
        #expect(!UpdatePolicy.requiresInstaller(
            Self.offer(trust: .myGoSignatureOnly, kind: .pkg), environment: Self.environment))
        #expect(InstallCoordinator.route(for: Self.offer(trust: .developerID), requiresInstaller: false) == .vendor)
    }

    private static let bundleID = "com.example.zzfixture.mygoadhoc"

    private static func failure(_ result: UpdateResult, _ download: DownloadedUpdate, allowed: Bool) async -> Error? {
        do {
            try await VendorInstaller().apply(
                result, download: download, digestOnlyAllowed: allowed, onStage: { _ in })
            return nil
        } catch {
            return error
        }
    }

    /// What stopped it was this route's gate: the setting or the signature.
    private static func gate(_ error: Error?) -> String? {
        if case VendorInstaller.InstallError.digestOnlyNotAllowed? = error { return "notAllowed" }
        if let error = error as? SignatureVerifier.VerifyError {
            switch error {
            case .myGoSignatureMissing: return "missing"
            case .myGoSignatureInvalid: return "invalid"
            default: return nil
            }
        }
        if let route = error as? DeltaRouteFailure { return gate(route.underlying) }
        return nil
    }

    /// The vendor's signature over exactly the downloaded bytes — the archive, or
    /// the patch when a patch was downloaded — is checked before anything is
    /// unpacked, and the setting is not consulted. Mutations: put the setting
    /// guard back → refused while off; verify the archive's signature for a patch
    /// download → the wrong file passes or the right one fails.
    @Test func theInstallerChecksTheVendorsSignatureNotTheSetting() async throws {
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: "/Applications/ZZMyGoAdHoc-Installed.app"))
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("ZZMyGoAdHoc-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        let vendor = Curve25519.Signing.PrivateKey()
        let key = vendor.publicKey.rawRepresentation.base64EncodedString()
        func sign(_ bytes: Data) throws -> String {
            try vendor.signature(for: Data(SHA256.hash(data: bytes))).base64EncodedString()
        }

        let archive = scratch.appendingPathComponent("update.tar.gz")
        let archiveBytes = Data("not really an archive".utf8)
        try archiveBytes.write(to: archive)
        let full = DownloadedUpdate(archiveURL: archive, bytesDownloaded: 1, workDir: scratch)

        func result(signature: String?) -> UpdateResult {
            let r = Self.offer(trust: .myGoSignatureOnly)
            let remote = RemoteVersion(
                shortVersion: "1.2.0", version: "1.2.0", downloadURL: r.remote?.downloadURL,
                sourceName: MyGoUpdateSource.sourceName, vendorInstallerKind: .tarGz,
                installTrust: .myGoSignatureOnly,
                myGoSignature: MyGoSignature(publicKey: key, signature: signature))
            return UpdateResult(app: r.app, remote: remote, status: r.status)
        }

        // Off: not consulted — past the gate, as when on (refused later: the
        // bytes are no archive).
        let offPast = await Self.failure(result(signature: try sign(archiveBytes)), full, allowed: false)
        #expect(offPast != nil)
        #expect(Self.gate(offPast) == nil, "the setting stopped a signed MyGo download: \(String(describing: offPast))")
        // On, another key's signature, or none: refused at the gate.
        let stranger = try Curve25519.Signing.PrivateKey()
            .signature(for: Data(SHA256.hash(data: archiveBytes))).base64EncodedString()
        #expect(Self.gate(await Self.failure(result(signature: stranger), full, allowed: true)) == "invalid")
        #expect(Self.gate(await Self.failure(result(signature: nil), full, allowed: true)) == "missing")
        // On and signed by the app's key: past the gate (refused later — the
        // bytes are no archive).
        let past = await Self.failure(result(signature: try sign(archiveBytes)), full, allowed: true)
        #expect(past != nil)
        #expect(Self.gate(past) == nil, "a good signature was refused: \(String(describing: past))")

        // A patch download is checked against the patch's own signature.
        let patchFile = scratch.appendingPathComponent("update.delta")
        let patchBytes = Data("mygo delta 1\nnot really".utf8)
        try patchBytes.write(to: patchFile)
        func patched(_ signature: String?, key patchKey: String? = key) -> DownloadedUpdate {
            DownloadedUpdate(
                archiveURL: patchFile, bytesDownloaded: 1, workDir: scratch,
                appliedPatch: DeltaPatch(
                    fromBuild: "1.1.0", url: URL(string: "https://example.com/a.delta")!, size: 1,
                    edSignature: signature, format: .myGo, toVersion: "1.2.0", publicKey: patchKey))
        }
        // The archive's signature does not speak for the patch.
        #expect(Self.gate(await Self.failure(
            result(signature: try sign(archiveBytes)), patched(try sign(archiveBytes)), allowed: true)) == "invalid")
        #expect(Self.gate(await Self.failure(
            result(signature: try sign(archiveBytes)), patched(try sign(patchBytes), key: nil), allowed: true)) == "missing")
        let patchPast = await Self.failure(
            result(signature: try sign(archiveBytes)), patched(try sign(patchBytes)), allowed: true)
        #expect(patchPast != nil)
        #expect(Self.gate(patchPast) == nil, "a good patch signature was refused: \(String(describing: patchPast))")
    }
}
